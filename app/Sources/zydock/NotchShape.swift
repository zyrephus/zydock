import SwiftUI

/// Notch silhouette: flat top edge flush with the screen, concave arcs at the
/// top corners that flare outward (mimicking the hardware notch), and convex
/// rounded corners at the bottom.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat = Layout.shapeInset
    var bottomCornerRadius: CGFloat = Layout.bottomCornerRadius

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = topCornerRadius
        let br = bottomCornerRadius
        let w = rect.width
        let h = rect.height

        p.move(to: CGPoint(x: 0, y: 0))
        p.addQuadCurve(
            to: CGPoint(x: tr, y: tr),
            control: CGPoint(x: tr, y: 0)
        )
        p.addLine(to: CGPoint(x: tr, y: h - br))
        p.addQuadCurve(
            to: CGPoint(x: tr + br, y: h),
            control: CGPoint(x: tr, y: h)
        )
        p.addLine(to: CGPoint(x: w - tr - br, y: h))
        p.addQuadCurve(
            to: CGPoint(x: w - tr, y: h - br),
            control: CGPoint(x: w - tr, y: h)
        )
        p.addLine(to: CGPoint(x: w - tr, y: tr))
        p.addQuadCurve(
            to: CGPoint(x: w, y: 0),
            control: CGPoint(x: w - tr, y: 0)
        )
        p.closeSubpath()
        return p
    }
}
