import AppKit
import CoreText

// The installer window is the first thing anyone sees, so it uses the product's own
// language: true black, one hairline of light, and type rather than chrome.
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./dmg-bg.png"
let fonts = ["Sill/Resources/IBMPlexSans.ttf", "Sill/Resources/Fraunces.ttf"]
for f in fonts {
    CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: f) as CFURL, .process, nil)
}

let W = 660, H = 420
let ctx = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: 2, y: 2)
ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

func text(_ s: String, _ font: String, _ size: CGFloat, _ color: CGColor, _ x: CGFloat, _ y: CGFloat, centered: Bool = true) {
    let f = CTFontCreateWithName(font as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        .font: f, .foregroundColor: NSColor(cgColor: color)!
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    ctx.textPosition = CGPoint(x: centered ? x - bounds.width / 2 : x, y: y)
    CTLineDraw(line, ctx)
}

let caustic = CGColor(red: 0xF4/255, green: 0xE7/255, blue: 0xC9/255, alpha: 1)
let foam = CGColor(red: 0xE9/255, green: 0xEE/255, blue: 0xEB/255, alpha: 1)
let silt = CGColor(red: 0x7C/255, green: 0x8B/255, blue: 0x88/255, alpha: 1)

// The sill itself, at the top, exactly as it appears at rest.
ctx.setFillColor(caustic)
ctx.fill(CGRect(x: CGFloat(W)/2 - 44, y: CGFloat(H) - 54, width: 88, height: 1.5))

text("Sill", "Fraunces", 30, foam, CGFloat(W)/2, CGFloat(H) - 108)
text("Drag it into Applications.", "IBMPlexSans-Regular", 13, silt, CGFloat(W)/2, CGFloat(H) - 136)

// A hairline between the two drop targets, at their vertical centre. Distance does most of
// the work; the line is only there so the gap reads as deliberate.
ctx.setFillColor(CGColor(red: 0x7C/255, green: 0x8B/255, blue: 0x88/255, alpha: 0.30))
ctx.fill(CGRect(x: CGFloat(W)/2 - 34, y: 196, width: 68, height: 1))

text("no dock icon. click the notch.", "IBMPlexSans-Regular", 11, silt, CGFloat(W)/2, 44)

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
rep.size = NSSize(width: W, height: H)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
