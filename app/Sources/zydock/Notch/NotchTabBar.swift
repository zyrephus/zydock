import SwiftUI

struct NotchTabBar: View {
    @Binding var selected: String
    var itemSize: CGFloat
    @ObservedObject var registry: ModuleRegistry = .shared
    @Namespace private var ns

    private let spacing: CGFloat = 4

    private var tabs: [(id: String, icon: String)] {
        [("home", "house.fill")] + registry.enabled.map { ($0.id, $0.icon) }
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(tabs, id: \.id) { t in
                tab(id: t.id, icon: t.icon)
            }
        }
    }

    private func tab(id: String, icon: String) -> some View {
        let isSelected = selected == id
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selected = id
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .padding(.vertical, 5)
                        .matchedGeometryEffect(id: "tabPill", in: ns)
                }
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? Color.white
                            : Color.white.opacity(0.45)
                    )
            }
            .frame(width: itemSize, height: itemSize)
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressStyle())
    }
}

struct NotchPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
