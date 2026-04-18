import SwiftUI
import AppKit
import Carbon

struct ShortcutRecorderView: NSViewRepresentable {
    var currentDisplay: String
    var onRecord: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.displayString = currentDisplay
        view.onRecord = onRecord
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.displayString = currentDisplay
    }
}

final class ShortcutRecorderNSView: NSView {
    var displayString: String = "" {
        didSet { needsDisplay = true }
    }
    var onRecord: ((UInt32, UInt32) -> Void)?
    private var isRecording = false
    private var previousDisplay: String = ""

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        previousDisplay = displayString
        isRecording = true
        needsDisplay = true
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        if event.keyCode == 53 { // Escape — cancel
            isRecording = false
            displayString = previousDisplay
            return
        }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard mods.contains(.command) || mods.contains(.option) || mods.contains(.control) else {
            return
        }

        let carbonMods = HotkeyManager.carbonModifiers(from: mods)
        isRecording = false
        onRecord?(UInt32(event.keyCode), carbonMods)
    }

    override func draw(_ dirtyRect: NSRect) {
        let bg: NSColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.15)
            : NSColor.controlBackgroundColor
        bg.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6)
        path.fill()

        if isRecording {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let text = isRecording ? "Press shortcut..." : displayString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: isRecording ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let point = NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        (text as NSString).draw(at: point, withAttributes: attrs)
    }
}
