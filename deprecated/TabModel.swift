import Foundation
import Combine

enum Tab: String, CaseIterable, Identifiable {
    case home
    case tray
    case sessions

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:     return "house.fill"
        case .tray:     return "tray.full.fill"
        case .sessions: return "terminal.fill"
        }
    }
}

class TabState: ObservableObject {
    @Published var activeTab: Tab = .home
    @Published var visibleTabs: [Tab] = [.home, .tray]

    private var cancellable: AnyCancellable?

    init() {
        recomputeTabs()
        cancellable = NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recomputeTabs() }
    }

    private func recomputeTabs() {
        var tabs: [Tab] = [.home, .tray]
        if UserDefaults.standard.bool(forKey: "widgetSessionsEnabled") {
            tabs.append(.sessions)
        }
        visibleTabs = tabs
        // If active tab was removed, go home
        if !visibleTabs.contains(activeTab) {
            activeTab = .home
        }
    }

    func selectNext() {
        let tabs = visibleTabs
        guard let idx = tabs.firstIndex(of: activeTab) else { return }
        let next = tabs.index(after: idx)
        activeTab = next < tabs.endIndex ? tabs[next] : tabs[0]
    }

    func selectPrevious() {
        let tabs = visibleTabs
        guard let idx = tabs.firstIndex(of: activeTab) else { return }
        if idx > tabs.startIndex {
            activeTab = tabs[tabs.index(before: idx)]
        } else {
            activeTab = tabs[tabs.index(before: tabs.endIndex)]
        }
    }
}
