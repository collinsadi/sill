import SwiftUI

/// The signature transition.
///
/// This is a real metaball, not five keyframes crossfaded. Two masses are drawn into one
/// compositing layer, blurred, then alpha thresholded. Blur spreads the alpha, the threshold
/// snaps it back to a hard edge, and the in between values become the neck. Fusion and
/// separation fall out of the physics rather than being drawn.
///
/// Consequence worth stating: the meniscus cove where the panel meets the notch is NOT
/// authored here. It is what the threshold produces where the two masses meet.
enum Morph {

    /// Where the drop is, as one continuous function of progress. Bead, bulge, neck, detach
    /// and settle are samples along this, not separate assets.
    struct DropGeometry {
        var width: CGFloat
        var height: CGFloat
        var centerY: CGFloat
        var cornerRadius: CGFloat
    }

    /// Segment boundaries in normalised progress, derived from the motion token durations
    /// so the timeline and the tokens can never drift apart.
    static var bulgeEnd: Double { Motion.morphBulge.duration / Motion.openDuration }
    static var neckEnd: Double { bulgeEnd + Motion.morphNeck.duration / Motion.openDuration }
    static var detachEnd: Double { neckEnd + Motion.morphDetach.duration / Motion.openDuration }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(max(0, min(1, t)))
    }

    private static func segment(_ p: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return p >= to ? 1 : 0 }
        return max(0, min(1, (p - from) / (to - from)))
    }

    /// Ease out so the drop decelerates into each stage rather than arriving linearly.
    private static func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    static func drop(progress p: Double, g: Silhouette.Geometry) -> DropGeometry {
        // Everything below is measured from the bottom of the host, wherever that is.
        let notchH = g.hostTop + g.hostHeight

        if p <= bulgeEnd {
            // Mass gathers and swells downward. Still one body with the bead.
            let t = easeOut(segment(p, 0, bulgeEnd))
            let h = lerp(2, 26, t)
            let w = lerp(g.hostWidth * 0.62, g.hostWidth * 0.80, t)
            return DropGeometry(width: w, height: h,
                                centerY: notchH - 2 + h / 2,
                                cornerRadius: h / 2)
        }

        if p <= neckEnd {
            // The drop pulls away and a neck thins. The threshold still fuses them.
            let t = easeOut(segment(p, bulgeEnd, neckEnd))
            let d = lerp(48, 66, t)
            return DropGeometry(width: d, height: d,
                                centerY: lerp(notchH + 12, notchH + 44, t),
                                cornerRadius: d / 2)
        }

        if p <= detachEnd {
            // Pinch off. The neck breaks and the drop falls free.
            let t = easeOut(segment(p, neckEnd, detachEnd))
            let d = lerp(66, 76, t)
            return DropGeometry(width: d, height: d,
                                centerY: lerp(notchH + 44, notchH + 74, t),
                                cornerRadius: d / 2)
        }

        // Settle. The circle grows into the panel. A rounded rect whose width, height and
        // corner all interpolate IS a circle at the start, so no crossfade is needed and
        // there is never a moment where two different shapes are blended.
        let t = easeOut(segment(p, detachEnd, 1))
        let finalH = g.panelHeight - notchH
        return DropGeometry(width: lerp(76, g.panelWidth, t),
                            height: lerp(76, finalH, t),
                            centerY: lerp(notchH + 74, notchH + finalH / 2, t),
                            cornerRadius: lerp(38, g.hardwareRadius, t))
    }

    /// Blur radius drives how long the neck survives before the threshold cuts it.
    /// Too small and the drop separates instantly with no neck at all.
    ///
    /// It has to scale with the host, though. A 22pt floating pill blurred by 11 loses so
    /// much alpha that the threshold erases it completely, which is exactly what happened
    /// the first time the flat display case was rendered.
    static func blurRadius(for g: Silhouette.Geometry) -> CGFloat {
        min(11, g.hostHeight * 0.34)
    }
    static let alphaThreshold: CGFloat = 0.55
}

/// Draws the two masses through the metaball filter chain.
struct MetaballCanvas: View {
    var progress: Double
    var geometry: Silhouette.Geometry
    var insetX: CGFloat
    /// Set by the profiler. Called once per Canvas draw, which is once per frame while animating.
    var onDraw: (() -> Void)?

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { ctx, size in
            onDraw?()

            // Order matters. Filters apply to subsequent drawing, innermost last: the layer
            // is blurred first, then the threshold snaps the soft alpha back to a hard edge.
            ctx.addFilter(.alphaThreshold(min: Morph.alphaThreshold, color: .black))
            ctx.addFilter(.blur(radius: Morph.blurRadius(for: geometry)))

            ctx.drawLayer { inner in
                let midX = insetX + geometry.panelWidth / 2

                // The host. On a notched Mac this is the bezel itself, extended upward past
                // the top of the window so it never shows an edge. On a flat display it is a
                // floating pill that has to define itself completely, with no hardware to
                // fuse with, which is the harder of the two cases.
                if geometry.isNotched {
                    let notch = CGRect(x: midX - geometry.hostWidth / 2,
                                       y: -geometry.hostHeight,
                                       width: geometry.hostWidth,
                                       height: geometry.hostHeight * 2)
                    inner.fill(Path(roundedRect: notch, cornerRadius: 0), with: .color(.black))
                } else {
                    let pill = CGRect(x: midX - geometry.hostWidth / 2,
                                      y: geometry.hostTop,
                                      width: geometry.hostWidth,
                                      height: geometry.hostHeight)
                    inner.fill(Path(roundedRect: pill, cornerRadius: geometry.hostHeight / 2),
                               with: .color(.black))
                }

                // The drop.
                let d = Morph.drop(progress: progress, g: geometry)
                if d.height > 0.5 {
                    let rect = CGRect(x: midX - d.width / 2,
                                      y: d.centerY - d.height / 2,
                                      width: d.width,
                                      height: d.height)
                    inner.fill(Path(roundedRect: rect, cornerRadius: d.cornerRadius),
                               with: .color(.black))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
