import Carbon
import AppKit

class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private struct Extra {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }
    private var extras: [UInt32: Extra] = [:]

    private let keyCodeKey = "hotkeyKeyCode"
    private let modifiersKey = "hotkeyModifiers"

    static let defaultKeyCode: UInt32 = 49          // Space
    static let defaultModifiers: UInt32 = UInt32(optionKey)  // ⌥
    private static let toggleHotkeyID: UInt32 = 1

    func start() {
        register(keyCode: savedKeyCode(), modifiers: savedModifiers())
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> [String] {
        unregister()
        installEventHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: 0x5A59444B, id: HotkeyManager.toggleHotkeyID) // "ZYDK"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotkeyRef)

        UserDefaults.standard.set(Int(keyCode), forKey: keyCodeKey)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey)

        return checkConflicts(keyCode: keyCode, modifiers: modifiers)
    }

    func unregister() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
    }

    /// Register an additional hotkey identified by `id` (must not be 1).
    /// Re-registering the same id replaces the previous binding.
    func registerExtra(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        precondition(id != HotkeyManager.toggleHotkeyID, "id 1 reserved for toggle")
        unregisterExtra(id: id)
        installEventHandlerIfNeeded()

        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: 0x5A59444B, id: id)
        RegisterEventHotKey(keyCode, modifiers, hkID, GetApplicationEventTarget(), 0, &ref)
        if let ref = ref {
            extras[id] = Extra(ref: ref, handler: handler)
        }
    }

    func unregisterExtra(id: UInt32) {
        if let extra = extras.removeValue(forKey: id) {
            UnregisterEventHotKey(extra.ref)
        }
    }

    // MARK: - Conflict Detection

    func checkConflicts(keyCode: UInt32, modifiers: UInt32) -> [String] {
        var cfArray: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&cfArray) == noErr,
              let hotkeys = cfArray?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }

        var conflicts: [String] = []
        for entry in hotkeys {
            guard let enabled = entry[kHISymbolicHotKeyEnabled as String] as? Bool, enabled,
                  let code = entry[kHISymbolicHotKeyCode as String] as? Int,
                  let mods = entry[kHISymbolicHotKeyModifiers as String] as? Int else {
                continue
            }
            if code == Int(keyCode) && mods == Int(modifiers) {
                conflicts.append("macOS system shortcut (key \(code))")
            }
        }
        return conflicts
    }

    // MARK: - Private

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let userData = userData, let eventRef = eventRef else {
                    return OSStatus(eventNotHandledErr)
                }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard status == noErr else { return OSStatus(eventNotHandledErr) }
                DispatchQueue.main.async {
                    if hkID.id == HotkeyManager.toggleHotkeyID {
                        manager.onTrigger?()
                    } else if let extra = manager.extras[hkID.id] {
                        extra.handler()
                    }
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPtr,
            &eventHandlerRef
        )
    }

    private func savedKeyCode() -> UInt32 {
        let val = UserDefaults.standard.integer(forKey: keyCodeKey)
        return val != 0 ? UInt32(val) : HotkeyManager.defaultKeyCode
    }

    private func savedModifiers() -> UInt32 {
        let val = UserDefaults.standard.integer(forKey: modifiersKey)
        return val != 0 ? UInt32(val) : HotkeyManager.defaultModifiers
    }

    // MARK: - Helpers

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option)  { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift)   { carbon |= UInt32(shiftKey) }
        return carbon
    }

    static func cocoaModifiers(from carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(cmdKey) != 0     { flags.insert(.command) }
        if carbon & UInt32(optionKey) != 0  { flags.insert(.option) }
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(shiftKey) != 0   { flags.insert(.shift) }
        return flags
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let flags = cocoaModifiers(from: modifiers)
        var parts: [String] = []
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option)  { parts.append("⌥") }
        if flags.contains(.shift)   { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }

        let keyNames: [UInt32: String] = [
            49: "Space", 36: "↩", 53: "⎋", 51: "⌫", 48: "⇥",
            126: "↑", 125: "↓", 123: "←", 124: "→",
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F",
            5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
            46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R",
            1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X",
            16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4",
            23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
            103: "F11", 111: "F12",
        ]
        parts.append(keyNames[keyCode] ?? "Key\(keyCode)")

        return parts.joined()
    }
}
