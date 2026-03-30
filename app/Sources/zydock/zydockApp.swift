import SwiftUI

@main
struct zydockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We don't use a normal window — the notch panel is created manually
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DaemonManager.shared.start()
        notchWindow = NotchWindow()
        notchWindow?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DaemonManager.shared.stop()
    }
}
