import SwiftUI

struct NotchTabBar: View {
    @Binding var selected: String
    var itemSize: CGFloat
    var appear: Bool = true
    @ObservedObject var registry: ModuleRegistry = .shared

    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(registry.tabs.enumerated()), id: \.element.id) { idx, t in
                tab(id: t.id, icon: t.icon)
                    .popIn(appear, order: idx)
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
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(
                    isSelected
                        ? Color.white
                        : Color.white.opacity(0.45)
                )
                .frame(width: itemSize, height: itemSize)
                .contentShape(Rectangle())
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
