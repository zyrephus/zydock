import AppKit
import SwiftUI

class NotchWindow {
    private var panel: NSPanel?
    private let sessionState = SessionState()
    private var wsClient: WebSocketClient?

    func show() {
        let view = NotchView(sessionState: sessionState)
        let hostingView = NSHostingView(rootView: view)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView

        positionAtNotch(panel)
        panel.orderFrontRegardless()
        self.panel = panel

        wsClient = WebSocketClient(state: sessionState)
        wsClient?.connect()
    }

    private func positionAtNotch(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let safeArea = screen.safeAreaInsets

        let x = screenFrame.midX - panel.frame.width / 2
        let y = screenFrame.maxY - safeArea.top - panel.frame.height

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
