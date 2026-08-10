import SwiftUI

/// Motion tokens, generated from the Figma `Motion` collection.
///
/// Named by behaviour, never by number. `response` and `dampingFraction` are what SwiftUI
/// consumes, so they are the tokens; the millisecond figures are documentation and the
/// morph timeline. One exception: `sillBreathe` is linear and must never be given a spring.
enum Motion {

    struct Spring {
        let response: Double
        let dampingFraction: Double
        /// Nominal duration in seconds. Used to sequence the morph timeline, not to drive it.
        let duration: Double

        var animation: Animation { .spring(response: response, dampingFraction: dampingFraction) }
    }

    /// The bead swells in place. Nothing detaches and nothing moves.
    static let morphBulge   = Spring(response: 0.28, dampingFraction: 0.72, duration: 0.140)
    /// A neck thins between bead and drop. Looser damping so it overshoots INTO the pinch.
    static let morphNeck    = Spring(response: 0.32, dampingFraction: 0.62, duration: 0.180)
    /// Pinch off. Fastest and least damped: surface tension releases, it does not decelerate.
    static let morphDetach  = Spring(response: 0.22, dampingFraction: 0.55, duration: 0.120)
    /// The drop lands and resolves into the panel.
    static let settleSoft   = Spring(response: 0.48, dampingFraction: 0.78, duration: 0.420)
    /// Going home. Nearly critically damped: bouncing on the way back is where cute turns
    /// into annoying. The return is not a performance.
    static let retractSwallow = Spring(response: 0.34, dampingFraction: 0.92, duration: 0.260)
    static let rowComplete  = Spring(response: 0.36, dampingFraction: 0.70, duration: 0.320)
    static let hoverLift    = Spring(response: 0.16, dampingFraction: 0.95, duration: 0.090)
    static let sillExtend   = Spring(response: 0.40, dampingFraction: 0.85, duration: 0.300)

    /// A timer is running. LINEAR, not a spring.
    static let sillBreathe: Animation = .linear(duration: 2.4).repeatForever(autoreverses: false)

    /// Total wall clock of the open sequence: bulge, neck, detach, settle.
    static var openDuration: Double {
        morphBulge.duration + morphNeck.duration + morphDetach.duration + settleSoft.duration
    }

    /// Reduce Motion is not optional. The morph IS the product, so when it is off the panel
    /// must still arrive, just without the liquid.
    static func open(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : settleSoft.animation
    }

    static func close(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : retractSwallow.animation
    }
}

extension Motion.Spring {
    /// Analytic value of a unit step response at time `t`, matching SwiftUI's
    /// `.spring(response:dampingFraction:)`. We evaluate this ourselves because Canvas does
    /// not interpolate a value animated by `withAnimation`: its closure only re-runs when the
    /// body re-evaluates, which produced four frames for the whole morph.
    func value(at t: Double) -> Double {
        guard t > 0 else { return 0 }
        let omega0 = 2 * Double.pi / response
        let zeta = dampingFraction

        if zeta < 1 {
            let omegaD = omega0 * (1 - zeta * zeta).squareRoot()
            let decay = exp(-zeta * omega0 * t)
            return 1 - decay * (cos(omegaD * t) + (zeta * omega0 / omegaD) * sin(omegaD * t))
        }
        // Critically damped and above. No overshoot, which is what retract/swallow wants.
        let decay = exp(-omega0 * t)
        return 1 - decay * (1 + omega0 * t)
    }

    /// Time after which the spring is within 0.1 percent of its target.
    var settleTime: Double {
        let omega0 = 2 * Double.pi / response
        return min(4.0, 7.0 / (dampingFraction * omega0))
    }
}

/// The open sequence as a function of elapsed time.
///
/// Four chained springs, each retargeting from wherever the previous one handed off, which is
/// what `withAnimation` does when it interrupts an in flight animation. Handoff values are
/// computed rather than assumed, so a spring that has not finished ringing does not snap.
enum MorphTimeline {
    struct Segment { let spring: Motion.Spring; let target: Double }

    static var open: [Segment] {
        [Segment(spring: Motion.morphBulge,  target: Morph.bulgeEnd),
         Segment(spring: Motion.morphNeck,   target: Morph.neckEnd),
         Segment(spring: Motion.morphDetach, target: Morph.detachEnd),
         Segment(spring: Motion.settleSoft,  target: 1.0)]
    }

    /// Handoff points: the first three segments hand over at their nominal duration, the last
    /// runs until it has settled.
    static var totalDuration: Double {
        let segs = open
        let chained = segs.dropLast().reduce(0) { $0 + $1.spring.duration }
        return chained + segs[segs.count - 1].spring.settleTime
    }

    static func openProgress(at t: Double) -> Double {
        var from = 0.0
        var clock = 0.0
        let segs = open
        for (i, seg) in segs.enumerated() {
            let isLast = i == segs.count - 1
            let span = isLast ? seg.spring.settleTime : seg.spring.duration
            if t < clock + span || isLast {
                let local = min(t - clock, span)
                return from + (seg.target - from) * seg.spring.value(at: local)
            }
            from += (seg.target - from) * seg.spring.value(at: span)
            clock += span
        }
        return 1
    }

    static func closeProgress(from start: Double, at t: Double) -> Double {
        start * (1 - Motion.retractSwallow.value(at: t))
    }

    static var closeDuration: Double { Motion.retractSwallow.settleTime }
}
