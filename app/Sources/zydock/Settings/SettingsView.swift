import SwiftUI
import AppKit
import Carbon

struct SettingsView: View {
    @State private var currentKeyCode: UInt32 = HotkeyManager.defaultKeyCode
    @State private var currentModifiers: UInt32 = HotkeyManager.defaultModifiers
    @State private var conflicts: [String] = []
    @State private var shortcutDisplay: String = ""
    @ObservedObject private var registry: ModuleRegistry = .shared

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

                    Button("Reset") {
                        let kc = HotkeyManager.defaultKeyCode
                        let mod = HotkeyManager.defaultModifiers
                        let newConflicts = HotkeyManager.shared.register(keyCode: kc, modifiers: mod)
                        currentKeyCode = kc
                        currentModifiers = mod
                        conflicts = newConflicts
                        shortcutDisplay = HotkeyManager.displayString(keyCode: kc, modifiers: mod)
                    }
                }

                if !conflicts.isEmpty {
                    Label("Conflicts with: \(conflicts.joined(separator: ", "))",
                          systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                }

                Text("Press the shortcut once to pin the notch open; press again to collapse. Only detects macOS system shortcut conflicts, not third-party apps.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Modules") {
                ForEach(registry.all, id: \.id) { module in
                    Toggle(module.title, isOn: binding(for: module))
                }
                Text("Disable modules you don't use. Their tabs and background work are fully stopped.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Quit zydock") {
                        NSApp.terminate(nil)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
        .onAppear { loadCurrentShortcut() }
    }

    private func binding(for module: Module) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(module.id) },
            set: { registry.setEnabled(module.id, $0) }
        )
    }

    private func loadCurrentShortcut() {
        let kc = UserDefaults.standard.integer(forKey: "hotkeyKeyCode")
        let mod = UserDefaults.standard.integer(forKey: "hotkeyModifiers")
        currentKeyCode = kc != 0 ? UInt32(kc) : HotkeyManager.defaultKeyCode
        currentModifiers = mod != 0 ? UInt32(mod) : HotkeyManager.defaultModifiers
        shortcutDisplay = HotkeyManager.displayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }
}
