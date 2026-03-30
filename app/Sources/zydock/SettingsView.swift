import SwiftUI
import AppKit
import Carbon

struct SettingsView: View {
    @State private var currentKeyCode: UInt32 = HotkeyManager.defaultKeyCode
    @State private var currentModifiers: UInt32 = HotkeyManager.defaultModifiers
    @State private var conflicts: [String] = []
    @State private var shortcutDisplay: String = ""

    var body: some View {
        Form {
            Section("Keyboard Shortcut") {
                HStack {
                    Text("Toggle notch:")
                    ShortcutRecorderView(
                        currentDisplay: shortcutDisplay,
                        onRecord: { keyCode, modifiers in
                            let newConflicts = HotkeyManager.shared.register(keyCode: keyCode, modifiers: modifiers)
                            currentKeyCode = keyCode
                            currentModifiers = modifiers
                            conflicts = newConflicts
                            shortcutDisplay = HotkeyManager.displayString(keyCode: keyCode, modifiers: modifiers)
                        }
                    )
                    .frame(width: 140, height: 28)
                }

                if !conflicts.isEmpty {
                    Label("Conflicts with: \(conflicts.joined(separator: ", "))", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }

                Text("Only detects macOS system shortcut conflicts, not third-party apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380, height: 160)
        .onAppear { loadCurrentShortcut() }
    }

    private func loadCurrentShortcut() {
        let kc = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let mod = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        currentKeyCode = kc != 0 ? UInt32(kc) : HotkeyManager.defaultKeyCode
        currentModifiers = mod != 0 ? UInt32(mod) : HotkeyManager.defaultModifiers
        shortcutDisplay = HotkeyManager.displayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }
}

// MARK: - Shortcut Recorder

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

class ShortcutRecorderNSView: NSView {
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
        displayString = "Press shortcut..."
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
        let bg: NSColor = isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor
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
