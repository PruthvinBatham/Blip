import AppKit
import CoreGraphics

struct Pose {
    var mood: Mood
    var t: Double        // seconds since launch, drives all animation
    var energy: Double   // 0...1, how hard the current mood is being felt
}

private enum EyeStyle {
    case round      // open, or partly closed by a lid
    case archUp     // ⌒  delighted
    case archDown   // ⌣  asleep
}

/// Blip is drawn as a single silhouette with the eyes and mouth taken out of
/// it. In monochrome that silhouette is a template image, so the system tints
/// him and he stays legible on a light or dark menu bar with no appearance
/// handling at all; in colour he carries his own mood hue and the face is
/// painted rather than carved. `Skin` is the only difference between the two.
enum PetRenderer {
    static let canvas = CGSize(width: 22, height: 18)

    /// Nothing may be drawn above this line. The menu bar gives a status item
    /// 18 points and silently crops the rest, so the floating extras — bubbles,
    /// hearts — have to finish their rise inside it.
    static let ceiling: CGFloat = canvas.height - 0.6

    /// Every animation below is built from integer multiples of this loop, so
    /// the whole character repeats exactly every `loopPeriod` seconds. That is
    /// what lets the app render one cycle of frames and then reuse them
    /// forever instead of drawing something new 3-12 times a second.
    static let loopPeriod: Double = 4.0
    static let w = 2 * Double.pi / loopPeriod

    /// The colours in force for the current draw. Set through `image(_:skin:)`
    /// for the status item, or assigned directly by the offline renderers.
    static var skin: Skin = .mono(.black)

    // MARK: - Public entry points

    static func image(_ pose: Pose, skin: Skin = .mono(.black)) -> NSImage {
        let img = NSImage(size: NSSize(width: canvas.width, height: canvas.height),
                          flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // NSImage runs this handler whenever it feels like redrawing, which
            // is not necessarily now — so the skin is captured and applied here
            // rather than read off the global at call time.
            let previous = PetRenderer.skin
            PetRenderer.skin = skin
            draw(pose, in: ctx)
            PetRenderer.skin = previous
            return true
        }
        img.isTemplate = skin.isTemplate
        return img
    }

    // MARK: - Drawing

    static func draw(_ pose: Pose, in ctx: CGContext) {
        let t = pose.t
        let m = pose.mood

        // Per-mood body language. Everything downstream reads from these.
        var bob: CGFloat = 0        // vertical bounce
        var jitter: CGFloat = 0     // horizontal shake
        var stretch: CGFloat = 1    // >1 taller, <1 squatter
        var eyeOpen: CGFloat = 1    // 0 shut, 1 normal, >1 startled
        var eyeShift: CGFloat = 0   // looking left/right
        var mouth: CGFloat = 0      // 0 none, 1 wide open
        var eyes: EyeStyle = .round

        switch m {
        case .idle:
            bob = sin(t * w) * 0.35
        case .curious:
            bob = sin(t * w * 2) * 0.3
            eyeShift = CGFloat(sin(t * w)) * 0.9
        case .working:
            bob = sin(t * w * 3) * 0.55
            stretch = 0.97
            mouth = 0.25
        case .frantic:
            jitter = CGFloat(sin(t * w * 21) * 0.85 + sin(t * w * 13) * 0.45)
            bob = sin(t * w * 6) * 0.4
            eyeOpen = 1.35
            mouth = 0.85
        case .zoomies:
            bob = abs(sin(t * w * 6)) * 1.5 - 0.4
            stretch = 1.10
            mouth = 0.6
            eyeOpen = 1.15
        case .sleeping:
            bob = sin(t * w) * 0.45             // slow breathing
            stretch = 0.86                      // settled into a loaf
            eyes = .archDown
        case .hungry:
            bob = sin(t * w) * 0.2 - 0.5        // sagging
            stretch = 0.9
            eyeOpen = 0.5
            mouth = 0.2
        case .happy:
            bob = abs(sin(t * w * 3)) * 1.7
            stretch = 1.05
            eyes = .archUp
            mouth = 0.55
        }

        // One blink per loop, for eyes that can actually shut.
        if eyes == .round {
            let phase = t.truncatingRemainder(dividingBy: loopPeriod)
            if phase < 0.16 { eyeOpen *= max(0.05, abs(phase - 0.08) / 0.08) }
        }

        let cx: CGFloat = 9.6 + jitter
        let baseY: CGFloat = 2.4 + bob

        let rx: CGFloat = 5.9
        let ry: CGFloat = 5.1 * stretch

        let bodyRect = CGRect(x: cx - rx, y: baseY, width: rx * 2, height: ry * 2)

        // Silhouette: loaf-shaped body, two feet, one antenna.
        let solid = CGMutablePath()
        solid.addPath(CGPath(roundedRect: bodyRect,
                             cornerWidth: rx * 0.82, cornerHeight: rx * 0.82,
                             transform: nil))
        solid.addEllipse(in: CGRect(x: cx - rx * 0.70, y: baseY - 0.95, width: 2.8, height: 2.2))
        solid.addEllipse(in: CGRect(x: cx + rx * 0.70 - 2.8, y: baseY - 0.95, width: 2.8, height: 2.2))
        let ant = antenna(cx: cx, topY: bodyRect.maxY, t: t, mood: m)

        // The face, carved back out of the silhouette or painted onto it.
        let holes = CGMutablePath()
        let eyeY = baseY + ry * 1.16
        let eyeDX: CGFloat = 2.35
        let eyeR: CGFloat = 1.42

        for side in [-1.0, 1.0] as [CGFloat] {
            let ex = cx + side * eyeDX + eyeShift
            switch eyes {
            case .round:    holes.addPath(lidEye(x: ex, y: eyeY, r: eyeR, open: eyeOpen))
            case .archUp:   holes.addPath(arcEye(x: ex, y: eyeY, r: eyeR * 1.05, up: true))
            case .archDown: holes.addPath(arcEye(x: ex, y: eyeY, r: eyeR * 1.05, up: false))
            }
        }

        if mouth > 0.01 {
            let my = baseY + ry * 0.56
            if m == .happy {
                holes.addPath(arcEye(x: cx + eyeShift, y: my, r: 1.5, up: false))
            } else {
                let mw: CGFloat = 1.3 + 1.4 * CGFloat(mouth)
                let mh: CGFloat = 0.9 + 1.9 * CGFloat(mouth)
                holes.addEllipse(in: CGRect(x: cx + eyeShift - mw / 2, y: my - mh / 2,
                                            width: mw, height: mh))
            }
        }

        ctx.saveGState()
        if let face = skin.face {
            // Coloured: the face is painted over the silhouette in a deeper
            // shade, so it doesn't depend on what is behind him.
            fillSilhouette(solid, antenna: ant, in: ctx)
            ctx.setFillColor(face.cgColor)
            ctx.addPath(holes)
            ctx.fillPath(using: .evenOdd)
        } else {
            // Monochrome: the face is carved out with destination-out, leaving
            // the bar showing through. The transparency layer keeps that carve
            // from punching through whatever was on the context underneath him.
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            fillSilhouette(solid, antenna: ant, in: ctx)
            ctx.setBlendMode(.destinationOut)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.addPath(holes)
            ctx.fillPath(using: .evenOdd)
            ctx.endTransparencyLayer()
        }
        ctx.restoreGState()

        drawExtras(pose, cx: cx, top: bodyRect.maxY, right: bodyRect.maxX, in: ctx)
    }

    /// Body, feet and antenna, unioned into one opaque shape.
    ///
    /// They have to be filled as separate passes rather than as one path. An
    /// even-odd fill turns every overlap between them into a hole; a winding
    /// fill fixes the body and feet, which are all wound the same way, but not
    /// the antenna — the stalk is a *stroked* outline, and where its contour
    /// runs against the ball's the two windings cancel and the ball comes out
    /// as a ring. Three separate opaque fills can't cancel each other.
    private static func fillSilhouette(_ solid: CGPath, antenna: (stalk: CGPath, ball: CGPath),
                                       in ctx: CGContext) {
        ctx.setFillColor(skin.body.cgColor)
        for piece in [solid, antenna.stalk, antenna.ball] {
            ctx.addPath(piece)
            ctx.fillPath(using: .winding)
        }
    }

    /// Whatever floats around Blip: sleep bubbles, panic sweat, affection.
    /// Everything here rises, so every path is kept under `ceiling` — the menu
    /// bar crops what it can't fit and the top bubble simply vanished.
    private static func drawExtras(_ pose: Pose, cx: CGFloat, top: CGFloat,
                                   right: CGFloat, in ctx: CGContext) {
        let t = pose.t
        ctx.saveGState()
        defer { ctx.restoreGState() }

        switch pose.mood {
        case .sleeping:
            // Three bubbles rising and fading on a staggered loop.
            for i in 0..<3 {
                let phase = (t / loopPeriod + Double(i) * 0.33).truncatingRemainder(dividingBy: 1)
                let r = CGFloat(0.5 + phase * 0.6)
                let x = right - 0.6 + CGFloat(phase) * 2.6
                let y = min(top - 2.4 + CGFloat(phase) * 3.6, ceiling - r * 2)
                ctx.setFillColor(skin.body.withAlphaComponent(1 - phase * 0.95).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
            }

        case .frantic:
            // One sweat bead, launched sideways and falling away.
            let phase = (t * 2).truncatingRemainder(dividingBy: 1)
            let x = right - 0.2 + CGFloat(phase) * 3.0
            let y = min(top - 3.0 + CGFloat(sin(phase * .pi)) * 2.6, ceiling - 1.9)
            ctx.setFillColor(skin.body.withAlphaComponent(1 - phase * 0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.9))

        case .happy:
            for i in 0..<2 {
                let phase = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let s = CGFloat(1.4 + phase * 0.7)
                let x = right - 1.4 + CGFloat(phase) * 2.2
                let y = min(top - 3.4 + CGFloat(phase) * 3.4, ceiling - s)
                ctx.setFillColor(skin.body.withAlphaComponent(1 - phase * 0.9).cgColor)
                ctx.addPath(heart(in: CGRect(x: x, y: y, width: s, height: s)))
                ctx.fillPath()
            }

        case .zoomies:
            // Speed lines trailing behind him.
            ctx.setFillColor(skin.body.withAlphaComponent(0.75).cgColor)
            for i in 0..<2 {
                let y = top - 4.0 - CGFloat(i) * 2.6
                let w = 2.2 + CGFloat(sin(t * PetRenderer.w * 9 + Double(i) * .pi)) * 0.9
                ctx.fill(CGRect(x: cx - 8.6, y: y, width: w, height: 0.75))
            }

        default:
            break
        }
    }

    // MARK: - Shape helpers

    /// The stalk and the ball, handed back separately so the caller can fill
    /// them as a union — see `fillSilhouette`.
    private static func antenna(cx: CGFloat, topY: CGFloat, t: Double,
                                mood: Mood) -> (stalk: CGPath, ball: CGPath) {
        // The antenna is where most of the mood actually reads: it whips around
        // when he's excited and flops over when he's flat.
        let wobble: CGFloat
        let droop: CGFloat
        switch mood {
        case .frantic:  wobble = CGFloat(sin(t * w * 15)) * 2.0; droop = 0
        case .zoomies:  wobble = CGFloat(sin(t * w * 8)) * 1.7;  droop = 0
        case .working:  wobble = CGFloat(sin(t * w * 4)) * 0.7;  droop = 0
        case .happy:    wobble = CGFloat(sin(t * w * 5)) * 1.2;  droop = 0
        case .hungry:   wobble = 1.9;                            droop = 1.5
        case .sleeping: wobble = 1.1;                            droop = 1.3
        default:        wobble = CGFloat(sin(t * w)) * 0.5;      droop = 0
        }

        let tipX = cx + wobble
        let tipY = topY + 3.0 - droop

        let stalk = CGMutablePath()
        stalk.move(to: CGPoint(x: cx, y: topY - 0.5))
        stalk.addQuadCurve(to: CGPoint(x: tipX, y: tipY),
                           control: CGPoint(x: cx + wobble * 0.15, y: topY + 2.0))
        let stroked = stalk.copy(strokingWithWidth: 0.85, lineCap: .round,
                                 lineJoin: .round, miterLimit: 10)

        let ball = CGMutablePath()
        ball.addEllipse(in: CGRect(x: tipX - 0.95, y: tipY - 0.95, width: 1.9, height: 1.9))
        return (stroked, ball)
    }

    /// A round eye with an eyelid closing over it from above. The lidded shape
    /// is built directly as a circular segment — the arc below the lid line,
    /// closed by its chord. Subtracting a lid rectangle instead would be
    /// simpler, but the part of that rectangle hanging outside the eye carves
    /// straight through the rest of the head.
    private static func lidEye(x: CGFloat, y: CGFloat, r: CGFloat, open: CGFloat) -> CGPath {
        let rr = r * min(1.25, max(1.0, open))
        let o = max(0, min(1, open))
        let p = CGMutablePath()

        guard o < 0.98 else {
            p.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
            return p
        }

        // Lid line, as a signed offset from the eye's centre.
        let d = rr * (2 * o - 1)
        let theta = asin(max(-1, min(1, d / rr)))
        let centre = CGPoint(x: x, y: y)
        // Anticlockwise, i.e. the long way round *under* the lid line. Going the
        // short way instead keeps the cap above it, which inverts the whole
        // control: a nearly-open eye becomes a sliver and a blink swells into a
        // full circle.
        p.move(to: CGPoint(x: x + rr * cos(.pi - theta), y: y + rr * sin(.pi - theta)))
        p.addArc(center: centre, radius: rr,
                 startAngle: .pi - theta, endAngle: theta, clockwise: false)
        p.closeSubpath()
        return p
    }

    /// A ⌒ or ⌣ eye, made by stroking an arc rather than by subtracting two
    /// circles — subtraction leaves a stray second crescent on the far side.
    private static func arcEye(x: CGFloat, y: CGFloat, r: CGFloat, up: Bool) -> CGPath {
        let p = CGMutablePath()
        let centre = CGPoint(x: x, y: up ? y - r * 0.35 : y + r * 0.35)
        let start: CGFloat = up ? .pi * 0.12 : .pi * 1.12
        let end: CGFloat   = up ? .pi * 0.88 : .pi * 1.88
        p.addArc(center: centre, radius: r, startAngle: start, endAngle: end, clockwise: false)
        return p.copy(strokingWithWidth: 0.8, lineCap: .round, lineJoin: .round, miterLimit: 10)
    }

    private static func heart(in r: CGRect) -> CGPath {
        let p = CGMutablePath()
        let w = r.width, h = r.height
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.68),
                   control1: CGPoint(x: r.midX - w * 0.30, y: r.minY + h * 0.22),
                   control2: CGPoint(x: r.minX, y: r.minY + h * 0.40))
        p.addArc(center: CGPoint(x: r.minX + w * 0.25, y: r.minY + h * 0.70),
                 radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addArc(center: CGPoint(x: r.minX + w * 0.75, y: r.minY + h * 0.70),
                 radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.maxX, y: r.minY + h * 0.40),
                   control2: CGPoint(x: r.midX + w * 0.30, y: r.minY + h * 0.22))
        p.closeSubpath()
        return p
    }
}
