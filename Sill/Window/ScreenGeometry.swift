import AppKit

/// Everything the window layer needs to know about the display it is living on.
/// Nothing here is hardcoded: the notch is derived from the auxiliary areas the
/// system reports, and the no-notch case is a first class path rather than a fallback.
struct HostMetrics: Equatable, Sendable {
    /// True when the display actually has a notch.
    var isNotched: Bool
    /// Width of the notch itself, or the resting width of the floating pill on a flat display.
    var hostWidth: CGFloat
    /// Height of the notch, or of the resting pill.
    var hostHeight: CGFloat
    /// Horizontal centre of the host, in screen coordinates.
    var hostCenterX: CGFloat
    /// Top edge of the display, in screen coordinates.
    var screenTopY: CGFloat
    var screenFrame: CGRect

    /// The notch's own corner radius, which the design reuses for every outer corner of the
    /// panel and which deliberately does not grow as the panel extends.
    var hardwareCornerRadius: CGFloat { isNotched ? 9 : 11 }

    static let fallbackPillWidth: CGFloat = 132
    static let fallbackPillHeight: CGFloat = 22
}

enum ScreenGeometry {
    /// The screen carrying the menu bar. Falls back to main, then to any screen.
    static var hostScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main ?? NSScreen.screens.first
    }

    static func metrics(for screen: NSScreen) -> HostMetrics {
        let frame = screen.frame

        // The notch is the gap between the two auxiliary areas. When either is nil the
        // display has no notch and we switch to the floating pill geometry.
        if let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            let width = right.minX - left.maxX
            return HostMetrics(
                isNotched: true,
                hostWidth: width,
                hostHeight: left.height,
                hostCenterX: left.maxX + width / 2,
                screenTopY: frame.maxY,
                screenFrame: frame
            )
        }

        return HostMetrics(
            isNotched: false,
            hostWidth: HostMetrics.fallbackPillWidth,
            hostHeight: HostMetrics.fallbackPillHeight,
            hostCenterX: frame.midX,
            screenTopY: frame.maxY,
            screenFrame: frame
        )
    }

    static func currentMetrics() -> HostMetrics? {
        guard let screen = hostScreen else { return nil }
        return metrics(for: screen)
    }
}
