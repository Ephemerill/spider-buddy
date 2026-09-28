import AppKit

// MARK: - Painting the pieces
//
// The pieces structures are built from (HabitatPieces.swift), painted from
// their own layouts: every stick filled along its outline and shaded as a
// round thing lit from the top left, every block as what it is made of.
// Hardware is dark and matt, so it keeps to the back.

extension HabitatArt {
    /// What a stick is made of: how it is coloured and marked.
    enum StickLook {
        case wood(light: CGColor, mid: CGColor, dark: CGColor)
        case root, driftwood, bamboo, straw, liana, greenVine, metal, cord, birch, pvc, craft, jute
        /// Cork bark, and a green, soft plant stem.
        case bark, greenStem
    }

    static func stickLook(_ kind: HabitatItemKind, _ s: Int) -> StickLook {
        switch kind {
        case .root, .climbingRoot: return .root
        case .driftwoodArch, .driftwoodSnag: return .driftwood
        case .bambooPole, .bambooSegment: return .bamboo
        case .driedStem: return .straw
        case .thickVine: return .liana
        case .thinVine: return .greenVine
        case .brace, .horizontalSupport, .crossBrace: return .metal
        case .verticalSupport:
            let w = woodColours(s + 5)
            return .wood(light: shade(w.light, -0.15), mid: shade(w.mid, -0.15), dark: shade(w.dark, -0.1))
        case .hangingHook: return .cord
        case .dowel: return .birch
        case .pipe: return .pvc
        case .ladder: return .craft
        case .rope: return .jute
        default:
            let w = woodColours(s)
            return .wood(light: w.light, mid: w.mid, dark: w.dark)
        }
    }

    static func colours(_ look: StickLook) -> (light: CGColor, mid: CGColor, dark: CGColor) {
        switch look {
        case .wood(let l, let m, let d): return (l, m, d)
        case .root: return (c(0.56, 0.42, 0.3), c(0.4, 0.29, 0.2), c(0.24, 0.17, 0.12))
        case .driftwood: return (c(0.88, 0.84, 0.77), c(0.72, 0.67, 0.6), c(0.5, 0.46, 0.41))
        case .bamboo: return (c(0.8, 0.8, 0.46), c(0.6, 0.66, 0.32), c(0.38, 0.46, 0.2))
        case .straw: return (c(0.86, 0.76, 0.52), c(0.7, 0.58, 0.36), c(0.48, 0.38, 0.22))
        case .liana: return (c(0.52, 0.5, 0.32), c(0.38, 0.36, 0.22), c(0.22, 0.22, 0.14))
        case .greenVine: return (c(0.42, 0.66, 0.36), c(0.28, 0.52, 0.28), c(0.18, 0.36, 0.2))
        case .metal: return (c(0.36, 0.37, 0.4), c(0.2, 0.2, 0.22), c(0.1, 0.1, 0.11))
        case .cord: return (c(0.46, 0.4, 0.34), c(0.3, 0.26, 0.22), c(0.18, 0.15, 0.12))
        case .birch: return (c(0.93, 0.84, 0.66), c(0.82, 0.7, 0.5), c(0.6, 0.48, 0.32))
        case .pvc: return (c(0.98, 0.98, 0.96), c(0.86, 0.87, 0.86), c(0.62, 0.64, 0.64))
        case .craft: return (c(0.95, 0.86, 0.66), c(0.86, 0.74, 0.52), c(0.64, 0.52, 0.34))
        case .jute: return (c(0.82, 0.7, 0.5), c(0.66, 0.54, 0.36), c(0.44, 0.34, 0.22))
        case .bark: return (c(0.62, 0.46, 0.3), c(0.42, 0.3, 0.19), c(0.24, 0.16, 0.1))
        case .greenStem: return (c(0.5, 0.72, 0.38), c(0.34, 0.56, 0.28), c(0.2, 0.38, 0.18))
        }
    }

    /// A stick: filled, shaded round, marked as what it is made of, outlined.
    static func paintStick(_ st: Stick, look: StickLook, seed s: Int, u: CGFloat, _ ctx: CGContext) {
        let (light, mid, dark) = colours(look)
        let path = st.path()
        let sp = st.spine(step: 3)
        guard sp.count >= 2 else { return }
        let hw = st.halfWidths(sp)
        // Each point's side toward the light (the top left).
        let lightDir = V2(-0.45, 0.9).normalized
        let normals: [V2] = sp.indices.map { i in
            let d = (sp[min(i + 1, sp.count - 1)] - sp[max(i - 1, 0)]).normalized
            let n = V2(-d.y, d.x)
            return n.dot(lightDir) >= 0 ? n : -n
        }
        func offset(_ k: CGFloat) -> CGPath {
            let p = CGMutablePath()
            for i in sp.indices {
                let q = sp[i] + normals[i] * hw[i] * k
                if i == 0 { p.move(to: q.point) } else { p.addLine(to: q.point) }
            }
            return p
        }
        let avg = hw.reduce(0, +) / CGFloat(hw.count)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(mid)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.clip()
        ctx.setLineCap(.round)
        // Shade on the far side, light on the near.
        ctx.addPath(offset(-0.75))
        ctx.setStrokeColor(alpha(dark, 0.75))
        ctx.setLineWidth(max(avg * 1.1, 1))
        ctx.strokePath()
        ctx.addPath(offset(0.42))
        ctx.setStrokeColor(alpha(light, 0.8))
        ctx.setLineWidth(max(avg * 0.55, 0.8))
        ctx.strokePath()
        switch look {
        case .wood, .root, .driftwood, .straw, .liana, .birch, .craft, .bark:
            // Grain along it.
            ctx.setLineWidth(0.7 * u)
            ctx.setStrokeColor(alpha(shade(dark, -0.2), 0.4))
            for k: CGFloat in [-0.45, 0.05, 0.5] where avg > 2.5 * u {
                ctx.addPath(offset(k))
                ctx.strokePath()
            }
        case .bamboo:
            // Nodes across it.
            var run: CGFloat = 0
            var next = (26 + rnd(s, 3) * 8) * u
            for i in 1..<sp.count {
                run += sp[i].distance(to: sp[i - 1])
                guard run >= next else { continue }
                next += (30 + rnd(s, i) * 8) * u
                let n = normals[i]
                ctx.setStrokeColor(alpha(dark, 0.9))
                ctx.setLineWidth(2.2 * u)
                ctx.move(to: (sp[i] + n * hw[i] * 1.2).point)
                ctx.addLine(to: (sp[i] - n * hw[i] * 1.2).point)
                ctx.strokePath()
                ctx.setStrokeColor(alpha(light, 0.8))
                ctx.setLineWidth(0.9 * u)
                let d = (sp[i] - sp[i - 1]).normalized * (1.8 * u)
                ctx.move(to: (sp[i] + d + n * hw[i] * 1.2).point)
                ctx.addLine(to: (sp[i] + d - n * hw[i] * 1.2).point)
                ctx.strokePath()
            }
        case .jute, .cord, .metal, .pvc, .greenVine, .greenStem:
            break
        }
        if case .jute = look { twist(sp, normals, hw, dark, u, ctx) }
        if case .cord = look { twist(sp, normals, hw, dark, u, ctx) }
        ctx.restoreGState()
        outline(ctx, path, mid, u * (look.isHardware ? 0.7 : 1))
    }

    /// The strands of a rope: short slanted strokes across it.
    private static func twist(_ sp: [V2], _ normals: [V2], _ hw: [CGFloat], _ dark: CGColor, _ u: CGFloat, _ ctx: CGContext) {
        ctx.setStrokeColor(alpha(dark, 0.6))
        ctx.setLineWidth(0.8 * u)
        var run: CGFloat = 0
        for i in 1..<sp.count {
            run += sp[i].distance(to: sp[i - 1])
            guard run > 4 * u else { continue }
            run = 0
            let d = (sp[i] - sp[i - 1]).normalized
            ctx.move(to: (sp[i] + normals[i] * hw[i] - d * hw[i] * 0.6).point)
            ctx.addLine(to: (sp[i] - normals[i] * hw[i] + d * hw[i] * 0.6).point)
            ctx.strokePath()
        }
    }

    static func polyPath(_ pts: [V2]) -> CGPath {
        let p = CGMutablePath()
        guard let f = pts.first else { return p }
        p.move(to: f.point)
        for q in pts.dropFirst() { p.addLine(to: q.point) }
        p.closeSubpath()
        return p
    }

    /// Dark matt metal, for the hardware.
    static let metalMid = c(0.2, 0.2, 0.22)

    static func paintMetal(_ ctx: CGContext, _ pts: [V2], _ u: CGFloat, light: CGFloat = 0) {
        let p = polyPath(pts)
        let b = Poly.bounds(pts)
        fill(ctx, p, [c(0.34 + light, 0.35 + light, 0.38 + light), metalMid, c(0.1, 0.1, 0.11)], [0, 0.45, 1],
             from: CGPoint(x: b.minX, y: b.maxY), to: CGPoint(x: b.maxX, y: b.minY))
        outline(ctx, p, metalMid, u * 0.7)
    }

    static func screw(_ ctx: CGContext, at p: V2, _ u: CGFloat, wood: Bool = false) {
        let r = 1.8 * u
        ctx.setFillColor(wood ? c(0.55, 0.55, 0.56) : c(0.45, 0.45, 0.48))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(c(0.15, 0.15, 0.16, 0.9))
        ctx.setLineWidth(0.6 * u)
        ctx.move(to: CGPoint(x: p.x - r * 0.7, y: p.y))
        ctx.addLine(to: CGPoint(x: p.x + r * 0.7, y: p.y))
        ctx.strokePath()
    }

    /// Sawn wood: a board face, lengthwise grain, a knot or two.
    static func paintBoard(_ ctx: CGContext, _ r: CGRect, _ s: Int, _ u: CGFloat, upright: Bool, ply: Bool = false, pale: CGFloat = 0) {
        let base = c(0.84 + pale, 0.68 + pale, 0.46 + pale * 0.8)
        let p = CGPath(roundedRect: r, cornerWidth: 1.2 * u, cornerHeight: 1.2 * u, transform: nil)
        fill(ctx, p, [shade(base, 0.12), base, shade(base, -0.18)], [0, 0.5, 1],
             from: CGPoint(x: upright ? r.minX : r.midX, y: upright ? r.midY : r.maxY), to: CGPoint(x: upright ? r.maxX : r.midX, y: upright ? r.midY : r.minY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        if ply {
            // The plies, seen edge on.
            let n = max(3, Int(r.height / (2.6 * u)))
            for k in 0..<n {
                let y = r.minY + r.height * (CGFloat(k) + 0.5) / CGFloat(n)
                ctx.setStrokeColor(alpha(k % 2 == 0 ? shade(base, -0.3) : shade(base, 0.15), 0.6))
                ctx.setLineWidth(0.8 * u)
                ctx.move(to: CGPoint(x: r.minX, y: y))
                ctx.addLine(to: CGPoint(x: r.maxX, y: y))
                ctx.strokePath()
            }
        } else {
            let len = upright ? r.height : r.width, across = upright ? r.width : r.height
            let n = max(2, Int(across / (3.4 * u)))
            ctx.setLineWidth(0.7 * u)
            for k in 0..<n {
                let o = across * (CGFloat(k) + 0.5) / CGFloat(n)
                ctx.setStrokeColor(alpha(shade(base, -0.35), 0.35 + rnd(s, k) * 0.2))
                ctx.beginPath()
                var t: CGFloat = 0
                var first = true
                while t <= len {
                    let w = sin(t / (40 * u) + rnd(s, k) * 6) * 1.2 * u
                    let q = upright ? CGPoint(x: r.minX + o + w, y: r.minY + t) : CGPoint(x: r.minX + t, y: r.minY + o + w)
                    if first { ctx.move(to: q); first = false } else { ctx.addLine(to: q) }
                    t += 8 * u
                }
                ctx.strokePath()
            }
            // A knot.
            if len > 60 * u, rnd(s, 9) < 0.7 {
                let f = 0.25 + rnd(s, 10) * 0.5
                let kc = upright ? CGPoint(x: r.midX, y: r.minY + r.height * f) : CGPoint(x: r.minX + r.width * f, y: r.midY)
                let kr = min(across * 0.28, 5 * u)
                ctx.setFillColor(alpha(shade(base, -0.45), 0.7))
                ctx.fillEllipse(in: CGRect(x: kc.x - kr * (upright ? 0.8 : 1.4), y: kc.y - kr * (upright ? 1.4 : 0.8),
                                           width: kr * (upright ? 1.6 : 2.8), height: kr * (upright ? 2.8 : 1.6)))
            }
        }
        // A sawn edge catches the light.
        ctx.setFillColor(c(1, 1, 1, 0.18))
        ctx.fill(upright ? CGRect(x: r.minX, y: r.minY, width: 1.2 * u, height: r.height) : CGRect(x: r.minX, y: r.maxY - 1.2 * u, width: r.width, height: 1.2 * u))
        ctx.restoreGState()
        outline(ctx, p, shade(base, -0.2), u * 0.8)
    }

    static func paintBarkBlock(_ ctx: CGContext, _ pts: [V2], _ s: Int, _ u: CGFloat, biome: Biome, upright: Bool) {
        let (light, mid, dark) = woodColours(s + 3)
        let p = polyPath(pts)
        let b = Poly.bounds(pts)
        fill(ctx, p, [dark, mid, light, mid, shade(dark, -0.1)], [0, 0.2, 0.42, 0.75, 1],
             from: CGPoint(x: upright ? b.minX : b.midX, y: upright ? b.midY : b.maxY), to: CGPoint(x: upright ? b.maxX : b.midX, y: upright ? b.midY : b.minY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        let n = upright ? 9 : 12
        for k in 0..<n {
            let f = (CGFloat(k) + 0.5) / CGFloat(n)
            ctx.setStrokeColor(alpha(k % 2 == 0 ? shade(dark, -0.35) : shade(light, 0.15), k % 2 == 0 ? 0.65 : 0.4))
            ctx.setLineWidth((k % 2 == 0 ? 2.2 : 1) * u)
            ctx.beginPath()
            if upright {
                let x = b.minX + f * b.width
                ctx.move(to: CGPoint(x: x, y: b.minY))
                ctx.addCurve(to: CGPoint(x: x + (rnd(s, k) - 0.5) * 8 * u, y: b.maxY),
                             control1: CGPoint(x: x + (rnd(s + 1, k) - 0.5) * 12 * u, y: b.minY + b.height * 0.33),
                             control2: CGPoint(x: x + (rnd(s + 2, k) - 0.5) * 12 * u, y: b.minY + b.height * 0.66))
            } else {
                let x = b.minX + f * b.width
                ctx.move(to: CGPoint(x: x, y: b.minY))
                ctx.addLine(to: CGPoint(x: x + (rnd(s, k) - 0.5) * 10 * u, y: b.maxY))
            }
            ctx.strokePath()
        }
        linear(ctx, [c(1, 1, 1, 0.18), c(1, 1, 1, 0)], from: CGPoint(x: 0, y: b.maxY), to: CGPoint(x: 0, y: b.maxY - min(b.height * 0.4, 12 * u)))
        ctx.restoreGState()
        outline(ctx, p, mid, u)
        if !upright, rnd(s, 8) < 0.55 || biome == .tundra {
            mossPatch(ctx, along: b.insetBy(dx: b.width * 0.1, dy: 0), y: b.maxY - 2 * u, seed: s, u: u, biome: biome)
        }
    }

    /// Paints any of the pieces structures are built from. `backed`: it is
    /// fixed to a backing wall (screwed in), not just to the glass at the
    /// back (held on by suction cups).
    static func paintPiece(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, backed: Bool = false, leaf: Bool = true, _ ctx: CGContext) {
        if paintHome(kind, r, s, u, biome, backed: backed, leaf: leaf, ctx) { return }
        if paintNature(kind, r, s, u, biome, ctx) { return }
        let b = HabitatShape.piece(kind, r, s, u, leaves: false)
        func P(_ x: CGFloat, _ y: CGFloat) -> V2 { V2(r.minX + r.width * x, r.minY + r.height * y) }
        switch kind {
        case .corkSlab, .barkLedge:
            if let blk = b.blocks.first { paintBarkBlock(ctx, blk.outline, s, u, biome: biome, upright: false) }
        case .corkTube:
            if let blk = b.blocks.first { paintBarkBlock(ctx, blk.outline, s, u, biome: biome, upright: true) }
            // Its mouth, dark inside.
            let mouth = CGRect(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.9 - r.width * 0.05, width: r.width * 0.72, height: r.width * 0.16)
            fill(ctx, CGPath(ellipseIn: mouth.insetBy(dx: -3 * u, dy: -2 * u), transform: nil), [c(0.8, 0.64, 0.42), c(0.6, 0.44, 0.28)],
                 from: CGPoint(x: 0, y: mouth.maxY), to: CGPoint(x: 0, y: mouth.minY))
            fill(ctx, CGPath(ellipseIn: mouth, transform: nil), [c(0.05, 0.03, 0.02), c(0.2, 0.13, 0.08)],
                 from: CGPoint(x: 0, y: mouth.maxY), to: CGPoint(x: 0, y: mouth.minY))
        case .slateLedge:
            guard let blk = b.blocks.first else { break }
            let p = polyPath(blk.outline)
            let base = c(0.38, 0.4, 0.44)
            fill(ctx, p, [shade(base, 0.25), base, shade(base, -0.3)], [0, 0.5, 1], from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY))
            ctx.saveGState()
            ctx.addPath(p)
            ctx.clip()
            for k in 1..<4 {
                ctx.setStrokeColor(alpha(shade(base, k % 2 == 0 ? 0.3 : -0.35), 0.5))
                ctx.setLineWidth(0.8 * u)
                let y = r.minY + r.height * CGFloat(k) / 4 + (rnd(s, k) - 0.5) * 2 * u
                ctx.move(to: CGPoint(x: r.minX, y: y))
                ctx.addLine(to: CGPoint(x: r.maxX, y: y + (rnd(s, k + 4) - 0.5) * 3 * u))
                ctx.strokePath()
            }
            ctx.restoreGState()
            outline(ctx, p, base, u)
        case .branchBracket, .shelfBracket, .angleBracket:
            if !backed {
                // On the glass: a suction cup behind its foot.
                suction(ctx, at: kind == .branchBracket ? P(0.5, 0.14) : P(0.5, 0.35), r.width * (kind == .branchBracket ? 0.42 : 0.28), u)
            }
            for (i, v) in b.visual.enumerated() {
                // (Held on by a cup, it has no plate to screw.)
                if !backed, kind == .branchBracket, i == 0 { continue }
                paintMetal(ctx, v, u)
            }
            if backed {
                if kind == .branchBracket {
                    screw(ctx, at: P(0.34, 0.13), u)
                    screw(ctx, at: P(0.66, 0.13), u)
                } else {
                    screw(ctx, at: P(0.5, 0.25), u)
                    screw(ctx, at: P(0.5, 0.6), u)
                }
            }
        case .wallAnchor:
            if !backed { suction(ctx, at: P(0.5, 0.5), r.width * 0.62, u) }
            if let v = b.visual.first { paintMetal(ctx, v.map { P(0.5, 0.5) + ($0 - P(0.5, 0.5)) * (backed ? 1 : 0.7) }, u, light: 0.04) }
            // A hex bolt head.
            let hex = (0..<6).map { k in P(0.5, 0.5) + V2.angle(CGFloat(k) / 6 * 2 * .pi + 0.3) * (r.width * 0.22) }
            paintMetal(ctx, hex, u, light: 0.12)
        case .glassMount:
            for (i, v) in b.visual.enumerated() {
                let p = polyPath(v)
                ctx.addPath(p)
                ctx.setFillColor(i == 0 ? c(0.9, 0.95, 1, 0.38) : c(0.92, 0.95, 1, 0.22))
                ctx.fillPath()
                ctx.addPath(p)
                ctx.setStrokeColor(c(1, 1, 1, 0.55))
                ctx.setLineWidth(0.8 * u)
                ctx.strokePath()
            }
        case .suctionCup:
            if let cup = b.visual.first {
                let p = polyPath(cup)
                fill(ctx, p, [c(0.95, 0.97, 1, 0.45), c(0.8, 0.85, 0.9, 0.25)], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
                ctx.addPath(p)
                ctx.setStrokeColor(c(1, 1, 1, 0.6))
                ctx.setLineWidth(0.8 * u)
                ctx.strokePath()
            }
            for v in b.visual.dropFirst() { paintMetal(ctx, v, u) }
        case .vineClip:
            // A few turns of twine.
            let knot = b.visual[0]
            fill(ctx, polyPath(knot), [c(0.62, 0.5, 0.34), c(0.42, 0.33, 0.22)], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            ctx.setStrokeColor(c(0.3, 0.22, 0.14, 0.8))
            ctx.setLineWidth(0.8 * u)
            let bb = Poly.bounds(knot)
            for k in 0..<3 {
                let x = bb.minX + bb.width * (0.25 + CGFloat(k) * 0.25)
                ctx.move(to: CGPoint(x: x - 2 * u, y: bb.minY + 1))
                ctx.addLine(to: CGPoint(x: x + 2 * u, y: bb.maxY - 1))
            }
            ctx.strokePath()
            paintMetal(ctx, b.visual[1], u, light: 0.05)
        case .wallRail:
            if let blk = b.bars.first {
                if !backed { for x: CGFloat in [0.08, 0.92] { suction(ctx, at: P(x, 0.5), r.height * 0.8, u) } }
                paintBoard(ctx, Poly.bounds(blk.outline), s, u, upright: false, pale: -0.12)
                if backed { for x: CGFloat in [0.08, 0.5, 0.92] { screw(ctx, at: P(x, 0.5), u, wood: true) } }
            }
        case .metalStrut:
            if let blk = b.bars.first {
                if !backed { for y: CGFloat in [0.06, 0.94] { suction(ctx, at: P(0.5, y), r.width * 0.8, u) } }
                paintMetal(ctx, blk.outline, u, light: 0.06)
                let bb = Poly.bounds(blk.outline)
                var y = bb.minY + 10 * u
                while y < bb.maxY - 10 * u {
                    ctx.setFillColor(c(0.05, 0.05, 0.06, 0.9))
                    ctx.addPath(CGPath(roundedRect: CGRect(x: bb.midX - 2 * u, y: y - 5 * u, width: 4 * u, height: 10 * u),
                                       cornerWidth: 2 * u, cornerHeight: 2 * u, transform: nil))
                    ctx.fillPath()
                    y += 18 * u
                }
            }
        case .beam:
            paintBoard(ctx, r, s, u, upright: false)
            screw(ctx, at: P(0.04, 0.5), u, wood: true)
            screw(ctx, at: P(0.96, 0.5), u, wood: true)
        case .plank:
            paintBoard(ctx, r, s, u, upright: false, pale: 0.04)
        case .plywood:
            paintBoard(ctx, r, s, u, upright: false, ply: true, pale: 0.06)
        case .post:
            paintBoard(ctx, r, s, u, upright: true, pale: -0.04)
            // Its sawn top.
            ctx.setFillColor(c(0.62, 0.48, 0.3, 0.8))
            ctx.fill(CGRect(x: r.minX + 1, y: r.maxY - 2.5 * u, width: r.width - 2, height: 2.5 * u))
        case .woodBlock:
            paintBoard(ctx, r, s, u, upright: false, pale: -0.02)
            // The end grain: rings.
            let rc = r.insetBy(dx: r.width * 0.18, dy: r.height * 0.18)
            ctx.setStrokeColor(c(0.5, 0.36, 0.2, 0.35))
            ctx.setLineWidth(0.7 * u)
            for k in 1...3 { ctx.strokeEllipse(in: rc.insetBy(dx: CGFloat(k) * rc.width * 0.12, dy: CGFloat(k) * rc.height * 0.12)) }
        case .brick:
            let base = c(0.66, 0.3, 0.22)
            let p = CGPath(roundedRect: r, cornerWidth: 1.5 * u, cornerHeight: 1.5 * u, transform: nil)
            fill(ctx, p, [shade(base, 0.15), base, shade(base, -0.25)], [0, 0.5, 1], from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY))
            for k in 0..<Int(r.width * r.height / (40 * u * u)) {
                ctx.setFillColor(k % 2 == 0 ? c(0.3, 0.12, 0.08, 0.35) : c(0.9, 0.6, 0.45, 0.3))
                let x = r.minX + rnd(s, k) * r.width, y = r.minY + rnd(s + 1, k) * r.height
                ctx.fillEllipse(in: CGRect(x: x, y: y, width: 1.4 * u, height: 1.4 * u))
            }
            outline(ctx, p, c(0.82, 0.78, 0.7), u * 1.1)
        case .crate:
            // Slats across, and a post at each corner.
            let slats = 4
            let gap = 3 * u
            let h = (r.height - gap * CGFloat(slats - 1)) / CGFloat(slats)
            ctx.setFillColor(c(0.12, 0.08, 0.05, 0.9))
            ctx.fill(r.insetBy(dx: 4 * u, dy: 1))
            for k in 0..<slats {
                paintBoard(ctx, CGRect(x: r.minX, y: r.minY + CGFloat(k) * (h + gap), width: r.width, height: h), s + k, u, upright: false, pale: 0.02)
            }
            let pw = max(9 * u, r.width * 0.09)
            paintBoard(ctx, CGRect(x: r.minX, y: r.minY, width: pw, height: r.height), s + 7, u, upright: true, pale: -0.06)
            paintBoard(ctx, CGRect(x: r.maxX - pw, y: r.minY, width: pw, height: r.height), s + 8, u, upright: true, pale: -0.06)
            for x in [r.minX + pw / 2, r.maxX - pw / 2] {
                for k in 0..<slats { screw(ctx, at: V2(x, r.minY + CGFloat(k) * (h + gap) + h / 2), u * 0.8, wood: true) }
            }
        case .backPanel:
            let base = c(0.62, 0.52, 0.4)
            ctx.setFillColor(base)
            ctx.fill(r)
            ctx.setStrokeColor(alpha(shade(base, -0.2), 0.3))
            ctx.setLineWidth(1 * u)
            for k in 0..<Int(r.height / (9 * u)) {
                let y = r.minY + CGFloat(k) * 9 * u + rnd(s, k) * 4 * u
                ctx.move(to: CGPoint(x: r.minX, y: y))
                ctx.addCurve(to: CGPoint(x: r.maxX, y: y + (rnd(s + 1, k) - 0.5) * 6 * u),
                             control1: CGPoint(x: r.minX + r.width * 0.3, y: y + 3 * u), control2: CGPoint(x: r.minX + r.width * 0.7, y: y - 3 * u))
            }
            ctx.strokePath()
            ctx.setStrokeColor(c(0.2, 0.15, 0.1, 0.45))
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5), width: 1.2 * u)
            for p in [P(0.04, 0.05), P(0.96, 0.05), P(0.04, 0.95), P(0.96, 0.95)] { screw(ctx, at: p, u, wood: true) }
        case .pegboard:
            let base = c(0.56, 0.42, 0.28)
            ctx.setFillColor(base)
            ctx.fill(r)
            let step = 12 * u
            ctx.setFillColor(c(0.16, 0.1, 0.06, 0.85))
            var y = r.minY + step / 2
            while y < r.maxY {
                var x = r.minX + step / 2
                while x < r.maxX {
                    ctx.fillEllipse(in: CGRect(x: x - 1.6 * u, y: y - 1.6 * u, width: 3.2 * u, height: 3.2 * u))
                    x += step
                }
                y += step
            }
            ctx.setStrokeColor(c(0.2, 0.14, 0.08, 0.5))
            ctx.stroke(r.insetBy(dx: 0.5, dy: 0.5), width: 1.2 * u)
        default:
            // Made of sticks: the offshoots behind, the main one over their feet.
            let look = stickLook(kind, s)
            for st in b.sticks.reversed() { paintStick(st, look: look, seed: s, u: u, ctx) }
            switch kind {
            case .brace:
                if backed { paintMetal(ctx, b.visual[0], u, light: 0.05) } else { suction(ctx, at: P(0.5, 0.03), 8 * u, u) }
                paintMetal(ctx, b.visual[1], u)
                if backed { screw(ctx, at: P(0.5, 0.03), u * 0.9) }
            case .crossBrace:
                if !backed { for q in [P(0.5, 0.5), P(0.08, 0.08), P(0.92, 0.92), P(0.08, 0.92), P(0.92, 0.08)] { suction(ctx, at: q, 6 * u, u) } }
                paintMetal(ctx, b.visual[0], u, light: 0.1)
            case .hangingHook:
                paintMetal(ctx, b.visual[0], u, light: 0.12)
            case .driedStem:
                // A dry seed head: a burst of fine bristles.
                let cc = P(0.54, 0.93)
                ctx.setStrokeColor(c(0.78, 0.68, 0.48, 0.9))
                ctx.setLineWidth(0.7 * u)
                for k in 0..<22 {
                    let a = CGFloat(k) / 22 * 2 * .pi
                    let l = (6 + rnd(s, k) * 4) * u
                    ctx.move(to: cc.point)
                    ctx.addLine(to: CGPoint(x: cc.x + cos(a) * l, y: cc.y + sin(a) * l))
                }
                ctx.strokePath()
                ctx.setFillColor(c(0.6, 0.48, 0.3))
                ctx.fillEllipse(in: CGRect(x: cc.x - 3 * u, y: cc.y - 3 * u, width: 6 * u, height: 6 * u))
            case .ladder:
                for st in b.sticks where st.name == "rung" {
                    let sp = st.spine()
                    for p in [sp.first!, sp.last!] { screw(ctx, at: p, u * 0.6, wood: true) }
                }
            case .pipe:
                // Its open ends.
                for (i, st) in b.sticks.enumerated() where i == 0 {
                    let sp = st.spine()
                    let hh = st.w0 / 2
                    for p in [sp.first!, sp.last!] {
                        let e = CGRect(x: p.x - hh * 0.35, y: p.y - hh, width: hh * 0.7, height: hh * 2)
                        ctx.setFillColor(c(0.3, 0.32, 0.33))
                        ctx.fillEllipse(in: e)
                        ctx.setStrokeColor(c(0.95, 0.95, 0.94))
                        ctx.setLineWidth(1.4 * u)
                        ctx.strokeEllipse(in: e)
                    }
                }
            case .thickBranch, .driftwoodSnag, .root:
                // A knot.
                if let st = b.sticks.first {
                    let q = st.along("x").point(at: 0.3 + rnd(s, 4) * 0.3)
                    let kr = st.w0 * 0.18
                    ctx.setFillColor(alpha(colours(look).dark, 0.8))
                    ctx.fillEllipse(in: CGRect(x: q.x - kr * 1.4, y: q.y - kr, width: kr * 2.8, height: kr * 2))
                }
            default:
                break
            }
        }
        // Leaves last, over the wood.
        for (k, leaf) in HabitatShape.pieceLeaves(kind, r, s, u).enumerated() {
            switch kind {
            case .twig:
                leafShape(ctx, at: leaf.at.point, length: leaf.size, angle: leaf.angle, colour: k % 2 == 0 ? c(0.42, 0.66, 0.32) : c(0.33, 0.56, 0.27), u: u)
            case .driedStem:
                leafShape(ctx, at: leaf.at.point, length: leaf.size, angle: leaf.angle, colour: c(0.66, 0.56, 0.36), u: u)
            default:
                heartLeaf(ctx, at: leaf.at.point, size: leaf.size, angle: leaf.angle,
                          colour: k % 3 == 0 ? c(0.36, 0.62, 0.34) : c(0.28, 0.52, 0.28), u: u)
            }
        }
    }
}

extension HabitatArt.StickLook {
    var isHardware: Bool {
        switch self {
        case .metal, .cord, .pvc: return true
        default: return false
        }
    }
}
