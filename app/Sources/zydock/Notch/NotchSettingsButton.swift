import SwiftUI
import AppKit

struct NotchSettingsButton: View {
    var size: CGFloat
    @State private var hovering = false

    var body: some View {
        Button {
            SettingsWindowController.shared.show()
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(hovering ? 0.95 : 0.7))
            .frame(width: size, height: size)
            .contentShape(Capsule())
        }
        .buttonStyle(NotchPressStyle())
        .onHover { entering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                hovering = entering
            }
        }
    }
}
