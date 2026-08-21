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

/// Blip is drawn as a single template shape: one filled silhouette with the
/// eyes and mouth carved out of it. Template rendering means the system tints
/// him for us, so he stays legible on a light or dark menu bar without us
/// tracking appearance changes at all.
enum PetRenderer {
    static let canvas = CGSize(width: 22, height: 18)

    /// Every animation below is built from integer multiples of this loop, so
    /// the whole character repeats exactly every `loopPeriod` seconds. That is
    /// what lets the app render one cycle of frames and then reuse them
    /// forever instead of drawing something new 3-12 times a second.
    static let loopPeriod: Double = 4.0
    static let w = 2 * Double.pi / loopPeriod

    /// Template images ignore this and let the system tint them, but the
    /// offline contact-sheet and icon renderers need real colours.
    static var tint: NSColor = .black

    // MARK: - Public entry points

    static func image(_ pose: Pose) -> NSImage {
        let img = NSImage(size: NSSize(width: canvas.width, height: canvas.height),
                          flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            draw(pose, in: ctx)
            return true
        }
        img.isTemplate = true
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
        solid.addPath(antenna(cx: cx, topY: bodyRect.maxY, t: t, mood: m))

        // The face, carved back out of the silhouette.
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

        // Two passes rather than one even-odd fill: the body, feet and antenna
        // overlap each other, and a single even-odd pass would turn every one
        // of those overlaps into an unwanted hole. So fill the silhouette with
        // the winding rule, then carve the face out with destination-out. The
        // transparency layer keeps that carve from punching through whatever
        // was already on the context underneath him.
        ctx.saveGState()
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(tint.cgColor)
        ctx.addPath(solid)
        ctx.fillPath(using: .winding)

        ctx.setBlendMode(.destinationOut)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(holes)
        ctx.fillPath(using: .evenOdd)
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        drawExtras(pose, cx: cx, top: bodyRect.maxY, right: bodyRect.maxX, in: ctx)
    }

    /// Whatever floats around Blip: sleep bubbles, panic sweat, affection.
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
                let r = CGFloat(0.55 + phase * 0.85)
                let x = right - 0.6 + CGFloat(phase) * 2.6
                let y = top - 1.2 + CGFloat(phase) * 5.2
                ctx.setFillColor(tint.withAlphaComponent(1 - phase * 0.95).cgColor)
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
            }

        case .frantic:
            // One sweat bead, launched sideways and falling away.
            let phase = (t * 2).truncatingRemainder(dividingBy: 1)
            let x = right - 0.2 + CGFloat(phase) * 3.0
            let y = top - 3.0 + CGFloat(sin(phase * .pi)) * 2.6
            ctx.setFillColor(tint.withAlphaComponent(1 - phase * 0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.9))

        case .happy:
            for i in 0..<2 {
                let phase = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let s = CGFloat(1.6 + phase * 0.9)
                let x = right - 1.4 + CGFloat(phase) * 2.2
                let y = top - 2.4 + CGFloat(phase) * 5.4
                ctx.setFillColor(tint.withAlphaComponent(1 - phase * 0.9).cgColor)
                ctx.addPath(heart(in: CGRect(x: x, y: y, width: s, height: s)))
                ctx.fillPath()
            }

        case .zoomies:
            // Speed lines trailing behind him.
            ctx.setFillColor(tint.withAlphaComponent(0.75).cgColor)
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

    private static func antenna(cx: CGFloat, topY: CGFloat, t: Double, mood: Mood) -> CGPath {
        // The antenna is where most of the mood actually reads: it whips around
        // when he's excited and flops over when he's flat.
        let wobble: CGFloat
        let droop: CGFloat
        switch mood {
        case .frantic:  wobble = CGFloat(sin(t * w * 15)) * 2.0; droop = 0
        case .zoomies:  wobble = CGFloat(sin(t * w * 8)) * 1.7;  droop = 0
        case .working:  wobble = CGFloat(sin(t * w * 4)) * 0.7;  droop = 0
        case .happy:    wobble = CGFloat(sin(t * w * 5)) * 1.2;  droop = 0
        case .hungry:   wobble = 1.9;                        droop = 1.5
        case .sleeping: wobble = 1.1;                        droop = 1.3
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

        let path = CGMutablePath()
        path.addPath(stroked)
        path.addEllipse(in: CGRect(x: tipX - 0.95, y: tipY - 0.95, width: 1.9, height: 1.9))
        return path
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
        p.move(to: CGPoint(x: x + rr * cos(.pi - theta), y: y + rr * sin(.pi - theta)))
        p.addArc(center: centre, radius: rr,
                 startAngle: .pi - theta, endAngle: theta, clockwise: true)
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
