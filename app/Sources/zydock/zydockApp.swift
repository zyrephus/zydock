import SwiftUI
import AppKit

@main
struct zydockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var notchWindow: NotchWindow?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        DaemonManager.shared.start()

        notchWindow = NotchWindow()
        notchWindow?.show()

        setupMenuBar()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DaemonManager.shared.stop()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "zydock"
        )
        let menu = NSMenu()
        menu.addItem(NSMenuItem(
            title: "Quit zydock",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        statusItem?.menu = menu
    }
}
