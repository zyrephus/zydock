import AppKit
import Combine

class NowPlayingManager: ObservableObject {
    @Published var title: String = ""
    @Published var artist: String = ""
    @Published var artwork: NSImage?
    @Published var isPlaying: Bool = false
    @Published var hasMedia: Bool = false
    @Published var elapsedTime: Double = 0
    @Published var duration: Double = 0

    private var getNowPlayingInfo: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void)?
    private var registerForNotifications: (@convention(c) (DispatchQueue) -> Void)?
    private var sendCommand: (@convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool)?
    private var progressTimer: Timer?

    // MRMediaRemoteCommand constants
    private let kTogglePlayPause: UInt32 = 2
    private let kNextTrack: UInt32 = 4
    private let kPreviousTrack: UInt32 = 5

    init() {
        loadMediaRemoteFramework()
        registerForNotifications?(DispatchQueue.main)
        observeNotifications()
        fetchNowPlaying()
    }

    // MARK: - Public Controls

    func togglePlayPause() {
        _ = sendCommand?(kTogglePlayPause, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    func nextTrack() {
        _ = sendCommand?(kNextTrack, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    func previousTrack() {
        _ = sendCommand?(kPreviousTrack, nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.fetchNowPlaying()
        }
    }

    // MARK: - Private

    func fetchNowPlaying() {
        getNowPlayingInfo?(DispatchQueue.main) { [weak self] info in
            guard let self = self else { return }

            let newTitle = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
            let newArtist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
            let playbackRate = info["kMRMediaRemoteNowPlayingInfoPlaybackRate"] as? Double ?? 0
            let newIsPlaying = playbackRate > 0

            self.title = newTitle
            self.artist = newArtist
            self.isPlaying = newIsPlaying
            self.hasMedia = !newTitle.isEmpty

            // Track progress
            self.duration = info["kMRMediaRemoteNowPlayingInfoDuration"] as? Double ?? 0
            self.elapsedTime = info["kMRMediaRemoteNowPlayingInfoElapsedTime"] as? Double ?? 0

            if let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                self.artwork = NSImage(data: artworkData)
            } else if newTitle.isEmpty {
                self.artwork = nil
            }

            self.updateProgressTimer()
        }
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

    private func loadMediaRemoteFramework() {
        guard let bundle = CFBundleCreate(
            kCFAllocatorDefault,
            NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
        ) else { return }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString) {
            getNowPlayingInfo = unsafeBitCast(
                ptr,
                to: (@convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void).self
            )
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) {
            registerForNotifications = unsafeBitCast(
                ptr,
                to: (@convention(c) (DispatchQueue) -> Void).self
            )
        }

        if let ptr = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteSendCommand" as CFString) {
            sendCommand = unsafeBitCast(
                ptr,
                to: (@convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool).self
            )
        }
    }

    private func observeNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlaying()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlaying()
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("kMRMediaRemoteNowPlayingApplicationDidChangeNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.fetchNowPlaying()
        }
    }
}
