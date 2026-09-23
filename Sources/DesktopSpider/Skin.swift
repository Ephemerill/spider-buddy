import AppKit
import CoreGraphics

// MARK: - Skin
//
// How the coat is painted. A flat coat is one colour for the body and one
// for the legs. Everything else — gradients, the living coats — is a
// *paint*: a function from a point in body space (and the clock) to a
// colour. The body is filled with it as a gradient clipped to the outline,
// with any texture (crust, stars, blobs) drawn on top; each leg segment is
// stroked in the colour sampled at its middle, which is what makes a
// rainbow spider's legs each a different colour.

/// A colour field over the body, in body units: +x toward the nose, +y up.
struct Paint {
    /// The colours in order along the axis.
    var stops: [RGB]
    var direction: GradientDirection
    /// Shift along the axis, in whole cycles; what the living coats move.
    var phase: CGFloat = 0
    /// How many times the colours repeat across the body. 1 = once.
    var repeats: CGFloat = 1
    /// Whether the stops wrap round (rainbow) or the ends hold (sunset).
    var wraps = false
    /// Mixed toward white by this much: a lightning flash, a pulse.
    var flash: CGFloat = 0
    var texture: Texture = .none

    enum Texture {
        case none
        /// Mottled blotches in the given tones.
        case blotches([RGB], drift: CGFloat)
        /// Dark plates floating over the glow beneath.
        case crust(RGB, t: CGFloat)
        /// Little points of light that come and go.
        case stars(RGB, t: CGFloat, count: Int)
        /// A lightning bolt across the abdomen.
        case bolt(CGFloat)
    }

    // The body spans roughly x -32…26, y -22…18; the axis maps that onto 0…1.
    static func axis(_ p: V2, _ dir: GradientDirection) -> CGFloat {
        switch dir {
        case .along: return (26 - p.x) / 58
        case .down: return (18 - p.y) / 40
        case .diagonal: return ((26 - p.x) / 58 + (18 - p.y) / 40) / 2
        case .radial: return min((p - V2(-3, -2)).length / 30, 1)
        }
    }

    /// The colour at `u` along the axis, before texture.
    func colour(u raw: CGFloat) -> RGB {
        var u = raw * repeats + phase
        if wraps { u -= floor(u) } else { u = clamp(u, 0, 1) }
        let n = stops.count
        guard n > 1 else { return stops.first ?? RGB(0.5, 0.5, 0.5) }
        let segs = CGFloat(wraps ? n : n - 1)
        let f = u * segs
        let i = min(Int(f), Int(segs) - 1)
        let t = f - CGFloat(i)
        let a = stops[i % n], b = stops[(i + 1) % n]
        var c = a.mix(b, t)
        if flash > 0 { c = c.lighter(flash) }
        return c
    }

    func colour(at p: V2) -> RGB { colour(u: Paint.axis(p, direction)) }

    /// The colour of the whole thing, roughly: what the outline and eyes
    /// are derived from.
    var average: RGB {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        for s in stops { r += s.r; g += s.g; b += s.b }
        let n = CGFloat(max(stops.count, 1))
        var c = RGB(r / n, g / n, b / n)
        if case .crust(let k, _) = texture { c = c.mix(k, 0.5) }
        return c
    }

    /// Fills `path` (in body space) with the paint. The gradient is
    /// resampled into many even stops, so moving and repeating ones need
    /// nothing special from Core Graphics.
    func fill(_ path: CGPath, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let n = 48
        var comps: [CGFloat] = []
        var locs: [CGFloat] = []
        comps.reserveCapacity(n * 4)
        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            let c = colour(u: u)
            comps += [c.r, c.g, c.b, 1]
            locs.append(u)
        }
        if let grad = CGGradient(colorSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: comps, locations: locs, count: n) {
            let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            switch direction {
            case .along:
                ctx.drawLinearGradient(grad, start: CGPoint(x: 26, y: 0), end: CGPoint(x: -32, y: 0), options: opts)
            case .down:
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 18), end: CGPoint(x: 0, y: -22), options: opts)
            case .diagonal:
                ctx.drawLinearGradient(grad, start: CGPoint(x: 26, y: 18), end: CGPoint(x: -32, y: -22), options: opts)
            case .radial:
                ctx.drawRadialGradient(grad, startCenter: CGPoint(x: -3, y: -2), startRadius: 0,
                                       endCenter: CGPoint(x: -3, y: -2), endRadius: 30, options: opts)
            }
        }
        drawTexture(in: ctx)
        ctx.restoreGState()
    }

    /// Fixed, well-spread spots over the body for blotches, plates and
    /// stars, so a texture never crawls about on its own.
    private static let spots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (-22, 6, 7), (-9, 9, 6), (-18, -6, 5.5), (-4, -3, 6.5), (12, 5, 6), (4, 10, 4.5), (18, -4, 5),
        (-27, -2, 4), (-12, 1, 3.5), (8, -8, 4), (-2, 14, 3.5), (16, 12, 3), (-20, 14, 3), (22, 6, 3.5),
        (-8, -12, 3), (2, -13, 2.8), (-30, 8, 2.5), (10, 15, 2.5), (-14, 16, 2.4), (20, 0, 2.6),
    ]

    private func drawTexture(in ctx: CGContext) {
        switch texture {
        case .none:
            break
        case .blotches(let tones, let drift):
            guard !tones.isEmpty else { return }
            for (i, s) in Paint.spots.enumerated() {
                let tone = tones[i % tones.count]
                let dx = sin(drift * 0.7 + CGFloat(i) * 1.9) * 1.2
                let dy = cos(drift * 0.5 + CGFloat(i) * 1.3) * 1.0
                ctx.setFillColor(tone.cg)
                ctx.fillEllipse(in: CGRect(x: s.x + dx - s.r * 1.3, y: s.y + dy - s.r, width: s.r * 2.6, height: s.r * 2))
            }
        case .crust(let dark, let t):
            // Plates of cooled rock drifting over the glow, each with a
            // softer core so they read as thick.
            for (i, s) in Paint.spots.enumerated() where i % 2 == 0 {
                let k = CGFloat(i)
                let dx = sin(t * 0.45 + k * 2.1) * 2.2
                let dy = cos(t * 0.38 + k * 1.7) * 1.6
                let r = s.r * (0.95 + 0.12 * sin(t * 0.9 + k))
                let rect = CGRect(x: s.x + dx - r * 1.2, y: s.y + dy - r * 0.85, width: r * 2.4, height: r * 1.7)
                ctx.setFillColor(dark.cg)
                ctx.fillEllipse(in: rect)
                ctx.setFillColor(dark.lighter(0.12).cg)
                ctx.fillEllipse(in: rect.insetBy(dx: r * 0.45, dy: r * 0.4))
            }
        case .stars(let tint, let t, let count):
            for (i, s) in Paint.spots.prefix(count).enumerated() {
                let k = CGFloat(i)
                let tw = 0.5 + 0.5 * sin(t * (1.6 + 0.3 * CGFloat(i % 4)) + k * 2.3)
                let r = 0.6 + tw * 0.9
                ctx.setFillColor(tint.alpha(0.35 + 0.65 * tw))
                let c = CGPoint(x: s.x + sin(k * 3.1) * 3, y: s.y + cos(k * 2.7) * 3)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                if i % 5 == 0, tw > 0.6 {
                    // A four-point twinkle on the brightest.
                    ctx.setStrokeColor(tint.alpha((tw - 0.6) * 2))
                    ctx.setLineWidth(0.7)
                    let l = r * 2.6
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: c.x - l, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + l, y: c.y))
                    ctx.move(to: CGPoint(x: c.x, y: c.y - l)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + l))
                    ctx.strokePath()
                }
            }
        case .bolt(let a):
            guard a > 0.01 else { return }
            ctx.setStrokeColor(CGColor(red: 1, green: 0.98, blue: 0.75, alpha: a))
            ctx.setLineWidth(2.2)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -8, y: 15))
            ctx.addLine(to: CGPoint(x: -15, y: 4))
            ctx.addLine(to: CGPoint(x: -10, y: 4))
            ctx.addLine(to: CGPoint(x: -18, y: -9))
            ctx.strokePath()
        }
    }
}

// MARK: - Palette

/// The derived colours the renderer actually paints with.
struct Palette {
    var outline: CGColor
    var outlineFar: CGColor
    var bodyFill: CGColor
    var bodyLight: CGColor
    var headFill: CGColor
    var legFill: CGColor
    var legLight: CGColor
    var legFar: CGColor
    var eyeDark: CGColor
    var accent: CGColor
    var accentRGB: RGB
    /// Present for anything that is not one flat colour.
    var paint: Paint?
    /// For paints whose legs should not simply sample the gradient (lava
    /// legs are cooled rock, camouflage legs are its tones).
    var legTones: [RGB]?
    /// How much of the body's own light/shadow to keep over a paint.
    var sheen: CGFloat = 1

    init(body: RGB, legs: RGB, accent: RGB, paint: Paint? = nil) {
        // Dark coats need a rim that is lighter than the body, not darker,
        // or the outline disappears.
        let dark = body.luma < 0.3
        let rim = dark ? body.lighter(0.22) : body.darker(0.66)
        outline = rim.cg
        outlineFar = (dark ? rim.darker(0.25) : rim.darker(0.15)).cg
        bodyFill = body.cg
        bodyLight = body.lighter(dark ? 0.16 : 0.34).cg
        headFill = body.mix(legs, 0.25).lighter(0.06).cg
        legFill = legs.cg
        legLight = legs.lighter(0.18).cg
        legFar = legs.darker(0.24).cg
        eyeDark = (dark ? RGB(0.05, 0.04, 0.05) : body.darker(0.78)).cg
        accentRGB = accent
        self.accent = accent.cg
        self.paint = paint
    }

    /// The leg colour at a point, for whichever way the coat is painted.
    func legColour(at p: V2, segment: Int) -> RGB {
        if let tones = legTones, !tones.isEmpty {
            return tones[abs(Int(p.x.rounded()) / 7 + segment) % tones.count]
        }
        if let paint { return paint.colour(at: p).darker(0.12) }
        let c = legFill.components ?? [0.5, 0.5, 0.5, 1]
        return RGB(c[0], c[1], c[2])
    }

    /// Fills a body part: the flat colour, or the paint.
    func fillBody(_ path: CGPath, head: Bool, in ctx: CGContext) {
        if let paint {
            paint.fill(path, in: ctx)
        } else {
            ctx.addPath(path)
            ctx.setFillColor(head ? headFill : bodyFill)
            ctx.fillPath()
        }
    }
}

extension SpiderLook {
    /// The palette for this look at this moment. `surroundings` is what is
    /// behind it, for camouflage.
    func palette(time: CGFloat, surroundings: RGB) -> Palette {
        let accent = accentRGB
        switch skin {
        case .coat:
            return Palette(body: coat.body, legs: coat.legs, accent: accent)
        case .custom:
            return Palette(body: custom.body, legs: custom.legs, accent: accent)
        case .gradient:
            let p = Paint(stops: gradient.stops, direction: gradient.direction)
            return Palette.painted(p, accent: accent)
        case .customGradient:
            var p = Paint(stops: customGradient.stops, direction: customGradient.direction)
            if customGradient.shimmer { p.phase = sin(time * 0.6) * 0.18 }
            return Palette.painted(p, accent: accent)
        case .living:
            return living.palette(time: time, surroundings: surroundings, accent: accent)
        }
    }
}

extension Palette {
    /// A palette for a paint: outline and eyes from its average colour.
    static func painted(_ paint: Paint, accent: RGB, legTones: [RGB]? = nil, sheen: CGFloat = 1) -> Palette {
        let avg = paint.average
        var pal = Palette(body: avg, legs: avg.darker(0.12), accent: accent, paint: paint)
        pal.legTones = legTones
        pal.sheen = sheen
        return pal
    }
}

extension LivingCoat {
    func palette(time t: CGFloat, surroundings: RGB, accent: RGB) -> Palette {
        switch self {
        case .rainbow:
            var p = Paint(stops: (0..<7).map { RGB.hue(CGFloat($0) / 7, sat: 0.85, val: 0.95) }, direction: .along)
            p.wraps = true
            p.repeats = 1.2
            p.phase = t * 0.25
            return .painted(p, accent: accent, sheen: 0.5)
        case .lava:
            var p = Paint(stops: [RGB(0.98, 0.86, 0.22), RGB(0.98, 0.42, 0.08), RGB(0.72, 0.10, 0.04), RGB(0.98, 0.42, 0.08)], direction: .diagonal)
            p.wraps = true
            p.repeats = 1.6
            p.phase = t * 0.18
            let crust = RGB(0.16, 0.08, 0.06)
            p.texture = .crust(crust, t: t)
            var pal = Palette.painted(p, accent: accent, legTones: [crust.lighter(0.08), RGB(0.42, 0.14, 0.06), crust.lighter(0.16)], sheen: 0.3)
            pal.outline = RGB(0.10, 0.04, 0.03).cg
            pal.outlineFar = RGB(0.06, 0.02, 0.02).cg
            pal.eyeDark = RGB(0.10, 0.04, 0.03).cg
            return pal
        case .camo:
            // Its base is whatever is behind it; the blotches are that
            // colour pushed a little either way, so it still reads as a
            // spider up close and melts away from across the room.
            let base = surroundings
            let dark = base.luma < 0.3
            let tones = [base.darker(dark ? 0 : 0.16).lighter(dark ? 0.12 : 0), base.lighter(dark ? 0.22 : 0.14), base.darker(dark ? 0 : 0.28).lighter(dark ? 0.06 : 0)]
            var p = Paint(stops: [base, base.mix(tones[0], 0.4), base], direction: .down)
            p.texture = .blotches(tones, drift: t)
            var pal = Palette.painted(p, accent: accent, legTones: [base, tones[0], tones[1]], sheen: 0.35)
            let rim = dark ? base.lighter(0.30) : base.darker(0.42)
            pal.outline = rim.cg
            pal.outlineFar = rim.darker(0.12).cg
            pal.eyeDark = (dark ? RGB(0.05, 0.04, 0.05) : base.darker(0.72)).cg
            return pal
        case .galaxy:
            var p = Paint(stops: [RGB(0.08, 0.06, 0.22), RGB(0.30, 0.12, 0.46), RGB(0.10, 0.20, 0.50), RGB(0.08, 0.06, 0.22)], direction: .diagonal)
            p.wraps = true
            p.repeats = 1.3
            p.phase = t * 0.06
            p.texture = .stars(RGB(1, 0.98, 0.92), t: t, count: 16)
            var pal = Palette.painted(p, accent: accent, sheen: 0.4)
            pal.outline = RGB(0.36, 0.30, 0.56).cg
            pal.outlineFar = RGB(0.26, 0.22, 0.42).cg
            return pal
        case .ocean:
            var p = Paint(stops: [RGB(0.10, 0.36, 0.62), RGB(0.24, 0.72, 0.78), RGB(0.86, 0.96, 0.98), RGB(0.24, 0.72, 0.78)], direction: .down)
            p.wraps = true
            p.repeats = 1.5
            p.phase = -t * 0.35
            return .painted(p, accent: accent, sheen: 0.4)
        case .aurora:
            var p = Paint(stops: [RGB(0.10, 0.14, 0.30), RGB(0.16, 0.80, 0.56), RGB(0.42, 0.28, 0.72), RGB(0.16, 0.62, 0.80)], direction: .diagonal)
            p.wraps = true
            p.repeats = 1.4
            p.phase = t * 0.12 + sin(t * 0.7) * 0.08
            var pal = Palette.painted(p, accent: accent, sheen: 0.5)
            pal.outline = RGB(0.12, 0.16, 0.30).cg
            pal.outlineFar = RGB(0.08, 0.10, 0.22).cg
            return pal
        case .disco:
            let h = (t * 0.08).truncatingRemainder(dividingBy: 1)
            let body = RGB.hue(h, sat: 0.75, val: 0.92)
            return Palette(body: body, legs: RGB.hue(h + 0.06, sat: 0.8, val: 0.78), accent: accent)
        case .fire:
            let flick = sin(t * 9.1) * 0.05 + sin(t * 13.7) * 0.035
            var p = Paint(stops: [RGB(0.98, 0.94, 0.42), RGB(0.98, 0.58, 0.10), RGB(0.86, 0.18, 0.06), RGB(0.30, 0.06, 0.04)], direction: .down)
            p.phase = -0.1 + flick
            p.repeats = 1.15
            var pal = Palette.painted(p, accent: accent, sheen: 0.3)
            pal.outline = RGB(0.34, 0.08, 0.04).cg
            pal.outlineFar = RGB(0.24, 0.05, 0.03).cg
            return pal
        case .frost:
            var p = Paint(stops: [RGB(0.90, 0.97, 1.0), RGB(0.68, 0.86, 0.98), RGB(0.86, 0.94, 1.0)], direction: .diagonal)
            p.phase = sin(t * 0.5) * 0.1
            p.texture = .stars(RGB(1, 1, 1), t: t * 1.6, count: 12)
            var pal = Palette.painted(p, accent: accent, sheen: 0.7)
            pal.outline = RGB(0.44, 0.60, 0.76).cg
            pal.outlineFar = RGB(0.36, 0.50, 0.66).cg
            pal.eyeDark = RGB(0.16, 0.26, 0.42).cg
            return pal
        case .toxic:
            let pulse = 0.5 + 0.5 * sin(t * 2.4)
            let glow = RGB(0.56, 1.0, 0.18).mix(RGB(0.30, 0.78, 0.10), 1 - pulse)
            var p = Paint(stops: [RGB(0.12, 0.16, 0.10), RGB(0.16, 0.26, 0.12)], direction: .down)
            p.texture = .blotches([glow, glow.darker(0.2), glow.lighter(0.25)], drift: t * 0.8)
            var pal = Palette.painted(p, accent: accent, legTones: [RGB(0.16, 0.22, 0.12), glow.darker(0.35), RGB(0.16, 0.22, 0.12)], sheen: 0.3)
            pal.outline = RGB(0.08, 0.10, 0.06).cg
            pal.outlineFar = RGB(0.05, 0.06, 0.04).cg
            pal.eyeDark = glow.darker(0.5).cg
            return pal
        case .pearl:
            var p = Paint(stops: (0..<6).map { RGB.hue(CGFloat($0) / 6, sat: 0.22, val: 0.98) }, direction: .diagonal)
            p.wraps = true
            p.repeats = 0.8
            p.phase = t * 0.05
            var pal = Palette.painted(p, accent: accent, sheen: 0.9)
            pal.outline = RGB(0.62, 0.56, 0.62).cg
            pal.outlineFar = RGB(0.52, 0.46, 0.52).cg
            pal.eyeDark = RGB(0.30, 0.24, 0.32).cg
            return pal
        case .candy:
            let red = RGB(0.88, 0.16, 0.20), white = RGB(0.99, 0.97, 0.95)
            var p = Paint(stops: [red, red, white, white], direction: .diagonal)
            p.wraps = true
            p.repeats = 3
            p.phase = t * 0.3
            var pal = Palette.painted(p, accent: accent, sheen: 0.4)
            pal.outline = RGB(0.42, 0.08, 0.10).cg
            pal.outlineFar = RGB(0.30, 0.05, 0.07).cg
            return pal
        case .storm:
            // Grey cloud; every few seconds a flash, with a bolt on the
            // abdomen at its brightest.
            let cycle = t.truncatingRemainder(dividingBy: 5.3)
            let flash = cycle < 0.35 ? max(0, sin(cycle / 0.35 * .pi)) : (cycle > 0.5 && cycle < 0.62 ? 0.5 : 0)
            var p = Paint(stops: [RGB(0.36, 0.38, 0.44), RGB(0.22, 0.24, 0.30), RGB(0.30, 0.32, 0.38)], direction: .down)
            p.phase = sin(t * 0.4) * 0.06
            p.flash = flash * 0.55
            p.texture = .bolt(flash)
            var pal = Palette.painted(p, accent: accent, sheen: 0.5)
            pal.outline = RGB(0.14, 0.15, 0.18).lighter(flash * 0.4).cg
            pal.outlineFar = RGB(0.10, 0.11, 0.14).cg
            return pal
        case .chrome:
            var p = Paint(stops: [RGB(0.62, 0.64, 0.68), RGB(0.98, 0.98, 1.0), RGB(0.40, 0.42, 0.48), RGB(0.86, 0.88, 0.92), RGB(0.62, 0.64, 0.68)], direction: .diagonal)
            p.wraps = true
            p.repeats = 1.1
            p.phase = t * 0.2
            var pal = Palette.painted(p, accent: accent, sheen: 0.2)
            pal.outline = RGB(0.22, 0.23, 0.26).cg
            pal.outlineFar = RGB(0.16, 0.17, 0.20).cg
            return pal
        }
    }
}
