import AppKit
import Combine

/// Polls Music.app and Spotify via AppleScript for Now Playing info and playback
/// controls. MediaRemote's C API was locked down on macOS 14.4+, so AppleScript
/// is the only reliable path for third-party apps without private entitlements.
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
    }

    private var activeSource: Source?
    private var pollTimer: Timer?
    private var progressTimer: Timer?
    private let artworkPath = NSTemporaryDirectory() + "zydock_art.dat"
    private var lastArtworkKey: String = ""

    init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
        progressTimer?.invalidate()
    }

    // MARK: - Controls

    func togglePlayPause() {
        guard let source = activeSource else { return }
        sendCommand("playpause", to: source)
        isPlaying.toggle()
        updateProgressTimer()
        scheduleRefresh(after: 0.25)
    }

    func nextTrack() {
        guard let source = activeSource else { return }
        sendCommand("next track", to: source)
        scheduleRefresh(after: 0.4)
    }

    func previousTrack() {
        guard let source = activeSource else { return }
        sendCommand("previous track", to: source)
        scheduleRefresh(after: 0.4)
    }

    /// Optimistically update `elapsedTime` while the user drags the scrubber.
    /// Suspends the progress timer so it doesn't tug the value back.
    func scrub(fraction: Double) {
        guard duration > 0 else { return }
        elapsedTime = max(0, min(duration, fraction * duration))
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Commit a scrub: send the seek command to the active player and restart
    /// the progress timer if we're still playing.
    func seek(fraction: Double) {
        guard let source = activeSource, duration > 0 else { return }
        let seconds = max(0, min(duration, fraction * duration))
        elapsedTime = seconds
        let script = "tell application \"\(source.rawValue)\" to set player position to \(seconds)"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.runAppleScript(script)
        }
        updateProgressTimer()
        scheduleRefresh(after: 0.3)
    }

    // MARK: - Polling

    private func startPolling() {
        poll()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.poll()
        }
    }

    private func poll() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            if let info = Self.queryMusic() {
                DispatchQueue.main.async { self.apply(info, source: .music) }
                return
            }
            if let info = Self.querySpotify() {
                DispatchQueue.main.async { self.apply(info, source: .spotify) }
                return
            }
            DispatchQueue.main.async { self.clear() }
        }
    }

    // MARK: - AppleScript

    private struct Snapshot {
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let position: Double
        let isPlaying: Bool
    }

    private static func queryMusic() -> Snapshot? {
        let script = """
        tell application "System Events"
            if not (exists process "Music") then return ""
        end tell
        tell application "Music"
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
        return runAndParse(script)
    }

    private static func querySpotify() -> Snapshot? {
        // Spotify reports duration in milliseconds; convert to seconds.
        let script = """
        tell application "System Events"
            if not (exists process "Spotify") then return ""
        end tell
        tell application "Spotify"
            try
                if player state is stopped then return ""
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to (duration of current track) / 1000
                set p to player position
                set s to player state as text
                return t & "\\n" & a & "\\n" & al & "\\n" & d & "\\n" & p & "\\n" & s
            on error
                return ""
            end try
        end tell
        """
        return runAndParse(script)
    }

    private static func runAndParse(_ source: String) -> Snapshot? {
        guard let output = runAppleScript(source),
              !output.isEmpty else { return nil }
        let parts = output.components(separatedBy: "\n")
        guard parts.count >= 6 else { return nil }
        let state = parts[5].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Snapshot(
            title: parts[0],
            artist: parts[1],
            album: parts[2],
            duration: Double(parts[3]) ?? 0,
            position: Double(parts[4]) ?? 0,
            isPlaying: state.contains("playing")
        )
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

    // MARK: - State

    private func apply(_ snap: Snapshot, source: Source) {
        activeSource = source
        title = snap.title
        artist = snap.artist
        album = snap.album
        duration = snap.duration
        elapsedTime = snap.position
        isPlaying = snap.isPlaying
        hasMedia = !snap.title.isEmpty
        updateProgressTimer()
        refreshArtwork(for: source, trackKey: "\(snap.title)|\(snap.album)|\(snap.artist)")
    }

    private func clear() {
        guard hasMedia || !title.isEmpty else { return }
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

    private func updateProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        guard isPlaying, duration > 0 else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying else { return }
            self.elapsedTime = min(self.elapsedTime + 1.0, self.duration)
        }
    }

    // MARK: - Artwork

    private func refreshArtwork(for source: Source, trackKey: String) {
        guard trackKey != lastArtworkKey else { return }
        lastArtworkKey = trackKey
        let path = artworkPath
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = Self.fetchArtwork(source: source, tempPath: path)
            DispatchQueue.main.async {
                self?.artwork = image
            }
        }
    }

    private static func fetchArtwork(source: Source, tempPath: String) -> NSImage? {
        // Music.app exposes `raw data` on artwork; Spotify exposes `artwork url`.
        switch source {
        case .music:
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
            guard let path = runAppleScript(script), !path.isEmpty,
                  let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                return nil
            }
            return NSImage(data: data)

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
