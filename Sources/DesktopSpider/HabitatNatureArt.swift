import AppKit

// MARK: - Painting the natural world
//
// The things of HabitatNature.swift, painted from their own layouts: every
// stick, block and leaf filled along the very outline the spider walks
// round, then marked as what it is — bark ridges, stone strata, veins, the
// rings of a cut face — clipped to it, so that nothing solid is drawn where
// there is nothing to stand on. Lit from the top left like everything else
// in the tank; moss, snow and sand settle on it as the scenery has them.

extension HabitatArt {
    /// Paints one of the natural things; false if `kind` isn't one.
    static func paintNature(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, _ ctx: CGContext) -> Bool {
        guard let b = HabitatShape.nature(kind, r, s, u) else { return false }
        let k = NatureKit(r: r, s: s, u: u)
        func P(_ x: CGFloat, _ y: CGFloat) -> V2 { k.P(x, y) }
        let wood = stickLook(.thinBranch, s)
        let greens = leafGreens(biome, s)
        func sticks(_ look: StickLook, _ list: [Stick]? = nil) { for st in (list ?? b.sticks).reversed() { paintStick(st, look: look, seed: s, u: u, ctx) } }
        func leaves(_ col: CGColor, veins: Bool = true) {
            for (i, bar) in b.bars.enumerated() where bar.name == "leaf" || bar.name == "blade" {
                paintBlade(ctx, bar.outline, rib: b.ribs[i], i % 2 == 0 ? col : shade(col, -0.08), u, veins: veins)
            }
        }
        switch kind {
        // MARK: Structures
        case .twistedBranch:
            let a = b.sticks[0], c2 = b.sticks[1]
            paintStick(c2, look: wood, seed: s, u: u, ctx)
            paintStick(a, look: wood, seed: s, u: u, ctx)
            // Over and under: the middle of the second back over the first.
            let n = c2.pts.count
            let part = Stick(Array(c2.pts[(n / 3)...(2 * n / 3)]), lerp(c2.w0, c2.w1, 0.33), lerp(c2.w0, c2.w1, 0.67), start: nil, end: nil)
            paintStick(part, look: wood, seed: s, u: u, ctx)
            for st in [a, part] { spiralGrain(ctx, st, colours(wood).dark, u) }
        case .threeFork:
            sticks(wood)
            knot(ctx, b.sticks[0].pts.last!, 5 * u, colours(wood).dark)
        case .exposedRoot, .rootTangle:
            let look = StickLook.root
            for st in b.sticks { rootHairs(ctx, st, u, s) }
            sticks(look)
            for st in b.sticks {
                for e in [st.pts.first!, st.pts.last!] where e.y < r.minY { soilMound(ctx, V2(e.x, r.minY), 16 * u, biome) }
            }
            if rnd(s, 5) < 0.6 || biome == .tundra, let st = b.sticks.max(by: { ($0.pts.map(\.y).max() ?? 0) < ($1.pts.map(\.y).max() ?? 0) }) {
                mossAlong(ctx, st, u, s, biome)
            }
        case .stump:
            let o = b.blocks[0].outline
            paintCork(ctx, o, s, u, biome, horizontal: false, tone: -0.05)
            // The sawn top: a pale face, ringed.
            let face = CGRect(x: r.minX + r.width * 0.17, y: r.minY + r.height * 0.83, width: r.width * 0.66, height: r.height * 0.075)
            ctx.saveGState()
            ctx.addPath(polyPath(o))
            ctx.clip()
            cutFace(ctx, face, u, s)
            ctx.restoreGState()
            outline(ctx, polyPath(o), c(0.45, 0.32, 0.2), u)
            if rnd(s, 8) < 0.7 || biome == .tundra { mossTufts(ctx, o, s, u, biome, above: r.minY + r.height * 0.8, sparse: biome != .tundra) }
        case .driftwoodRoot:
            sticks(.driftwood, Array(b.sticks))
            let knotPts = b.blocks[0].outline
            let bb = Poly.bounds(knotPts)
            let (light, mid, dark) = colours(.driftwood)
            ctx.saveGState()
            ctx.addPath(polyPath(knotPts))
            ctx.clip()
            radial(ctx, [light, mid, dark], [0, 0.55, 1], at: CGPoint(x: bb.minX + bb.width * 0.35, y: bb.maxY - bb.height * 0.3), radius: max(bb.width, bb.height) * 0.8)
            ctx.setStrokeColor(alpha(dark, 0.5))
            ctx.setLineWidth(0.8 * u)
            for i in 1...4 { ctx.strokeEllipse(in: bb.insetBy(dx: bb.width * 0.1 * CGFloat(i), dy: bb.height * 0.09 * CGFloat(i)).offsetBy(dx: CGFloat(i) * u, dy: 0)) }
            ctx.restoreGState()
            outline(ctx, polyPath(knotPts), mid, u)
        case .driftwoodBranch:
            sticks(.driftwood)
            let snag = b.sticks[2].pts.last!
            ctx.setFillColor(colours(.driftwood).light)
            for i in 0..<3 { ctx.fillEllipse(in: CGRect(x: snag.x - 4 * u + CGFloat(i) * 3 * u, y: snag.y - 2 * u, width: 2.4 * u, height: 3 * u)) }
        case .corkTunnel:
            let t = min(r.height * 0.2, 15 * u)
            hollowBack(ctx, CGRect(x: r.minX + 3 * u, y: r.minY + r.height * 0.08, width: r.width - 6 * u, height: r.height * 0.9 - t), s, u, curved: true)
            paintCork(ctx, b.visual[0], s, u, biome, horizontal: true, tone: 0.18, inner: true)
            paintCork(ctx, b.bars[0].outline, s, u, biome, horizontal: true, tone: 0)
            // The cut rims of its two ends.
            for st in b.sticks { paintStick(st, look: .wood(light: c(0.9, 0.74, 0.52), mid: c(0.74, 0.56, 0.36), dark: c(0.5, 0.36, 0.22)), seed: s, u: u, ctx) }
            if rnd(s, 8) < 0.6 || biome == .tundra { mossPatch(ctx, along: r.insetBy(dx: r.width * 0.15, dy: 0), y: r.maxY - 2 * u, seed: s, u: u, biome: biome) }
        case .leaningBark:
            sticks(.bark)
        case .bambooTipi:
            sticks(.bamboo)
            lashing(ctx, P(0.5, 0.82), 9 * u, u)
        case .hangingBranch:
            for v in b.visual { paintJute(ctx, v, u) }
            paintStick(b.sticks[1], look: .jute, seed: s, u: u, ctx)
            paintStick(b.sticks[0], look: wood, seed: s, u: u, ctx)
            lashing(ctx, V2(r.midX, r.minY + min(r.height * 0.45, 70 * u)), 4 * u, u)
            let sp = b.sticks[0].spine()
            for (i, q) in [sp[2], sp[sp.count - 3]].enumerated() {
                leafShape(ctx, at: q.point, length: 12 * u, angle: 1 + CGFloat(i) * 1.2, colour: greens[i % greens.count], u: u)
            }
        case .lianaLoop:
            sticks(.liana)
            for st in b.sticks {
                let sp = st.spine(step: 3)
                for (i, q) in sp.enumerated() where i % 9 == 4 {
                    heartLeaf(ctx, at: q.point, size: (10 + rnd(s, i) * 4) * u, angle: -0.6 - rnd(s + 1, i) * 1.8, colour: greens[i % greens.count], u: u)
                }
            }
        case .hangingRoots:
            sticks(.root)
            paintMoss(ctx, b.blocks[0].outline, s, u, biome, soil: true)
        case .stickRaft:
            let rr = min(r.height * 0.32, 8 * u)
            let n = max(4, Int((r.width - 2 * rr) / (rr * 1.9)))
            let cy = r.maxY - rr
            paintBoard(ctx, CGRect(x: r.minX, y: r.minY + r.height * 0.04, width: r.width, height: cy - r.minY - r.height * 0.04), s, u, upright: false, pale: -0.1)
            for i in 0..<n {
                let cx = r.minX + rr + (r.width - 2 * rr) * CGFloat(i) / CGFloat(n - 1)
                let d = CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)
                ctx.setFillColor(c(0.36, 0.25, 0.15))
                ctx.fillEllipse(in: d)
                cutFace(ctx, d.insetBy(dx: rr * 0.18, dy: rr * 0.18), u * 0.6, s + i)
            }
            for x: CGFloat in [0.2, 0.8] { paintJute(ctx, HabitatShape.bar(P(x, 0.1), P(x, 0.98), 2 * u), u) }
        case .mossPlatform:
            paintCork(ctx, b.blocks[0].outline, s, u, biome, horizontal: true, tone: 0)
            paintMoss(ctx, b.blocks[1].outline, s, u, biome)
            // Moss trailing off its front edge.
            ctx.setStrokeColor(alpha(greens[0], 0.85))
            ctx.setLineWidth(1.4 * u)
            for i in 0..<5 {
                let x = r.minX + r.width * (0.1 + CGFloat(i) * 0.19)
                ctx.move(to: CGPoint(x: x, y: r.minY + r.height * 0.15))
                ctx.addQuadCurve(to: CGPoint(x: x + 3 * u, y: r.minY - (6 + rnd(s, i) * 8) * u), control: CGPoint(x: x - 3 * u, y: r.minY))
            }
            ctx.strokePath()
        case .rockSpire:
            for blk in b.blocks { paintStone(ctx, blk.outline, s, u, biome, strata: true) }
        case .stoneArch:
            paintStoneStick(ctx, b.sticks[0], s, u, biome)

        // MARK: Shelters
        case .barkCave:
            fillHollow(ctx, b.hollows[0].cavity, s, u)
            let o = b.blocks[0].outline
            paintCork(ctx, o, s, u, biome, horizontal: false, tone: 0)
            // Ridges following the curl.
            let cc = V2(r.midX - r.width * 0.02, r.minY - r.height * 0.04)
            ctx.saveGState()
            ctx.addPath(polyPath(o))
            ctx.clip()
            for i in 1..<5 {
                let d = CGFloat(i) * 13 * u / 5
                ctx.setStrokeColor(alpha(i % 2 == 0 ? c(0.2, 0.12, 0.07) : c(0.85, 0.68, 0.46), 0.5))
                ctx.setLineWidth((i % 2 == 0 ? 1.8 : 1) * u)
                ctx.strokeEllipse(in: CGRect(x: cc.x - r.width * 0.5 + d, y: cc.y - r.height + d, width: (r.width * 0.5 - d) * 2, height: (r.height - d) * 2))
            }
            ctx.restoreGState()
            outline(ctx, polyPath(o), c(0.45, 0.32, 0.2), u)
            if rnd(s, 3) < 0.75 || biome == .tundra { mossPatch(ctx, along: r.insetBy(dx: r.width * 0.25, dy: 0), y: r.maxY - 3 * u, seed: s, u: u, biome: biome) }
        case .rockCrevice:
            fillHollow(ctx, Poly.grown(b.hollows[0].cavity, by: 3 * u), s, u, stone: true)
            paintStone(ctx, b.blocks[0].outline, s, u, biome, strata: true)
            for i in 0..<4 {
                let x = r.minX + r.width * (0.45 + CGFloat(i) * 0.12), rr = (3 + rnd(s, i) * 2) * u
                let pe = CGRect(x: x, y: r.minY + r.height * 0.205, width: rr * 2, height: rr * 1.3)
                ctx.setFillColor(shade(rockColour(biome, s + i), -0.1))
                ctx.fillEllipse(in: pe)
            }
        case .logDen:
            let t = min(r.height * 0.16, 15 * u)
            hollowBack(ctx, CGRect(x: r.minX + 2 * u, y: r.minY + t * 0.5, width: r.width * 0.86 - 2 * u, height: r.height - t), s, u, curved: false)
            let o = b.blocks[0].outline
            let (light, mid, dark) = woodColours(s)
            fill(ctx, polyPath(o), [light, mid, dark], [0, 0.45, 1], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
            ctx.saveGState()
            ctx.addPath(polyPath(o))
            ctx.clip()
            for i in 0..<8 {
                let y = r.minY + (CGFloat(i) + 0.5) / 8 * r.height
                ctx.setStrokeColor(alpha(i % 2 == 0 ? shade(dark, -0.2) : shade(light, 0.1), i % 2 == 0 ? 0.5 : 0.3))
                ctx.setLineWidth((i % 2 == 0 ? 1.6 : 1) * u)
                ctx.move(to: CGPoint(x: r.minX, y: y))
                ctx.addCurve(to: CGPoint(x: r.maxX, y: y + (rnd(s, i) - 0.5) * 4 * u), control1: CGPoint(x: r.minX + r.width * 0.3, y: y + 2 * u),
                             control2: CGPoint(x: r.minX + r.width * 0.7, y: y - 2 * u))
                ctx.strokePath()
            }
            // Where the side broke away: pale splintered wood along the inside edges.
            for y in [r.minY + t, r.maxY - t] {
                ctx.setFillColor(c(0.88, 0.72, 0.5))
                ctx.fill(CGRect(x: r.minX, y: y - (y > r.midY ? 0 : 2.2 * u), width: r.width * 0.86, height: 2.2 * u))
                ctx.setFillColor(c(0.8, 0.62, 0.4))
                var x = r.minX + r.height * 0.2
                var i = 0
                while x < r.maxX - r.width * 0.16 {
                    let w = (5 + rnd(s, i) * 7) * u, hgt = (3 + rnd(s + 1, i) * 4) * u
                    let dir: CGFloat = y > r.midY ? -1 : 1
                    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + w * 0.5, y: y + dir * hgt)); ctx.addLine(to: CGPoint(x: x + w, y: y))
                    ctx.fillPath()
                    x += w + (4 + rnd(s + 2, i) * 10) * u
                    i += 1
                }
            }
            ctx.restoreGState()
            outline(ctx, polyPath(o), mid, u)
            if rnd(s, 7) < 0.7 || biome == .tundra { mossPatch(ctx, along: r.insetBy(dx: r.width * 0.2, dy: 0), y: r.maxY - 1.5 * u, seed: s, u: u, biome: biome) }
        case .curledLeafHide:
            let dry = c(0.7, 0.52, 0.3)
            // The far side of the scroll, seen inside it: the leaf's own face, in shadow.
            let cav = b.hollows[0].cavity
            fill(ctx, polyPath(cav), [shade(dry, -0.45), shade(dry, -0.62)], from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY))
            ctx.saveGState()
            ctx.addPath(polyPath(cav))
            ctx.clip()
            ctx.setStrokeColor(alpha(shade(dry, -0.2), 0.5))
            ctx.setLineWidth(1 * u)
            for i in 0..<7 {
                let x = r.minX + r.width * (0.15 + CGFloat(i) * 0.11)
                ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addQuadCurve(to: CGPoint(x: x + r.width * 0.1, y: r.maxY), control: CGPoint(x: x - r.width * 0.06, y: r.midY))
            }
            ctx.strokePath()
            ctx.restoreGState()
            let o = b.blocks[0].outline
            fill(ctx, polyPath(o), [shade(dry, 0.25), dry, shade(dry, -0.3)], [0, 0.5, 1], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            ctx.saveGState()
            ctx.addPath(polyPath(o))
            ctx.clip()
            ctx.setFillColor(alpha(shade(dry, -0.35), 0.5))
            for i in 0..<14 { ctx.fillEllipse(in: CGRect(x: r.minX + rnd(s, i) * r.width, y: r.minY + rnd(s + 1, i) * r.height, width: 2 * u, height: 1.4 * u)) }
            ctx.restoreGState()
            outline(ctx, polyPath(o), dry, u * 0.8)
        case .leafCanopy:
            groundShade(ctx, r)
            sticks(.greenStem)
            leaves(greens[1])
        case .rootHollow:
            fillHollow(ctx, b.hollows[0].cavity, s, u)
            paintStick(b.sticks[0], look: .root, seed: s, u: u, ctx)
            paintCork(ctx, b.blocks[1].outline, s, u, biome, horizontal: false, tone: -0.12)
            let trunk = b.blocks[0].outline
            paintCork(ctx, trunk, s, u, biome, horizontal: false, tone: -0.02)
            ctx.saveGState()
            ctx.addPath(polyPath(trunk))
            ctx.clip()
            cutFace(ctx, CGRect(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.86, width: r.width * 0.47, height: r.height * 0.07), u, s)
            ctx.restoreGState()
            if rnd(s, 5) < 0.7 || biome == .tundra { mossPatch(ctx, along: CGRect(x: r.minX + r.width * 0.3, y: 0, width: r.width * 0.45, height: 1), y: r.minY + r.height * 0.5, seed: s, u: u, biome: biome) }
        case .mossyHide:
            fillHollow(ctx, b.hollows[0].cavity, s, u, stone: true)
            let o = b.blocks[0].outline
            paintStone(ctx, o, s, u, biome, strata: false, tint: biome == .desert ? nil : c(0.5, 0.52, 0.48), cap: false)
            // A blanket of moss over its top, hanging over the edge.
            ctx.saveGState()
            ctx.addPath(polyPath(o))
            ctx.clip()
            let moss = biome == .tundra ? c(0.93, 0.95, 1) : c(0.36, 0.56, 0.26)
            linear(ctx, [alpha(moss, 1), alpha(moss, 1), alpha(moss, 0)], [0, 0.55, 0.8], from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY + r.height * 0.3))
            ctx.restoreGState()
            mossTufts(ctx, o, s, u, biome, above: r.minY + r.height * 0.45)
            outline(ctx, polyPath(o), c(0.36, 0.4, 0.34), u)
        case .hangingLeafShelter:
            let leafCol = greens[0]
            paintStick(b.sticks[1], look: .cord, seed: s, u: u, ctx)
            let cav = b.hollows[0].cavity
            fill(ctx, polyPath(cav), [shade(leafCol, -0.35), shade(leafCol, -0.55)], from: CGPoint(x: r.midX, y: r.maxY), to: CGPoint(x: r.midX, y: r.minY))
            paintStick(b.sticks[0], look: .greenStem, seed: s, u: u, ctx)
            let sp = b.sticks[0].spine(step: 3)
            for (i, q) in sp.enumerated() where i % 5 == 2 {
                ctx.setFillColor(alpha(shade(leafCol, 0.4), 0.7))
                ctx.fillEllipse(in: CGRect(x: q.x - 0.8 * u, y: q.y - 0.8 * u, width: 1.6 * u, height: 1.6 * u))
            }
        case .overhang:
            fillHollow(ctx, b.hollows[0].cavity, s, u, stone: true)
            paintStone(ctx, b.blocks[0].outline, s, u, biome, strata: true)
            // Ferns and moss hanging from the lip.
            let lip = P(0.97, 0.58)
            if biome != .desert && biome != .beach {
                for i in 0..<4 {
                    leafShape(ctx, at: CGPoint(x: lip.x - CGFloat(i) * 12 * u, y: lip.y - 2 * u), length: (14 + rnd(s, i) * 8) * u, angle: -1.2 - rnd(s + 1, i) * 0.8,
                              colour: greens[i % greens.count], u: u)
                }
            }

        // MARK: Plants
        case .smallFern:
            paintFronds(ctx, base: P(0.5, 0), r, s, u, count: 5, greens: [c(0.42, 0.68, 0.34), c(0.34, 0.6, 0.3), c(0.5, 0.74, 0.38)])
        case .largeFern:
            for (i, st) in b.sticks.enumerated() {
                paintStick(st, look: .greenStem, seed: s, u: u, ctx)
                pinnae(ctx, st, greens[i % greens.count], u)
            }
        case .broadLeaf:
            sticks(.greenStem)
            leaves(greens[s % 2 == 0 ? 1 : 0])
            if s % 3 == 0 {
                // Variegated: a pale stripe down each.
                for (i, bar) in b.bars.enumerated() {
                    guard let rib = b.ribs[i] else { continue }
                    ctx.saveGState()
                    ctx.addPath(polyPath(bar.outline))
                    ctx.clip()
                    ctx.setStrokeColor(c(0.86, 0.92, 0.66, 0.5))
                    ctx.setLineWidth(r.width * 0.05)
                    strokeLine(ctx, rib)
                    ctx.restoreGState()
                }
            }
        case .trailingPlant:
            let pot = s % 2 == 0 ? c(0.78, 0.46, 0.3) : c(0.5, 0.36, 0.24)
            let potPts = b.blocks[0].outline, rim = b.blocks[1].outline
            fill(ctx, polyPath(potPts), [shade(pot, -0.2), shade(pot, 0.15), shade(pot, -0.25)], [0, 0.4, 1], from: CGPoint(x: r.minX, y: 0), to: CGPoint(x: r.minX + r.width * 0.55, y: 0))
            outline(ctx, polyPath(potPts), pot, u)
            fill(ctx, polyPath(rim), [shade(pot, 0.2), pot], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY + r.height * 0.92))
            outline(ctx, polyPath(rim), pot, u)
            sticks(.greenStem)
            for (n, st) in b.sticks.enumerated() {
                for (i, q) in st.spine(step: 3).enumerated() where i % 5 == 3 {
                    heartLeaf(ctx, at: q.point, size: (9 + rnd(s + n, i) * 4) * u, angle: (i % 10 < 5 ? -0.3 : .pi + 0.3) - 0.9, colour: greens[(i + n) % greens.count], u: u)
                }
            }
        case .climbingVine:
            sticks(.greenStem)
            let sp = b.sticks[0].spine(step: 3)
            for (i, q) in sp.enumerated() where i % 6 == 3 {
                let side: CGFloat = (i / 6) % 2 == 0 ? 1 : -1
                heartLeaf(ctx, at: q.point, size: (11 + rnd(s, i) * 4) * u, angle: side > 0 ? 0.3 : .pi - 0.3, colour: greens[i % greens.count], u: u)
                if i % 12 == 9 { tendril(ctx, q, side, u, greens[0]) }
            }
        case .grassClump:
            let dry = biome == .desert || biome == .beach || biome == .tundra
            let col = dry ? c(0.74, 0.68, 0.42) : c(0.38, 0.62, 0.28)
            for (i, bar) in b.bars.enumerated() { paintBlade(ctx, bar.outline, rib: b.ribs[i], i % 2 == 0 ? col : shade(col, -0.12), u, veins: false) }
        case .floweringPlant:
            sticks(.greenStem)
            leaves(greens[0])
            flowerHead(ctx, P(0.52, 0.84), r.width * 0.26, s, u)
        case .tinyFlowers:
            let cols = [c(0.55, 0.7, 1), c(1, 1, 0.96), c(1, 0.86, 0.36), c(0.96, 0.62, 0.8)]
            for i in 0..<14 {
                let x = r.minX + r.width * (0.05 + rnd(s, i) * 0.9), h = r.height * (0.4 + rnd(s + 1, i) * 0.6)
                ctx.setStrokeColor(c(0.34, 0.56, 0.3))
                ctx.setLineWidth(0.9 * u)
                ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addLine(to: CGPoint(x: x + (rnd(s + 2, i) - 0.5) * 3 * u, y: r.minY + h))
                ctx.strokePath()
                blossom(ctx, CGPoint(x: x + (rnd(s + 2, i) - 0.5) * 3 * u, y: r.minY + h), 2.6 * u, cols[(i + s) % cols.count])
            }
        case .aloe:
            let col = c(0.46, 0.64, 0.56)
            for (i, bar) in b.bars.enumerated() {
                paintBlade(ctx, bar.outline, rib: b.ribs[i], i % 2 == 0 ? col : shade(col, -0.1), u, veins: false)
                ctx.saveGState()
                ctx.addPath(polyPath(bar.outline))
                ctx.clip()
                ctx.setFillColor(c(0.9, 0.96, 0.9, 0.55))
                for q in 0..<6 {
                    guard let rib = b.ribs[i] else { break }
                    let p = rib[min(rib.count - 1, 2 + q * 2)]
                    ctx.fillEllipse(in: CGRect(x: p.x - 1.2 * u + (rnd(s, q + i * 7) - 0.5) * 4 * u, y: p.y - 0.8 * u, width: 2.4 * u, height: 1.4 * u))
                }
                ctx.restoreGState()
            }
        case .jadePlant:
            sticks(.wood(light: c(0.6, 0.58, 0.4), mid: c(0.46, 0.44, 0.3), dark: c(0.3, 0.28, 0.18)))
            let pad = c(0.36, 0.6, 0.36)
            for i in 0..<9 {
                let st = b.sticks[1 + i % 3]
                let sp = st.spine()
                let q = sp[max(0, sp.count - 1 - (i / 3) * 3)]
                let e = CGRect(x: q.x - 9 * u + (rnd(s, i) - 0.5) * 8 * u, y: q.y - 4 * u + (rnd(s + 1, i) - 0.3) * 8 * u, width: 18 * u, height: 11 * u)
                jadePad(ctx, CGPath(ellipseIn: e, transform: nil), pad, u)
            }
            for bar in b.bars { jadePad(ctx, polyPath(bar.outline), shade(pad, 0.05), u) }
        case .lithops:
            for i in 0..<4 {
                let w = r.width * (0.2 + rnd(s, i) * 0.06), x = r.minX + r.width * (0.05 + CGFloat(i) * 0.24)
                let rect = CGRect(x: x, y: r.minY, width: w, height: r.height * (0.75 + rnd(s + 1, i) * 0.25))
                let col = [c(0.72, 0.64, 0.52), c(0.6, 0.62, 0.5), c(0.74, 0.58, 0.52)][(i + s) % 3]
                let p = CGPath(roundedRect: rect, cornerWidth: w * 0.45, cornerHeight: w * 0.45, transform: nil)
                fill(ctx, p, [shade(col, 0.25), col, shade(col, -0.25)], [0, 0.5, 1], from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
                ctx.setStrokeColor(alpha(shade(col, -0.5), 0.8))
                ctx.setLineWidth(1 * u)
                ctx.move(to: CGPoint(x: rect.midX, y: rect.maxY)); ctx.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.35))
                ctx.strokePath()
                ctx.setFillColor(alpha(shade(col, -0.3), 0.4))
                ctx.fillEllipse(in: CGRect(x: rect.minX + w * 0.15, y: rect.maxY - rect.height * 0.3, width: w * 0.25, height: rect.height * 0.14))
                outline(ctx, p, col, u * 0.7)
            }
        case .airPlant:
            let base = P(0.5, 0.1)
            for i in 0..<16 {
                let a = .pi / 2 + (CGFloat(i) / 15 - 0.5) * 3 + (rnd(s, i) - 0.5) * 0.3
                let len = r.height * (0.45 + rnd(s + 1, i) * 0.45)
                let tip = CGPoint(x: base.x + cos(a) * len, y: base.y + sin(a) * len * 0.9)
                let curl = CGPoint(x: base.x + cos(a) * len * 0.6 + (a > .pi / 2 ? -1 : 1) * 3 * u, y: base.y + sin(a) * len * 0.7 + 6 * u)
                ctx.setStrokeColor(i % 3 == 0 ? c(0.74, 0.8, 0.72) : c(0.6, 0.7, 0.6))
                ctx.setLineWidth((2.6 - CGFloat(i % 3) * 0.4) * u)
                ctx.move(to: base.point); ctx.addQuadCurve(to: tip, control: curl)
                ctx.strokePath()
            }
            if s % 2 == 0 { blossom(ctx, CGPoint(x: base.x, y: base.y + r.height * 0.55), 4 * u, c(0.92, 0.36, 0.6)) }
        case .miniPalm:
            paintStick(b.sticks[0], look: .greenStem, seed: s, u: u, ctx)
            ringed(ctx, b.sticks[0], u)
            for (i, st) in b.sticks.dropFirst().enumerated() {
                paintStick(st, look: .greenStem, seed: s, u: u, ctx)
                pinnae(ctx, st, greens[i % greens.count], u, long: true)
            }
        case .deadPlant:
            sticks(.straw)
            for (i, st) in b.sticks.enumerated() {
                guard let tip = st.spine().last else { continue }
                if i % 2 == 0 {
                    ctx.setFillColor(c(0.62, 0.5, 0.32))
                    ctx.fillEllipse(in: CGRect(x: tip.x - 3 * u, y: tip.y - 2 * u, width: 6 * u, height: 8 * u))
                } else {
                    leafShape(ctx, at: tip.point, length: 10 * u, angle: -0.8 + rnd(s, i), colour: c(0.66, 0.5, 0.32), u: u)
                }
            }
        case .fiddleheads:
            sticks(.greenStem)
            // The tip curled in tight inside its coil.
            for st in b.sticks {
                let sp = st.spine(step: 2)
                guard sp.count > 8 else { continue }
                let end = sp[sp.count - 1], before = sp[sp.count - 5]
                let d = (end - before).normalized
                let c0 = end + d.perp * (-2.6 * u) * (d.cross(before - sp[sp.count - 9]) > 0 ? -1 : 1)
                ctx.setStrokeColor(c(0.4, 0.62, 0.32))
                ctx.setLineWidth(1.6 * u)
                ctx.addArc(center: c0.point, radius: 2.6 * u, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
                ctx.strokePath()
            }
            ctx.setFillColor(c(0.55, 0.4, 0.24, 0.8))
            for st in b.sticks {
                for (i, q) in st.spine(step: 3).enumerated() where i % 3 == 0 && i > st.spine(step: 3).count / 2 {
                    ctx.fillEllipse(in: CGRect(x: q.x - 1 * u, y: q.y - 1 * u, width: 2 * u, height: 2 * u))
                }
            }
        case .creepingCover:
            for i in 0..<42 {
                let x = r.minX + rnd(s, i) * r.width, y = r.minY + rnd(s + 1, i) * r.height * 0.8
                let rr = (2.6 + rnd(s + 2, i) * 2.4) * u
                let col = greens[i % greens.count]
                fill(ctx, CGPath(ellipseIn: CGRect(x: x - rr, y: y - rr * 0.7, width: rr * 2, height: rr * 1.5), transform: nil), [shade(col, 0.2), shade(col, -0.15)],
                     from: CGPoint(x: x, y: y + rr), to: CGPoint(x: x, y: y - rr))
                if i % 13 == 0 { blossom(ctx, CGPoint(x: x, y: y + rr), 1.8 * u, c(1, 0.9, 0.4)) }
            }
        case .hangingFoliage:
            sticks(.greenStem)
            for (n, st) in b.sticks.enumerated() {
                for (i, q) in st.spine(step: 3).enumerated() where i % 4 == 1 {
                    let side: CGFloat = i % 8 == 1 ? 1 : -1
                    leafShape(ctx, at: q.point, length: (10 + rnd(s + n, i) * 5) * u, angle: -.pi / 2 + side * 0.9, colour: greens[(i + n) % greens.count], u: u)
                }
            }
            paintMoss(ctx, b.blocks[0].outline, s, u, biome, soil: true)
        case .mossCushion:
            paintMoss(ctx, b.blocks[0].outline, s, u, biome)

        // MARK: The ground
        case .gravel:
            for i in 0..<60 {
                let x = r.minX + rnd(s, i) * r.width, y = r.minY + rnd(s + 1, i) * r.height * 0.7
                let rr = (1 + rnd(s + 2, i) * 2.2) * u
                ctx.setFillColor([c(0.6, 0.58, 0.55), c(0.48, 0.47, 0.46), c(0.72, 0.68, 0.62), c(0.4, 0.38, 0.36)][(i + s) % 4])
                ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr * 0.7, width: rr * 2, height: rr * 1.4))
            }
        case .sandDrift:
            let o = b.blocks[0].outline
            let sand = biome == .beach ? c(0.9, 0.82, 0.64) : c(0.9, 0.74, 0.5)
            fill(ctx, polyPath(o), [shade(sand, 0.15), sand, shade(sand, -0.15)], [0, 0.5, 1], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            ctx.saveGState()
            ctx.addPath(polyPath(o))
            ctx.clip()
            ctx.setStrokeColor(alpha(shade(sand, -0.25), 0.5))
            ctx.setLineWidth(0.9 * u)
            for i in 0..<5 {
                let y = r.minY + r.height * (0.2 + CGFloat(i) * 0.16)
                ctx.move(to: CGPoint(x: r.minX, y: y))
                var x = r.minX
                while x < r.maxX { x += 8 * u; ctx.addLine(to: CGPoint(x: x, y: y + sin(x / (9 * u) + CGFloat(i)) * 1.5 * u)) }
                ctx.strokePath()
            }
            ctx.restoreGState()
        case .pineNeedles:
            for i in 0..<46 {
                let x = r.minX + rnd(s, i) * r.width, y = r.minY + rnd(s + 1, i) * r.height * 0.8
                let a = (rnd(s + 2, i) - 0.5) * 0.8, len = (8 + rnd(s + 3, i) * 8) * u
                ctx.setStrokeColor([c(0.6, 0.42, 0.24), c(0.5, 0.34, 0.2), c(0.7, 0.54, 0.32)][i % 3])
                ctx.setLineWidth(0.9 * u)
                ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + cos(a) * len, y: y + sin(a) * len * 0.4))
                ctx.strokePath()
            }

        // MARK: Details
        case .mushroom:
            paintStick(b.sticks[0], look: .wood(light: c(1, 0.98, 0.92), mid: c(0.92, 0.88, 0.8), dark: c(0.72, 0.68, 0.6)), seed: s, u: u, ctx)
            paintCap(ctx, b.bars[0].outline, variant: s % 3, u, spots: s % 3 == 0)
        case .mushroomCluster:
            paintMoss(ctx, b.blocks[0].outline, s, u, biome, soil: true)
            for st in b.sticks { paintStick(st, look: .wood(light: c(0.98, 0.94, 0.84), mid: c(0.88, 0.82, 0.7), dark: c(0.66, 0.6, 0.5)), seed: s, u: u, ctx) }
            for bar in b.bars { paintCap(ctx, bar.outline, variant: 3, u, spots: false) }
        case .tinyMushrooms, .glowMushrooms:
            let glows = kind == .glowMushrooms
            let n = glows ? 5 : 7
            for i in 0..<n {
                let x = r.minX + r.width * (0.08 + CGFloat(i) / CGFloat(n - 1) * 0.84) + (rnd(s, i) - 0.5) * 4 * u
                let h = r.height * (0.5 + rnd(s + 1, i) * 0.45)
                let cw = (glows ? 7 + rnd(s + 2, i) * 5 : 3.5 + rnd(s + 2, i) * 2) * u
                ctx.setStrokeColor(glows ? c(0.8, 0.95, 0.9) : c(0.86, 0.82, 0.74))
                ctx.setLineWidth((glows ? 1.8 : 1) * u)
                ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addQuadCurve(to: CGPoint(x: x + 1 * u, y: r.minY + h), control: CGPoint(x: x - 2 * u, y: r.minY + h * 0.5))
                ctx.strokePath()
                let cap = CGRect(x: x + 1 * u - cw, y: r.minY + h - cw * 0.3, width: cw * 2, height: cw * (glows ? 1.1 : 1.5))
                let p = CGMutablePath()
                p.move(to: CGPoint(x: cap.minX, y: cap.minY))
                p.addQuadCurve(to: CGPoint(x: cap.maxX, y: cap.minY), control: CGPoint(x: cap.midX, y: cap.maxY + cap.height * 0.6))
                p.closeSubpath()
                let col = glows ? c(0.36, 0.92, 0.78) : c(0.7, 0.58, 0.46)
                if glows { glow(ctx, at: CGPoint(x: cap.midX, y: cap.midY), radius: cw * 2.4, alpha(col, 0.5)) }
                fill(ctx, p, [shade(col, 0.35), col, shade(col, -0.2)], [0, 0.5, 1], from: CGPoint(x: cap.midX, y: cap.maxY), to: CGPoint(x: cap.midX, y: cap.minY))
                outline(ctx, p, col, u * 0.6)
            }
        case .shelfFungus:
            let bands = [c(0.44, 0.3, 0.2), c(0.7, 0.54, 0.36), c(0.9, 0.82, 0.66), c(0.5, 0.5, 0.56), c(0.62, 0.42, 0.26)]
            for blk in b.blocks {
                let bb = Poly.bounds(blk.outline)
                // Bands of colour, each a smaller copy of the bracket, in toward where it grows from.
                let root = V2(bb.minX, bb.midY)
                for i in 0..<6 {
                    let f = 1 - CGFloat(i) * 0.15
                    let band = blk.outline.map { root + ($0 - root) * f }
                    ctx.addPath(polyPath(band))
                    ctx.setFillColor(i == 0 ? c(0.96, 0.93, 0.84) : bands[(i + s) % bands.count])
                    ctx.fillPath()
                }
                outline(ctx, polyPath(blk.outline), bands[1], u * 0.8)
            }
        case .lichen:
            let cols = s % 3 == 0 ? [c(0.92, 0.66, 0.24), c(0.98, 0.78, 0.36)] : [c(0.66, 0.74, 0.58), c(0.78, 0.84, 0.7)]
            for i in 0..<7 {
                let cx = r.minX + r.width * (0.15 + rnd(s, i) * 0.7), cy = r.minY + r.height * (0.15 + rnd(s + 1, i) * 0.7)
                let rr = (4 + rnd(s + 2, i) * 5) * u
                for q in 0..<6 {
                    let a = CGFloat(q) / 6 * 2 * .pi + rnd(s, i + q)
                    let lc = CGPoint(x: cx + cos(a) * rr * 0.55, y: cy + sin(a) * rr * 0.55)
                    ctx.setFillColor(cols[q % 2])
                    ctx.fillEllipse(in: CGRect(x: lc.x - rr * 0.45, y: lc.y - rr * 0.45, width: rr * 0.9, height: rr * 0.9))
                }
                ctx.setStrokeColor(alpha(shade(cols[0], -0.3), 0.6))
                ctx.setLineWidth(0.6 * u)
                ctx.strokeEllipse(in: CGRect(x: cx - rr * 0.3, y: cy - rr * 0.3, width: rr * 0.6, height: rr * 0.6))
            }
        case .acorn:
            let nut = CGRect(x: r.minX + r.width * 0.14, y: r.minY, width: r.width * 0.72, height: r.height * 0.72)
            fill(ctx, CGPath(ellipseIn: nut, transform: nil), [c(0.78, 0.56, 0.3), c(0.58, 0.38, 0.18)], from: CGPoint(x: nut.minX, y: nut.maxY), to: CGPoint(x: nut.maxX, y: nut.minY))
            outline(ctx, CGPath(ellipseIn: nut, transform: nil), c(0.6, 0.4, 0.2), u * 0.7)
            let capR = CGRect(x: r.minX + r.width * 0.06, y: r.minY + r.height * 0.5, width: r.width * 0.88, height: r.height * 0.38)
            let cap = CGPath(ellipseIn: capR, transform: nil)
            fill(ctx, cap, [c(0.62, 0.52, 0.36), c(0.42, 0.34, 0.22)], from: CGPoint(x: 0, y: capR.maxY), to: CGPoint(x: 0, y: capR.minY))
            ctx.saveGState(); ctx.addPath(cap); ctx.clip()
            ctx.setStrokeColor(c(0.3, 0.22, 0.12, 0.6)); ctx.setLineWidth(0.6 * u)
            for i in 0..<8 {
                let x = capR.minX + capR.width * CGFloat(i) / 7
                ctx.move(to: CGPoint(x: x, y: capR.minY)); ctx.addLine(to: CGPoint(x: x + capR.height, y: capR.maxY))
                ctx.move(to: CGPoint(x: x, y: capR.minY)); ctx.addLine(to: CGPoint(x: x - capR.height, y: capR.maxY))
            }
            ctx.strokePath(); ctx.restoreGState()
            ctx.setStrokeColor(c(0.4, 0.3, 0.18)); ctx.setLineWidth(1.6 * u)
            ctx.move(to: CGPoint(x: r.midX, y: capR.maxY - 1)); ctx.addLine(to: CGPoint(x: r.midX + 2 * u, y: r.maxY)); ctx.strokePath()
        case .seedPod:
            let pod = CGMutablePath()
            pod.move(to: P(0.02, 0.3).point)
            pod.addQuadCurve(to: P(0.98, 0.5).point, control: P(0.5, -0.3).point)
            pod.addQuadCurve(to: P(0.02, 0.3).point, control: P(0.5, 0.55).point)
            fill(ctx, pod, [c(0.72, 0.64, 0.42), c(0.5, 0.44, 0.28)], from: P(0.5, 0.5).point, to: P(0.5, 0).point)
            outline(ctx, pod, c(0.5, 0.44, 0.28), u * 0.8)
            ctx.setStrokeColor(c(1, 1, 0.98, 0.8)); ctx.setLineWidth(0.6 * u)
            for i in 0..<16 {
                let o = P(0.3 + rnd(s, i) * 0.5, 0.3)
                let a = 0.6 + rnd(s + 1, i) * 2, len = (6 + rnd(s + 2, i) * 10) * u
                ctx.move(to: o.point); ctx.addLine(to: CGPoint(x: o.x + cos(a) * len, y: o.y + sin(a) * len))
            }
            ctx.strokePath()
            ctx.setFillColor(c(0.46, 0.3, 0.16))
            for i in 0..<5 { ctx.fillEllipse(in: CGRect(x: P(0.3 + CGFloat(i) * 0.1, 0.24).x, y: P(0, 0.24).y, width: 4 * u, height: 2.6 * u)) }
        case .pineCone:
            let o = b.blocks[0].outline
            let col = c(0.56, 0.38, 0.22)
            fill(ctx, polyPath(o), [shade(col, 0.2), col, shade(col, -0.3)], [0, 0.5, 1], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            ctx.saveGState(); ctx.addPath(polyPath(o)); ctx.clip()
            for row in 0..<9 {
                let y = r.minY + r.height * (0.05 + CGFloat(row) * 0.1)
                let off: CGFloat = row % 2 == 0 ? 0 : 0.5
                for i in 0..<5 {
                    let x = r.minX + r.width * ((CGFloat(i) + off) / 4.5)
                    let sc = CGRect(x: x - 5 * u, y: y - 3 * u, width: 10 * u, height: 7 * u)
                    fill(ctx, CGPath(ellipseIn: sc, transform: nil), [shade(col, 0.3), shade(col, -0.2)], from: CGPoint(x: sc.midX, y: sc.maxY), to: CGPoint(x: sc.midX, y: sc.minY))
                    ctx.setStrokeColor(alpha(shade(col, -0.5), 0.6)); ctx.setLineWidth(0.6 * u); ctx.strokeEllipse(in: sc)
                }
            }
            ctx.restoreGState()
            outline(ctx, polyPath(o), col, u)
        case .seaShell:
            let o = b.blocks[0].outline
            let col = [c(0.96, 0.84, 0.74), c(0.94, 0.9, 0.82), c(0.9, 0.72, 0.64)][s % 3]
            fill(ctx, polyPath(o), [shade(col, 0.2), col, shade(col, -0.25)], [0, 0.5, 1], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            ctx.saveGState(); ctx.addPath(polyPath(o)); ctx.clip()
            ctx.setStrokeColor(alpha(shade(col, -0.35), 0.6)); ctx.setLineWidth(0.9 * u)
            for i in 1...6 {
                let x = r.minX + r.width * (0.35 + CGFloat(i) * 0.1)
                ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addQuadCurve(to: CGPoint(x: x - r.width * 0.06, y: r.maxY), control: CGPoint(x: x + r.width * 0.08, y: r.midY))
            }
            ctx.strokePath()
            let ap = CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.14, width: r.width * 0.34, height: r.height * 0.42)
            fill(ctx, CGPath(ellipseIn: ap, transform: nil), [c(0.98, 0.66, 0.56), c(0.86, 0.46, 0.4)], from: CGPoint(x: ap.midX, y: ap.maxY), to: CGPoint(x: ap.midX, y: ap.minY))
            ctx.restoreGState()
            outline(ctx, polyPath(o), col, u)
        case .snailShell:
            let o = b.blocks[0].outline
            let col = [c(0.74, 0.54, 0.3), c(0.66, 0.6, 0.46), c(0.8, 0.68, 0.46)][s % 3]
            fill(ctx, polyPath(o), [shade(col, 0.25), col, shade(col, -0.3)], [0, 0.5, 1], from: CGPoint(x: r.minX, y: r.maxY), to: CGPoint(x: r.maxX, y: r.minY))
            ctx.saveGState(); ctx.addPath(polyPath(o)); ctx.clip()
            let cc = P(0.44, 0.52)
            ctx.setStrokeColor(alpha(shade(col, -0.45), 0.8)); ctx.setLineWidth(1.6 * u)
            var a: CGFloat = 0
            ctx.move(to: cc.point)
            while a < 4.2 * .pi { a += 0.2; let rr = a / (4.2 * .pi) * r.width * 0.5; ctx.addLine(to: CGPoint(x: cc.x + cos(a) * rr, y: cc.y + sin(a) * rr * 0.9)) }
            ctx.strokePath()
            ctx.restoreGState()
            ctx.setFillColor(c(0.98, 0.94, 0.86))
            ctx.fillEllipse(in: CGRect(x: P(0.72, 0.02).x, y: P(0, 0.02).y, width: r.width * 0.24, height: r.height * 0.2))
            outline(ctx, polyPath(o), col, u)
        case .fallenLeaf, .deadLeaf, .looseLeaf:
            let cols = kind == .deadLeaf ? [c(0.56, 0.4, 0.24), c(0.48, 0.34, 0.2)]
                : kind == .looseLeaf ? [c(0.62, 0.72, 0.3), c(0.86, 0.72, 0.28)] : [c(0.9, 0.52, 0.2), c(0.84, 0.3, 0.18), c(0.92, 0.74, 0.26), c(0.6, 0.68, 0.28)]
            let col = cols[s % cols.count]
            let l = NatureKit.blade(P(0.04, 0.4), angle: 0.12, len: r.width * 0.9, wide: r.height * (kind == .deadLeaf ? 1 : 1.3), bend: 0.05)
            var pts = l.outline
            if kind == .deadLeaf { pts = pts.enumerated().map { $0.element + V2(0, (rnd(s, $0.offset) - 0.5) * 3 * u) } }
            paintBlade(ctx, pts, rib: l.rib, col, u)
            if kind == .deadLeaf {
                ctx.setFillColor(c(0.2, 0.14, 0.08, 0.8))
                for i in 0..<3 { ctx.fillEllipse(in: CGRect(x: P(0.3 + CGFloat(i) * 0.18, 0.45).x, y: P(0, 0.35 + rnd(s, i) * 0.3).y, width: 3 * u, height: 2 * u)) }
            }
            ctx.setStrokeColor(shade(col, -0.4)); ctx.setLineWidth(1.2 * u)
            ctx.move(to: P(0.04, 0.4).point); ctx.addLine(to: P(-0.04, 0.3).point); ctx.strokePath()
        case .curledLeaf:
            let col = c(0.72, 0.5, 0.28)
            let roll = CGRect(x: r.minX + r.width * 0.08, y: r.minY, width: r.width * 0.84, height: r.height * 0.7)
            let p = CGPath(roundedRect: roll, cornerWidth: roll.height / 2, cornerHeight: roll.height / 2, transform: nil)
            fill(ctx, p, [shade(col, 0.25), col, shade(col, -0.3)], [0, 0.45, 1], from: CGPoint(x: 0, y: roll.maxY), to: CGPoint(x: 0, y: roll.minY))
            outline(ctx, p, col, u * 0.8)
            // Its rolled end.
            let end = CGRect(x: roll.maxX - roll.height * 0.8, y: roll.minY + 1 * u, width: roll.height * 0.7, height: roll.height - 2 * u)
            ctx.setStrokeColor(shade(col, -0.45)); ctx.setLineWidth(1.2 * u)
            ctx.strokeEllipse(in: end); ctx.strokeEllipse(in: end.insetBy(dx: end.width * 0.25, dy: end.height * 0.25))
            ctx.setStrokeColor(alpha(shade(col, -0.3), 0.6)); ctx.setLineWidth(0.7 * u)
            for i in 0..<4 {
                let x = roll.minX + roll.width * (0.18 + CGFloat(i) * 0.14)
                ctx.move(to: CGPoint(x: x, y: roll.minY + 2 * u)); ctx.addLine(to: CGPoint(x: x + 4 * u, y: roll.maxY - 2 * u))
            }
            ctx.strokePath()
        case .leafHeap:
            let o = b.blocks[0].outline
            let cols: [CGColor] = biome == .tundra ? [c(0.62, 0.56, 0.46), c(0.72, 0.64, 0.52)] : [c(0.8, 0.46, 0.2), c(0.9, 0.64, 0.24), c(0.64, 0.34, 0.16), c(0.72, 0.56, 0.22)]
            fill(ctx, polyPath(o), [c(0.5, 0.32, 0.16), c(0.3, 0.2, 0.1)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
            ctx.saveGState(); ctx.addPath(polyPath(Poly.grown(o, by: 3 * u))); ctx.clip()
            for i in 0..<46 {
                let x = r.minX + rnd(s, i) * r.width, y = r.minY + rnd(s + 1, i) * r.height * 1.05
                leafShape(ctx, at: CGPoint(x: x - 7 * u, y: y), length: (12 + rnd(s + 2, i) * 6) * u, angle: (rnd(s + 3, i) - 0.5) * 1.6, colour: cols[i % cols.count], u: u)
            }
            ctx.restoreGState()
        case .pebblePile:
            let o = b.blocks[0].outline
            fill(ctx, polyPath(o), [c(0.4, 0.38, 0.36), c(0.28, 0.26, 0.25)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
            ctx.saveGState(); ctx.addPath(polyPath(Poly.grown(o, by: 2 * u))); ctx.clip()
            for row in 0..<5 {
                for i in 0..<9 {
                    let x = r.minX + r.width * (CGFloat(i) + (row % 2 == 0 ? 0.2 : 0.7)) / 9, y = r.minY + r.height * CGFloat(row) * 0.22
                    let w = (9 + rnd(s + row, i) * 6) * u, h = w * 0.62
                    let col = [c(0.62, 0.6, 0.57), c(0.72, 0.64, 0.54), c(0.5, 0.5, 0.52), c(0.8, 0.76, 0.7)][(i + row + s) % 4]
                    let pe = CGRect(x: x - w / 2, y: y, width: w, height: h)
                    ctx.saveGState(); ctx.addEllipse(in: pe); ctx.clip()
                    radial(ctx, [shade(col, 0.35), col, shade(col, -0.3)], [0, 0.45, 1], at: CGPoint(x: pe.minX + w * 0.35, y: pe.maxY - h * 0.3), radius: w * 0.8)
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()
        case .smoothStones:
            for (i, blk) in b.blocks.enumerated() {
                let col = [c(0.56, 0.56, 0.58), c(0.66, 0.6, 0.54), c(0.48, 0.5, 0.52)][(i + s) % 3]
                let bb = Poly.bounds(blk.outline)
                ctx.saveGState(); ctx.addPath(polyPath(blk.outline)); ctx.clip()
                radial(ctx, [shade(col, 0.4), col, shade(col, -0.35)], [0, 0.5, 1], at: CGPoint(x: bb.minX + bb.width * 0.35, y: bb.maxY - bb.height * 0.25), radius: bb.width * 0.75)
                ctx.restoreGState()
                outline(ctx, polyPath(blk.outline), col, u * 0.8)
            }
        case .crystalCluster:
            paintStone(ctx, b.blocks[0].outline, s, u, biome, strata: false, tint: c(0.34, 0.3, 0.38), cap: false)
            let hue = crystalHue(s)
            for bar in b.bars.reversed() { paintCrystal(ctx, bar.outline, hue, u) }
        case .petals, .petal:
            let col = [c(0.98, 0.72, 0.82), c(1, 0.96, 0.94), c(0.98, 0.84, 0.5)][s % 3]
            let n = kind == .petal ? 1 : 10
            for i in 0..<n {
                let w = (kind == .petal ? r.width * 0.9 : (8 + rnd(s, i) * 4) * u), h = kind == .petal ? r.height * 0.8 : w * 0.5
                let cx = kind == .petal ? r.midX : r.minX + rnd(s + 1, i) * r.width, cy = kind == .petal ? r.midY : r.minY + rnd(s + 2, i) * r.height * 0.7
                ctx.saveGState()
                ctx.translateBy(x: cx, y: cy); ctx.rotate(by: (rnd(s + 3, i) - 0.5) * 1.2)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: -w / 2, y: 0))
                p.addQuadCurve(to: CGPoint(x: w / 2, y: 0), control: CGPoint(x: 0, y: h))
                p.addQuadCurve(to: CGPoint(x: -w / 2, y: 0), control: CGPoint(x: w * 0.1, y: -h * 0.7))
                fill(ctx, p, [shade(col, 0.2), shade(col, -0.12)], from: CGPoint(x: 0, y: h / 2), to: CGPoint(x: 0, y: -h / 2))
                ctx.restoreGState()
            }
        case .puddle:
            let e = CGRect(x: r.minX, y: r.minY - r.height * 0.1, width: r.width, height: r.height)
            ctx.setFillColor(c(0.2, 0.14, 0.09, 0.45))
            ctx.fillEllipse(in: e.insetBy(dx: -4 * u, dy: -1.5 * u))
            fill(ctx, CGPath(ellipseIn: e, transform: nil), [c(0.66, 0.82, 0.92), c(0.36, 0.56, 0.74)], from: CGPoint(x: 0, y: e.maxY), to: CGPoint(x: 0, y: e.minY))
            ctx.setFillColor(c(1, 1, 1, 0.5))
            ctx.fillEllipse(in: CGRect(x: e.minX + e.width * 0.2, y: e.midY, width: e.width * 0.25, height: e.height * 0.18))
        case .shedBark:
            let st = Stick([P(0.02, 0.06), P(0.3, 0.84), P(0.7, 0.9), P(0.94, 0.42), P(0.84, 0.22)], 6 * u, 5 * u)
            let o = b.blocks[0].outline
            fill(ctx, polyPath(o), [c(0.5, 0.36, 0.22), c(0.32, 0.22, 0.13)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
            ctx.saveGState(); ctx.addPath(polyPath(o)); ctx.clip()
            // Its pale inside, where it curls.
            ctx.setStrokeColor(c(0.86, 0.66, 0.44, 0.85)); ctx.setLineWidth(2 * u)
            strokeLine(ctx, st.spine().map { $0 + V2(0, -2.4 * u) })
            ctx.restoreGState()
            outline(ctx, polyPath(o), c(0.4, 0.28, 0.16), u)
        case .twigPile:
            sticks(wood)

        // MARK: Functional
        case .rockPool:
            paintStone(ctx, b.blocks[0].outline, s, u, biome, strata: true, cap: false)
            let water = CGRect(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.74, width: r.width * 0.72, height: r.height * 0.18)
            fill(ctx, CGPath(ellipseIn: water, transform: nil), [c(0.52, 0.8, 0.92), c(0.3, 0.56, 0.78)], from: CGPoint(x: 0, y: water.maxY), to: CGPoint(x: 0, y: water.minY))
            ctx.setFillColor(c(1, 1, 1, 0.5))
            ctx.fillEllipse(in: CGRect(x: water.minX + water.width * 0.2, y: water.midY, width: water.width * 0.2, height: water.height * 0.3))
            if biome != .desert && biome != .beach {
                mossPatch(ctx, along: CGRect(x: r.minX, y: 0, width: r.width * 0.25, height: 1), y: r.minY + r.height * 0.9, seed: s, u: u, biome: biome)
            }
        case .feedingPlatform:
            sticks(wood)
            let tray = b.blocks[0].outline
            paintCork(ctx, tray, s, u, biome, horizontal: true, tone: 0.2, inner: true)
            ctx.setFillColor(c(0.35, 0.24, 0.14, 0.6))
            ctx.fill(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.905, width: r.width * 0.76, height: 1.4 * u))
        case .baskingStone:
            paintStone(ctx, b.blocks[0].outline, s, u, biome, strata: true, tint: shade(rockColour(biome, s), 0.08), cap: biome == .tundra)
            ctx.saveGState(); ctx.addPath(polyPath(b.blocks[0].outline)); ctx.clip()
            linear(ctx, [c(1, 0.86, 0.5, 0.32), c(1, 0.86, 0.5, 0)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.maxY - r.height * 0.35))
            ctx.restoreGState()
        case .lookout:
            sticks(.driftwood)
            paintCork(ctx, b.blocks[0].outline, s, u, biome, horizontal: true, tone: 0)
        case .silkFrame:
            sticks(wood)
            for v in b.visual { lashing(ctx, Poly.bounds(v).mid, 5 * u, u) }
        case .climbingBark:
            paintCork(ctx, b.blocks[0].outline, s, u, biome, horizontal: false, tone: -0.04)
            for y: CGFloat in [0.06, 0.94] { screw(ctx, at: P(0.5, y), u, wood: true) }
        case .moistMoss:
            let saucer = b.blocks[0].outline, pot = c(0.74, 0.44, 0.3)
            fill(ctx, polyPath(saucer), [shade(pot, 0.15), shade(pot, -0.25)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
            outline(ctx, polyPath(saucer), pot, u)
            paintMoss(ctx, b.blocks[1].outline, s, u, biome, wet: true)
            for i in 0..<8 {
                let x = r.minX + r.width * (0.12 + rnd(s, i) * 0.76), y = r.minY + r.height * (0.55 + rnd(s + 1, i) * 0.35)
                let rr = (1.4 + rnd(s + 2, i) * 1.2) * u
                ctx.setFillColor(c(0.86, 0.96, 1, 0.8)); ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
                ctx.setFillColor(c(1, 1, 1, 0.95)); ctx.fillEllipse(in: CGRect(x: x - rr * 0.4, y: y + rr * 0.1, width: rr * 0.6, height: rr * 0.6))
            }
        case .shelterCanopy:
            for v in b.visual { paintStick(Stick([Poly.bounds(v).mid, Poly.bounds(v).mid], 3 * u, 3 * u), look: wood, seed: s, u: u, ctx); paintBarShape(ctx, v, wood, u) }
            sticks(wood)
            paintCork(ctx, b.bars[0].outline, s, u, biome, horizontal: true, tone: 0)
            if rnd(s, 4) < 0.6 || biome == .tundra { mossPatch(ctx, along: r.insetBy(dx: r.width * 0.2, dy: 0), y: r.minY + r.height * 0.84, seed: s, u: u, biome: biome) }

        // MARK: Loose
        case .tinyTwig:
            let st = Stick([P(0.02, 0.4), P(0.5, 0.55), P(0.98, 0.45)], 3.2 * u, 2 * u)
            paintStick(Stick([P(0.55, 0.55), P(0.72, 0.95)], 1.8 * u, 1.2 * u), look: wood, seed: s, u: u, ctx)
            paintStick(st, look: wood, seed: s, u: u, ctx)
        case .feather:
            let col = [c(0.9, 0.9, 0.92), c(0.56, 0.44, 0.34), c(0.36, 0.38, 0.44)][s % 3]
            let vane = NatureKit.blade(P(0.12, 0.45), angle: 0.06, len: r.width * 0.86, wide: r.height * 1.25, bend: 0.06)
            fill(ctx, polyPath(vane.outline), [alpha(shade(col, 0.25), 0.95), alpha(shade(col, -0.15), 0.9)], from: P(0.5, 1).point, to: P(0.5, 0).point)
            ctx.saveGState(); ctx.addPath(polyPath(vane.outline)); ctx.clip()
            ctx.setStrokeColor(alpha(shade(col, -0.35), 0.5)); ctx.setLineWidth(0.5 * u)
            for (i, q) in vane.rib.enumerated() where i > 0 {
                ctx.move(to: q.point); ctx.addLine(to: CGPoint(x: q.x + 4 * u, y: q.y + r.height))
                ctx.move(to: q.point); ctx.addLine(to: CGPoint(x: q.x + 4 * u, y: q.y - r.height))
            }
            ctx.strokePath(); ctx.restoreGState()
            ctx.setStrokeColor(shade(col, -0.2)); ctx.setLineWidth(1.2 * u)
            strokeLine(ctx, [P(0.0, 0.42)] + vane.rib)
        case .seed:
            let wing = NatureKit.blade(P(0.25, 0.4), angle: 0.2, len: r.width * 0.72, wide: r.height * 0.95, bend: 0.1)
            fill(ctx, polyPath(wing.outline), [c(0.86, 0.72, 0.5, 0.9), c(0.7, 0.54, 0.34, 0.9)], from: P(0.5, 1).point, to: P(0.5, 0).point)
            ctx.setStrokeColor(c(0.5, 0.36, 0.2, 0.6)); ctx.setLineWidth(0.6 * u)
            for i in 0..<5 { ctx.move(to: P(0.25, 0.4).point); ctx.addLine(to: P(0.6 + CGFloat(i) * 0.08, 0.2 + CGFloat(i) * 0.14).point) }
            ctx.strokePath()
            let nut = CGRect(x: r.minX, y: r.minY + r.height * 0.15, width: r.width * 0.32, height: r.height * 0.6)
            fill(ctx, CGPath(ellipseIn: nut, transform: nil), [c(0.66, 0.46, 0.26), c(0.46, 0.3, 0.16)], from: CGPoint(x: 0, y: nut.maxY), to: CGPoint(x: 0, y: nut.minY))
        case .smallShell:
            let col = [c(0.98, 0.84, 0.78), c(0.94, 0.9, 0.84), c(0.86, 0.7, 0.6)][s % 3]
            let fan = CGMutablePath()
            fan.move(to: P(0.5, 0.02).point)
            fan.addLine(to: P(0.02, 0.62).point)
            fan.addQuadCurve(to: P(0.98, 0.62).point, control: P(0.5, 1.3).point)
            fan.closeSubpath()
            fill(ctx, fan, [shade(col, 0.2), shade(col, -0.2)], from: P(0.5, 1).point, to: P(0.5, 0).point)
            ctx.setStrokeColor(alpha(shade(col, -0.35), 0.7)); ctx.setLineWidth(0.6 * u)
            for i in 0..<7 { ctx.move(to: P(0.5, 0.04).point); ctx.addLine(to: P(0.08 + CGFloat(i) * 0.14, 0.85 - abs(CGFloat(i) - 3) * 0.06).point) }
            ctx.strokePath()
            outline(ctx, fan, col, u * 0.7)
        case .tinyPebble:
            let col = rockColour(biome, s)
            let pe = r.insetBy(dx: r.width * 0.05, dy: r.height * 0.05)
            ctx.saveGState(); ctx.addEllipse(in: pe); ctx.clip()
            radial(ctx, [shade(col, 0.4), col, shade(col, -0.3)], [0, 0.45, 1], at: CGPoint(x: pe.minX + pe.width * 0.35, y: pe.maxY - pe.height * 0.3), radius: pe.width * 0.8)
            ctx.restoreGState()
        default:
            // (Anything without its own picture yet: its parts, plainly.)
            for st in b.sticks { paintStick(st, look: wood, seed: s, u: u, ctx) }
            for blk in b.blocks + b.bars { paintStone(ctx, blk.outline, s, u, biome, strata: false) }
        }
        return true
    }

    // MARK: Materials

    /// The greens of leaves here.
    static func leafGreens(_ biome: Biome, _ s: Int) -> [CGColor] {
        switch biome {
        case .jungle: return [c(0.2, 0.5, 0.28), c(0.26, 0.56, 0.3), c(0.16, 0.42, 0.24)]
        case .night, .cave: return [c(0.22, 0.42, 0.3), c(0.28, 0.48, 0.34), c(0.18, 0.36, 0.26)]
        case .desert, .beach: return [c(0.46, 0.6, 0.36), c(0.52, 0.64, 0.4), c(0.4, 0.54, 0.32)]
        case .tundra: return [c(0.3, 0.46, 0.34), c(0.36, 0.52, 0.38), c(0.26, 0.4, 0.3)]
        default: return [c(0.32, 0.58, 0.3), c(0.4, 0.64, 0.34), c(0.26, 0.5, 0.26)]
        }
    }

    /// A leaf blade: shaded across, with its midrib and side veins along `rib`.
    static func paintBlade(_ ctx: CGContext, _ pts: [V2], rib: [V2]?, _ col: CGColor, _ u: CGFloat, veins: Bool = true) {
        let p = polyPath(pts)
        let bb = Poly.bounds(pts)
        let across: V2
        if let rib, rib.count > 2 { across = (rib[rib.count - 1] - rib[0]).normalized.perp } else { across = V2(0, 1) }
        let side = across.y >= 0 ? across : -across
        let m = V2(bb.midX, bb.midY), half = max(bb.width, bb.height) * 0.3
        fill(ctx, p, [shade(col, 0.24), col, shade(col, -0.24)], [0, 0.5, 1], from: (m + side * half).point, to: (m - side * half).point)
        if let rib, rib.count > 2 {
            ctx.saveGState()
            ctx.addPath(p)
            ctx.clip()
            ctx.setStrokeColor(alpha(shade(col, 0.4), 0.75))
            ctx.setLineWidth(1 * u)
            strokeLine(ctx, rib)
            if veins {
                ctx.setStrokeColor(alpha(shade(col, 0.3), 0.45))
                ctx.setLineWidth(0.6 * u)
                for i in stride(from: 2, to: rib.count - 2, by: 2) {
                    let d = (rib[i + 1] - rib[i - 1]).normalized
                    let reach = bb.width + bb.height
                    for sgn: CGFloat in [-1, 1] {
                        ctx.move(to: rib[i].point)
                        ctx.addLine(to: (rib[i] + (d * 0.8 + d.perp * sgn).normalized * reach).point)
                    }
                }
                ctx.strokePath()
            }
            ctx.restoreGState()
        }
        outline(ctx, p, col, u * 0.8)
    }

    /// Cork bark over an outline: rough, ridged — along it (`horizontal`)
    /// or up it. `tone` lightens or darkens it; `inner`: its pale inside.
    static func paintCork(_ ctx: CGContext, _ pts: [V2], _ s: Int, _ u: CGFloat, _ biome: Biome, horizontal: Bool, tone: CGFloat, inner: Bool = false) {
        var (light, mid, dark) = woodColours(s + 3)
        if inner { (light, mid, dark) = (c(0.9, 0.74, 0.52), c(0.78, 0.6, 0.4), c(0.58, 0.42, 0.26)) }
        light = shade(light, tone); mid = shade(mid, tone); dark = shade(dark, tone)
        let p = polyPath(pts)
        let bb = Poly.bounds(pts)
        fill(ctx, p, [dark, mid, light, mid, shade(dark, -0.1)], [0, 0.2, 0.45, 0.75, 1],
             from: CGPoint(x: horizontal ? bb.midX : bb.minX, y: horizontal ? bb.maxY : bb.midY), to: CGPoint(x: horizontal ? bb.midX : bb.maxX, y: horizontal ? bb.minY : bb.midY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        let span = horizontal ? bb.height : bb.width
        let n = max(4, Int(span / (5 * u)))
        for i in 0..<n {
            let f = (CGFloat(i) + 0.5) / CGFloat(n)
            ctx.setStrokeColor(alpha(i % 2 == 0 ? shade(dark, -0.35) : shade(light, 0.15), i % 2 == 0 ? (inner ? 0.3 : 0.6) : 0.4))
            ctx.setLineWidth((i % 2 == 0 ? 2 : 1) * u)
            if horizontal {
                let y = bb.minY + f * bb.height
                ctx.move(to: CGPoint(x: bb.minX, y: y))
                ctx.addCurve(to: CGPoint(x: bb.maxX, y: y + (rnd(s, i) - 0.5) * 6 * u), control1: CGPoint(x: bb.minX + bb.width * 0.33, y: y + (rnd(s + 1, i) - 0.5) * 8 * u),
                             control2: CGPoint(x: bb.minX + bb.width * 0.66, y: y + (rnd(s + 2, i) - 0.5) * 8 * u))
            } else {
                let x = bb.minX + f * bb.width
                ctx.move(to: CGPoint(x: x, y: bb.minY))
                ctx.addCurve(to: CGPoint(x: x + (rnd(s, i) - 0.5) * 6 * u, y: bb.maxY), control1: CGPoint(x: x + (rnd(s + 1, i) - 0.5) * 10 * u, y: bb.minY + bb.height * 0.33),
                             control2: CGPoint(x: x + (rnd(s + 2, i) - 0.5) * 10 * u, y: bb.minY + bb.height * 0.66))
            }
            ctx.strokePath()
        }
        // Cracks across the grain.
        ctx.setStrokeColor(alpha(shade(dark, -0.4), inner ? 0.2 : 0.45))
        ctx.setLineWidth(0.9 * u)
        for i in 0..<max(3, Int(bb.width * bb.height / (900 * u * u))) {
            let x = bb.minX + rnd(s + 5, i) * bb.width, y = bb.minY + rnd(s + 6, i) * bb.height
            let len = (8 + rnd(s + 7, i) * 10) * u
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: horizontal ? CGPoint(x: x + 2 * u, y: y + len * 0.4) : CGPoint(x: x + len, y: y + 2 * u))
        }
        ctx.strokePath()
        linear(ctx, [c(1, 1, 1, 0.16), c(1, 1, 1, 0)], from: CGPoint(x: 0, y: bb.maxY), to: CGPoint(x: 0, y: bb.maxY - min(bb.height * 0.4, 12 * u)))
        ctx.restoreGState()
        outline(ctx, p, mid, u)
    }

    /// Stone over an outline: lit, speckled, layered, and capped with what
    /// settles on stone here.
    static func paintStone(_ ctx: CGContext, _ pts: [V2], _ s: Int, _ u: CGFloat, _ biome: Biome, strata: Bool, tint: CGColor? = nil, cap: Bool = true) {
        let base = tint ?? rockColour(biome, s)
        let p = polyPath(pts)
        let bb = Poly.bounds(pts)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        radial(ctx, [shade(base, 0.3), base, shade(base, -0.38)], [0, 0.5, 1],
               at: CGPoint(x: bb.minX + bb.width * 0.32, y: bb.maxY - bb.height * 0.2), radius: max(bb.width, bb.height) * 0.95)
        if strata {
            for i in 0..<Int(max(2, bb.height / (14 * u))) {
                let y = bb.minY + (CGFloat(i) + 0.6) * 14 * u + (rnd(s, i + 30) - 0.5) * 4 * u
                ctx.setStrokeColor(alpha(i % 2 == 0 ? shade(base, -0.4) : shade(base, 0.25), 0.35))
                ctx.setLineWidth((i % 2 == 0 ? 1.2 : 0.8) * u)
                ctx.move(to: CGPoint(x: bb.minX, y: y))
                ctx.addCurve(to: CGPoint(x: bb.maxX, y: y + (rnd(s, i) - 0.5) * 6 * u), control1: CGPoint(x: bb.minX + bb.width * 0.3, y: y + 3 * u),
                             control2: CGPoint(x: bb.minX + bb.width * 0.7, y: y - 3 * u))
                ctx.strokePath()
            }
        }
        for i in 0..<Int(max(8, bb.width * bb.height / (70 * u * u))) {
            let x = bb.minX + rnd(s + 9, i) * bb.width, y = bb.minY + rnd(s + 10, i) * bb.height
            let rr = (0.5 + rnd(s + 11, i) * 1.2) * u
            ctx.setFillColor(i % 2 == 0 ? alpha(shade(base, -0.4), 0.4) : alpha(shade(base, 0.4), 0.35))
            ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }
        // A crack or two.
        ctx.setStrokeColor(alpha(shade(base, -0.5), 0.5))
        ctx.setLineWidth(1 * u)
        for i in 0..<2 {
            let cx = bb.minX + bb.width * (0.25 + rnd(s, 20 + i) * 0.5)
            ctx.move(to: CGPoint(x: cx, y: bb.maxY))
            ctx.addLine(to: CGPoint(x: cx + 4 * u, y: bb.maxY - bb.height * 0.2))
            ctx.addLine(to: CGPoint(x: cx - 2 * u, y: bb.maxY - bb.height * 0.36))
            ctx.strokePath()
        }
        switch biome {
        case .desert, .beach:
            linear(ctx, [alpha(c(0.96, 0.86, 0.66), 0.45), alpha(c(0.96, 0.86, 0.66), 0)], from: CGPoint(x: 0, y: bb.minY), to: CGPoint(x: 0, y: bb.minY + min(bb.height * 0.35, 30 * u)))
        default: break
        }
        ctx.restoreGState()
        if cap { mossTufts(ctx, pts, s, u, biome, above: bb.maxY - min(bb.height * 0.3, 40 * u), sparse: biome != .tundra) }
        outline(ctx, p, base, u)
    }

    /// A stone stick (an arch): stone along its whole length.
    static func paintStoneStick(_ ctx: CGContext, _ st: Stick, _ s: Int, _ u: CGFloat, _ biome: Biome) {
        let pts = st.outline()
        paintStone(ctx, pts, s, u, biome, strata: false, cap: false)
        ctx.saveGState()
        ctx.addPath(polyPath(pts))
        ctx.clip()
        let base = rockColour(biome, s)
        let sp = st.spine(step: 4)
        let hw = st.halfWidths(sp)
        for k: CGFloat in [-0.55, -0.1, 0.4] {
            ctx.setStrokeColor(alpha(k < 0 ? shade(base, -0.4) : shade(base, 0.3), 0.4))
            ctx.setLineWidth(1.1 * u)
            let line = sp.indices.map { i -> V2 in
                let d = (sp[min(i + 1, sp.count - 1)] - sp[max(i - 1, 0)]).normalized
                return sp[i] + d.perp * (hw[i] * k)
            }
            strokeLine(ctx, line)
        }
        ctx.restoreGState()
        mossTufts(ctx, pts, s, u, biome, above: Poly.bounds(pts).maxY - 30 * u, sparse: biome != .tundra)
        outline(ctx, polyPath(pts), base, u)
    }

    /// Moss (or, soil: a clump of earth and moss) filling an outline, tufted.
    static func paintMoss(_ ctx: CGContext, _ pts: [V2], _ s: Int, _ u: CGFloat, _ biome: Biome, soil: Bool = false, wet: Bool = false) {
        let snow = biome == .tundra && !soil
        var base = snow ? c(0.9, 0.93, 1) : (biome == .night || biome == .cave ? c(0.24, 0.4, 0.28) : c(0.34, 0.56, 0.26))
        if wet { base = c(0.22, 0.46, 0.2) }
        let p = polyPath(pts)
        let bb = Poly.bounds(pts)
        fill(ctx, p, soil ? [c(0.36, 0.3, 0.2), c(0.2, 0.15, 0.1)] : [shade(base, 0.12), shade(base, -0.25)],
             from: CGPoint(x: 0, y: bb.maxY), to: CGPoint(x: 0, y: bb.minY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        for i in 0..<Int(max(10, bb.width * bb.height / (40 * u * u))) {
            let x = bb.minX + rnd(s, i) * bb.width, y = bb.minY + rnd(s + 1, i) * bb.height
            let rr = (2.5 + rnd(s + 2, i) * 3.5) * u
            let col = soil ? (i % 3 == 0 ? c(0.36, 0.52, 0.26) : c(0.3, 0.24, 0.16)) : shade(base, rnd(s + 3, i) * 0.3 - 0.1)
            ctx.setFillColor(col)
            ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr * 0.7, width: rr * 2, height: rr * 1.4))
        }
        if wet {
            linear(ctx, [c(1, 1, 1, 0.22), c(1, 1, 1, 0)], from: CGPoint(x: 0, y: bb.maxY), to: CGPoint(x: 0, y: bb.midY))
        }
        ctx.restoreGState()
        mossTufts(ctx, pts, s, u, biome, above: bb.maxY - bb.height * 0.4, soil: soil)
    }

    /// Little clumps of moss (snow, in the snow) along the top of an outline, above `above`.
    static func mossTufts(_ ctx: CGContext, _ pts: [V2], _ s: Int, _ u: CGFloat, _ biome: Biome, above: CGFloat, sparse: Bool = false, soil: Bool = false) {
        let snow = biome == .tundra
        guard snow || [.forest, .jungle, .night, .meadow, .cave].contains(biome) || soil else { return }
        let base = snow ? c(0.96, 0.97, 1) : (biome == .night || biome == .cave ? c(0.24, 0.4, 0.28) : c(0.38, 0.58, 0.28))
        let bb = Poly.bounds(pts)
        let step = 5 * u
        var x = bb.minX + step
        var i = 0
        while x < bb.maxX - step {
            defer { x += step; i += 1 }
            if sparse, rnd(s, 200 + i / 4) < 0.5 { continue }
            guard let y = topY(pts, x), y > above else { continue }
            let rr = (2.4 + rnd(s + 4, i) * 2.6) * u
            ctx.setFillColor(i % 3 == 0 ? shade(base, 0.18) : base)
            ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr * 0.9, width: rr * 2, height: rr * 1.5))
        }
    }

    /// The highest point of an outline at `x`, if it is there at all.
    static func topY(_ pts: [V2], _ x: CGFloat) -> CGFloat? {
        var best: CGFloat?
        for i in pts.indices {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            guard (a.x - x) * (b.x - x) <= 0, abs(b.x - a.x) > 1e-6 else { continue }
            let y = a.y + (b.y - a.y) * (x - a.x) / (b.x - a.x)
            if best.map({ y > $0 }) ?? true { best = y }
        }
        return best
    }

    /// The dark inside of a hollow: fading back into the shadow.
    static func fillHollow(_ ctx: CGContext, _ pts: [V2], _ s: Int, _ u: CGFloat, stone: Bool = false) {
        let bb = Poly.bounds(pts)
        let p = polyPath(pts)
        fill(ctx, p, stone ? [c(0.2, 0.19, 0.2), c(0.08, 0.07, 0.08)] : [c(0.22, 0.14, 0.08), c(0.07, 0.04, 0.02)],
             from: CGPoint(x: bb.midX, y: bb.minY), to: CGPoint(x: bb.midX, y: bb.maxY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        ctx.setStrokeColor(stone ? c(0.3, 0.3, 0.32, 0.35) : c(0.36, 0.24, 0.14, 0.35))
        ctx.setLineWidth(1 * u)
        for i in 0..<Int(max(3, bb.width / (9 * u))) {
            let x = bb.minX + (CGFloat(i) + rnd(s, i + 50)) * 9 * u
            ctx.move(to: CGPoint(x: x, y: bb.minY)); ctx.addLine(to: CGPoint(x: x + (rnd(s, i) - 0.5) * 6 * u, y: bb.maxY))
        }
        ctx.strokePath()
        // Light comes in at the floor.
        linear(ctx, [c(1, 0.9, 0.7, 0.12), c(1, 0.9, 0.7, 0)], from: CGPoint(x: 0, y: bb.minY), to: CGPoint(x: 0, y: bb.minY + bb.height * 0.3))
        ctx.restoreGState()
    }

    /// The far wall of a tube or a hollow log, seen through its open side.
    static func hollowBack(_ ctx: CGContext, _ rect: CGRect, _ s: Int, _ u: CGFloat, curved: Bool) {
        fill(ctx, CGPath(rect: rect, transform: nil), [c(0.3, 0.2, 0.12), c(0.12, 0.08, 0.04), c(0.24, 0.16, 0.09)], [0, 0.5, 1],
             from: CGPoint(x: rect.midX, y: rect.maxY), to: CGPoint(x: rect.midX, y: rect.minY))
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.setStrokeColor(c(0.46, 0.32, 0.2, 0.32))
        ctx.setLineWidth(1 * u)
        for i in 0..<Int(max(3, rect.width / (7 * u))) {
            let x = rect.minX + (CGFloat(i) + rnd(s, i)) * 7 * u
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            if curved { ctx.addQuadCurve(to: CGPoint(x: x, y: rect.maxY), control: CGPoint(x: x - 6 * u, y: rect.midY)) } else { ctx.addLine(to: CGPoint(x: x + 2 * u, y: rect.maxY)) }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A sawn face: pale wood, with its rings and a crack.
    static func cutFace(_ ctx: CGContext, _ e: CGRect, _ u: CGFloat, _ s: Int) {
        fill(ctx, CGPath(ellipseIn: e, transform: nil), [c(0.93, 0.78, 0.55), c(0.78, 0.6, 0.38)], from: CGPoint(x: e.minX, y: e.maxY), to: CGPoint(x: e.maxX, y: e.minY))
        ctx.setStrokeColor(alpha(c(0.55, 0.38, 0.22), 0.6))
        ctx.setLineWidth(0.7 * u)
        for i in 1...4 { ctx.strokeEllipse(in: e.insetBy(dx: CGFloat(i) * e.width * 0.1, dy: CGFloat(i) * e.height * 0.1)) }
        ctx.move(to: CGPoint(x: e.midX, y: e.midY))
        ctx.addLine(to: CGPoint(x: e.midX + e.width * (0.2 + rnd(s, 3) * 0.2), y: e.maxY - e.height * 0.15))
        ctx.strokePath()
        ctx.setStrokeColor(alpha(c(0.45, 0.3, 0.18), 0.9))
        ctx.setLineWidth(1 * u)
        ctx.strokeEllipse(in: e)
    }

    /// A little pile of soil where something goes into the ground.
    static func soilMound(_ ctx: CGContext, _ at: V2, _ w: CGFloat, _ biome: Biome) {
        let e = CGRect(x: at.x - w / 2, y: at.y - w * 0.12, width: w, height: w * 0.32)
        let col = biome == .desert || biome == .beach ? c(0.78, 0.64, 0.44) : c(0.34, 0.24, 0.15)
        fill(ctx, CGPath(ellipseIn: e, transform: nil), [shade(col, 0.15), shade(col, -0.2)], from: CGPoint(x: 0, y: e.maxY), to: CGPoint(x: 0, y: e.minY))
    }

    /// Fine roots dangling off the underside of a root.
    static func rootHairs(_ ctx: CGContext, _ st: Stick, _ u: CGFloat, _ s: Int) {
        let sp = st.spine(step: 5)
        let hw = st.halfWidths(sp)
        ctx.setStrokeColor(c(0.32, 0.23, 0.15, 0.7))
        ctx.setLineWidth(0.8 * u)
        for i in stride(from: 3, to: sp.count - 3, by: 3) {
            let q = sp[i] - V2(0, hw[i] * 0.8)
            let len = (5 + rnd(s, i) * 8) * u
            ctx.move(to: q.point)
            ctx.addQuadCurve(to: CGPoint(x: q.x + (rnd(s + 1, i) - 0.5) * 6 * u, y: q.y - len), control: CGPoint(x: q.x + 3 * u, y: q.y - len * 0.5))
        }
        ctx.strokePath()
    }

    /// Moss along the top of a stick, where it lies flattest.
    static func mossAlong(_ ctx: CGContext, _ st: Stick, _ u: CGFloat, _ s: Int, _ biome: Biome) {
        let sp = st.spine(step: 5)
        let hw = st.halfWidths(sp)
        let snow = biome == .tundra
        let base = snow ? c(0.96, 0.97, 1) : c(0.38, 0.58, 0.28)
        for i in 1..<(sp.count - 1) {
            let d = (sp[i + 1] - sp[i - 1]).normalized
            guard abs(d.y) < 0.45, rnd(s, i) < 0.7 else { continue }
            let q = sp[i] + V2(0, hw[i] * 0.8)
            let rr = (2.4 + rnd(s + 1, i) * 2.4) * u
            ctx.setFillColor(i % 3 == 0 ? shade(base, 0.18) : base)
            ctx.fillEllipse(in: CGRect(x: q.x - rr, y: q.y - rr * 0.6, width: rr * 2, height: rr * 1.4))
        }
    }

    /// Diagonal grain round a twisted stick.
    static func spiralGrain(_ ctx: CGContext, _ st: Stick, _ dark: CGColor, _ u: CGFloat) {
        let sp = st.spine(step: 7)
        let hw = st.halfWidths(sp)
        ctx.saveGState()
        ctx.addPath(st.path())
        ctx.clip()
        ctx.setStrokeColor(alpha(dark, 0.4))
        ctx.setLineWidth(0.8 * u)
        for i in 1..<(sp.count - 1) {
            let d = (sp[i + 1] - sp[i - 1]).normalized
            ctx.move(to: (sp[i] + d.perp * hw[i] - d * hw[i]).point)
            ctx.addLine(to: (sp[i] - d.perp * hw[i] + d * hw[i]).point)
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func knot(_ ctx: CGContext, _ at: V2, _ rad: CGFloat, _ dark: CGColor) {
        ctx.setFillColor(alpha(dark, 0.85))
        ctx.fillEllipse(in: CGRect(x: at.x - rad * 1.2, y: at.y - rad * 0.8, width: rad * 2.4, height: rad * 1.6))
    }

    /// Twine wound round where things are lashed.
    static func lashing(_ ctx: CGContext, _ at: V2, _ rad: CGFloat, _ u: CGFloat) {
        let (light, _, dark) = colours(.jute)
        for i in 0..<5 {
            let y = at.y - rad * 0.6 + CGFloat(i) * rad * 0.3
            ctx.setStrokeColor(i % 2 == 0 ? light : shade(light, -0.12))
            ctx.setLineWidth(2 * u)
            ctx.move(to: CGPoint(x: at.x - rad, y: y - rad * 0.3)); ctx.addLine(to: CGPoint(x: at.x + rad, y: y + rad * 0.3))
            ctx.strokePath()
        }
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(1.2 * u)
        ctx.move(to: CGPoint(x: at.x + rad * 0.6, y: at.y - rad * 0.3)); ctx.addQuadCurve(to: CGPoint(x: at.x + rad * 0.9, y: at.y - rad * 1.4), control: CGPoint(x: at.x + rad * 1.3, y: at.y - rad * 0.6))
        ctx.strokePath()
    }

    /// A length of twine, drawn as the bar it is laid out as.
    static func paintJute(_ ctx: CGContext, _ pts: [V2], _ u: CGFloat) {
        let (light, mid, _) = colours(.jute)
        let p = polyPath(pts)
        ctx.addPath(p); ctx.setFillColor(mid); ctx.fillPath()
        ctx.addPath(p); ctx.setStrokeColor(alpha(light, 0.8)); ctx.setLineWidth(0.5 * u); ctx.strokePath()
    }

    static func paintBarShape(_ ctx: CGContext, _ pts: [V2], _ look: StickLook, _ u: CGFloat) {
        let (light, mid, _) = colours(look)
        let p = polyPath(pts)
        fill(ctx, p, [light, mid], from: CGPoint(x: Poly.bounds(pts).minX, y: Poly.bounds(pts).maxY), to: CGPoint(x: Poly.bounds(pts).maxX, y: Poly.bounds(pts).minY))
        outline(ctx, p, mid, u * 0.8)
    }

    /// Leaflets in pairs along a frond: a fern's, a palm's.
    static func pinnae(_ ctx: CGContext, _ st: Stick, _ col: CGColor, _ u: CGFloat, long: Bool = false) {
        let sp = st.spine(step: 3)
        guard sp.count > 3 else { return }
        for i in stride(from: 2, to: sp.count - 1, by: long ? 2 : 1) {
            let t = CGFloat(i) / CGFloat(sp.count)
            let d = (sp[min(i + 1, sp.count - 1)] - sp[i - 1]).normalized
            let a = atan2(d.y, d.x)
            let len = ((long ? 16 : 9) * (1 - t * 0.7) + 2) * u
            for sgn: CGFloat in [-1, 1] {
                leafShape(ctx, at: sp[i].point, length: len, angle: a + sgn * (long ? 1.25 : 1.05) + (long ? -0.35 : 0), colour: i % 2 == 0 ? col : shade(col, 0.08), u: u * 0.55)
            }
        }
    }

    /// A fern's fronds from `base`, fanned across the rectangle.
    static func paintFronds(_ ctx: CGContext, base: V2, _ r: CGRect, _ s: Int, _ u: CGFloat, count: Int, greens: [CGColor]) {
        for i in 0..<count {
            let a = CGFloat(i) / CGFloat(count - 1) * 2.4 - 1.2 + (rnd(s, i) - 0.5) * 0.2
            let len = r.height * (0.75 + rnd(s + 1, i) * 0.3)
            let tip = V2(base.x + sin(a) * len * 1.1 * r.width / r.height * 0.6, base.y + cos(a) * len * 0.95)
            let ctl = V2(base.x + sin(a) * len * 0.3, base.y + len * 0.95)
            let pts = (0...10).map { k -> V2 in
                let t = CGFloat(k) / 10
                return base * ((1 - t) * (1 - t)) + ctl * (2 * t * (1 - t)) + tip * (t * t)
            }
            let st = Stick(pts, 1.6 * u, 0.8 * u)
            paintStick(st, look: .greenStem, seed: s, u: u, ctx)
            pinnae(ctx, st, greens[i % greens.count], u * 0.8)
        }
    }

    /// A ringed trunk (a palm's).
    static func ringed(_ ctx: CGContext, _ st: Stick, _ u: CGFloat) {
        let sp = st.spine(step: 5)
        let hw = st.halfWidths(sp)
        ctx.setStrokeColor(c(0.3, 0.3, 0.18, 0.6))
        ctx.setLineWidth(1 * u)
        for i in stride(from: 1, to: sp.count - 1, by: 1) {
            let d = (sp[i + 1] - sp[i - 1]).normalized
            ctx.move(to: (sp[i] + d.perp * hw[i]).point); ctx.addLine(to: (sp[i] - d.perp * hw[i]).point)
        }
        ctx.strokePath()
    }

    /// A curl of tendril off a climbing stem.
    static func tendril(_ ctx: CGContext, _ at: V2, _ side: CGFloat, _ u: CGFloat, _ col: CGColor) {
        ctx.setStrokeColor(shade(col, 0.1))
        ctx.setLineWidth(0.9 * u)
        var a: CGFloat = 0
        ctx.move(to: at.point)
        let c0 = at + V2(side * 7 * u, 4 * u)
        while a < 3.5 * .pi {
            a += 0.35
            let rr = 6 * u * (1 - a / (4 * .pi))
            ctx.addLine(to: CGPoint(x: c0.x - side * cos(a) * rr, y: c0.y + sin(a) * rr))
        }
        ctx.strokePath()
    }

    /// A tiny flower: five petals and a middle.
    static func blossom(_ ctx: CGContext, _ at: CGPoint, _ rad: CGFloat, _ col: CGColor) {
        ctx.setFillColor(col)
        for q in 0..<5 {
            let a = CGFloat(q) / 5 * 2 * .pi
            ctx.fillEllipse(in: CGRect(x: at.x + cos(a) * rad * 0.7 - rad * 0.55, y: at.y + sin(a) * rad * 0.7 - rad * 0.55, width: rad * 1.1, height: rad * 1.1))
        }
        ctx.setFillColor(c(1, 0.86, 0.3))
        ctx.fillEllipse(in: CGRect(x: at.x - rad * 0.35, y: at.y - rad * 0.35, width: rad * 0.7, height: rad * 0.7))
    }

    /// A flower's head, seen side on: petals round a disc.
    static func flowerHead(_ ctx: CGContext, _ c0: V2, _ half: CGFloat, _ s: Int, _ u: CGFloat) {
        let kinds: [(petal: CGColor, disc: CGColor)] = [(c(0.94, 0.5, 0.7), c(0.86, 0.46, 0.18)), (c(1, 0.8, 0.2), c(0.4, 0.24, 0.12)), (c(1, 1, 0.97), c(1, 0.8, 0.24)), (c(0.66, 0.5, 0.94), c(0.96, 0.84, 0.3))]
        let f = kinds[s % kinds.count]
        for q in 0..<12 {
            let a = CGFloat(q) / 12 * 2 * .pi
            let tip = CGPoint(x: c0.x + cos(a) * half * 1.7, y: c0.y + sin(a) * half * 0.55 - (q > 6 ? half * 0.1 : 0))
            ctx.saveGState()
            ctx.translateBy(x: c0.x, y: c0.y)
            ctx.rotate(by: atan2(tip.y - c0.y, tip.x - c0.x))
            let l = hypot(tip.x - c0.x, tip.y - c0.y)
            let p = CGPath(ellipseIn: CGRect(x: l * 0.2, y: -half * 0.16, width: l * 0.85, height: half * 0.32), transform: nil)
            fill(ctx, p, [shade(f.petal, 0.2), shade(f.petal, -0.12)], from: CGPoint(x: 0, y: half * 0.2), to: CGPoint(x: 0, y: -half * 0.2))
            ctx.restoreGState()
        }
        let disc = CGRect(x: c0.x - half * 0.75, y: c0.y - half * 0.28, width: half * 1.5, height: half * 0.8)
        fill(ctx, CGPath(ellipseIn: disc, transform: nil), [shade(f.disc, 0.25), shade(f.disc, -0.25)], from: CGPoint(x: 0, y: disc.maxY), to: CGPoint(x: 0, y: disc.minY))
        outline(ctx, CGPath(ellipseIn: disc, transform: nil), f.disc, u * 0.6)
    }

    /// A mushroom's cap: coloured by `variant`, spotted or not, its gills under it.
    static func paintCap(_ ctx: CGContext, _ pts: [V2], variant: Int, _ u: CGFloat, spots: Bool) {
        let col = [c(0.86, 0.22, 0.16), c(0.56, 0.36, 0.2), c(0.94, 0.6, 0.2), c(0.82, 0.62, 0.36)][variant % 4]
        let p = polyPath(pts)
        let bb = Poly.bounds(pts)
        fill(ctx, p, [shade(col, 0.3), col, shade(col, -0.3)], [0, 0.5, 1], from: CGPoint(x: bb.minX + bb.width * 0.3, y: bb.maxY), to: CGPoint(x: bb.maxX, y: bb.minY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        // The gills, pale, along its underside.
        ctx.setFillColor(c(0.96, 0.9, 0.8))
        ctx.fill(CGRect(x: bb.minX, y: bb.minY, width: bb.width, height: bb.height * 0.16))
        ctx.setStrokeColor(c(0.7, 0.6, 0.5, 0.7))
        ctx.setLineWidth(0.5 * u)
        for i in 0..<Int(bb.width / (3 * u)) {
            let x = bb.minX + CGFloat(i) * 3 * u
            ctx.move(to: CGPoint(x: x, y: bb.minY)); ctx.addLine(to: CGPoint(x: bb.midX + (x - bb.midX) * 0.6, y: bb.minY + bb.height * 0.16))
        }
        ctx.strokePath()
        if spots {
            ctx.setFillColor(c(1, 0.98, 0.93))
            for i in 0..<7 {
                let x = bb.minX + bb.width * (0.15 + rnd(i, 3) * 0.7), y = bb.minY + bb.height * (0.35 + rnd(i, 4) * 0.5)
                let rr = (1.6 + rnd(i, 5) * 1.6) * u
                ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr * 0.8, width: rr * 2, height: rr * 1.6))
            }
        }
        ctx.restoreGState()
        outline(ctx, p, col, u * 0.8)
    }

    /// A crystal: a light face and a dark one, and a glint up it.
    static func paintCrystal(_ ctx: CGContext, _ pts: [V2], _ hue: CGColor, _ u: CGFloat) {
        let p = polyPath(pts)
        let bb = Poly.bounds(pts)
        fill(ctx, p, [shade(hue, 0.45), shade(hue, 0.05), shade(hue, -0.3)], [0, 0.5, 1], from: CGPoint(x: bb.minX, y: bb.maxY), to: CGPoint(x: bb.maxX, y: bb.minY))
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip()
        if pts.count >= 5 {
            // The ridge down its middle, from its point.
            let tip = pts.max { $0.distance(to: pts[0]) + $0.distance(to: pts[1]) < $1.distance(to: pts[0]) + $1.distance(to: pts[1]) } ?? pts[0]
            let foot = V2.lerp(pts[0], pts[1], 0.5)
            ctx.setStrokeColor(c(1, 1, 1, 0.55))
            ctx.setLineWidth(0.9 * u)
            ctx.move(to: tip.point); ctx.addLine(to: foot.point); ctx.strokePath()
        }
        ctx.restoreGState()
        outline(ctx, p, hue, u * 0.6)
    }

    static func jadePad(_ ctx: CGContext, _ p: CGPath, _ col: CGColor, _ u: CGFloat) {
        let bb = p.boundingBox
        fill(ctx, p, [shade(col, 0.3), col, shade(col, -0.2)], [0, 0.5, 1], from: CGPoint(x: bb.minX, y: bb.maxY), to: CGPoint(x: bb.maxX, y: bb.minY))
        ctx.addPath(p)
        ctx.setStrokeColor(c(0.78, 0.3, 0.26, 0.7))
        ctx.setLineWidth(1 * u)
        ctx.strokePath()
    }

    /// A soft shadow on the ground under something that roofs it over.
    static func groundShade(_ ctx: CGContext, _ r: CGRect) {
        ctx.saveGState()
        ctx.translateBy(x: r.midX, y: r.minY + 2)
        ctx.scaleBy(x: 1, y: 0.12)
        radial(ctx, [c(0, 0, 0, 0.25), c(0, 0, 0, 0)], [0, 1], at: .zero, radius: r.width * 0.5)
        ctx.restoreGState()
    }

    static func strokeLine(_ ctx: CGContext, _ pts: [V2]) {
        guard let f = pts.first else { return }
        ctx.move(to: f.point)
        for q in pts.dropFirst() { ctx.addLine(to: q.point) }
        ctx.strokePath()
    }
}

extension CGRect {
    /// Its middle, as a vector.
    var mid: V2 { V2(midX, midY) }
}
