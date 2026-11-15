import SwiftUI

enum PeekKind: Equatable {
    case nowPlaying
}

final class NotchState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var selectedTabID: String = "home"
    /// Transient event surfaced as a small sliver under the collapsed notch.
    @Published var peek: PeekKind?
    /// A drag is over the notch and the Tray module can take it.
    @Published var isTrayDropTargeted = false
    /// A file drag is in progress near the notch.
    @Published var isFileDragging = false

    var expandedSize: CGSize {
        selectedTabID == "tray" && ModuleRegistry.shared.isEnabled("tray")
            ? Layout.trayExpandedSize
            : Layout.expandedSize
    }
}
