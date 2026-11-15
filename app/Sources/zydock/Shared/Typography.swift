import SwiftUI

enum Typography {
    static let primary: CGFloat = 12
    static let secondary: CGFloat = 10
    static let icon: CGFloat = 8
}

enum Layout {
    /// Shape's vertical sides are inset this far from the window edge (= NotchShape.topCornerRadius).
    static let shapeInset: CGFloat = 14
    /// Convex rounding on the bottom corners (collapsed).
    static let bottomCornerRadius: CGFloat = 12
    /// Convex rounding on the bottom corners (expanded).
    static let expandedBottomCornerRadius: CGFloat = 24
    /// Desired visual padding between the shape edge and content.
    static let contentPadding: CGFloat = 20
    /// Window-relative horizontal padding = shapeInset + contentPadding.
    static let horizontalPadding: CGFloat = shapeInset + contentPadding
    /// Small inward nudge applied to ear components so they don't sit too far outward.
    static let earInwardNudge: CGFloat = 1
    /// Height of the transient peek sliver below the collapsed notch.
    static let peekHeight: CGFloat = 30
    /// Extra width the collapsed notch springs out to on a track change or play/pause.
    static let skipBumpWidth: CGFloat = 24
    /// Expanded content area below the notch.
    static let expandedSize = CGSize(width: 550, height: 150)
    /// Expanded content area on the Tray tab: two rows of six cells.
    static let trayExpandedSize = CGSize(width: 640, height: 240)
    /// Distance below the hardware notch over which black fades into the glass panel.
    static let glassFadeHeight: CGFloat = 56
}

/// Tint of the glass panel below the notch.
enum GlassTint: String, CaseIterable, Identifiable {
    case black, blue, purple, pink, red, orange, yellow, green, teal

    static let key = "glassTint"

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .black: return .black
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .teal: return .teal
        }
    }
}

// MARK: - Staggered pop-in

extension View {
    /// Bouncy, staggered entrance keyed on `visible`. Each sibling gets a
    /// different `order` so they spring in one after another rather than all
    /// fading together. Collapse is a quick fade with no bounce so content
    /// clears before the notch shape shrinks over it.
    func popIn(_ visible: Bool, order: Int = 0) -> some View {
        modifier(PopIn(visible: visible, order: order))
    }
}

private struct PopIn: ViewModifier {
    let visible: Bool
    let order: Int

    func body(content: Content) -> some View {
        content
            .scaleEffect(visible ? 1 : 0.5, anchor: .center)
            .opacity(visible ? 1 : 0)
            .blur(radius: visible ? 0 : 12)
            .animation(animation, value: visible)
    }

    private var animation: Animation {
        visible
            ? .spring(response: 0.36, dampingFraction: 0.56)
                .delay(0.05 + Double(order) * 0.045)
            : .easeIn(duration: 0.12)
    }
}
