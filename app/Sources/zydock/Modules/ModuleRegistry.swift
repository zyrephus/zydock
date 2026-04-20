import Foundation
import Combine

final class ModuleRegistry: ObservableObject {
    static let shared = ModuleRegistry()

    let all: [Module]
    @Published private(set) var enabledIDs: Set<String>

    private let defaults = UserDefaults.standard

    private init() {
        let modules: [Module] = [
            ClaudeCodeModule()
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

    private static func key(for id: String) -> String {
        "module.\(id).enabled"
    }
}
