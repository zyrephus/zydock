import SwiftUI

enum PeekKind: Equatable {
    case nowPlaying
}

final class NotchState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var selectedTabID: String = "home"
    /// Transient event surfaced as a small sliver under the collapsed notch.
    @Published var peek: PeekKind?
}
