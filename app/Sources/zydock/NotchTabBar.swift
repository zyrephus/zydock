import SwiftUI

struct NotchTabBar: View {
    @Binding var selected: Int
    var itemSize: CGFloat
    @Namespace private var ns

    private let icons: [String] = ["house.fill", "square.grid.2x2.fill"]
    private let spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(icons.indices, id: \.self) { i in
                tab(i)
            }
        }
    }

    private func tab(_ i: Int) -> some View {
        let isSelected = selected == i
        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selected = i
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .matchedGeometryEffect(id: "tabPill", in: ns)
                }
                Image(systemName: icons[i])
                    .font(.system(size: 11, weight: .semibold))
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
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}
