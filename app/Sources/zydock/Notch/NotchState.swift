import SwiftUI

final class NotchState: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var selectedTab: Int = 0
}
