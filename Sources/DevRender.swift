import AppKit

/// Offline renderers. `--sheet` exists so the art can be reviewed without
/// squinting at an 18-point icon, and `--icon` reuses the same silhouette so
/// the app icon can never drift from the actual character.
enum DevRender {

    static func contactSheet(to path: String, scale: CGFloat = 9) {
        let moods = Mood.allCases
        let times: [Double] = [0.0, 0.55, 1.1, 1.65]
        let cell = CGSize(width: PetRenderer.canvas.width * scale,
                          height: PetRenderer.canvas.height * scale)
        let labelW: CGFloat = 110
        let gap: CGFloat = 26
        let panelW = cell.width * CGFloat(times.count)
        let W = labelW + panelW + gap + panelW + 20
        let H = cell.height * CGFloat(moods.count) + 34

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(W), pixelsHigh: Int(H),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: W, height: H).fill()
        // Dark panel on the right, standing in for a dark menu bar.
        NSColor(white: 0.13, alpha: 1).setFill()
        NSRect(x: labelW + panelW + gap, y: 0, width: panelW + 20, height: H).fill()

        for (row, mood) in moods.enumerated() {
            let y = H - 34 - CGFloat(row + 1) * cell.height

            let label = NSAttributedString(string: mood.rawValue, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.black,
            ])
            label.draw(at: NSPoint(x: 12, y: y + cell.height / 2 - 8))

            for (col, dt) in times.enumerated() {
                for (panel, bg) in [(CGFloat(0), NSColor.black), (CGFloat(1), NSColor.white)] {
                    PetRenderer.tint = bg
                    let ox = labelW + panel * (panelW + gap) + CGFloat(col) * cell.width
                    ctx.saveGState()
                    ctx.translateBy(x: ox, y: y)
                    ctx.scaleBy(x: scale, y: scale)
                    PetRenderer.draw(Pose(mood: mood, t: dt, energy: 0.7), in: ctx)
                    ctx.restoreGState()
                }
            }
        }

        let header = NSAttributedString(string: "Blip  ·  light menu bar                                     dark menu bar",
                                        attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.black,
        ])
        header.draw(at: NSPoint(x: 12, y: H - 26))

        NSGraphicsContext.restoreGraphicsState()
        PetRenderer.tint = .black

        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }

    /// Rounded-square app icon at one size, pet in white on a soft gradient.
    static func iconPNG(size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return nil }

        let S = CGFloat(size)
        let inset = S * 0.06
        let rect = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
        let squircle = CGPath(roundedRect: rect, cornerWidth: rect.width * 0.225,
                              cornerHeight: rect.width * 0.225, transform: nil)
        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        let colors = [NSColor(srgbRed: 0.35, green: 0.52, blue: 0.98, alpha: 1).cgColor,
                      NSColor(srgbRed: 0.53, green: 0.36, blue: 0.94, alpha: 1).cgColor]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: colors as CFArray, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0),
                                   options: [])
        }
        ctx.restoreGState()

        PetRenderer.tint = .white
        let scale = rect.width * 0.62 / PetRenderer.canvas.width
        ctx.saveGState()
        ctx.translateBy(x: S / 2 - PetRenderer.canvas.width * scale / 2,
                        y: S / 2 - PetRenderer.canvas.height * scale / 2)
        ctx.scaleBy(x: scale, y: scale)
        PetRenderer.draw(Pose(mood: .happy, t: 0.32, energy: 1), in: ctx)
        ctx.restoreGState()
        PetRenderer.tint = .black

        return rep.representation(using: .png, properties: [:])
    }

    static func iconSet(to dir: String) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // The sizes `iconutil` expects in a .iconset.
        let specs: [(Int, String)] = [
            (16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"),
            (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"),
            (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"),
            (1024, "icon_512x512@2x"),
        ]
        for (px, name) in specs {
            if let d = iconPNG(size: px) {
                try? d.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }
        print("wrote iconset to \(dir)")
    }
}

extension DevRender {
    /// Renders Blip at the true retina size the menu bar uses (2x), then blows
    /// that bitmap up with no interpolation. The 9x contact sheet is vector-
    /// scaled and flatters the art; this shows the actual pixels.
    static func pixelCheck(to path: String) {
        let moods: [Mood] = [.idle, .curious, .working, .frantic, .zoomies, .sleeping, .hungry, .happy]
        let scale: CGFloat = 2                 // retina menu bar
        let zoom: CGFloat = 7                  // inspection blow-up
        let w = Int(PetRenderer.canvas.width * scale)
        let h = Int(PetRenderer.canvas.height * scale)

        let cellW = CGFloat(w) * zoom
        let cellH = CGFloat(h) * zoom
        let W = cellW * CGFloat(moods.count)
        let H = cellH * 2 + 30

        guard let out = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: Int(W), pixelsHigh: Int(H),
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        guard let octx = NSGraphicsContext.current?.cgContext else { return }
        octx.interpolationQuality = .none

        for (i, mood) in moods.enumerated() {
            for (row, bg) in [(0, NSColor(white: 0.16, alpha: 1)), (1, NSColor(white: 0.93, alpha: 1))] {
                // Render one true-size frame.
                guard let cell = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                  pixelsWide: w, pixelsHigh: h,
                                                  bitsPerSample: 8, samplesPerPixel: 4,
                                                  hasAlpha: true, isPlanar: false,
                                                  colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: cell)
                if let cctx = NSGraphicsContext.current?.cgContext {
                    bg.setFill()
                    NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)).fill()
                    PetRenderer.tint = row == 0 ? .white : .black
                    cctx.scaleBy(x: scale, y: scale)
                    PetRenderer.draw(Pose(mood: mood, t: 0.9, energy: 0.7), in: cctx)
                    PetRenderer.tint = .black
                }
                NSGraphicsContext.restoreGraphicsState()

                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
                let dest = NSRect(x: CGFloat(i) * cellW, y: H - 30 - CGFloat(row + 1) * cellH,
                                  width: cellW, height: cellH)
                if let cg = cell.cgImage { octx.draw(cg, in: dest) }
            }

            let label = NSAttributedString(string: mood.rawValue, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
                .foregroundColor: NSColor.black,
            ])
            label.draw(at: NSPoint(x: CGFloat(i) * cellW + 6, y: 8))
        }

        NSGraphicsContext.restoreGraphicsState()
        if let data = out.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
}

import ImageIO
import UniformTypeIdentifiers

extension DevRender {
    /// An animated GIF cycling through every mood, for the README. Written via
    /// ImageIO so the project still depends on nothing but the system.
    static func gif(to path: String, dark: Bool) {
        let moods: [Mood] = [.idle, .curious, .working, .frantic,
                             .zoomies, .hungry, .sleeping, .happy]
        let fps = 12.0
        let framesPerMood = 18          // 1.5s each
        let scale: CGFloat = 5
        let pad: CGFloat = 5

        let w = Int((PetRenderer.canvas.width + pad * 2) * scale)
        let h = Int((PetRenderer.canvas.height + pad * 2) * scale)

        let bg = dark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
                      : NSColor(srgbRed: 0.94, green: 0.94, blue: 0.95, alpha: 1)

        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL,
            UTType.gif.identifier as CFString,
            moods.count * framesPerMood, nil) else { return }

        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)

        let frameProps = [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]
        ] as CFDictionary

        var t = 0.0
        for mood in moods {
            for _ in 0..<framesPerMood {
                guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: w, pixelsHigh: h,
                                                 bitsPerSample: 8, samplesPerPixel: 4,
                                                 hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB,
                                                 bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                if let ctx = NSGraphicsContext.current?.cgContext {
                    bg.setFill()
                    NSRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)).fill()
                    PetRenderer.tint = dark ? .white : .black
                    ctx.scaleBy(x: scale, y: scale)
                    ctx.translateBy(x: pad, y: pad)
                    PetRenderer.draw(Pose(mood: mood, t: t, energy: 0.7), in: ctx)
                    PetRenderer.tint = .black
                }
                NSGraphicsContext.restoreGraphicsState()

                if let cg = rep.cgImage {
                    CGImageDestinationAddImage(dest, cg, frameProps)
                }
                t += 1.0 / fps
            }
        }

        guard CGImageDestinationFinalize(dest) else { return }

        // ImageIO stamps a GIF87a header even though it writes 89a-only blocks
        // (per-frame delays and the NETSCAPE loop extension). Every real
        // decoder reads them anyway, but the file shouldn't claim 87a.
        if var data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           data.starts(with: Array("GIF87a".utf8)) {
            data.replaceSubrange(3..<6, with: Array("89a".utf8))
            try? data.write(to: URL(fileURLWithPath: path))
        }
        print("wrote \(path)")
    }

    /// Blip at true size inside a mock menu bar, so the README can show what he
    /// actually looks like rather than only the blown-up art.
    static func menuBarMock(to path: String, dark: Bool) {
        let scale: CGFloat = 2
        let barH: CGFloat = 24
        let barW: CGFloat = 190
        let w = Int(barW * scale), h = Int(barH * scale)

        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.scaleBy(x: scale, y: scale)
            (dark ? NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
                  : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)).setFill()
            NSRect(x: 0, y: 0, width: barW, height: barH).fill()

            PetRenderer.tint = dark ? .white : .black
            ctx.saveGState()
            ctx.translateBy(x: 8, y: (barH - PetRenderer.canvas.height) / 2)
            PetRenderer.draw(Pose(mood: .curious, t: 0.9, energy: 0.3), in: ctx)
            ctx.restoreGState()

            // A couple of stand-in system items for context.
            let fg = (dark ? NSColor.white : NSColor.black).withAlphaComponent(0.55)
            let text = NSAttributedString(string: "100%   Fri 21 Aug  6:14 PM", attributes: [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .regular),
                .foregroundColor: fg,
            ])
            text.draw(at: NSPoint(x: 45, y: barH / 2 - 6))
            PetRenderer.tint = .black
        }
        NSGraphicsContext.restoreGraphicsState()
        if let d = rep.representation(using: .png, properties: [:]) {
            try? d.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
}
