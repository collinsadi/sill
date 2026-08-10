import AppKit
import SwiftUI

/// Container whose hit testing is masked by the drawn silhouette.
///
/// The window never resizes. It sits at the union of the notch and the maximum expanded
/// panel for the whole session, and this view decides what is actually clickable, so clicks
/// outside the shape fall through to whatever is behind. Resizing an NSPanel per frame
/// instead would fight the animation, and the morph is the reason this product exists.
///
/// `isFlipped` is true so local coordinates share SwiftUI's top left origin and the path
/// needs no conversion.
final class HitMaskView: NSView {

    /// Supplies the current silhouette in this view's coordinate space.
    var maskProvider: (() -> Path)?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let provider = maskProvider else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        guard provider().contains(local) else { return nil }
        return super.hitTest(point)
    }
}
