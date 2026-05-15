import AppKit
import Combine

/// Receives playback updates from Music.app and Spotify via
/// DistributedNotificationCenter. Both apps broadcast system-wide notifications
/// on every state change (play/pause/track/seek), so we subscribe once and
/// avoid polling. A local 1s timer ticks `elapsedTime` between events, and
/// AppleScript is reserved for user-initiated commands, seeding state at
/// launch, and fetching fields the notifications don't carry (Music position,
/// Music artwork bytes).
class NowPlayingManager: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var album: String = ""
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false
    @Published var hasMedia: Bool = false
    @Published var elapsedTime: Double = 0
    @Published var duration: Double = 0

    private enum Source: String {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String {
            switch self {
            case .music:   return "com.apple.Music"
            case .spotify: return "com.spotify.client"
            }
        }

        var notificationName: Notification.Name {
            switch self {
            case .music:   return Notification.Name("com.apple.Music.playerInfo")
            case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
            }
        }
    }

    private var activeSource: Source?
    private var progressTimer: Timer?
    private var lastArtworkKey: String = ""

    init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(
            self,
            selector: #selector(handleMusicNotification(_:)),
            name: Source.music.notificationName,
            object: nil
        )
        dnc.addObserver(
            self,
            selector: #selector(handleSpotifyNotification(_:)),
            name: Source.spotify.notificationName,
            object: nil
        )
        seedFromRunningApps()
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        progressTimer?.invalidate()
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let source = activeSource else { return }
        // No optimistic toggle: Music.app's playerInfo notification can briefly
        // carry the pre-command state, causing a visible play/pause flicker if
        // we flip locally first. The notification arrives quickly enough.
        sendCommand("playpause", to: source)
    }

    func nextTrack() {
        guard let source = activeSource else { return }
        sendCommand("next track", to: source)
        // Music.app's `next track` preserves paused state; force play so skip
        // behaves like Spotify (load + play the next song).
        if source == .music {
            sendCommand("play", to: source)
        }
    }

    func previousTrack() {
        guard let source = activeSource else { return }
        sendCommand("previous track", to: source)
        if source == .music {
            sendCommand("play", to: source)
        }
    }

    /// Optimistic update while the user drags the scrubber; progress timer
    /// is suspended so it doesn't tug the value back.
    func scrub(fraction: Double) {
        guard duration > 0 else { return }
        elapsedTime = max(0, min(duration, fraction * duration))
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Bring the active music app (Music.app or Spotify) to the foreground.
    func openActiveApp() {
        guard let source = activeSource,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Commit a scrub: seek the active player and resume progress ticking.
    func seek(fraction: Double) {
        guard let source = activeSource, duration > 0 else { return }
        let seconds = max(0, min(duration, fraction * duration))
        elapsedTime = seconds
        let script = "tell application \"\(source.rawValue)\" to set player position to \(seconds)"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.runAppleScript(script)
        }
        updateProgressTimer()
    }

    // MARK: - Distributed notification handlers

    @objc private func handleMusicNotification(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = (info["Player State"] as? String) ?? "Stopped"
        // Don't let a non-Playing event from a background source steal focus.
        if let current = activeSource, current != .music, state != "Playing" { return }
        if state == "Stopped" {
            if activeSource == .music { clear() }
            return
        }
        activeSource = .music
        title  = (info["Name"]   as? String) ?? ""
        artist = (info["Artist"] as? String) ?? ""
        album  = (info["Album"]  as? String) ?? ""
        // "Total Time" is milliseconds (NSNumber bridges to Double).
        let totalMs = (info["Total Time"] as? Double) ?? 0
        duration = totalMs / 1000.0
        isPlaying = (state == "Playing")
        hasMedia  = !title.isEmpty
        let persistentID = (info["Persistent ID"] as? String) ?? title
        refreshArtworkIfNeeded(source: .music, key: "music|\(persistentID)", spotifyURL: nil)
        // Music notifications don't carry position; fetch once per state change.
        fetchPosition(from: .music)
        updateProgressTimer()
    }

    @objc private func handleSpotifyNotification(_ note: Notification) {
        guard let info = note.userInfo else { return }
        let state = (info["Player State"] as? String) ?? "Stopped"
        if let current = activeSource, current != .spotify, state != "Playing" { return }
        if state == "Stopped" {
            if activeSource == .spotify { clear() }
            return
        }
        activeSource = .spotify
        title  = (info["Name"]   as? String) ?? ""
        artist = (info["Artist"] as? String) ?? ""
        album  = (info["Album"]  as? String) ?? ""
        // Spotify "Duration" is milliseconds.
        let durMs = (info["Duration"] as? Double) ?? 0
        duration = durMs / 1000.0
        isPlaying = (state == "Playing")
        hasMedia  = !title.isEmpty
        let trackID = (info["Track ID"] as? String) ?? title
        let artworkURL = info["Artwork URL"] as? String
        refreshArtworkIfNeeded(source: .spotify, key: "spotify|\(trackID)", spotifyURL: artworkURL)
        if let pos = info["Playback Position"] as? Double {
            elapsedTime = pos
        } else {
            fetchPosition(from: .spotify)
        }
        updateProgressTimer()
    }

    private func clear() {
        activeSource = nil
        title = ""
        artist = ""
        album = ""
        duration = 0
        elapsedTime = 0
        isPlaying = false
        hasMedia = false
        artwork = nil
        lastArtworkKey = ""
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Progress timer

    private func updateProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        guard isPlaying, duration > 0 else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.elapsedTime = min(self.elapsedTime + 1.0, self.duration)
        }
    }

    // MARK: - Launch-time seed

    /// Distributed notifications are fire-and-forget, so if a music app was
    /// already running when we launched, we'd miss its current state until the
    /// next play/pause. One AppleScript snapshot at init closes that gap.
    private func seedFromRunningApps() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if Self.isRunning(bundleID: Source.music.bundleID),
               let snap = Self.appleScriptSnapshot(source: .music) {
                DispatchQueue.main.async { self.applySnapshot(snap, source: .music) }
                return
            }
            if Self.isRunning(bundleID: Source.spotify.bundleID),
               let snap = Self.appleScriptSnapshot(source: .spotify) {
                DispatchQueue.main.async { self.applySnapshot(snap, source: .spotify) }
            }
        }
    }

    private struct Snapshot {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let isPlaying: Bool
    }

    private func applySnapshot(_ snap: Snapshot, source: Source) {
        guard !snap.title.isEmpty else { return }
        activeSource = source
        title = snap.title
        artist = snap.artist
        album = snap.album
        duration = snap.duration
        elapsedTime = snap.position
        isPlaying = snap.isPlaying
        hasMedia = true
        updateProgressTimer()
        let key = "\(source.rawValue)|\(snap.title)|\(snap.album)|\(snap.artist)"
        if key != lastArtworkKey {
            lastArtworkKey = key
            fetchArtworkViaAppleScript(source: source)
        }
    }

    // MARK: - AppleScript helpers

    private static func isRunning(bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static func appleScriptSnapshot(source: Source) -> Snapshot? {
        let script = """
        tell application "\(source.rawValue)"
            try
                if player state is stopped then return ""
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to duration of current track
                set p to player position
                set s to player state as text
                return t & "\\n" & a & "\\n" & al & "\\n" & d & "\\n" & p & "\\n" & s
            on error
                return ""
            end try
        end tell
        """
        guard let output = runAppleScript(script), !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 6 else { return nil }
        let state = parts[5].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let rawDuration = Double(parts[3]) ?? 0
        // Music's scripting dictionary returns duration in seconds; Spotify's in ms.
        let durSeconds = source == .spotify ? rawDuration / 1000.0 : rawDuration
        return Snapshot(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            duration: durSeconds,
            position: Double(parts[4]) ?? 0,
            isPlaying: state.contains("playing")
        )
    }

    private func fetchPosition(from source: Source) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let script = """
            tell application "\(source.rawValue)"
                try
                    return (player position as text)
                on error
                    return ""
                end try
            end tell
            """
            guard let output = Self.runAppleScript(script),
                  let pos = Double(output.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return
            }
            DispatchQueue.main.async {
                guard let self = self, self.activeSource == source else { return }
                self.elapsedTime = pos
            }
        }
    }

    private static func runAppleScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if error != nil { return nil }
        return result.stringValue
    }

    private func sendCommand(_ verb: String, to source: Source) {
        let script = "tell application \"\(source.rawValue)\" to \(verb)"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.runAppleScript(script)
        }
    }

    // MARK: - Artwork

    private func refreshArtworkIfNeeded(source: Source, key: String, spotifyURL: String?) {
        guard key != lastArtworkKey else { return }
        lastArtworkKey = key
        switch source {
        case .spotify:
            if let urlString = spotifyURL, let url = URL(string: urlString) {
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    guard let data = try? Data(contentsOf: url),
                          let image = NSImage(data: data) else { return }
                    DispatchQueue.main.async {
                        guard let self = self, self.lastArtworkKey == key else { return }
                        self.artwork = image
                    }
                }
            } else {
                fetchArtworkViaAppleScript(source: .spotify)
            }
        case .music:
            fetchArtworkViaAppleScript(source: .music)
        }
    }

    private func fetchArtworkViaAppleScript(source: Source) {
        let key = lastArtworkKey
        let title = self.title
        let artist = self.artist
        let album = self.album
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Local library tracks expose artwork bytes via AppleScript. Apple
            // Music streamed tracks return 0 artworks even when art is shown,
            // so fall back to the iTunes Search API by title+artist.
            let image = Self.loadArtwork(source: source)
                ?? (source == .music ? Self.lookupITunesArtwork(title: title, artist: artist, album: album) : nil)
            DispatchQueue.main.async {
                guard let self = self, self.lastArtworkKey == key else { return }
                self.artwork = image
            }
        }
    }

    private static func lookupITunesArtwork(title: String, artist: String, album: String) -> NSImage? {
        guard !title.isEmpty else { return nil }
        let term = "\(artist) \(title)".trimmingCharacters(in: .whitespaces)
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let artURL = first["artworkUrl100"] as? String else {
            return nil
        }
        // Bump to a higher resolution — the API returns 100x100 by default.
        let hiRes = artURL.replacingOccurrences(of: "100x100bb", with: "600x600bb")
        guard let imageURL = URL(string: hiRes),
              let imageData = try? Data(contentsOf: imageURL) else {
            return nil
        }
        return NSImage(data: imageData)
    }

    private static func loadArtwork(source: Source) -> NSImage? {
        switch source {
        case .music:
            let tempPath = NSTemporaryDirectory() + "zydock_art_\(UUID().uuidString).dat"
            let script = """
            tell application "Music"
                try
                    set artData to raw data of artwork 1 of current track
                    set tmpFile to POSIX file "\(tempPath)"
                    try
                        set f to open for access tmpFile with write permission
                        set eof of f to 0
                        write artData to f
                        close access f
                        return "\(tempPath)"
                    on error
                        try
                            close access tmpFile
                        end try
                        return ""
                    end try
                on error
                    return ""
                end try
            end tell
            """
            guard let path = runAppleScript(script), !path.isEmpty else { return nil }
            defer { try? FileManager.default.removeItem(atPath: path) }
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  !data.isEmpty,
                  let image = NSImage(data: data) else {
                return nil
            }
            return image
        case .spotify:
            let script = """
            tell application "Spotify"
                try
                    return artwork url of current track
                on error
                    return ""
                end try
            end tell
            """
            guard let urlString = runAppleScript(script),
                  !urlString.isEmpty,
                  let url = URL(string: urlString),
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return NSImage(data: data)
        }
    }
}
