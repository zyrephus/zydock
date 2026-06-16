import AppKit
import Carbon
import Combine
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
    private var pendingFrameShrink: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
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
            expandedWidth: expandedW,
            expandedHeight: expandedH,
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

        state.$peek
            .removeDuplicates()
            .sink { [weak self] peek in self?.handlePeekChange(peek) }
            .store(in: &cancellables)
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

        let target: NSRect
        if isExpanded {
            target = expandedFrame()
        } else if state.peek != nil {
            target = peekFrame()
        } else {
            target = collapsedFrame()
        }
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
        } else if collapsedZone.contains(loc)
                    || (state.peek != nil && peekFrame().contains(loc)) {
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

    private func peekFrame() -> NSRect {
        let w = notchW + earExtension * 2
        return NSRect(
            x: screenFrame.midX - w / 2,
            y: screenFrame.maxY - notchH - Layout.peekHeight,
            width: w,
            height: notchH + Layout.peekHeight
        )
    }

    /// Grow the window for the peek sliver (instant — the extra area is
    /// transparent until SwiftUI animates the shape into it).
    private func handlePeekChange(_ peek: PeekKind?) {
        guard !isExpanded else { return }
        if peek != nil {
            pendingFrameShrink?.cancel()
            pendingFrameShrink = nil
            panel?.setFrame(peekFrame(), display: true)
        } else {
            scheduleFrameShrink()
        }
    }

    // Animating the NSPanel frame re-layouts the hosting view every frame and
    // stutters. Instead the panel snaps to the expanded rect instantly (the
    // extra area is transparent, so nothing changes visually) and SwiftUI
    // animates the notch shape inside it. On collapse, the frame shrinks back
    // only after the shape animation has finished.
    private func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        pendingFrameShrink?.cancel()
        pendingFrameShrink = nil
        panel?.setFrame(expandedFrame(), display: true)
        state.peek = nil
        state.isExpanded = true
        registerTabHotkeys()
    }

    private func collapse() {
        guard isExpanded else { return }
        if pinned { return }
        isExpanded = false
        state.isExpanded = false
        unregisterTabHotkeys()
        scheduleFrameShrink()
    }

    /// Shrink the window back once the close animation has finished.
    private func scheduleFrameShrink() {
        pendingFrameShrink?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingFrameShrink = nil
            guard !self.isExpanded, self.state.peek == nil else { return }
            self.panel?.setFrame(self.collapsedFrame(), display: true)
        }
        pendingFrameShrink = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    // MARK: - Tab cycling hotkeys (only registered while expanded)

    private let nextTabHotkeyID: UInt32 = 100
    private let prevTabHotkeyID: UInt32 = 101
    private let tabKeyCode: UInt32 = 48

    private func registerTabHotkeys() {
        HotkeyManager.shared.registerExtra(
            id: nextTabHotkeyID,
            keyCode: tabKeyCode,
            modifiers: UInt32(controlKey)
        ) { [weak self] in self?.cycleTab(forward: true) }

        HotkeyManager.shared.registerExtra(
            id: prevTabHotkeyID,
            keyCode: tabKeyCode,
            modifiers: UInt32(controlKey | shiftKey)
        ) { [weak self] in self?.cycleTab(forward: false) }
    }

    private func unregisterTabHotkeys() {
        HotkeyManager.shared.unregisterExtra(id: nextTabHotkeyID)
        HotkeyManager.shared.unregisterExtra(id: prevTabHotkeyID)
    }

    private func cycleTab(forward: Bool) {
        let ids = ["home"] + ModuleRegistry.shared.enabled.map(\.id)
        guard !ids.isEmpty else { return }
        let idx = ids.firstIndex(of: state.selectedTabID) ?? 0
        let next = forward
            ? (idx + 1) % ids.count
            : (idx - 1 + ids.count) % ids.count
        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
            state.selectedTabID = ids[next]
        }
    }

    func togglePinned() {
        pinned.toggle()
        if pinned {
            if !isExpanded { expand() }
        } else {
            collapse()
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
