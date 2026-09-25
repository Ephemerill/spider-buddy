import AppKit

// MARK: - Painting the furniture
//
// Each thing in the tank is painted once into an image of its own (and
// again only if it is resized, flipped or the scenery changes), lit from
// the top left, with a soft shadow where it meets the ground.

extension HabitatArt {
    /// Room around a thing's rectangle in its image: for leaves that
    /// spill over, its shadow, and its sway.
    static func itemPad(_ size: CGSize) -> CGFloat { max(10, min(size.width, size.height) * 0.14) }

    /// A thing's picture, `size` points across (its rectangle), painted
    /// with `pad` points of room round it.
    static func itemImage(_ it: HabitatItem, size: CGSize, biome: Biome, scale: CGFloat) -> CGImage? {
        let pad = itemPad(size)
        let full = CGSize(width: size.width + pad * 2, height: size.height + pad * 2)
        return image(full, scale: scale) { ctx in
            let r = CGRect(x: pad, y: pad, width: size.width, height: size.height)
            if it.onGround { contactShadow(ctx, r, it.kind) }
            ctx.saveGState()
            if it.flipped {
                ctx.translateBy(x: full.width, y: 0)
                ctx.scaleBy(x: -1, y: 1)
            }
            paintItem(it.kind, seed: it.seed, in: r, biome: biome, ctx)
            ctx.restoreGState()
            // The light of the place: dimmer and bluer by moonlight, and so on.
            let p = palette(biome)
            if p.tintAmount > 0.01 {
                ctx.saveGState()
                ctx.setBlendMode(.sourceAtop)
                ctx.setFillColor(alpha(p.tint, p.tintAmount))
                ctx.fill(CGRect(origin: .zero, size: full))
                ctx.restoreGState()
            }
        }
    }

    /// Something in it gives off light in the dark: the colour of it.
    static func glowColour(_ kind: HabitatItemKind, seed: Int, biome: Biome) -> CGColor? {
        switch kind {
        case .crystal: return crystalHue(seed)
        case .mushrooms: return biome == .cave || biome == .night ? c(0.55, 1, 0.75) : nil
        default: return nil
        }
    }

    static func crystalHue(_ seed: Int) -> CGColor {
        [c(0.62, 0.45, 0.95), c(0.35, 0.8, 0.98), c(0.98, 0.55, 0.75), c(0.45, 0.95, 0.75)][abs(seed) % 4]
    }

    static func contactShadow(_ ctx: CGContext, _ r: CGRect, _ kind: HabitatItemKind) {
        let w: CGFloat
        switch kind {
        case .plant: w = r.width * 0.5
        case .cactus, .corkBark, .bamboo: w = r.width * 0.8
        case .grass, .fern, .flower: w = r.width * 0.6
        default: w = r.width * 0.96
        }
        let h = min(max(r.height * 0.12, 5), 12)
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.minY + 1)
        ctx.scaleBy(x: 1, y: h / w)
        radial(ctx, [c(0, 0, 0, 0.32), c(0, 0, 0, 0.14), c(0, 0, 0, 0)], [0, 0.55, 1], at: .zero, radius: w / 2)
        ctx.restoreGState()
    }

    static func paintItem(_ kind: HabitatItemKind, seed s: Int, in r: CGRect, biome: Biome, _ ctx: CGContext) {
        let u = max(0.5, min(r.width / kind.defaultSize.width, r.height / kind.defaultSize.height))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        switch kind {
        case .log: paintLog(r, s, u, biome, ctx, hollow: false)
        case .hide: paintLog(r, s, u, biome, ctx, hollow: true)
        case .branch: paintBranch(r, s, u, ctx)
        case .driftwood: paintDriftwood(r, s, u, ctx)
        case .corkBark: paintBark(r, s, u, biome, ctx)
        case .rock, .boulder: paintRock(r, s, u, biome, ctx)
        case .bamboo: paintBamboo(r, s, u, ctx)
        case .cactus: paintCactus(r, s, u, ctx)
        case .plant: paintPlant(r, s, u, ctx)
        case .vine: paintVine(r, s, u, ctx)
        case .waterDish: paintDish(r, s, u, ctx)
        case .fern: paintFern(r, s, u, ctx)
        case .grass: paintGrass(r, s, u, biome, ctx)
        case .flower: paintFlowers(r, s, u, ctx)
        case .succulent: paintSucculent(r, s, u, ctx)
        case .mushrooms: paintMushrooms(r, s, u, biome, ctx)
        case .moss: paintMoss(r, s, u, biome, ctx)
        case .leafPile: paintLeaves(r, s, u, biome, ctx)
        case .pebbles: paintPebbles(r, s, u, ctx)
        case .twigs: paintTwigs(r, s, u, ctx)
        case .crystal: paintCrystals(r, s, u, ctx)
        }
    }

    // MARK: Wood

    static func woodColours(_ s: Int) -> (light: CGColor, mid: CGColor, dark: CGColor) {
        let v = rnd(s, 1) * 0.08
        return (c(0.72 + v, 0.54 + v, 0.34), c(0.55 + v, 0.38 + v * 0.8, 0.23), c(0.34 + v, 0.23 + v * 0.5, 0.14))
    }

    static func outline(_ ctx: CGContext, _ path: CGPath, _ col: CGColor, _ u: CGFloat) {
        ctx.addPath(path)
        ctx.setStrokeColor(alpha(shade(col, -0.5), 0.9))
        ctx.setLineWidth(1.2 * u)
        ctx.strokePath()
    }

    static func mossPatch(_ ctx: CGContext, along r: CGRect, y: CGFloat, seed s: Int, u: CGFloat, biome: Biome) {
        let snow = biome == .tundra
        let base = snow ? c(0.96, 0.97, 1) : (biome == .night ? c(0.2, 0.34, 0.26) : c(0.36, 0.56, 0.26))
        let hi = snow ? c(1, 1, 1) : shade(base, 0.2)
        let n = 5 + s % 4
        let x0 = r.minX + r.width * (0.1 + rnd(s, 40) * 0.3)
        let span = r.width * (snow ? 0.8 : 0.35 + rnd(s, 41) * 0.3)
        for k in 0..<n {
            let x = (snow ? r.minX + r.width * 0.1 : x0) + span * CGFloat(k) / CGFloat(n)
            let rr = (4 + rnd(s, 50 + k) * 5) * u
            ctx.setFillColor(k % 3 == 0 ? hi : base)
            ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr * 0.55, width: rr * 2.2, height: rr * 1.3))
        }
    }

    static func paintLog(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext, hollow: Bool) {
        let (light, mid, dark) = woodColours(s)
        let body = CGPath(roundedRect: r, cornerWidth: r.height / 2, cornerHeight: r.height / 2, transform: nil)
        fill(ctx, body, [light, mid, dark], [0, 0.45, 1], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        // Bark: long ridges and furrows.
        for k in 0..<9 {
            let y = r.minY + (CGFloat(k) + 0.5) / 9 * r.height
            ctx.setStrokeColor(alpha(k % 2 == 0 ? shade(dark, -0.2) : shade(light, 0.1), k % 2 == 0 ? 0.55 : 0.35))
            ctx.setLineWidth((k % 2 == 0 ? 1.6 : 1) * u)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: r.minX + r.height * 0.3, y: y))
            var x = r.minX + r.height * 0.3
            var j = 0
            while x < r.maxX - r.height * 0.3 {
                x += (14 + rnd(s + k, j) * 20) * u
                ctx.addLine(to: CGPoint(x: min(x, r.maxX), y: y + (rnd(s + 2, k * 20 + j) - 0.5) * 3 * u))
                j += 1
            }
            ctx.strokePath()
        }
        // Knots.
        for k in 0..<2 {
            let cx = r.minX + r.width * (0.3 + rnd(s + 3, k) * 0.4), cy = r.midY + (rnd(s + 4, k) - 0.5) * r.height * 0.35
            let kr = r.height * 0.13
            fill(ctx, CGPath(ellipseIn: CGRect(x: cx - kr * 1.4, y: cy - kr, width: kr * 2.8, height: kr * 2), transform: nil),
                 [shade(dark, -0.2), shade(mid, 0.1)], from: CGPoint(x: cx, y: cy - kr), to: CGPoint(x: cx, y: cy + kr))
            ctx.setStrokeColor(alpha(shade(dark, -0.3), 0.7))
            ctx.setLineWidth(0.9 * u)
            ctx.strokeEllipse(in: CGRect(x: cx - kr * 0.8, y: cy - kr * 0.5, width: kr * 1.6, height: kr))
        }
        // Light along the top, shade underneath.
        linear(ctx, [c(1, 1, 1, 0.22), c(1, 1, 1, 0)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.maxY - r.height * 0.3))
        ctx.restoreGState()
        outline(ctx, body, mid, u)
        // The ends: a cut face at the right, rings; a hollow at the left.
        let endW = r.height * 0.46
        let cut = CGRect(x: r.maxX - endW - 1 * u, y: r.minY + r.height * 0.04, width: endW, height: r.height * 0.92)
        let face = CGPath(ellipseIn: cut, transform: nil)
        fill(ctx, face, [c(0.93, 0.78, 0.55), c(0.78, 0.6, 0.38)], from: CGPoint(x: cut.minX, y: cut.maxY), to: CGPoint(x: cut.maxX, y: cut.minY))
        ctx.setStrokeColor(alpha(c(0.55, 0.38, 0.22), 0.6))
        ctx.setLineWidth(0.8 * u)
        for k in 1...4 {
            ctx.strokeEllipse(in: cut.insetBy(dx: CGFloat(k) * cut.width * 0.1, dy: CGFloat(k) * cut.height * 0.1))
        }
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cut.midX, y: cut.midY))
        ctx.addLine(to: CGPoint(x: cut.midX + cut.width * 0.3, y: cut.maxY - cut.height * 0.15))
        ctx.strokePath()
        outline(ctx, face, mid, u)
        if hollow {
            let hole = CGRect(x: r.minX + 2 * u, y: r.minY + r.height * 0.06, width: endW, height: r.height * 0.88)
            let rim = CGPath(ellipseIn: hole, transform: nil)
            fill(ctx, rim, [c(0.86, 0.7, 0.48), c(0.66, 0.5, 0.32)], from: CGPoint(x: hole.minX, y: hole.maxY), to: CGPoint(x: hole.maxX, y: hole.minY))
            let inside = hole.insetBy(dx: hole.width * 0.14, dy: hole.height * 0.12)
            fill(ctx, CGPath(ellipseIn: inside, transform: nil), [c(0.04, 0.03, 0.02), c(0.2, 0.13, 0.08)],
                 from: CGPoint(x: inside.midX, y: inside.maxY), to: CGPoint(x: inside.midX, y: inside.minY))
            outline(ctx, rim, mid, u)
        }
        if rnd(s, 7) < 0.7 || biome == .tundra {
            mossPatch(ctx, along: r.insetBy(dx: r.height * 0.3, dy: 0), y: r.maxY - 1.5 * u, seed: s, u: u, biome: biome)
        }
    }

    static func paintBranch(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let (light, mid, dark) = woodColours(s)
        let pts = Habitat.branchPoints(r, flipped: false).map(\.point)
        let base = max(6 * u, r.height * 0.1), tip = max(3 * u, r.height * 0.045)
        // A tapering limb: offset each side of the line, smoothed.
        func side(_ sign: CGFloat) -> [CGPoint] {
            var out: [CGPoint] = []
            for (i, p) in pts.enumerated() {
                let a = i == 0 ? pts[0] : pts[i - 1], b = i == pts.count - 1 ? pts[i] : pts[i + 1]
                let d = CGPoint(x: b.x - a.x, y: b.y - a.y)
                let len = max(hypot(d.x, d.y), 0.001)
                let n = CGPoint(x: -d.y / len, y: d.x / len)
                let w = (base + (tip - base) * CGFloat(i) / CGFloat(pts.count - 1)) / 2
                out.append(CGPoint(x: p.x + n.x * w * sign, y: p.y + n.y * w * sign))
            }
            return out
        }
        let top = side(1), bottom = side(-1)
        let limb = CGMutablePath()
        limb.move(to: bottom[0])
        limb.addLine(to: top[0])
        limb.addQuadCurve(to: top[2], control: top[1])
        limb.addArc(center: pts[2], radius: tip / 2, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
        limb.addQuadCurve(to: bottom[0], control: bottom[1])
        limb.closeSubpath()
        // Twigs first, behind.
        for k in 0..<4 {
            let t = 0.3 + CGFloat(k) * 0.17
            let bx = pts[0].x + (pts[2].x - pts[0].x) * t, by = pts[0].y + (pts[2].y - pts[0].y) * t + r.height * 0.04
            let dir = CGPoint(x: 0.35 + (rnd(s, k) - 0.5) * 0.6, y: 1)
            let len = r.height * (0.2 + rnd(s + 1, k) * 0.15)
            let end = CGPoint(x: bx + dir.x * len, y: by + dir.y * len)
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(2.4 * u)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: bx, y: by))
            ctx.addQuadCurve(to: end, control: CGPoint(x: bx + dir.x * len * 0.2, y: by + len * 0.6))
            ctx.strokePath()
            for q in 0..<2 {
                leafShape(ctx, at: CGPoint(x: end.x + CGFloat(q) * 3 * u, y: end.y - CGFloat(q) * 5 * u), length: (11 + rnd(s + 2, k * 2 + q) * 6) * u,
                          angle: 0.4 + CGFloat(q) * 1.6 + rnd(s + 3, k) * 0.5, colour: q == 0 ? c(0.42, 0.66, 0.32) : c(0.33, 0.56, 0.27), u: u)
            }
        }
        fill(ctx, limb, [light, mid, dark], [0, 0.5, 1], from: CGPoint(x: pts[1].x - base, y: pts[1].y + base), to: CGPoint(x: pts[1].x + base, y: pts[1].y - base))
        ctx.saveGState()
        ctx.addPath(limb)
        ctx.clip()
        ctx.setStrokeColor(alpha(shade(dark, -0.2), 0.45))
        ctx.setLineWidth(0.8 * u)
        for k in 0..<5 {
            let off = (CGFloat(k) - 2) * base * 0.18
            ctx.beginPath()
            ctx.move(to: CGPoint(x: pts[0].x, y: pts[0].y + off))
            ctx.addQuadCurve(to: CGPoint(x: pts[2].x, y: pts[2].y + off * 0.4), control: CGPoint(x: pts[1].x, y: pts[1].y + off))
            ctx.strokePath()
        }
        ctx.restoreGState()
        outline(ctx, limb, mid, u)
    }

    static func leafShape(_ ctx: CGContext, at p: CGPoint, length l: CGFloat, angle: CGFloat, colour: CGColor, u: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        let leaf = CGMutablePath()
        leaf.move(to: .zero)
        leaf.addQuadCurve(to: CGPoint(x: l, y: 0), control: CGPoint(x: l * 0.45, y: l * 0.4))
        leaf.addQuadCurve(to: .zero, control: CGPoint(x: l * 0.55, y: -l * 0.34))
        fill(ctx, leaf, [shade(colour, 0.18), shade(colour, -0.12)], from: CGPoint(x: 0, y: l * 0.3), to: CGPoint(x: 0, y: -l * 0.3))
        ctx.setStrokeColor(alpha(shade(colour, -0.35), 0.8))
        ctx.setLineWidth(0.7 * u)
        ctx.beginPath()
        ctx.move(to: .zero)
        ctx.addLine(to: CGPoint(x: l * 0.9, y: 0))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func paintDriftwood(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let light = c(0.86, 0.81, 0.73), mid = c(0.7, 0.65, 0.58), dark = c(0.5, 0.46, 0.41)
        // A bleached trunk lying on its side: thick and knobbly at the root
        // end, tapering off to a broken tip.
        let body = CGMutablePath()
        let h = r.height * 0.6
        body.move(to: CGPoint(x: r.minX + r.width * 0.03, y: r.minY + h * 0.12))
        // The root end: a couple of knuckles.
        body.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.55), control: CGPoint(x: r.minX - r.width * 0.02, y: r.minY + h * 0.3))
        body.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.05, y: r.minY + h * 0.98), control: CGPoint(x: r.minX - r.width * 0.01, y: r.minY + h * 0.85))
        body.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.14, y: r.minY + h * 0.92), control: CGPoint(x: r.minX + r.width * 0.1, y: r.minY + h * 1.08))
        // Along the top to the tip.
        body.addCurve(to: CGPoint(x: r.maxX - r.width * 0.02, y: r.minY + h * 0.5),
                      control1: CGPoint(x: r.minX + r.width * 0.45, y: r.minY + h * 0.95), control2: CGPoint(x: r.minX + r.width * 0.75, y: r.minY + h * 0.62))
        // A splintered end.
        body.addLine(to: CGPoint(x: r.maxX, y: r.minY + h * 0.4))
        body.addLine(to: CGPoint(x: r.maxX - r.width * 0.03, y: r.minY + h * 0.33))
        body.addLine(to: CGPoint(x: r.maxX - r.width * 0.01, y: r.minY + h * 0.24))
        body.addCurve(to: CGPoint(x: r.minX + r.width * 0.03, y: r.minY + h * 0.12),
                      control1: CGPoint(x: r.minX + r.width * 0.7, y: r.minY + h * 0.05), control2: CGPoint(x: r.minX + r.width * 0.3, y: r.minY - h * 0.04))
        body.closeSubpath()
        // A stub of a branch sticking up.
        let stub = CGMutablePath()
        let sx = r.minX + r.width * (0.3 + rnd(s, 1) * 0.2)
        stub.move(to: CGPoint(x: sx, y: r.minY + h * 0.7))
        stub.addLine(to: CGPoint(x: sx - r.width * 0.06, y: r.maxY))
        stub.addLine(to: CGPoint(x: sx - r.width * 0.02, y: r.maxY - 2 * u))
        stub.addLine(to: CGPoint(x: sx + r.width * 0.05, y: r.minY + h * 0.75))
        stub.closeSubpath()
        fill(ctx, stub, [light, mid], from: CGPoint(x: sx - 10 * u, y: 0), to: CGPoint(x: sx + 10 * u, y: 0))
        outline(ctx, stub, mid, u)
        fill(ctx, body, [light, mid, dark], [0, 0.5, 1], from: CGPoint(x: 0, y: r.minY + h), to: CGPoint(x: 0, y: r.minY))
        ctx.saveGState()
        ctx.addPath(body)
        ctx.clip()
        ctx.setStrokeColor(alpha(dark, 0.5))
        ctx.setLineWidth(0.9 * u)
        // Grain running along it and swirling round the knot.
        for k in 0..<7 {
            let y0 = r.minY + h * (0.15 + CGFloat(k) * 0.12)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: r.minX, y: y0))
            ctx.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * (0.28 + CGFloat(k) * 0.04) + (rnd(s, k) - 0.5) * 4 * u),
                         control1: CGPoint(x: r.minX + r.width * 0.3, y: y0 + h * 0.15), control2: CGPoint(x: r.minX + r.width * 0.65, y: y0 - h * 0.05))
            ctx.strokePath()
        }
        let knot = CGPoint(x: r.minX + r.width * (0.45 + rnd(s, 3) * 0.2), y: r.minY + h * 0.5)
        ctx.setFillColor(alpha(dark, 0.8))
        ctx.fillEllipse(in: CGRect(x: knot.x - 5 * u, y: knot.y - 3 * u, width: 10 * u, height: 6 * u))
        ctx.strokeEllipse(in: CGRect(x: knot.x - 9 * u, y: knot.y - 5 * u, width: 18 * u, height: 10 * u))
        linear(ctx, [c(1, 1, 1, 0.25), c(1, 1, 1, 0)], from: CGPoint(x: 0, y: r.minY + h), to: CGPoint(x: 0, y: r.minY + h * 0.6))
        ctx.restoreGState()
        outline(ctx, body, mid, u)
    }

    static func paintBark(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) {
        let (light, mid, dark) = woodColours(s + 3)
        let slab = CGMutablePath()
        slab.move(to: CGPoint(x: r.minX, y: r.minY))
        slab.addLine(to: CGPoint(x: r.minX + r.width * 0.04, y: r.maxY - r.width * 0.3))
        slab.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.maxY - r.width * 0.12), control: CGPoint(x: r.midX, y: r.maxY + r.width * 0.05))
        slab.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        slab.closeSubpath()
        // Round like a split trunk: dark at the edges, light down the middle.
        fill(ctx, slab, [dark, mid, light, mid, shade(dark, -0.1)], [0, 0.2, 0.42, 0.75, 1],
             from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        ctx.saveGState()
        ctx.addPath(slab)
        ctx.clip()
        for k in 0..<10 {
            let x = r.minX + (CGFloat(k) + 0.5) / 10 * r.width
            ctx.setStrokeColor(alpha(k % 2 == 0 ? shade(dark, -0.35) : shade(light, 0.15), k % 2 == 0 ? 0.7 : 0.45))
            ctx.setLineWidth((k % 2 == 0 ? 2.6 : 1.2) * u)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: r.minY))
            ctx.addCurve(to: CGPoint(x: x + (rnd(s, k) - 0.5) * 8 * u, y: r.maxY),
                         control1: CGPoint(x: x + (rnd(s + 1, k) - 0.5) * 14 * u, y: r.minY + r.height * 0.33),
                         control2: CGPoint(x: x + (rnd(s + 2, k) - 0.5) * 14 * u, y: r.minY + r.height * 0.66))
            ctx.strokePath()
        }
        // Cross cracks.
        ctx.setStrokeColor(alpha(shade(dark, -0.4), 0.5))
        ctx.setLineWidth(1 * u)
        for k in 0..<6 {
            let y = r.minY + rnd(s + 5, k) * r.height
            let x = r.minX + rnd(s + 6, k) * r.width * 0.7
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + r.width * 0.25, y: y + 2 * u))
            ctx.strokePath()
        }
        ctx.restoreGState()
        outline(ctx, slab, mid, u)
        if rnd(s, 8) < 0.6 || biome == .tundra {
            mossPatch(ctx, along: r, y: r.maxY - r.width * 0.2, seed: s, u: u, biome: biome)
        }
    }

    // MARK: Stone

    static func rockPath(_ r: CGRect, _ s: Int) -> CGPath {
        let n = 9
        var pts: [CGPoint] = []
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi + 0.2
            let rad = 1 - rnd(s, k) * 0.16
            // A flat-bottomed stone: the lower half squashed onto the ground.
            pts.append(CGPoint(x: r.midX + cos(a) * r.width / 2 * rad,
                               y: r.minY + r.height * 0.3 + sin(a) * r.height * (sin(a) < 0 ? 0.3 : 0.7) * rad))
        }
        let p = CGMutablePath()
        p.move(to: CGPoint(x: (pts[n - 1].x + pts[0].x) / 2, y: (pts[n - 1].y + pts[0].y) / 2))
        for k in 0..<n {
            let nx = pts[(k + 1) % n]
            p.addQuadCurve(to: CGPoint(x: (pts[k].x + nx.x) / 2, y: (pts[k].y + nx.y) / 2), control: pts[k])
        }
        p.closeSubpath()
        return p
    }

    static func rockColour(_ biome: Biome, _ s: Int) -> CGColor {
        let v = (rnd(s, 1) - 0.5) * 0.08
        switch biome {
        case .desert: return c(0.76 + v, 0.58 + v, 0.44 + v)
        case .beach: return c(0.66 + v, 0.64 + v, 0.6 + v)
        case .cave: return c(0.46 + v, 0.43 + v, 0.48 + v)
        case .tundra: return c(0.52 + v, 0.54 + v, 0.6 + v)
        default: return c(0.58 + v, 0.57 + v, 0.54 + v)
        }
    }

    static func paintRock(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) {
        let base = rockColour(biome, s)
        let path = rockPath(r, s)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        radial(ctx, [shade(base, 0.32), base, shade(base, -0.35)], [0, 0.5, 1],
               at: CGPoint(x: r.minX + r.width * 0.34, y: r.maxY - r.height * 0.2), radius: max(r.width, r.height) * 0.95)
        // Speckle and a crack or two.
        for k in 0..<Int(max(8, r.width * r.height / (60 * u * u))) {
            let x = r.minX + rnd(s + 9, k) * r.width, y = r.minY + rnd(s + 10, k) * r.height
            let rr = (0.5 + rnd(s + 11, k) * 1.2) * u
            ctx.setFillColor(k % 2 == 0 ? alpha(shade(base, -0.4), 0.4) : alpha(shade(base, 0.4), 0.35))
            ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }
        ctx.setStrokeColor(alpha(shade(base, -0.5), 0.55))
        ctx.setLineWidth(1 * u)
        let cx = r.minX + r.width * (0.4 + rnd(s, 20) * 0.3)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: cx, y: r.maxY))
        ctx.addLine(to: CGPoint(x: cx + 4 * u, y: r.maxY - r.height * 0.25))
        ctx.addLine(to: CGPoint(x: cx - 2 * u, y: r.maxY - r.height * 0.45))
        ctx.strokePath()
        // A cap of whatever settles on stone here.
        switch biome {
        case .tundra:
            let cap = CGMutablePath()
            cap.addEllipse(in: CGRect(x: r.minX + r.width * 0.1, y: r.maxY - r.height * 0.28, width: r.width * 0.8, height: r.height * 0.5))
            fill(ctx, cap, [c(1, 1, 1), c(0.86, 0.9, 1)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.maxY - r.height * 0.28))
        case .forest, .jungle, .night, .meadow:
            if rnd(s, 21) < 0.65 { mossPatch(ctx, along: r, y: r.maxY - r.height * 0.1, seed: s, u: u, biome: biome) }
        case .desert, .beach:
            linear(ctx, [alpha(c(0.96, 0.86, 0.66), 0.45), alpha(c(0.96, 0.86, 0.66), 0)], from: CGPoint(x: 0, y: r.minY), to: CGPoint(x: 0, y: r.minY + r.height * 0.35))
        case .cave:
            break
        }
        ctx.restoreGState()
        outline(ctx, path, base, u)
    }

    static func paintPebbles(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        for k in 0..<9 {
            let w = (10 + rnd(s, k) * 12) * u
            let h = w * (0.55 + rnd(s + 1, k) * 0.25)
            let x = r.minX + rnd(s + 2, k) * (r.width - w)
            let y = r.minY + (k % 3 == 0 ? h * 0.35 : 0)
            let col = [c(0.62, 0.6, 0.57), c(0.72, 0.64, 0.54), c(0.5, 0.5, 0.52), c(0.8, 0.76, 0.7)][(k + s) % 4]
            let p = CGPath(ellipseIn: CGRect(x: x, y: y, width: w, height: h), transform: nil)
            ctx.saveGState()
            ctx.addPath(p)
            ctx.clip()
            radial(ctx, [shade(col, 0.35), col, shade(col, -0.3)], [0, 0.45, 1], at: CGPoint(x: x + w * 0.35, y: y + h * 0.7), radius: w * 0.8)
            ctx.restoreGState()
            outline(ctx, p, col, u * 0.7)
        }
    }

    // MARK: Plants

    static func paintBamboo(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let stalks = 3
        for k in 0..<stalks {
            let w = r.width * 0.2
            let x = r.minX + r.width * (0.2 + CGFloat(k) * 0.3) - w / 2
            let h = r.height * (k == 1 ? 1 : 0.7 + rnd(s, k) * 0.2)
            let col = k == 1 ? c(0.56, 0.72, 0.3) : c(0.5, 0.66, 0.28)
            let stalk = CGPath(roundedRect: CGRect(x: x, y: r.minY, width: w, height: h), cornerWidth: w * 0.3, cornerHeight: w * 0.3, transform: nil)
            fill(ctx, stalk, [shade(col, -0.25), shade(col, 0.2), col, shade(col, -0.3)], [0, 0.3, 0.6, 1],
                 from: CGPoint(x: x, y: 0), to: CGPoint(x: x + w, y: 0))
            // Nodes.
            let seg = (34 + rnd(s + 1, k) * 10) * u
            var y = r.minY + seg
            while y < r.minY + h - 6 * u {
                ctx.setFillColor(shade(col, -0.35))
                ctx.fill(CGRect(x: x - 1 * u, y: y - 1.2 * u, width: w + 2 * u, height: 2.4 * u))
                ctx.setFillColor(alpha(shade(col, 0.35), 0.8))
                ctx.fill(CGRect(x: x, y: y + 1.2 * u, width: w, height: 1 * u))
                if rnd(s + 2, Int(y)) < 0.35 {
                    leafShape(ctx, at: CGPoint(x: x + w, y: y), length: (22 + rnd(s + 3, Int(y)) * 10) * u, angle: 0.5, colour: c(0.42, 0.62, 0.3), u: u)
                }
                y += seg
            }
            outline(ctx, stalk, col, u)
            // Leaves at the top.
            for q in 0..<3 {
                leafShape(ctx, at: CGPoint(x: x + w / 2, y: r.minY + h - 2 * u), length: (24 + rnd(s + 4, k * 3 + q) * 10) * u,
                          angle: 0.5 + CGFloat(q) * 1.0, colour: c(0.44, 0.66, 0.3), u: u)
            }
        }
    }

    static func paintCactus(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let green = c(0.4, 0.64, 0.4)
        let w = r.width * 0.4
        let trunk = CGPath(roundedRect: CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height * 0.97), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        let arms = CGMutablePath()
        for (side, lift, len) in [(CGFloat(-1), CGFloat(0.35), CGFloat(0.35)), (1, 0.5, 0.3)] {
            let aw = w * 0.62
            let elbowX = side > 0 ? r.midX + w * 0.3 : r.midX - w * 0.3
            let outX = side > 0 ? r.midX + w / 2 + aw * 0.55 : r.midX - w / 2 - aw * 0.55
            let y = r.minY + r.height * lift
            arms.addRoundedRect(in: CGRect(x: min(elbowX, outX) - aw * 0.1, y: y, width: abs(outX - elbowX) + aw * 0.5, height: aw), cornerWidth: aw / 2, cornerHeight: aw / 2)
            arms.addRoundedRect(in: CGRect(x: outX - aw / 2, y: y, width: aw, height: r.height * len + aw), cornerWidth: aw / 2, cornerHeight: aw / 2)
        }
        // The arms, outlined, then the trunk over where they join it.
        fill(ctx, arms, [shade(green, -0.25), shade(green, 0.18), green, shade(green, -0.3)], [0, 0.35, 0.6, 1],
             from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        outline(ctx, arms, green, u)
        fill(ctx, trunk, [shade(green, -0.25), shade(green, 0.2), green, shade(green, -0.3)], [0, 0.35, 0.6, 1],
             from: CGPoint(x: r.midX - w / 2, y: 0), to: CGPoint(x: r.midX + w / 2, y: 0))
        // Ribs down the trunk.
        ctx.saveGState()
        ctx.addPath(trunk)
        ctx.clip()
        ctx.setStrokeColor(alpha(shade(green, -0.35), 0.6))
        ctx.setLineWidth(1.1 * u)
        for k in 1..<4 {
            let x = r.midX - w / 2 + CGFloat(k) / 4 * w
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: r.minY))
            ctx.addLine(to: CGPoint(x: x, y: r.maxY))
            ctx.strokePath()
        }
        ctx.restoreGState()
        outline(ctx, trunk, green, u)
        // Spines.
        ctx.setStrokeColor(c(0.98, 0.96, 0.84))
        ctx.setLineWidth(0.8 * u)
        for k in 0..<22 {
            let y = r.minY + rnd(s, k) * r.height * 0.95
            let side: CGFloat = k % 2 == 0 ? 1 : -1
            let x = r.midX + side * w * (0.2 + rnd(s + 1, k) * 0.3)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + side * 3 * u, y: y + 2 * u))
            ctx.strokePath()
        }
        if rnd(s, 30) < 0.6 {
            let top = CGPoint(x: r.midX, y: r.minY + r.height * 0.97)
            for q in 0..<5 {
                let a = CGFloat(q) / 5 * .pi * 2
                ctx.setFillColor(c(0.98, 0.5, 0.65))
                ctx.fillEllipse(in: CGRect(x: top.x + cos(a) * 3 * u - 3 * u, y: top.y + sin(a) * 2 * u - 1 * u, width: 6 * u, height: 5 * u))
            }
            ctx.setFillColor(c(1, 0.85, 0.4))
            ctx.fillEllipse(in: CGRect(x: top.x - 2 * u, y: top.y, width: 4 * u, height: 4 * u))
        }
    }

    static func paintPlant(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        // Terracotta pot.
        let pot = CGMutablePath()
        let pw = r.width * 0.4, ph = r.height * 0.2
        pot.move(to: CGPoint(x: r.midX - pw * 0.4, y: r.minY))
        pot.addLine(to: CGPoint(x: r.midX + pw * 0.4, y: r.minY))
        pot.addLine(to: CGPoint(x: r.midX + pw * 0.5, y: r.minY + ph * 0.8))
        pot.addLine(to: CGPoint(x: r.midX - pw * 0.5, y: r.minY + ph * 0.8))
        pot.closeSubpath()
        let potCol = c(0.78, 0.46, 0.3)
        fill(ctx, pot, [shade(potCol, -0.2), shade(potCol, 0.15), shade(potCol, -0.25)], [0, 0.4, 1], from: CGPoint(x: r.midX - pw / 2, y: 0), to: CGPoint(x: r.midX + pw / 2, y: 0))
        outline(ctx, pot, potCol, u)
        let rim = CGPath(roundedRect: CGRect(x: r.midX - pw * 0.56, y: r.minY + ph * 0.76, width: pw * 1.12, height: ph * 0.28), cornerWidth: 2 * u, cornerHeight: 2 * u, transform: nil)
        fill(ctx, rim, [shade(potCol, 0.2), potCol], from: CGPoint(x: 0, y: r.minY + ph), to: CGPoint(x: 0, y: r.minY + ph * 0.76))
        outline(ctx, rim, potCol, u)
        let stemBase = CGPoint(x: r.midX, y: r.minY + ph)
        let greens = [c(0.3, 0.56, 0.3), c(0.38, 0.64, 0.34), c(0.26, 0.5, 0.28)]
        // Stems and big leaves fanning out.
        for k in 0..<7 {
            let a = CGFloat(k - 3) * 0.3 + (rnd(s, k) - 0.5) * 0.15
            let len = r.height * (0.45 + rnd(s + 1, k) * 0.25)
            let tip = CGPoint(x: stemBase.x + sin(a) * len * 0.9, y: stemBase.y + cos(a) * len)
            ctx.setStrokeColor(c(0.28, 0.46, 0.24))
            ctx.setLineWidth(2 * u)
            ctx.beginPath()
            ctx.move(to: stemBase)
            ctx.addQuadCurve(to: tip, control: CGPoint(x: stemBase.x + sin(a) * len * 0.2, y: stemBase.y + len * 0.7))
            ctx.strokePath()
            bigPlantLeaf(ctx, at: tip, size: r.width * (0.26 + rnd(s + 2, k) * 0.08), angle: .pi / 2 - a * 1.4, colour: greens[k % 3], u: u)
        }
        // The broad leaves on top it can sit on.
        for k in 0..<3 {
            let x = r.minX + r.width * (0.3 + CGFloat(k) * 0.2)
            bigPlantLeaf(ctx, at: CGPoint(x: x, y: r.maxY - r.height * 0.16), size: r.width * 0.3,
                         angle: CGFloat(k - 1) * 0.35 + .pi / 2 - 0.1, colour: greens[(k + 1) % 3], u: u, flat: true)
        }
    }

    static func bigPlantLeaf(_ ctx: CGContext, at p: CGPoint, size l: CGFloat, angle: CGFloat, colour: CGColor, u: CGFloat, flat: Bool = false) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: flat ? 0 : angle - .pi / 2)
        let w = flat ? l * 0.9 : l * 0.62, h = flat ? l * 0.34 : l
        let leaf = CGMutablePath()
        leaf.move(to: CGPoint(x: 0, y: flat ? 0 : -h * 0.1))
        if flat {
            leaf.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        } else {
            leaf.addCurve(to: CGPoint(x: 0, y: h), control1: CGPoint(x: -w * 0.8, y: h * 0.2), control2: CGPoint(x: -w * 0.5, y: h * 0.9))
            leaf.addCurve(to: CGPoint(x: 0, y: -h * 0.1), control1: CGPoint(x: w * 0.5, y: h * 0.9), control2: CGPoint(x: w * 0.8, y: h * 0.2))
        }
        fill(ctx, leaf, [shade(colour, 0.22), colour, shade(colour, -0.2)], [0, 0.5, 1], from: CGPoint(x: -w / 2, y: h), to: CGPoint(x: w / 2, y: 0))
        ctx.setStrokeColor(alpha(shade(colour, 0.35), 0.8))
        ctx.setLineWidth(0.9 * u)
        ctx.beginPath()
        if flat {
            ctx.move(to: CGPoint(x: -w * 0.42, y: 0))
            ctx.addLine(to: CGPoint(x: w * 0.42, y: 0))
        } else {
            ctx.move(to: CGPoint(x: 0, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: h * 0.9))
            for q in 1..<4 {
                let y = h * CGFloat(q) / 4.5
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: -w * 0.3, y: y + h * 0.1))
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: w * 0.3, y: y + h * 0.1))
            }
        }
        ctx.strokePath()
        outline(ctx, leaf, colour, u * 0.8)
        ctx.restoreGState()
    }

    static func paintVine(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let green = c(0.3, 0.55, 0.3), dark = c(0.2, 0.4, 0.22)
        for (col, w, off) in [(dark, 3.2 * u, -2 * u), (green, 2.6 * u, 2 * u)] {
            ctx.setStrokeColor(col)
            ctx.setLineWidth(w)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: r.midX + off, y: r.maxY))
            ctx.addCurve(to: CGPoint(x: r.midX - off, y: r.minY),
                         control1: CGPoint(x: r.midX + off * 4, y: r.maxY - r.height * 0.33),
                         control2: CGPoint(x: r.midX - off * 4, y: r.maxY - r.height * 0.66))
            ctx.strokePath()
        }
        let n = max(3, Int(r.height / (18 * u)))
        for k in 0..<n {
            let t = (CGFloat(k) + 0.5) / CGFloat(n)
            let y = r.maxY - t * r.height
            let side: CGFloat = k % 2 == 0 ? 1 : -1
            let x = r.midX + side * 2 * u + sin(t * 6) * 3 * u
            heartLeaf(ctx, at: CGPoint(x: x, y: y), size: (11 + rnd(s, k) * 5) * u * (1 - t * 0.3),
                      angle: side > 0 ? -0.5 - rnd(s + 1, k) * 0.4 : .pi + 0.5 + rnd(s + 1, k) * 0.4,
                      colour: k % 3 == 0 ? c(0.36, 0.62, 0.34) : c(0.28, 0.52, 0.28), u: u)
        }
    }

    static func heartLeaf(_ ctx: CGContext, at p: CGPoint, size l: CGFloat, angle: CGFloat, colour: CGColor, u: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        let leaf = CGMutablePath()
        leaf.move(to: .zero)
        leaf.addCurve(to: CGPoint(x: l, y: 0), control1: CGPoint(x: l * 0.1, y: l * 0.55), control2: CGPoint(x: l * 0.7, y: l * 0.45))
        leaf.addCurve(to: .zero, control1: CGPoint(x: l * 0.7, y: -l * 0.45), control2: CGPoint(x: l * 0.1, y: -l * 0.55))
        fill(ctx, leaf, [shade(colour, 0.2), shade(colour, -0.15)], from: CGPoint(x: 0, y: l * 0.4), to: CGPoint(x: 0, y: -l * 0.4))
        ctx.setStrokeColor(alpha(shade(colour, 0.35), 0.8))
        ctx.setLineWidth(0.6 * u)
        ctx.beginPath()
        ctx.move(to: .zero)
        ctx.addLine(to: CGPoint(x: l * 0.85, y: 0))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func paintDish(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let stone = c(0.6, 0.58, 0.55)
        // The front of the bowl, then its rim seen from above, then water.
        let front = CGMutablePath()
        front.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.6))
        front.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.6))
        front.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.1, y: r.minY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        front.addLine(to: CGPoint(x: r.minX + r.width * 0.1, y: r.minY))
        front.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.6), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.1))
        front.closeSubpath()
        fill(ctx, front, [shade(stone, -0.25), shade(stone, 0.12), shade(stone, -0.3)], [0, 0.35, 1], from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.maxX, y: 0))
        outline(ctx, front, stone, u)
        let rim = CGRect(x: r.minX, y: r.minY + r.height * 0.34, width: r.width, height: r.height * 0.56)
        let rimPath = CGPath(ellipseIn: rim, transform: nil)
        fill(ctx, rimPath, [shade(stone, 0.3), stone], from: CGPoint(x: 0, y: rim.maxY), to: CGPoint(x: 0, y: rim.minY))
        outline(ctx, rimPath, stone, u)
        let water = rim.insetBy(dx: rim.width * 0.07, dy: rim.height * 0.16)
        fill(ctx, CGPath(ellipseIn: water, transform: nil), [c(0.5, 0.78, 0.92), c(0.3, 0.58, 0.8)], from: CGPoint(x: 0, y: water.maxY), to: CGPoint(x: 0, y: water.minY))
        ctx.setFillColor(c(1, 1, 1, 0.5))
        ctx.fillEllipse(in: CGRect(x: water.minX + water.width * 0.18, y: water.midY, width: water.width * 0.22, height: water.height * 0.25))
    }

    static func paintFern(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let greens = [c(0.28, 0.56, 0.3), c(0.2, 0.46, 0.25), c(0.36, 0.62, 0.34)]
        let base = CGPoint(x: r.midX, y: r.minY)
        for k in 0..<8 {
            let a = CGFloat(k) / 7 * 2.4 - 1.2 + (rnd(s, k) - 0.5) * 0.2
            let len = r.height * (0.75 + rnd(s + 1, k) * 0.3)
            let tip = CGPoint(x: base.x + sin(a) * len * 1.15, y: base.y + cos(a) * len * 0.95)
            let ctl = CGPoint(x: base.x + sin(a) * len * 0.35, y: base.y + len * 0.95)
            let col = greens[k % 3]
            ctx.setStrokeColor(shade(col, -0.25))
            ctx.setLineWidth(1.4 * u)
            ctx.beginPath()
            ctx.move(to: base)
            ctx.addQuadCurve(to: tip, control: ctl)
            ctx.strokePath()
            let n = 11
            for j in 1..<n {
                let t = CGFloat(j) / CGFloat(n)
                let pt = CGPoint(x: (1 - t) * (1 - t) * base.x + 2 * (1 - t) * t * ctl.x + t * t * tip.x,
                                 y: (1 - t) * (1 - t) * base.y + 2 * (1 - t) * t * ctl.y + t * t * tip.y)
                let d = CGPoint(x: 2 * (1 - t) * (ctl.x - base.x) + 2 * t * (tip.x - ctl.x), y: 2 * (1 - t) * (ctl.y - base.y) + 2 * t * (tip.y - ctl.y))
                let ang = atan2(d.y, d.x)
                let lw = ((1 - t) * 9 + 2.5) * u
                for side in [-1.0, 1.0] as [CGFloat] {
                    leafShape(ctx, at: pt, length: lw, angle: ang + side * 1.1, colour: col, u: u * 0.5)
                }
            }
        }
    }

    static func paintGrass(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) {
        let dry = biome == .desert || biome == .beach || biome == .tundra
        let cols = dry ? [c(0.76, 0.7, 0.44), c(0.66, 0.6, 0.36), c(0.84, 0.78, 0.5)] : [c(0.36, 0.62, 0.28), c(0.28, 0.52, 0.24), c(0.46, 0.7, 0.32)]
        for k in 0..<18 {
            let x = r.minX + r.width * (0.25 + rnd(s, k) * 0.5)
            let h = r.height * (0.5 + rnd(s + 1, k) * 0.5)
            let lean = (rnd(s + 2, k) - 0.5) * r.width * 0.9
            let w = (2 + rnd(s + 3, k) * 2.5) * u
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: x - w, y: r.minY))
            blade.addQuadCurve(to: CGPoint(x: x + lean, y: r.minY + h), control: CGPoint(x: x - w * 0.5 + lean * 0.1, y: r.minY + h * 0.6))
            blade.addQuadCurve(to: CGPoint(x: x + w, y: r.minY), control: CGPoint(x: x + w * 0.5 + lean * 0.2, y: r.minY + h * 0.55))
            blade.closeSubpath()
            let col = cols[k % 3]
            fill(ctx, blade, [shade(col, 0.2), shade(col, -0.2)], from: CGPoint(x: 0, y: r.minY + h), to: CGPoint(x: 0, y: r.minY))
            if k % 5 == 0 {
                // A seed head.
                ctx.setFillColor(dry ? c(0.9, 0.84, 0.6) : c(0.7, 0.66, 0.42))
                ctx.fillEllipse(in: CGRect(x: x + lean - 2 * u, y: r.minY + h - 2 * u, width: 4 * u, height: 9 * u))
            }
        }
    }

    static func paintFlowers(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let petals = [c(0.96, 0.46, 0.58), c(0.99, 0.8, 0.3), c(0.66, 0.54, 0.96), c(1, 0.98, 0.95), c(0.98, 0.58, 0.32)]
        for k in 0..<5 {
            let x = r.minX + r.width * (0.14 + CGFloat(k) * 0.18) + (rnd(s, k) - 0.5) * 8 * u
            let h = r.height * (0.55 + rnd(s + 1, k) * 0.4)
            let lean = (rnd(s + 2, k) - 0.5) * 8 * u
            ctx.setStrokeColor(c(0.3, 0.54, 0.28))
            ctx.setLineWidth(1.8 * u)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: x, y: r.minY))
            ctx.addQuadCurve(to: CGPoint(x: x + lean, y: r.minY + h), control: CGPoint(x: x + lean * 0.2, y: r.minY + h * 0.5))
            ctx.strokePath()
            leafShape(ctx, at: CGPoint(x: x + lean * 0.1, y: r.minY + h * 0.35), length: 12 * u, angle: k % 2 == 0 ? 0.6 : .pi - 0.6, colour: c(0.34, 0.6, 0.3), u: u)
            let cc = CGPoint(x: x + lean, y: r.minY + h)
            let col = petals[(k + s) % petals.count]
            let pr = (4.5 + rnd(s + 3, k) * 2) * u
            for q in 0..<6 {
                let a = CGFloat(q) / 6 * 2 * .pi + rnd(s, k)
                let pc = CGPoint(x: cc.x + cos(a) * pr * 0.9, y: cc.y + sin(a) * pr * 0.9)
                fill(ctx, CGPath(ellipseIn: CGRect(x: pc.x - pr * 0.7, y: pc.y - pr * 0.7, width: pr * 1.4, height: pr * 1.4), transform: nil),
                     [shade(col, 0.25), shade(col, -0.1)], from: cc, to: pc)
            }
            fill(ctx, CGPath(ellipseIn: CGRect(x: cc.x - pr * 0.5, y: cc.y - pr * 0.5, width: pr, height: pr), transform: nil),
                 [c(1, 0.9, 0.45), c(0.9, 0.62, 0.2)], from: CGPoint(x: cc.x, y: cc.y + pr), to: CGPoint(x: cc.x, y: cc.y - pr))
        }
    }

    static func paintSucculent(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let base = [c(0.52, 0.72, 0.62), c(0.62, 0.74, 0.5), c(0.56, 0.66, 0.74)][abs(s) % 3]
        let c0 = CGPoint(x: r.midX, y: r.minY + r.height * 0.25)
        for ring in 0..<3 {
            let n = 7 - ring
            let len = r.width * (0.5 - CGFloat(ring) * 0.12)
            for k in 0..<n {
                let a = .pi / 2 + (CGFloat(k) - CGFloat(n - 1) / 2) * (2.4 / CGFloat(n)) + CGFloat(ring) * 0.2
                let tip = CGPoint(x: c0.x + cos(a) * len, y: c0.y + sin(a) * len * 0.75)
                let leaf = CGMutablePath()
                let sideA = CGPoint(x: -sin(a) * len * 0.22, y: cos(a) * len * 0.22)
                leaf.move(to: CGPoint(x: c0.x + sideA.x * 0.3, y: c0.y + sideA.y * 0.3))
                leaf.addQuadCurve(to: tip, control: CGPoint(x: c0.x + cos(a) * len * 0.55 + sideA.x, y: c0.y + sin(a) * len * 0.5 + sideA.y))
                leaf.addQuadCurve(to: CGPoint(x: c0.x - sideA.x * 0.3, y: c0.y - sideA.y * 0.3), control: CGPoint(x: c0.x + cos(a) * len * 0.55 - sideA.x, y: c0.y + sin(a) * len * 0.5 - sideA.y))
                leaf.closeSubpath()
                let col = shade(base, CGFloat(ring) * 0.1)
                fill(ctx, leaf, [shade(col, 0.2), col, c(0.9, 0.5, 0.6)], [0, 0.75, 1], from: c0, to: tip)
                outline(ctx, leaf, col, u * 0.7)
            }
        }
    }

    static func paintMushrooms(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) {
        let glowing = biome == .cave || biome == .night
        for k in 0..<3 {
            let x = r.minX + r.width * (0.2 + CGFloat(k) * 0.3) + (rnd(s, k) - 0.5) * 6 * u
            let h = r.height * (0.55 + rnd(s + 1, k) * 0.45)
            let cw = r.width * (0.26 + rnd(s + 2, k) * 0.12)
            let stalk = CGMutablePath()
            stalk.move(to: CGPoint(x: x - cw * 0.14, y: r.minY))
            stalk.addQuadCurve(to: CGPoint(x: x - cw * 0.1, y: r.minY + h * 0.65), control: CGPoint(x: x - cw * 0.22, y: r.minY + h * 0.3))
            stalk.addLine(to: CGPoint(x: x + cw * 0.1, y: r.minY + h * 0.65))
            stalk.addQuadCurve(to: CGPoint(x: x + cw * 0.14, y: r.minY), control: CGPoint(x: x + cw * 0.22, y: r.minY + h * 0.3))
            stalk.closeSubpath()
            fill(ctx, stalk, [c(0.98, 0.95, 0.88), c(0.84, 0.8, 0.72)], from: CGPoint(x: x - cw * 0.2, y: 0), to: CGPoint(x: x + cw * 0.2, y: 0))
            outline(ctx, stalk, c(0.9, 0.86, 0.78), u * 0.8)
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: x - cw / 2, y: r.minY + h * 0.58))
            cap.addCurve(to: CGPoint(x: x + cw / 2, y: r.minY + h * 0.58),
                         control1: CGPoint(x: x - cw * 0.5, y: r.minY + h * 1.1), control2: CGPoint(x: x + cw * 0.5, y: r.minY + h * 1.1))
            cap.addQuadCurve(to: CGPoint(x: x - cw / 2, y: r.minY + h * 0.58), control: CGPoint(x: x, y: r.minY + h * 0.5))
            cap.closeSubpath()
            let col = glowing ? c(0.36, 0.8, 0.62) : (k % 2 == 0 ? c(0.86, 0.3, 0.22) : c(0.76, 0.56, 0.36))
            fill(ctx, cap, [shade(col, 0.28), col, shade(col, -0.25)], [0, 0.5, 1], from: CGPoint(x: x - cw * 0.3, y: r.minY + h), to: CGPoint(x: x + cw * 0.3, y: r.minY + h * 0.55))
            outline(ctx, cap, col, u * 0.8)
            if k % 2 == 0 || glowing {
                ctx.setFillColor(glowing ? c(0.85, 1, 0.9, 0.9) : c(1, 0.98, 0.92))
                for q in 0..<4 {
                    let dx = (CGFloat(q) - 1.5) * cw * 0.2
                    let dy = h * (0.72 + CGFloat(q % 2) * 0.12)
                    ctx.fillEllipse(in: CGRect(x: x + dx - 1.6 * u, y: r.minY + dy, width: 3.2 * u, height: 2.6 * u))
                }
            }
        }
    }

    static func paintMoss(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) {
        let snow = biome == .tundra
        let base = snow ? c(0.9, 0.93, 1) : c(0.34, 0.58, 0.28)
        for layer in 0..<2 {
            for k in 0..<14 {
                let x = r.minX + rnd(s + layer, k) * r.width
                let w = (12 + rnd(s + 2, k) * 18) * u
                let h = r.height * (0.6 + rnd(s + 3, k) * 0.6) * (layer == 0 ? 1 : 0.7)
                let col = shade(base, layer == 0 ? -0.1 : 0.12)
                fill(ctx, CGPath(ellipseIn: CGRect(x: x - w / 2, y: r.minY - h * 0.3, width: w, height: h * 1.3), transform: nil),
                     [shade(col, 0.15), shade(col, -0.15)], from: CGPoint(x: 0, y: r.minY + h), to: CGPoint(x: 0, y: r.minY))
            }
        }
        ctx.setFillColor(snow ? c(1, 1, 1, 0.8) : c(0.6, 0.82, 0.4, 0.8))
        for k in 0..<18 {
            let x = r.minX + rnd(s + 5, k) * r.width, y = r.minY + rnd(s + 6, k) * r.height * 0.9
            ctx.fillEllipse(in: CGRect(x: x - 1 * u, y: y - 1 * u, width: 2 * u, height: 2 * u))
        }
    }

    static func paintLeaves(_ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) {
        let cols: [CGColor] = biome == .tundra ? [c(0.62, 0.56, 0.46), c(0.72, 0.64, 0.52)]
            : [c(0.8, 0.46, 0.2), c(0.9, 0.64, 0.24), c(0.64, 0.34, 0.16), c(0.72, 0.56, 0.22)]
        for k in 0..<20 {
            let x = r.minX + rnd(s, k) * r.width
            let y = r.minY + rnd(s + 1, k) * r.height * 0.7
            leafShape(ctx, at: CGPoint(x: x - 7 * u, y: y), length: (12 + rnd(s + 2, k) * 5) * u, angle: (rnd(s + 3, k) - 0.5) * 1.2,
                      colour: cols[k % cols.count], u: u)
        }
    }

    static func paintTwigs(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let (light, mid, dark) = woodColours(s)
        for k in 0..<6 {
            let x0 = r.minX + rnd(s, k) * r.width * 0.5
            let y0 = r.minY + rnd(s + 1, k) * r.height * 0.4
            let len = r.width * (0.35 + rnd(s + 2, k) * 0.4)
            let a = (rnd(s + 3, k) - 0.5) * 0.6
            let end = CGPoint(x: x0 + cos(a) * len, y: y0 + sin(a) * len)
            for (col, w) in [(shade(dark, -0.2), (3.6 + rnd(s + 4, k) * 2) * u), (k % 2 == 0 ? mid : light, (2.2 + rnd(s + 4, k) * 2) * u)] {
                ctx.setStrokeColor(col)
                ctx.setLineWidth(w)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x0, y: y0))
                ctx.addLine(to: end)
                ctx.strokePath()
            }
        }
    }

    static func paintCrystals(_ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        let hue = crystalHue(s)
        // A dark rock they grow out of.
        let rock = CGPath(ellipseIn: CGRect(x: r.minX + r.width * 0.1, y: r.minY - r.height * 0.06, width: r.width * 0.8, height: r.height * 0.28), transform: nil)
        fill(ctx, rock, [c(0.42, 0.38, 0.44), c(0.24, 0.22, 0.26)], from: CGPoint(x: 0, y: r.minY + r.height * 0.22), to: CGPoint(x: 0, y: r.minY))
        let n = 5
        for k in 0..<n {
            let a = (CGFloat(k) - CGFloat(n - 1) / 2) * 0.3 + (rnd(s, k) - 0.5) * 0.15
            let len = r.height * (k == n / 2 ? 0.95 : 0.5 + rnd(s + 1, k) * 0.3)
            let w = r.width * (0.1 + rnd(s + 2, k) * 0.05)
            let base = CGPoint(x: r.midX + (CGFloat(k) - CGFloat(n - 1) / 2) * r.width * 0.12, y: r.minY + r.height * 0.08)
            ctx.saveGState()
            ctx.translateBy(x: base.x, y: base.y)
            ctx.rotate(by: -a)
            let left = CGMutablePath()
            left.move(to: CGPoint(x: -w, y: 0))
            left.addLine(to: CGPoint(x: -w, y: len * 0.78))
            left.addLine(to: CGPoint(x: 0, y: len))
            left.addLine(to: CGPoint(x: 0, y: 0))
            left.closeSubpath()
            let right = CGMutablePath()
            right.move(to: CGPoint(x: 0, y: 0))
            right.addLine(to: CGPoint(x: 0, y: len))
            right.addLine(to: CGPoint(x: w, y: len * 0.78))
            right.addLine(to: CGPoint(x: w, y: 0))
            right.closeSubpath()
            fill(ctx, left, [shade(hue, 0.45), shade(hue, 0.1)], from: CGPoint(x: 0, y: len), to: .zero)
            fill(ctx, right, [shade(hue, 0.05), shade(hue, -0.3)], from: CGPoint(x: 0, y: len), to: .zero)
            ctx.setStrokeColor(c(1, 1, 1, 0.55))
            ctx.setLineWidth(0.8 * u)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -w * 0.5, y: len * 0.1))
            ctx.addLine(to: CGPoint(x: -w * 0.5, y: len * 0.7))
            ctx.strokePath()
            outline(ctx, left, hue, u * 0.6)
            outline(ctx, right, hue, u * 0.6)
            ctx.restoreGState()
        }
    }

    // MARK: Pictures for the picker

    /// A thing on its own, for the Add tiles.
    static func thumbnail(_ kind: HabitatItemKind, side: CGFloat = 64) -> NSImage {
        let size = kind.defaultSize
        let k = min((side - 8) / size.width, (side - 8) / size.height)
        let w = size.width * k, h = size.height * k
        let item = HabitatItem(id: 0, kind: kind, x: 0, y: 0, w: w, h: h, flipped: false, seed: 4242, front: false)
        let img = image(CGSize(width: side, height: side), scale: 2) { ctx in
            let r = CGRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h)
            if !kind.hangs { contactShadow(ctx, r, kind) }
            paintItem(kind, seed: item.seed, in: r, biome: .meadow, ctx)
        }
        return NSImage(cgImage: img!, size: CGSize(width: side, height: side))
    }

    /// The scenery on its own, for the Scene tiles.
    static func biomeThumbnail(_ b: Biome, size: CGSize) -> NSImage {
        let img = image(size, scale: 2) { ctx in
            let r = CGRect(origin: .zero, size: size)
            paintSky(b, in: r, ctx)
            paintScenery(b, in: r, ctx)
            paintGround(b, in: r, ctx)
        }
        return NSImage(cgImage: img!, size: size)
    }

    /// A whole layout, for the Layout tiles.
    static func habitatThumbnail(_ h: Habitat, size: CGSize) -> NSImage {
        let img = image(size, scale: 2) { ctx in
            let r = CGRect(origin: .zero, size: size)
            paintSky(h.biome, in: r, ctx)
            paintScenery(h.biome, in: r, ctx)
            paintGround(h.biome, in: r, ctx)
            let sx = size.width / HabitatLayout.width, sy = size.height / HabitatLayout.height
            for it in h.items.sorted(by: { !$0.inFront && $1.inFront }) {
                let ir = it.rect
                let vr = CGRect(x: ir.minX * sx, y: ir.minY * sy, width: ir.width * sx, height: ir.height * sy)
                ctx.saveGState()
                if it.flipped {
                    ctx.translateBy(x: vr.midX * 2, y: 0)
                    ctx.scaleBy(x: -1, y: 1)
                }
                paintItem(it.kind, seed: it.seed, in: vr, biome: h.biome, ctx)
                ctx.restoreGState()
            }
        }
        return NSImage(cgImage: img!, size: size)
    }
}
