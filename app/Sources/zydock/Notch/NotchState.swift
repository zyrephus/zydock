import SwiftUI

final class NotchState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var selectedTabID: String = "home"
}
