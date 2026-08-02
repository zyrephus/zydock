import Foundation

/// Tab the notch opens on. Empty means "whichever tab was last used".
enum DefaultTab {
    static let key = "defaultTabID"
    /// The configured tab, or nil when unset or no longer available.
    static func resolved() -> String? {
        let id = UserDefaults.standard.string(forKey: key) ?? ""
        return ModuleRegistry.shared.tabs.contains { $0.id == id } ? id : nil
    }
}

struct TabInfo: Identifiable {
    let id: String
    let title: String
    let icon: String
}

protocol Module {
    var id: String { get }
    var title: String { get }
    var icon: String { get }
    var defaultEnabled: Bool { get }
}
