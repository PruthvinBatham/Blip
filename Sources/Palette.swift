import AppKit

/// How Blip is coloured for one render.
///
/// A `nil` face carves the eyes and mouth out of the silhouette and leaves the
/// menu bar showing through, which is what a template image needs — the system
/// tints the remaining shape and he stays legible on any bar. Once he has a
/// colour of his own he can no longer borrow that trick, so the face is painted
/// on instead, in a deeper shade of whatever he currently is.
struct Skin {
    var body: NSColor
    var face: NSColor?

    static func mono(_ colour: NSColor) -> Skin { Skin(body: colour, face: nil) }

    /// Template rendering is exactly the case where nothing is painted in a
    /// colour of ours — the silhouette's alpha is the whole image.
    var isTemplate: Bool { face == nil }
}

extension Mood {
    /// One hue per mood, in two variants. A colour picked to read on a white
    /// menu bar is muddy on a black one and vice versa, so each mood carries
    /// both and `AppDelegate` asks for the one matching the bar he's sitting in.
    ///
    /// The hues are deliberately spread — sleeping and working would otherwise
    /// both land on blue, which is the one pair you most need to tell apart at
    /// a glance.
    func skin(dark: Bool) -> Skin {
        let body: NSColor
        switch self {
        case .sleeping: body = rgb(dark, (0.36, 0.38, 0.72), (0.60, 0.62, 0.95))   // indigo
        case .idle:     body = rgb(dark, (0.16, 0.52, 0.51), (0.42, 0.82, 0.78))   // teal
        case .curious:  body = rgb(dark, (0.13, 0.46, 0.79), (0.42, 0.72, 1.00))   // sky
        case .working:  body = rgb(dark, (0.16, 0.50, 0.26), (0.40, 0.82, 0.50))   // green
        case .zoomies:  body = rgb(dark, (0.78, 0.47, 0.05), (1.00, 0.72, 0.25))   // amber
        case .frantic:  body = rgb(dark, (0.80, 0.20, 0.16), (1.00, 0.44, 0.38))   // red
        case .hungry:   body = rgb(dark, (0.51, 0.40, 0.29), (0.78, 0.66, 0.53))   // drained brown
        case .happy:    body = rgb(dark, (0.80, 0.24, 0.53), (1.00, 0.51, 0.74))   // pink
        }
        // The face is a shade of the body rather than a fixed near-black: a flat
        // black face is invisible against the deep light-bar colours, and
        // guessing the bar's own colour goes wrong the moment it's translucent
        // over a wallpaper.
        return Skin(body: body, face: body.shaded(dark ? 0.26 : 0.34))
    }

    private func rgb(_ dark: Bool,
                     _ onLight: (CGFloat, CGFloat, CGFloat),
                     _ onDark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        let c = dark ? onDark : onLight
        return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
    }
}

extension NSColor {
    /// Same hue, multiplied toward black. Done by hand in sRGB rather than with
    /// `blended(withFraction:of:)`, which is optional and depends on the
    /// receiver already living in an RGB space.
    func shaded(_ factor: CGFloat) -> NSColor {
        let c = usingColorSpace(.sRGB) ?? self
        return NSColor(srgbRed: c.redComponent * factor,
                       green: c.greenComponent * factor,
                       blue: c.blueComponent * factor,
                       alpha: c.alphaComponent)
    }
}
