import SwiftUI

/// The single source of the app's outline.
///
/// Both the drawn shape and the window's hit mask are generated from this, so the clickable
/// region can never drift from the visible one. A transparent panel where those two disagree
/// is maddening to use and close to impossible to diagnose from a bug report.
enum Silhouette {

    struct Geometry {
        var hostWidth: CGFloat
        var hostHeight: CGFloat
        var panelWidth: CGFloat
        var panelHeight: CGFloat
        /// Notch corner radius. Reused for every outer corner and does not grow with the panel.
        var hardwareRadius: CGFloat
        /// False on a Mac with no notch. The host is then a floating pill rather than a
        /// hole in the bezel, which changes both its shape and where it sits.
        var isNotched: Bool = true
        /// Distance from the top of the window down to the host. Zero when notched, because
        /// the notch IS the top. On a flat display the pill hangs below the menu bar.
        var hostTop: CGFloat = 0
        /// The cove where the notch wall meets the panel shoulder. A transition, not a corner,
        /// so it is not bound by the corners-do-not-grow rule.
        var meniscusRadius: CGFloat = 20
    }

    /// Collapsed: the bead sitting in the notch. Its background is the bezel, which is the one
    /// background we know for certain, so it needs no edge treatment at all.
    static func collapsed(in rect: CGRect, g: Geometry) -> Path {
        let w = g.hostWidth
        let h = g.hostHeight
        let x = rect.midX - w / 2
        var p = Path()
        p.move(to: CGPoint(x: x, y: 0))
        p.addLine(to: CGPoint(x: x + w, y: 0))
        p.addLine(to: CGPoint(x: x + w, y: h - g.hardwareRadius))
        p.addArc(tangent1End: CGPoint(x: x + w, y: h),
                 tangent2End: CGPoint(x: x + w - g.hardwareRadius, y: h),
                 radius: g.hardwareRadius)
        p.addLine(to: CGPoint(x: x + g.hardwareRadius, y: h))
        p.addArc(tangent1End: CGPoint(x: x, y: h),
                 tangent2End: CGPoint(x: x, y: h - g.hardwareRadius),
                 radius: g.hardwareRadius)
        p.closeSubpath()
        return p
    }

    /// Expanded: the notch extended. One continuous mass, not a panel placed near a notch.
    static func expanded(in rect: CGRect, g: Geometry) -> Path {
        let pw = g.panelWidth
        let ph = g.panelHeight
        let nh = g.hostHeight
        let r = g.hardwareRadius
        let c = g.meniscusRadius

        let left = rect.midX - pw / 2
        let right = left + pw
        let notchLeft = rect.midX - g.hostWidth / 2
        let notchRight = rect.midX + g.hostWidth / 2
        let bottom = ph

        var p = Path()
        // Notch block
        p.move(to: CGPoint(x: notchLeft, y: 0))
        p.addLine(to: CGPoint(x: notchRight, y: 0))
        p.addLine(to: CGPoint(x: notchRight, y: nh - c))
        // Right cove: curves outward into the empty corner, adding material.
        p.addArc(center: CGPoint(x: notchRight + c, y: nh - c),
                 radius: c, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
        p.addLine(to: CGPoint(x: right - r, y: nh))
        p.addArc(tangent1End: CGPoint(x: right, y: nh),
                 tangent2End: CGPoint(x: right, y: nh + r),
                 radius: r)
        p.addLine(to: CGPoint(x: right, y: bottom - r))
        p.addArc(tangent1End: CGPoint(x: right, y: bottom),
                 tangent2End: CGPoint(x: right - r, y: bottom),
                 radius: r)
        p.addLine(to: CGPoint(x: left + r, y: bottom))
        p.addArc(tangent1End: CGPoint(x: left, y: bottom),
                 tangent2End: CGPoint(x: left, y: bottom - r),
                 radius: r)
        p.addLine(to: CGPoint(x: left, y: nh + r))
        p.addArc(tangent1End: CGPoint(x: left, y: nh),
                 tangent2End: CGPoint(x: left + r, y: nh),
                 radius: r)
        p.addLine(to: CGPoint(x: notchLeft - c, y: nh))
        // Left cove, mirrored.
        p.addArc(center: CGPoint(x: notchLeft - c, y: nh - c),
                 radius: c, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()
        return p
    }

    static func path(expanded isExpanded: Bool, in rect: CGRect, g: Geometry) -> Path {
        isExpanded ? expanded(in: rect, g: g) : collapsed(in: rect, g: g)
    }
}

/// SwiftUI wrapper so the same geometry drives the drawing.
struct SilhouetteShape: Shape {
    var isExpanded: Bool
    var geometry: Silhouette.Geometry

    func path(in rect: CGRect) -> Path {
        Silhouette.path(expanded: isExpanded, in: rect, g: geometry)
    }
}
