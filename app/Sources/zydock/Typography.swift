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
}
