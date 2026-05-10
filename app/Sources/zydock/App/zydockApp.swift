import SwiftUI
import AppKit

@main
struct zydockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Empty WindowGroup placeholder — settings is shown via SettingsWindowController.
        // Avoiding the SwiftUI Settings scene because it installs an app menu with
        // ⌘, / ⌘Q shortcuts and behaves unreliably in LSUIElement background apps.
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Strip the SwiftUI-installed main menu so no implicit shortcuts (⌘, ⌘Q ⌘W…)
        // exist. The only hotkey is the user-configurable toggle.
        NSApp.mainMenu = NSMenu()

        HookInstaller.installIfNeeded()
        DaemonManager.shared.start()

        notchWindow = NotchWindow()
        notchWindow?.show()

        HotkeyManager.shared.onTrigger = { [weak self] in
            self?.notchWindow?.togglePinned()
        }
        HotkeyManager.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DaemonManager.shared.stop()
    }
}
