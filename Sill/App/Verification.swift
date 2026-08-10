import SwiftUI
import AppKit

/// Milestone verification helpers. Not product code, and not reachable without an
/// environment variable. They exist because Screen Recording permission is unavailable
/// on this machine, so the app renders itself instead of being captured.
@MainActor
enum Verification {

    /// Renders the morph at evenly spaced progress values and writes a filmstrip to disk.
    /// This proves the shape of the transition. It does not prove how it composites over
    /// the wallpaper, which still needs a real screen capture.
    static func writeFilmstrip(geometry: Silhouette.Geometry, to directory: String) -> [String] {
        let samples: [Double] = [0.0, Morph.bulgeEnd, Morph.neckEnd,
                                 (Morph.neckEnd + Morph.detachEnd) / 2,
                                 Morph.detachEnd, 0.72, 1.0]
        let width = PanelState.panelWidth + PanelState.shadowMargin * 2
        let height = PanelState.maxPanelHeight + PanelState.shadowMargin
        var written: [String] = []

        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)

        for (i, p) in samples.enumerated() {
            let view = ZStack {
                // Mid grey stands in for wallpaper so the black silhouette is visible.
                Color(red: 0.502, green: 0.502, blue: 0.502)
                MetaballCanvas(progress: p, geometry: geometry,
                               insetX: PanelState.shadowMargin, onDraw: nil)
            }
            .frame(width: width, height: height)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }

            let name = String(format: "%@/morph-%02d-p%.2f.png", directory, i, p)
            try? png.write(to: URL(fileURLWithPath: name))
            written.append(name)
        }
        return written
    }
}
