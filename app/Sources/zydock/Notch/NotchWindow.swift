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
    /// Area around the closed notch where a file drag opens it.
    private var dragZone: NSRect = .zero
    private let dragApproach: CGFloat = 40
    /// Drag pasteboard change count at the last mouse-down. A different
    /// count while the button is held means a file drag is in progress,
    /// as opposed to a window drag or a text selection.
    private var dragChangeCountAtMouseDown = 0
    /// Lowest y the cursor can have while still being inside either zone.
    /// Used as a single-compare early-out to reject events far from the top.
    private var zoneMinY: CGFloat = 0

    func show() {
        guard let screen = Self.notchedScreen() else { return }
        screenFrame = screen.frame
        notchH = max(screen.safeAreaInsets.top, 32)
        notchW = Self.physicalNotchWidth(for: screen)

        let frame = panelFrame(collapsedFrame())

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

        updateHoverZones()

        installMouseMonitors()
        installScreenObserver()

        state.$peek
            .removeDuplicates()
            .sink { [weak self] peek in self?.handlePeekChange(peek) }
            .store(in: &cancellables)

        // The expanded size depends on the tab; hop to the next main-queue
        // turn so the zones read the tab after it is set.
        state.$selectedTabID
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateHoverZones() }
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

        updateHoverZones()

        let target: NSRect
        if isExpanded {
            target = expandedPanelFrame()
        } else if state.peek != nil {
            target = panelFrame(peekFrame())
        } else {
            target = panelFrame(collapsedFrame())
        }
        panel?.setFrame(target, display: true)
    }

    private func installMouseMonitors() {
        guard globalMonitor == nil else { return }
        // Include drag events so expansion works while the user is dragging —
        // macOS sends *MouseDragged instead of mouseMoved while a button is held.
        let mask: NSEvent.EventTypeMask = [
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged, .leftMouseDown
        ]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask
        ) { [weak self] event in self?.handleMouseEvent(event) }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.handleMouseEvent(event)
            return event
        }
    }

    private func handleMouseEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown {
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
        } else {
            handleMouseMoved()
        }
    }

    /// Cleared by the first plain mouse move after the drag, which comes
    /// after the drop has been delivered.
    private func setFileDragging(_ dragging: Bool) {
        if state.isFileDragging != dragging { state.isFileDragging = dragging }
    }

    private var isFileDragActive: Bool {
        NSEvent.pressedMouseButtons & 1 != 0
            && NSPasteboard(name: .drag).changeCount != dragChangeCountAtMouseDown
    }

    private func handleMouseMoved() {
        let loc = NSEvent.mouseLocation

        // Coarse band reject: most mouse events happen far from the notch.
        if loc.y < zoneMinY {
            if isExpanded { scheduleCollapse() }
            return
        }

        let fileDrag = isFileDragActive
        setFileDragging(fileDrag)

        if isExpanded {
            if expandedHoverZone.contains(loc) {
                cancelPendingCollapse()
            } else {
                scheduleCollapse()
            }
        } else if collapsedZone.contains(loc)
                    || (state.peek != nil && peekFrame().contains(loc)) {
            expand()
            if fileDrag { openTrayForDrag() }
        } else if dragZone.contains(loc), fileDrag,
                  ModuleRegistry.shared.isEnabled("tray") {
            expand()
            openTrayForDrag()
        }
    }

    /// The registry check keeps the persisted tab off a disabled module.
    private func openTrayForDrag() {
        if ModuleRegistry.shared.isEnabled("tray") {
            state.selectedTabID = "tray"
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

    private func expandedFrame(_ size: CGSize) -> NSRect {
        NSRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - notchH - size.height,
            width: size.width,
            height: notchH + size.height
        )
    }

    /// The panel takes the largest tab's rect; the shape animates between
    /// tab sizes inside it.
    private func expandedPanelFrame() -> NSRect {
        expandedFrame(Layout.trayExpandedSize)
    }

    private func updateHoverZones() {
        collapsedZone = collapsedFrame()
        expandedHoverZone = expandedFrame(state.expandedSize)
            .insetBy(dx: -collapseMargin, dy: -collapseMargin)
        dragZone = collapsedZone.insetBy(dx: -dragApproach, dy: -dragApproach)
        zoneMinY = min(collapsedZone.minY, expandedHoverZone.minY, dragZone.minY)
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

    /// Panel rect for a closed-state shape rect. The transparent side margins
    /// give the skip bump and its spring overshoot room to draw.
    private func panelFrame(_ shape: NSRect) -> NSRect {
        shape.insetBy(dx: -Layout.skipBumpWidth, dy: 0)
    }

    /// Grow the window for the peek sliver (instant — the extra area is
    /// transparent until SwiftUI animates the shape into it).
    private func handlePeekChange(_ peek: PeekKind?) {
        guard !isExpanded else { return }
        if peek != nil {
            pendingFrameShrink?.cancel()
            pendingFrameShrink = nil
            panel?.setFrame(panelFrame(peekFrame()), display: true)
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
        if let tab = DefaultTab.resolved() {
            state.selectedTabID = tab
        }
        pendingFrameShrink?.cancel()
        pendingFrameShrink = nil
        panel?.setFrame(expandedPanelFrame(), display: true)
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
            self.panel?.setFrame(self.panelFrame(self.collapsedFrame()), display: true)
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
        let ids = ModuleRegistry.shared.tabs.map(\.id)
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
