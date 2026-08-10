import SwiftUI
import AppKit
import CoreText

/// Design tokens, generated from the Figma variable collections.
/// Nothing in the view layer may use a literal colour, size, or radius.
enum Tokens {

    // MARK: Colour
    //
    // There is exactly ONE surface and it is true black, continuous with the bezel.
    // No lighter surface may ever be used for elevation. Hierarchy is type, spacing and
    // hairlines only. A lighter rectangle inside a black panel instantly reveals the panel
    // as a window, and the whole premise dies with it.

    /// The bezel. The only surface in the product.
    static let hardware = Color.black
    /// Primary text. 17.90:1 on true black.
    static let textPrimary = Color(red: 0xE9/255, green: 0xEE/255, blue: 0xEB/255)
    /// Supporting labels. 5.90:1.
    static let textSecondary = Color(red: 0x7C/255, green: 0x8B/255, blue: 0x88/255)
    /// Metadata that should be findable, not announced. 4.77:1, the AA floor at 11pt.
    static let textTertiary = Color(red: 0x6E/255, green: 0x7B/255, blue: 0x79/255)
    /// Not right, or not now. Overdue and failure, and nothing else may use it.
    static let attention = Color(red: 0x84/255, green: 0xA6/255, blue: 0xAA/255)
    /// The only real chroma in the product. Earned, never ambient.
    static let accent = Color(red: 0xF4/255, green: 0xE7/255, blue: 0xC9/255)

    /// Peak of the edge highlight. Reached only where the geometry curves.
    static let edgeSpecular = accent.opacity(0.70)
    /// Reflected light on the underside. A hint, never the sole affordance.
    static let edgeSpecularSoft = accent.opacity(0.28)
    /// The one shadow. Falls on the wallpaper, never on the panel.
    static let shadowCast = Color.black.opacity(0.42)
    /// The sanctioned separator. Distance first, this second, never a fill.
    static let hairline = textSecondary.opacity(0.38)

    static let controlRing = textSecondary
    static let controlRingHover = textPrimary
    static let controlComplete = accent

    // MARK: Space  (base unit 2)
    enum Space {
        static let s2: CGFloat = 2, s4: CGFloat = 4, s6: CGFloat = 6, s8: CGFloat = 8
        static let s12: CGFloat = 12, s16: CGFloat = 16, s20: CGFloat = 20, s24: CGFloat = 24
        /// The panel's outer padding, and the most important spacing decision in the system.
        static let s28: CGFloat = 28
        static let s32: CGFloat = 32, s36: CGFloat = 36, s40: CGFloat = 40, s48: CGFloat = 48
    }

    // MARK: Geometry
    enum Geo {
        /// The notch's own corner radius. Does NOT grow as the panel extends.
        static let hardwareRadius: CGFloat = 9
        static let meniscus: CGFloat = 20
        static let control: CGFloat = 18
        static let controlStroke: CGFloat = 1.5
        static let rowHeight: CGFloat = 48
        static let panelWidth: CGFloat = 400
        static let edgeWeight: CGFloat = 1.25
    }

    // MARK: Type
    //
    // The three faces are bundled with the app because none of them are installed on a
    // stock macOS system. Substituting system fonts would have been a silent design change.

    enum Face {
        static let display = "Fraunces"
        static let body = "IBMPlexSans-Regular"
        static let mono = "DMMono-Regular"
    }

    /// Fraunces is variable. The design specifies SOFT 60, which controls how swollen and
    /// rounded the terminals get, and that swell is the entire reason the face was chosen.
    /// Figma only ever had static instances, so this is the first time it renders as designed.
    static func display(_ size: CGFloat, soft: CGFloat = 60, wonk: CGFloat = 0) -> Font {
        let axes: [CFNumber: CFNumber] = [
            0x534F4654 as CFNumber: soft as CFNumber,   // SOFT
            0x574F4E4B as CFNumber: wonk as CFNumber,   // WONK
            0x6F70737A as CFNumber: size as CFNumber,   // opsz
            0x77676874 as CFNumber: 400 as CFNumber     // wght
        ]
        let base = CTFontDescriptorCreateWithNameAndSize(Face.display as CFString, size)
        let desc = CTFontDescriptorCreateCopyWithAttributes(
            base, [kCTFontVariationAttribute: axes] as CFDictionary)
        let ct = CTFontCreateWithFontDescriptor(desc, size, nil)
        return Font(ct)
    }

    static func body(_ size: CGFloat) -> Font { .custom(Face.body, fixedSize: size) }
    static func mono(_ size: CGFloat) -> Font { .custom(Face.mono, fixedSize: size) }

    enum TypeSize {
        static let displayEmpty: CGFloat = 17
        static let bodyCapture: CGFloat = 14
        static let bodyRow: CGFloat = 13
        static let labelMeta: CGFloat = 11
        static let monoStamp: CGFloat = 11
    }

    /// Confirms the bundled faces actually registered. Called once at launch so a missing
    /// font is a reported failure rather than a silent fallback to the system face.
    static func verifyFonts() -> [String: Bool] {
        [Face.display: NSFont(name: Face.display, size: 13) != nil,
         Face.body: NSFont(name: Face.body, size: 13) != nil,
         Face.mono: NSFont(name: Face.mono, size: 13) != nil]
    }
}
