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

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var pendingCollapse: DispatchWorkItem?
    /// Prevents sub-pixel wobble near the edge from toggling state.
    private let collapseMargin: CGFloat = 4
    private let collapseDelay: TimeInterval = 0.12

    // Cached hit zones — recomputed only when the screen/notch geometry changes
    // (i.e. in show()). Read by every mouse-move event, so worth caching.
    private var collapsedZone: NSRect = .zero
    private var expandedHoverZone: NSRect = .zero
    /// Lowest y the cursor can have while still being inside either zone.
    /// Used as a single-compare early-out to reject events far from the top.
    private var zoneMinY: CGFloat = 0

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
            state: state
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

        collapsedZone = collapsedFrame()
        expandedHoverZone = expandedFrame()
            .insetBy(dx: -collapseMargin, dy: -collapseMargin)
        zoneMinY = min(collapsedZone.minY, expandedHoverZone.minY)

        installMouseMonitors()
        installScreenObserver()
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func installScreenObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.handleScreensChanged() }
    }

    /// Re-pick the notched screen, refresh cached geometry, and snap the
    /// panel back into the correct spot for its current state. Without this,
    /// AppKit can reposition the borderless panel after a display
    /// connect/disconnect and the cached frames stay correct while the
    /// window drifts visually.
    private func handleScreensChanged() {
        guard let screen = Self.notchedScreen() else { return }
        screenFrame = screen.frame
        notchH = max(screen.safeAreaInsets.top, 32)
        notchW = Self.physicalNotchWidth(for: screen)

        collapsedZone = collapsedFrame()
        expandedHoverZone = expandedFrame()
            .insetBy(dx: -collapseMargin, dy: -collapseMargin)
        zoneMinY = min(collapsedZone.minY, expandedHoverZone.minY)

        let target = isExpanded ? expandedFrame() : collapsedFrame()
        panel?.setFrame(target, display: true)
    }

    private func installMouseMonitors() {
        guard globalMonitor == nil else { return }
        // Include drag events so expansion works while the user is dragging —
        // macOS sends *MouseDragged instead of mouseMoved while a button is held.
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask
        ) { [weak self] _ in self?.handleMouseMoved() }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.handleMouseMoved()
            return event
        }
    }

    private func handleMouseMoved() {
        let loc = NSEvent.mouseLocation

        // Coarse band reject: most mouse events happen far from the notch.
        if loc.y < zoneMinY {
            if isExpanded { scheduleCollapse() }
            return
        }

        if isExpanded {
            if expandedHoverZone.contains(loc) {
                cancelPendingCollapse()
            } else {
                scheduleCollapse()
            }
        } else if collapsedZone.contains(loc) {
            // If the user is dragging (any mouse button held) into the notch
            // AND the Tray module is enabled, force the Tray tab so they
            // have a drop target. Without the registry check the persisted
            // `selectedTabID` can point at a disabled module.
            if NSEvent.pressedMouseButtons != 0,
               ModuleRegistry.shared.isEnabled("tray") {
                state.selectedTabID = "tray"
            }
            expand()
        }
    }

    private func scheduleCollapse() {
        guard pendingCollapse == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingCollapse = nil
            guard self.isExpanded else { return }
            if !self.expandedHoverZone.contains(NSEvent.mouseLocation) {
                self.collapse()
            }
        }
        pendingCollapse = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + collapseDelay, execute: item
        )
    }

    private func cancelPendingCollapse() {
        pendingCollapse?.cancel()
        pendingCollapse = nil
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
