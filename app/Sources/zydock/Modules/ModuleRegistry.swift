import Foundation
import Combine

final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    let all: [Module]
    @Published private(set) var enabledIDs: Set<String>

    private let defaults = UserDefaults.standard

    private init() {
        let modules: [Module] = [
            TrayModule(),
            ClaudeCodeModule(),
            SystemModule()
        ]
        self.all = modules

        var ids = Set<String>()
        for m in modules {
            let key = Self.key(for: m.id)
            if defaults.object(forKey: key) == nil {
                if m.defaultEnabled { ids.insert(m.id) }
            } else if defaults.bool(forKey: key) {
                ids.insert(m.id)
            }
        }
        self.enabledIDs = ids
    }

    func isEnabled(_ id: String) -> Bool {
        enabledIDs.contains(id)
    }

    func setEnabled(_ id: String, _ value: Bool) {
        defaults.set(value, forKey: Self.key(for: id))
        if value {
            enabledIDs.insert(id)
        } else {
            enabledIDs.remove(id)
        }
    }

    var enabled: [Module] {
        all.filter { enabledIDs.contains($0.id) }
    }

    /// Every tab currently reachable in the expanded notch, in bar order.
    /// Home is always present; the rest come from the enabled modules.
    var tabs: [TabInfo] {
        [TabInfo(id: "home", title: "Home", icon: "house.fill")]
            + enabled.map { TabInfo(id: $0.id, title: $0.title, icon: $0.icon) }
    }

    private static func key(for id: String) -> String {
        "module.\(id).enabled"
    }
}
