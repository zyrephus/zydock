import Foundation

/// Manages the lifecycle of the zydockd Go daemon embedded in the app bundle.
class DaemonManager {
    static let shared = DaemonManager()

    private var process: Process?
    private let healthURL = URL(string: "http://localhost:6767/health")!

    private init() {}

    func start() {
        // Don't spawn a second daemon if one is already running
        if isDaemonRunning() { return }
        launch()
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
    }

    // MARK: - Private

    private func launch() {
        guard let execURL = Bundle.main.executableURL else { return }
        let daemonURL = execURL.deletingLastPathComponent().appendingPathComponent("zydockd")

        guard FileManager.default.isExecutableFile(atPath: daemonURL.path) else {
            NSLog("zydock: daemon binary not found at \(daemonURL.path)")
            return
        }

        let proc = Process()
        proc.executableURL = daemonURL
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] p in
            // Restart on unexpected crash (exit code != 0 and not SIGTERM)
            if p.terminationReason == .uncaughtSignal || p.terminationStatus != 0 {
                NSLog("zydock: daemon exited unexpectedly (status \(p.terminationStatus)), restarting...")
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    self?.launch()
                }
            }
        }

        do {
            try proc.run()
            self.process = proc
            NSLog("zydock: daemon started (pid \(proc.processIdentifier))")
        } catch {
            NSLog("zydock: failed to start daemon: \(error)")
        }
    }

    private func isDaemonRunning() -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var alive = false

        var request = URLRequest(url: healthURL)
        request.timeoutInterval = 1

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                alive = true
            }
            semaphore.signal()
        }.resume()

        semaphore.wait()
        return alive
    }
}
