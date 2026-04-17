import AppKit
import SwiftUI

final class NotchWindow {
    private var panel: NSPanel?
    private var host: NSHostingView<NotchView>?

    private var screenFrame: NSRect = .zero
    private var notchH: CGFloat = 32
    private var notchW: CGFloat = 200

    // Extra width past the hardware notch to widen the hover trigger zone.
    private let earExtension: CGFloat = 45
    // Dimensions of the expanded panel.
    private let expandedW: CGFloat = 550
    private let expandedH: CGFloat = 150

    private var isExpanded = false
    private var pinned = false
    private let state = NotchState()

    func show() {
        guard let screen = Self.notchedScreen() else { return }
        screenFrame = screen.frame
        notchH = max(screen.safeAreaInsets.top, 32)
        notchW = Self.physicalNotchWidth(for: screen)

        let frame = collapsedFrame()

        let view = NotchView(
            notchHeight: notchH,
            notchWidth: notchW,
            earWidth: earExtension,
            state: state,
            onHoverChange: { [weak self] entered in
                entered ? self?.expand() : self?.collapse()
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        self.host = host

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host

        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func collapsedFrame() -> NSRect {
        let w = notchW + earExtension * 2
        return NSRect(
            x: screenFrame.midX - w / 2,
            y: screenFrame.maxY - notchH,
            width: w,
            height: notchH
        )
    }

    private func expandedFrame() -> NSRect {
        NSRect(
            x: screenFrame.midX - expandedW / 2,
            y: screenFrame.maxY - notchH - expandedH,
            width: expandedW,
            height: notchH + expandedH
        )
    }

    private func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        withAnimation(.easeInOut(duration: 0.22)) { state.isExpanded = true }
        animate(to: expandedFrame(), duration: 0.22)
    }

    private func collapse() {
        guard isExpanded else { return }
        if pinned { return }
        isExpanded = false
        withAnimation(.easeInOut(duration: 0.28)) { state.isExpanded = false }
        animate(to: collapsedFrame(), duration: 0.28)
    }

    func togglePinned() {
        pinned.toggle()
        if pinned {
            if !isExpanded { expand() }
        } else {
            collapse()
        }
    }

    private func animate(to frame: NSRect, duration: CFTimeInterval) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel?.animator().setFrame(frame, display: true)
        }
    }

    /// Prefer the screen that physically has a notch (safeAreaInsets.top > 0).
    /// Falls back to the built-in display, then to NSScreen.main.
    private static func notchedScreen() -> NSScreen? {
        if #available(macOS 12.0, *) {
            if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
                return s
            }
        }
        let builtIn = NSScreen.screens.first { screen in
            guard let n = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(n) != 0
        }
        return builtIn ?? NSScreen.main
    }

    private static func physicalNotchWidth(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *),
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let gap = right.minX - left.maxX
            if gap > 0 { return gap }
        }
        return 200
    }
}
