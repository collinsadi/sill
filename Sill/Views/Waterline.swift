import SwiftUI

/// The line under the capture field, and the app's only waiting indicator.
///
/// While the model is working a meniscus forms in the line and travels along it. Not a
/// spinner: the identity is liquid, so waiting looks like surface tension moving. The text
/// is already committed behind this, so the motion is informative rather than blocking.
struct Waterline: View {
    var phase: IntelligenceBridge.Phase

    private var active: Bool { phase != .idle }

    var body: some View {
        TimelineView(.animation(minimumInterval: active ? nil : 1, paused: !active)) { timeline in
            Canvas { ctx, size in
                let y = size.height / 2
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(line, with: .color(Tokens.hairline), lineWidth: 1)

                guard active else { return }
                // One cycle every 2.4 seconds, matching the sill/breathe token. Linear, and
                // never given a spring.
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                let cx = size.width * t
                let w: CGFloat = 44
                let h: CGFloat = phase == .streaming ? 5 : 3.5

                var bump = Path()
                bump.move(to: CGPoint(x: cx - w / 2, y: y))
                bump.addCurve(to: CGPoint(x: cx, y: y - h),
                              control1: CGPoint(x: cx - w / 4, y: y),
                              control2: CGPoint(x: cx - w / 4, y: y - h))
                bump.addCurve(to: CGPoint(x: cx + w / 2, y: y),
                              control1: CGPoint(x: cx + w / 4, y: y - h),
                              control2: CGPoint(x: cx + w / 4, y: y))
                ctx.stroke(bump, with: .color(Tokens.accent), style: .init(lineWidth: 1, lineCap: .round))
            }
        }
        .frame(height: 8)
    }
}
