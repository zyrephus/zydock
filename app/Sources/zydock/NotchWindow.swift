import AppKit
import Combine
import SwiftUI

/// Bridges hover state from AppKit mouse tracking into SwiftUI.
class NotchState: ObservableObject {
    @Published var isExpanded = false
    @Published var contentHeight: CGFloat = 0
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
        let mouseInWindow = window.map { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? false
        if !mouseInWindow {
            onHoverChanged?(false)
        }
    }
}

/// NSPanel subclass that can become key without activating the app.
/// This allows local key event monitoring for tab shortcuts.
class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

class NotchWindow {
    private var panel: NotchPanel?
    private let sessionState = SessionState()
    private let notchState = NotchState()
    private let tabState = TabState()
    private var wsClient: WebSocketClient?
    private let metricsPoller = MetricsPoller()
    private let nowPlaying = NowPlayingManager()
    private let trayManager = TrayManager()
    private var keyMonitor: Any?
    private var heightObserver: AnyCancellable?

    private var collapsedFrame: NSRect = .zero
    private var screenFrame: NSRect = .zero
    private var notchH: CGFloat = 38
    private let expandedW: CGFloat = 420
    private let maxExpandedH: CGFloat = 500

    func show() {
        guard let screen = NSScreen.main else { return }
        screenFrame = screen.frame
        notchH = max(screen.safeAreaInsets.top, 38)

        let collapsedW: CGFloat = 280
        collapsedFrame = NSRect(
            x: screenFrame.midX - collapsedW / 2,
            y: screenFrame.maxY - notchH,
            width: collapsedW,
            height: notchH
        )

        let view = NotchView(
            sessionState: sessionState,
            notchState: notchState,
            metricsPoller: metricsPoller,
            nowPlaying: nowPlaying,
            trayManager: trayManager,
            tabState: tabState,
            notchHeight: notchH
        )
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        let tracker = HoverTrackingView()
        tracker.onHoverChanged = { [weak self] hovering in
            if hovering {
                self?.expand()
            } else {
                self?.collapse()
            }
        }

        let panel = NotchPanel(
            contentRect: collapsedFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        tracker.frame = NSRect(origin: .zero, size: collapsedFrame.size)
        tracker.autoresizingMask = [.width, .height] as NSView.AutoresizingMask
        hostingView.frame = tracker.bounds
        hostingView.autoresizingMask = [.width, .height] as NSView.AutoresizingMask
        tracker.addSubview(hostingView)
        panel.contentView = tracker

        panel.orderFrontRegardless()
        self.panel = panel

        wsClient = WebSocketClient(state: sessionState)
        wsClient?.connect()
        metricsPoller.start()
        trayManager.start()

        setupKeyMonitor()
        setupHeightObserver()
    }

    func toggle() {
        if notchState.isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    private func expandedFrame(for contentHeight: CGFloat) -> NSRect {
        let h = min(contentHeight, maxExpandedH)
        return NSRect(
            x: screenFrame.midX - expandedW / 2,
            y: screenFrame.maxY - notchH - h,
            width: expandedW,
            height: notchH + h
        )
    }

    private func expand() {
        guard !notchState.isExpanded else { return }
        notchState.isExpanded = true
        panel?.makeKey()

        let frame = expandedFrame(for: notchState.contentHeight)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel?.animator().setFrame(frame, display: true)
        }
    }

    private func collapse() {
        guard notchState.isExpanded else { return }
        notchState.isExpanded = false
        panel?.resignKey()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.panel?.animator().setFrame(self.collapsedFrame, display: true)
        }
    }

    private func setupHeightObserver() {
        heightObserver = notchState.$contentHeight
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] height in
                guard let self = self, self.notchState.isExpanded else { return }
                let frame = self.expandedFrame(for: height)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self.panel?.animator().setFrame(frame, display: true)
                }
            }
    }

    // MARK: - Key Event Monitoring

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.notchState.isExpanded else { return event }
            guard event.modifierFlags.contains(.command) else { return event }

            let tabs = self.tabState.visibleTabs
            switch event.charactersIgnoringModifiers {
            case "1":
                if tabs.count >= 1 {
                    withAnimation(.easeInOut(duration: 0.15)) { self.tabState.activeTab = tabs[0] }
                    return nil
                }
            case "2":
                if tabs.count >= 2 {
                    withAnimation(.easeInOut(duration: 0.15)) { self.tabState.activeTab = tabs[1] }
                    return nil
                }
            case "3":
                if tabs.count >= 3 {
                    withAnimation(.easeInOut(duration: 0.15)) { self.tabState.activeTab = tabs[2] }
                    return nil
                }
            case "[":
                withAnimation(.easeInOut(duration: 0.15)) { self.tabState.selectPrevious() }
                return nil
            case "]":
                withAnimation(.easeInOut(duration: 0.15)) { self.tabState.selectNext() }
                return nil
            default:
                break
            }
            return event
        }
    }

    deinit {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
