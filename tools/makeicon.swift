import AppKit
import CoreGraphics

// Generates the app icon at every size macOS asks for, then iconutil turns the .iconset
// into a .icns. The mark is the product: a hairline of light in the notch with a droplet
// pinching off below it. Nothing else survives being 16 points wide.

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./Sill.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func hex(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((h >> 16) & 0xFF) / 255,
            green: CGFloat((h >> 8) & 0xFF) / 255,
            blue: CGFloat(h & 0xFF) / 255, alpha: a)
}
let caustic = hex(0xF4E7C9)
let bezel = hex(0x000000)

func draw(_ px: Int) -> CGImage? {
    let s = CGFloat(px)
    guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // macOS icons sit inside the canvas with a margin, on a continuous rounded square.
    let inset = s * 0.086
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.2237

    ctx.setFillColor(bezel)
    let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(body)
    ctx.fillPath()

    // A single hairline of light, which is the whole product at rest. Scaled so it stays
    // visible at 16px rather than disappearing into a subpixel.
    let lineW = max(1, s * 0.0135)
    let lineLen = rect.width * 0.40
    let lineY = rect.midY + rect.height * 0.20
    ctx.setFillColor(caustic)
    ctx.fill(CGRect(x: rect.midX - lineLen / 2, y: lineY, width: lineLen, height: lineW))

    // The droplet, caught mid pinch off. Drawn as a teardrop: a circle with a drawn out top,
    // which is what a real drop looks like the instant the neck breaks.
    let r = rect.width * 0.135
    let cx = rect.midX
    let cy = rect.midY - rect.height * 0.10
    let tipY = lineY - rect.height * 0.055

    let drop = CGMutablePath()
    drop.move(to: CGPoint(x: cx, y: tipY))
    drop.addCurve(to: CGPoint(x: cx + r, y: cy),
                  control1: CGPoint(x: cx + r * 0.55, y: tipY - r * 0.75),
                  control2: CGPoint(x: cx + r, y: cy + r * 0.72))
    drop.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                startAngle: 0, endAngle: .pi, clockwise: true)
    drop.addCurve(to: CGPoint(x: cx, y: tipY),
                  control1: CGPoint(x: cx - r, y: cy + r * 0.72),
                  control2: CGPoint(x: cx - r * 0.55, y: tipY - r * 0.75))
    drop.closeSubpath()

    ctx.setFillColor(caustic)
    ctx.addPath(drop)
    ctx.fillPath()

    return ctx.makeImage()
}

let sizes: [(Int, String)] = [
    (16, "icon_16x16"), (32, "icon_16x16@2x"),
    (32, "icon_32x32"), (64, "icon_32x32@2x"),
    (128, "icon_128x128"), (256, "icon_128x128@2x"),
    (256, "icon_256x256"), (512, "icon_256x256@2x"),
    (512, "icon_512x512"), (1024, "icon_512x512@2x")
]

for (px, name) in sizes {
    guard let img = draw(px) else { continue }
    let rep = NSBitmapImageRep(cgImage: img)
    rep.size = NSSize(width: px, height: px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    try? data.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}
print("wrote \(sizes.count) sizes to \(out)")
