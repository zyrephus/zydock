import AppKit
import SwiftUI

/// Bridges hover state from AppKit mouse tracking into SwiftUI.
class NotchState: ObservableObject {
    @Published var isExpanded = false
}

/// NSView that detects mouse enter/exit via NSTrackingArea.
/// When the panel resizes, `.inVisibleRect` auto-updates the tracked region.
class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        // Verify the mouse is actually outside before collapsing.
        // Spurious mouseExited events fire when the tracking area is
        // recreated during panel resize, even if the cursor never left.
        let mouseInWindow = window.map { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? false
        if !mouseInWindow {
            onHoverChanged?(false)
        }
    }
}

class NotchWindow {
    private var panel: NSPanel?
    private let sessionState = SessionState()
    private let notchState = NotchState()
    private var wsClient: WebSocketClient?

    private var collapsedFrame: NSRect = .zero
    private var expandedFrame: NSRect = .zero

    func show() {
        guard let screen = NSScreen.main else { return }
        let sf = screen.frame
        let notchHeight = max(screen.safeAreaInsets.top, 38)

        // Collapsed: invisible hit target covering the notch
        let collapsedW: CGFloat = 220
        collapsedFrame = NSRect(
            x: sf.midX - collapsedW / 2,
            y: sf.maxY - notchHeight,
            width: collapsedW,
            height: notchHeight
        )

        // Expanded: wider + extends below the notch
        let expandedW: CGFloat = 420
        let expandedContentH: CGFloat = 160
        expandedFrame = NSRect(
            x: sf.midX - expandedW / 2,
            y: sf.maxY - notchHeight - expandedContentH,
            width: expandedW,
            height: notchHeight + expandedContentH
        )

        // SwiftUI view
        let view = NotchView(
            sessionState: sessionState,
            notchState: notchState,
            notchHeight: notchHeight
        )
        let hostingView = NSHostingView(rootView: view)

        // Tracking view wraps the hosting view for mouse events
        let tracker = HoverTrackingView()
        tracker.onHoverChanged = { [weak self] hovering in
            if hovering {
                self?.expand()
            } else {
                self?.collapse()
            }
        }

        // Panel — borderless, floating, transparent
        let panel = NSPanel(
            contentRect: collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Nest hosting view inside tracking view
        tracker.frame = NSRect(origin: .zero, size: collapsedFrame.size)
        tracker.autoresizingMask = [.width, .height]
        hostingView.frame = tracker.bounds
        hostingView.autoresizingMask = [.width, .height]
        tracker.addSubview(hostingView)
        panel.contentView = tracker

        panel.orderFrontRegardless()
        self.panel = panel

        wsClient = WebSocketClient(state: sessionState)
        wsClient?.connect()
    }

    /// Toggle the notch between expanded and collapsed.
    /// Called by HotkeyManager when the global shortcut fires.
    func toggle() {
        if notchState.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    private func expand() {
        guard !notchState.isExpanded else { return }
        notchState.isExpanded = true

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel?.animator().setFrame(self.expandedFrame, display: true)
        }
    }

    private func collapse() {
        guard notchState.isExpanded else { return }
        notchState.isExpanded = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel?.animator().setFrame(self.collapsedFrame, display: true)
        }
    }
}
