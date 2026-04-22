import Foundation

/// Owns the TrayManager runtime. Inert until the Tray module is enabled.
final class TrayController: ObservableObject {
    @Published private(set) var trayManager: TrayManager?

    func activate() {
        guard trayManager == nil else { return }
        let manager = TrayManager()
        self.trayManager = manager
        manager.start()
    }

    func deactivate() {
        trayManager?.stop()
        trayManager = nil
    }
}
