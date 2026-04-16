import SwiftUI

struct TabContentView: View {
    var selectedTab: Int

    var body: some View {
        ZStack {
            switch selectedTab {
            case 0:
                placeholder(title: "Home")
                    .transition(transition)
            default:
                placeholder(title: "Tab 2")
                    .transition(transition)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: selectedTab)
    }

    private var transition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.98))
    }

    private func placeholder(title: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
