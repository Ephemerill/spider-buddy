import AppKit

// MARK: - The pieces structures are built from
//
// Each kind of piece — a branch, a root, a bracket, a 2×4 — laid out in its
// rectangle: the sticks and solid blocks it is made of, what is only drawn
// (leaves, a wall plate, a bolt), and where things fasten to it. Its picture
// (HabitatPieceArt.swift) is painted from exactly this, and its physical
// shape and ports are taken from it, so the three always agree.

/// A piece, laid out.
struct PieceBuild {
    /// Slender parts: its limbs.
    var sticks: [Stick] = []
    /// Chunky parts: outlines, clockwise.
    var blocks: [(name: String, outline: [V2])] = []
    /// Slender parts with square ends (a post, a batten): limbs, like sticks.
    var bars: [(name: String, outline: [V2])] = []
    /// Drawn, but nothing to stand on.
    var visual: [[V2]] = []
    /// Where things fasten, besides the sticks' own ends and lengths.
    var ports: [HabitatPort] = []
    var anchors: [ObjectAnchor] = []
    var hollows: [Hollow] = []
    /// Its sticks' ends and lengths as ports too.
    var stickPorts = true
}

extension HabitatShape {
    /// A kind's shape, for its definition.
    static func pieceShape(_ kind: HabitatItemKind) -> (CGRect, Int, CGFloat) -> ObjectGeometry {
        { r, s, u in
            let b = piece(kind, r, s, u)
            var g = ObjectGeometry()
            let solid = kind.definition.category == .perch
            let limbs = b.sticks.map { ShapePart(name: $0.name, role: .limb, outline: $0.outline()) }.filter { $0.outline.count >= 3 }
            // (Each block a hair bigger than the one before, so that no two
            // of one thing's blocks — a sofa's seat and its arm — have edges
            // lying exactly along each other, which the surfaces can't sort out.)
            func hair(_ o: [V2], _ k: Int) -> [V2] { k == 0 ? Poly.clockwise(o) : Poly.grown(Poly.clockwise(o), by: CGFloat(k) * 0.06) }
            let bulk = b.blocks.enumerated().map { ShapePart(name: $0.element.name, role: .bulk, outline: hair($0.element.outline, $0.offset)) }.filter { $0.outline.count >= 3 }
                + b.bars.enumerated().map { ShapePart(name: $0.element.name, role: .limb, outline: hair($0.element.outline, $0.offset)) }.filter { $0.outline.count >= 3 }
            if solid {
                g.parts = bulk + limbs
                g.visual = b.visual
            } else {
                // Hardware you can't stand on: all of it only drawn.
                g.visual = (bulk + limbs).map(\.outline) + b.visual
            }
            g.anchors = b.anchors
            g.hollows = b.hollows
            return g
        }
    }

    /// A kind's ports, for its definition.
    static func piecePorts(_ kind: HabitatItemKind) -> (CGRect, Int, CGFloat) -> [HabitatPort] {
        { r, s, u in
            switch kind {
            case .branch: return branchPorts(r, u)
            case .vine: return vinePorts(r, u)
            default: break
            }
            let b = piece(kind, r, s, u)
            var ps = b.ports
            guard b.stickPorts else { return ps }
            for (i, st) in b.sticks.enumerated() {
                let sp = st.spine(step: 6)
                guard sp.count >= 2 else { continue }
                if (Stick.cumulative(sp).last ?? 0) > 24 { ps.append(st.along("along\(i)")) }
                if let k = st.start { ps.append(HabitatPort("a\(i)", k, sp[0], half: st.w0 / 2)) }
                if let k = st.end { ps.append(HabitatPort("b\(i)", k, sp[sp.count - 1], half: st.w1 / 2)) }
            }
            return ps
        }
    }

    /// The branch that came first: its base, its tip, and along it.
    static func branchPorts(_ r: CGRect, _ u: CGFloat) -> [HabitatPort] {
        let line = branchLine(r)
        let (base, tip) = branchWidths(r, u: u)
        // (It is drawn as two quadratic curves through the bend: close enough
        // to one through the middle of each side.)
        let pts = (0...16).map { k -> V2 in
            let t = CGFloat(k) / 16, m = 1 - t
            return line[0] * (m * m) + line[1] * (2 * m * t) + line[2] * (t * t)
        }
        let half = pts.indices.map { lerp(base, tip, CGFloat($0) / 16) / 2 }
        return [HabitatPort(name: "along0", kind: .along, pts: pts, half: half),
                HabitatPort("a0", .end, line[0], half: base / 2), HabitatPort("b0", .end, line[2], half: tip / 2)]
    }

    /// A hanging vine: its top, its tip, and along it.
    static func vinePorts(_ r: CGRect, _ u: CGFloat) -> [HabitatPort] {
        let st = vineStrands(r, u: u)
        let pts = (0...12).map { k -> V2 in
            let t = CGFloat(k) / 12, m = 1 - t
            func at(_ s: (from: CGPoint, c1: CGPoint, c2: CGPoint, to: CGPoint, width: CGFloat)) -> V2 {
                V2(s.from) * (m * m * m) + V2(s.c1) * (3 * m * m * t) + V2(s.c2) * (3 * m * t * t) + V2(s.to) * (t * t * t)
            }
            return (at(st[0]) + at(st[1])) * 0.5
        }
        return [HabitatPort(name: "along0", kind: .along, pts: pts, half: Array(repeating: 3 * u, count: pts.count)),
                HabitatPort("top", .hang, V2(r.midX, r.maxY), half: 3 * u), HabitatPort("tip", .hook, V2(r.midX, r.minY + 2 * u))]
    }

    // MARK: Laid out

    /// Leaves drawn along a piece (a twig's, a vine's): where each is, how
    /// long, which way it points.
    static func pieceLeaves(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat) -> [(at: V2, size: CGFloat, angle: CGFloat)] {
        switch kind {
        case .twig:
            let b = piece(kind, r, s, u, leaves: false)
            return b.sticks.enumerated().flatMap { i, st -> [(at: V2, size: CGFloat, angle: CGFloat)] in
                guard let tip = st.spine().last else { return [] }
                return [(tip, (10 + rnd(s, i) * 4) * u, 0.5 + rnd(s + 1, i)), (tip, (8 + rnd(s, i + 5) * 4) * u, 2.1 + rnd(s + 2, i) * 0.6)]
            }
        case .thickVine, .thinVine:
            let st = piece(kind, r, s, u, leaves: false).sticks[0]
            let sp = st.spine(step: 3)
            let gap = (kind == .thickVine ? 22 : 16) * u
            var out: [(at: V2, size: CGFloat, angle: CGFloat)] = []
            var next: CGFloat = gap * 0.5, run: CGFloat = 0
            for i in 1..<sp.count {
                run += sp[i].distance(to: sp[i - 1])
                guard run >= next else { continue }
                next += gap * (0.8 + rnd(s, i) * 0.4)
                let d = (sp[i] - sp[i - 1]).normalized
                let side: CGFloat = out.count % 2 == 0 ? 1 : -1
                let a = atan2(d.y, d.x) + side * (1.1 + rnd(s + 1, i) * 0.5) + (kind == .thickVine ? -0.3 : 0)
                out.append((sp[i], (kind == .thickVine ? 13 : 10) * u * (0.8 + rnd(s + 2, i) * 0.4), a))
            }
            return out
        case .driedStem:
            let st = piece(kind, r, s, u, leaves: false).sticks[0]
            return (0..<3).map { k in
                let f = 0.3 + CGFloat(k) * 0.2
                let side: CGFloat = k % 2 == 0 ? 1 : -1
                return (st.along("x").point(at: f), (16 + rnd(s, k) * 6) * u, .pi / 2 - side * (0.9 + rnd(s + 1, k) * 0.3))
            }
        default:
            return []
        }
    }

    /// How many rungs a ladder this tall has.
    static func rungs(_ r: CGRect, _ u: CGFloat) -> Int { max(2, Int((r.height - 16 * u) / (30 * u))) }

    static func piece(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat, leaves: Bool = true) -> PieceBuild {
        func P(_ x: CGFloat, _ y: CGFloat) -> V2 { V2(r.minX + r.width * x, r.minY + r.height * y) }
        /// A little give or take, so no two are the same.
        func j(_ k: Int, _ a: CGFloat = 0.03) -> CGFloat { (rnd(s, 60 + k) - 0.5) * 2 * a }
        func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [V2] {
            Poly.clockwise([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)])
        }
        func disc(_ c: V2, _ rad: CGFloat) -> [V2] {
            Poly.outlines(CGPath(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2), transform: nil)).first ?? []
        }
        func path(_ p: CGPath) -> [V2] { Poly.outlines(p).first ?? [] }
        var b = PieceBuild()
        switch kind {
        // Branches.
        case .thinBranch:
            b.sticks = [Stick([P(0.02, 0.35 + j(1)), P(0.3, 0.55 + j(2)), P(0.62, 0.5 + j(3)), P(0.98, 0.72 + j(4))], 5 * u, 2.4 * u),
                        Stick([P(0.55, 0.52), P(0.63, 0.75), P(0.72 + j(5), 0.95)], 2.6 * u, 1.4 * u, start: nil)]
        case .mediumBranch:
            b.sticks = [Stick([P(0.02, 0.25 + j(1)), P(0.35, 0.55 + j(2)), P(0.7, 0.62 + j(3)), P(0.98, 0.8)], 9 * u, 4 * u),
                        Stick([P(0.45, 0.58), P(0.5, 0.78), P(0.56 + j(4), 0.96)], 4 * u, 2 * u, start: nil)]
        case .thickBranch:
            b.sticks = [Stick([P(0.02, 0.3 + j(1)), P(0.4, 0.52 + j(2)), P(0.75, 0.5 + j(3)), P(0.98, 0.66)], 18 * u, 10 * u),
                        Stick([P(0.62, 0.52), P(0.7 + j(4), 0.9)], 8 * u, 5 * u, start: nil)]
        case .shortBranch:
            b.sticks = [Stick([P(0.03, 0.35 + j(1)), P(0.5, 0.6 + j(2)), P(0.97, 0.55 + j(3))], 8 * u, 4.5 * u)]
        case .longBranch:
            b.sticks = [Stick([P(0.01, 0.2 + j(1)), P(0.25, 0.45 + j(2)), P(0.55, 0.4 + j(3)), P(0.8, 0.62 + j(4)), P(0.99, 0.85)], 12 * u, 4 * u),
                        Stick([P(0.35, 0.44), P(0.38, 0.7), P(0.42 + j(5), 0.93)], 5 * u, 2.5 * u, start: nil)]
        case .forkedBranch:
            b.sticks = [Stick([P(0.02, 0.18 + j(1)), P(0.4, 0.42), P(0.98, 0.55 + j(2))], 11 * u, 4.5 * u),
                        Stick([P(0.42, 0.43), P(0.62, 0.72 + j(3)), P(0.8, 0.97)], 7 * u, 3.5 * u, start: nil)]
        case .yBranch:
            b.sticks = [Stick([P(0.5, 0.01), P(0.48 + j(1), 0.25), P(0.5, 0.48)], 14 * u, 11 * u, start: .foot, end: nil),
                        Stick([P(0.5, 0.46), P(0.34, 0.72 + j(2)), P(0.08, 0.98)], 10 * u, 5 * u, start: nil),
                        Stick([P(0.5, 0.46), P(0.66, 0.7 + j(3)), P(0.93, 0.95)], 10 * u, 5 * u, start: nil)]
        case .crookedBranch:
            b.sticks = [Stick([P(0.02, 0.3), P(0.22, 0.58 + j(1)), P(0.4, 0.34 + j(2)), P(0.62, 0.62 + j(3)), P(0.8, 0.46 + j(4)), P(0.98, 0.8)], 9 * u, 4 * u)]
        case .twig:
            b.sticks = [Stick([P(0.04, 0.3 + j(1)), P(0.5, 0.55), P(0.96, 0.62 + j(2))], 3.4 * u, 1.6 * u),
                        Stick([P(0.55, 0.57), P(0.7 + j(3), 0.92)], 1.8 * u, 1.1 * u, start: nil)]
        case .root:
            b.sticks = [Stick([P(0, 0.28), P(0.3, 0.45 + j(1)), P(0.62, 0.3 + j(2)), P(1, 0.38)], 16 * u, 4 * u),
                        Stick([P(0.3, 0.44), P(0.36, 0.2), P(0.42 + j(3), 0.02)], 5 * u, 1.5 * u, start: nil),
                        Stick([P(0.62, 0.32), P(0.72, 0.55), P(0.8 + j(4), 0.8)], 4.5 * u, 1.5 * u, start: nil),
                        Stick([P(0.14, 0.36), P(0.1, 0.6), P(0.06, 0.9)], 5 * u, 2 * u, start: nil)]
        case .climbingRoot:
            b.sticks = [Stick([P(0.5, 0), P(0.36 + j(1), 0.25), P(0.6 + j(2), 0.5), P(0.4 + j(3), 0.75), P(0.55, 1)], 16 * u, 6 * u, start: .foot),
                        Stick([P(0.39, 0.27), P(0.2, 0.36), P(0.04, 0.46)], 5 * u, 2 * u, start: nil),
                        Stick([P(0.58, 0.52), P(0.78, 0.6), P(0.96, 0.68)], 5 * u, 2 * u, start: nil),
                        Stick([P(0.42, 0.76), P(0.25, 0.84), P(0.1, 0.9)], 4 * u, 2 * u, start: nil)]
        case .driftwoodArch:
            b.sticks = [Stick([P(0.03, 0), P(0.18, 0.62 + j(1)), P(0.5, 0.93), P(0.82, 0.66 + j(2)), P(0.97, 0)], 18 * u, 14 * u, start: .foot, end: .foot)]
        case .driftwoodSnag:
            b.sticks = [Stick([P(0.45, 0), P(0.5, 0.4), P(0.42 + j(1), 0.75), P(0.5, 0.99)], 22 * u, 8 * u, start: .foot),
                        Stick([P(0.48, 0.45), P(0.25, 0.62 + j(2)), P(0.05, 0.66)], 10 * u, 4 * u, start: nil),
                        Stick([P(0.44, 0.72), P(0.7, 0.86 + j(3)), P(0.95, 0.95)], 9 * u, 4 * u, start: nil)]
        case .bambooPole:
            b.sticks = [Stick([P(0.5, 0), P(0.5, 1)], 18 * u, 16 * u, start: .foot)]
        case .bambooSegment:
            b.sticks = [Stick([P(0.03, 0.5), P(0.97, 0.5)], 16 * u, 16 * u)]
        case .driedStem:
            b.sticks = [Stick([P(0.5, 0), P(0.46, 0.5), P(0.54, 0.9)], 3.4 * u, 2.2 * u, start: .foot)]
            b.visual = [disc(P(0.54, 0.93), 9 * u)]
        // Vines.
        case .thickVine:
            b.sticks = [Stick([P(0, 0.9), P(0.3, 0.3 + j(1, 0.06)), P(0.7, 0.26 + j(2, 0.06)), P(1, 0.86)], 9 * u, 7 * u)]
        case .thinVine:
            b.sticks = [Stick([P(0.5, 1), P(0.4, 0.66), P(0.6, 0.33), P(0.5, 0.02)], 3.2 * u, 2.2 * u, start: .hang, end: .hook)]
        // Bark and platforms.
        case .corkSlab:
            let top = CGMutablePath()
            top.move(to: P(0.01, 0.3).point)
            top.addQuadCurve(to: P(0.99, 0.35).point, control: P(0.5, 1.35 + j(1, 0.08)).point)
            top.addQuadCurve(to: P(0.01, 0.3).point, control: P(0.5, 0.5).point)
            top.closeSubpath()
            b.blocks = [("slab", path(top))]
            b.ports = platformBase(r, bottom: { x in
                // The underside's curve, where it is across.
                let t = 1 - x, m = 1 - t
                return (0.35 * m * m + 0.5 * 2 * m * t + 0.3 * t * t)
            })
        case .corkTube:
            let tube = CGMutablePath()
            tube.move(to: P(0.08, 0).point)
            tube.addQuadCurve(to: P(0.05, 0.9).point, control: P(0.02 + j(1), 0.45).point)
            tube.addQuadCurve(to: P(0.95, 0.98).point, control: P(0.5, 1.02).point)
            tube.addQuadCurve(to: P(0.92, 0).point, control: P(0.98 + j(2), 0.5).point)
            tube.closeSubpath()
            b.blocks = [("tube", path(tube))]
            let mouth = CGRect(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.9 - r.width * 0.05, width: r.width * 0.72, height: r.width * 0.16)
            b.hollows = [Hollow(cavity: path(CGPath(roundedRect: CGRect(x: mouth.minX, y: r.minY + r.height * 0.12, width: mouth.width, height: mouth.maxY - r.minY - r.height * 0.12),
                                                         cornerWidth: mouth.width * 0.3, cornerHeight: mouth.width * 0.3, transform: nil)),
                                 mouth: V2(mouth.midX, mouth.midY), inward: V2(0, -1))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: V2(mouth.midX, mouth.maxY), normal: V2(0, 1))]
            b.ports = [HabitatPort("foot", .foot, P(0.5, 0), half: r.width * 0.45)]
        case .barkLedge:
            let ledge = CGMutablePath()
            ledge.move(to: P(0.03, 0.12).point)
            ledge.addLine(to: P(0.97, 0.12).point)
            ledge.addQuadCurve(to: P(0.98, 0.8).point, control: P(1.02, 0.4).point)
            ledge.addQuadCurve(to: P(0.5, 0.98 + j(1, 0.06)).point, control: P(0.75, 1.02).point)
            ledge.addQuadCurve(to: P(0.02, 0.84).point, control: P(0.25, 0.9).point)
            ledge.addQuadCurve(to: P(0.03, 0.12).point, control: P(-0.02, 0.4).point)
            ledge.closeSubpath()
            b.blocks = [("ledge", path(ledge))]
            b.ports = platformBase(r, bottom: { _ in 0.12 })
        case .slateLedge:
            b.blocks = [("slate", Poly.clockwise([P(0.02, 0.25), P(0.1, 0.03), P(0.55 + j(1), 0.0), P(0.9, 0.04), P(0.99, 0.28 + j(2, 0.1)),
                                                  P(0.97, 0.72), P(0.8, 0.96), P(0.4 + j(3), 1.0), P(0.07, 0.9), P(0.0, 0.62)]))]
            b.ports = platformBase(r, bottom: { x in x < 0.1 || x > 0.9 ? 0.1 : 0.02 })
        // Supports.
        case .brace:
            b.sticks = [Stick([P(0.5, 0.03), P(0.5, 0.92)], 4.4 * u, 4.4 * u, name: "rod", start: .foot, end: nil)]
            b.visual = [disc(P(0.5, 0.03), 6 * u), braceCup(P(0.5, 0.92), u)]
            b.ports = [HabitatPort("cup", .cradle, P(0.5, 0.92) + V2(0, 1.2 * u))]
        case .branchBracket:
            let cup = V2(r.midX, r.minY + r.height * 0.52)
            b.visual = [path(CGPath(roundedRect: CGRect(x: r.minX + r.width * 0.18, y: r.minY, width: r.width * 0.64, height: r.height * 0.26),
                                    cornerWidth: 3 * u, cornerHeight: 3 * u, transform: nil)),
                        rect(0.4, 0.2, 0.6, 0.52), bracketCup(cup, r.width * 0.46, u)]
            b.ports = [HabitatPort("cradle", .cradle, cup)]
        case .wallAnchor:
            b.visual = [disc(P(0.5, 0.5), min(r.width, r.height) * 0.46)]
            b.ports = [HabitatPort("socket", .socket, P(0.5, 0.5))]
        case .glassMount:
            b.visual = [path(CGPath(roundedRect: CGRect(x: r.minX, y: r.minY + r.height * 0.74, width: r.width, height: r.height * 0.18),
                                    cornerWidth: 2 * u, cornerHeight: 2 * u, transform: nil)),
                        disc(P(0.5, 0.42), r.height * 0.34)]
            b.ports = [HabitatPort("ledge", .cradle, P(0.5, 0.92))]
        case .suctionCup:
            let clip = P(0.5, 0.16)
            b.visual = [disc(P(0.5, 0.64), r.width * 0.46), bracketCup(clip, r.width * 0.5, u * 0.8)]
            b.ports = [HabitatPort("clip", .cradle, clip), HabitatPort("hook", .hook, clip)]
        case .verticalSupport:
            b.sticks = [Stick([P(0.5, 0), P(0.5, 0.99)], 7 * u, 7 * u, name: "rod", start: .foot, end: nil)]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 1), half: 3.5 * u)]
        case .horizontalSupport:
            b.sticks = [Stick([P(0.02, 0.5), P(0.98, 0.5)], 6.5 * u, 6.5 * u, name: "rod")]
        case .crossBrace:
            b.sticks = [Stick([P(0.05, 0.05), P(0.95, 0.95)], 5 * u, 5 * u, name: "rod"), Stick([P(0.05, 0.95), P(0.95, 0.05)], 5 * u, 5 * u, name: "rod")]
            b.visual = [disc(P(0.5, 0.5), 5 * u)]
        case .hangingHook:
            b.sticks = [Stick([P(0.5, 1), P(0.5, 0.14)], 2.2 * u, 2.2 * u, name: "cord", start: .hang, end: nil)]
            b.visual = [hookShape(P(0.5, 0.14), r.height * 0.12, u)]
            b.ports = [HabitatPort("hook", .hook, P(0.5, 0.03))]
        case .vineClip:
            b.visual = [disc(P(0.5, 0.62), r.width * 0.42), rect(0.42, 0.06, 0.58, 0.5)]
            b.ports = [HabitatPort("clip", .hang, P(0.5, 0.62), half: r.width * 0.2), HabitatPort("hook", .hook, P(0.5, 0.06))]
        case .shelfBracket:
            b.visual = [rect(0, 0.86, 1, 1), rect(0.42, 0, 0.58, 0.9),
                        Poly.clockwise([P(0.08, 0.86), P(0.2, 0.86), P(0.46, 0.25), P(0.42, 0.18)]),
                        Poly.clockwise([P(0.92, 0.86), P(0.8, 0.86), P(0.54, 0.25), P(0.58, 0.18)])]
            b.ports = [HabitatPort("shelf", .cradle, P(0.5, 1))]
        case .wallRail:
            b.bars = [("rail", rect(0, 0.12, 1, 0.88))]
            b.ports = [HabitatPort(name: "along0", kind: .along, pts: [P(0.01, 0.5), P(0.99, 0.5)], half: [r.height * 0.38, r.height * 0.38])]
        case .metalStrut:
            b.bars = [("strut", rect(0.12, 0, 0.88, 1))]
            b.ports = [HabitatPort(name: "along0", kind: .along, pts: [P(0.5, 0.01), P(0.5, 0.99)], half: [r.width * 0.38, r.width * 0.38]),
                       HabitatPort("top", .cradle, P(0.5, 1))]
        case .angleBracket:
            b.visual = [rect(0, 0.84, 1, 1), rect(0.4, 0, 0.56, 0.9), Poly.clockwise([P(0.56, 0.3), P(0.56, 0.84), P(0.9, 0.84)])]
            b.ports = [HabitatPort("shelf", .cradle, P(0.5, 1))]
        // Built.
        case .beam, .plank, .plywood:
            b.blocks = [("board", rect(0, 0, 1, 1))]
            b.ports = boardPorts(r)
        case .post:
            b.bars = [("post", rect(0, 0, 1, 1))]
            b.ports = [HabitatPort("foot", .foot, P(0.5, 0), half: r.width / 2), HabitatPort("top", .cradle, P(0.5, 1), half: r.width / 2),
                       HabitatPort(name: "along0", kind: .along, pts: [P(0.5, 0.04), P(0.5, 0.96)], half: [r.width / 2, r.width / 2])]
        case .dowel:
            b.sticks = [Stick([P(0.01, 0.5), P(0.99, 0.5)], 7 * u, 7 * u, name: "rod")]
        case .pipe:
            b.sticks = [Stick([P(0.02, 0.5), P(0.98, 0.5)], r.height * 0.9, r.height * 0.9, name: "pipe")]
        case .ladder:
            b.sticks = [Stick([P(0.12, 0), P(0.12, 1)], 5 * u, 5 * u, name: "rail", start: .foot),
                        Stick([P(0.88, 0), P(0.88, 1)], 5 * u, 5 * u, name: "rail", start: .foot)]
            let n = rungs(r, u)
            for k in 0..<n {
                let y = (12 * u + (r.height - 24 * u) * CGFloat(k) / CGFloat(max(n - 1, 1))) / r.height
                b.sticks.append(Stick([P(0.08, y), P(0.92, y)], 4 * u, 4 * u, name: "rung", start: nil, end: nil))
            }
        case .brick:
            b.blocks = [("brick", rect(0, 0, 1, 1))]
        case .woodBlock:
            b.blocks = [("block", rect(0, 0, 1, 1))]
        case .crate:
            b.blocks = [("crate", rect(0, 0, 1, 1))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 1))]
        case .rope:
            b.sticks = [Stick([P(0.5, 1), P(0.44 + j(1), 0.5), P(0.52, 0.02)], 7 * u, 6 * u, name: "rope", start: .hang, end: .hook)]
        case .backPanel, .pegboard, .woodBacking, .brickBacking, .stoneBacking, .logBacking, .wallpaper, .backWindow, .rug, .picture,
             .painting, .poster, .mirror, .curtains, .sconce:
            b.visual = [rect(0, 0, 1, 1)]
        case .clock, .dartboard:
            b.visual = [disc(P(0.5, 0.5), min(r.width, r.height) * 0.48)]
        // More furniture.
        case .armchair:
            b.blocks = [("seat", rect(0.04, 0.08, 0.96, 0.48)), ("back", rect(0.1, 0.4, 0.9, 1)),
                        ("arm", rect(0, 0.08, 0.16, 0.66)), ("arm", rect(0.84, 0.08, 1, 0.66))]
        case .desk:
            b.blocks = [("top", rect(0, 0.86, 1, 1)), ("drawers", rect(0.62, 0, 0.98, 0.88))]
            b.bars = [("leg", rect(0.04, 0, 0.11, 0.88))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 1))]
        case .dresser, .wardrobe, .fridge, .stove, .counter, .chest, .radio, .recordPlayer:
            // (A stove's pot, a counter's tap, a radio's handle stand up off its top.)
            let top: CGFloat = [.stove, .counter, .radio].contains(kind) ? 0.82 : 1
            b.blocks = [("body", rect(0, kind == .dresser || kind == .wardrobe ? 0.04 : 0, 1, top))]
            if kind == .chest { b.blocks[0].outline = path(chestPath(r)) }
            if top < 1 { b.visual = [rect(0.3, top, 0.7, 1)] }
            b.ports = [HabitatPort("top", .cradle, P(0.5, top))]
        case .bunkBed:
            b.bars = [("post", rect(0, 0, 0.07, 1)), ("post", rect(0.93, 0, 1, 1))]
            b.blocks = [("bunk", rect(0.02, 0.08, 0.98, 0.28)), ("bunk", rect(0.02, 0.62, 0.98, 0.82))]
            b.visual = [rect(0.05, 0.28, 0.35, 0.38), rect(0.05, 0.82, 0.35, 0.92)]
        case .piano:
            b.blocks = [("case", rect(0.02, 0.1, 0.72, 1)), ("keys", rect(0, 0.46, 1, 0.58))]
            b.bars = [("leg", rect(0.88, 0, 0.95, 0.5))]
            b.ports = [HabitatPort("top", .cradle, P(0.36, 1))]
        case .bathtub:
            // A bowl: it can walk down inside it.
            let t = 6 * u
            let pts: [V2] = [P(0.02, 1), P(0.06, 0.3), P(0.2, 0.12), P(0.8, 0.12), P(0.94, 0.3), P(0.98, 1),
                             P(0.98, 1) - V2(t, 0), P(0.94, 0.34) - V2(t, -t * 0.4), P(0.8, 0.12) + V2(-t * 0.2, t), P(0.2, 0.12) + V2(t * 0.2, t),
                             P(0.06, 0.34) + V2(t, t * 0.4), P(0.02, 1) + V2(t, 0)]
            b.blocks = [("tub", Poly.clockwise(pts))]
            b.bars = [("foot", rect(0.14, 0, 0.22, 0.16)), ("foot", rect(0.78, 0, 0.86, 0.16))]
        case .coatRack:
            b.bars = [("pole", rect(0.44, 0.04, 0.56, 1)), ("hook", bar(P(0.5, 0.86), P(0.08, 0.96), 3 * u)), ("hook", bar(P(0.5, 0.86), P(0.92, 0.96), 3 * u))]
            b.blocks = [("foot", Poly.clockwise([P(0.1, 0), P(0.9, 0), P(0.56, 0.08), P(0.44, 0.08)]))]
            b.visual = [rect(0.62, 0.36, 0.98, 0.86)]
        case .beanbag:
            b.blocks = [("bag", path(CGPath(ellipseIn: CGRect(x: r.minX, y: r.minY - r.height * 0.2, width: r.width, height: r.height * 1.2), transform: nil)))]
        // Decor.
        case .tv:
            b.blocks = [("set", rect(0.04, 0, 0.96, 0.78))]
            b.sticks = [Stick([P(0.5, 0.76), P(0.28, 1)], 1.6 * u, 1.4 * u, name: "aerial", start: nil, end: nil),
                        Stick([P(0.5, 0.76), P(0.72, 1)], 1.6 * u, 1.4 * u, name: "aerial", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [HabitatPort("top", .cradle, P(0.5, 0.78))]
        case .laptop:
            b.blocks = [("base", rect(0, 0, 1, 0.1))]
            b.bars = [("lid", bar(P(0.14, 0.06), P(0.3, 1), 3 * u))]
        case .globe:
            b.blocks = [("foot", rect(0.2, 0, 0.8, 0.08)), ("globe", disc(P(0.5, 0.62), r.width * 0.42))]
            b.bars = [("stand", rect(0.45, 0.06, 0.55, 0.3))]
        case .vase:
            b.blocks = [("vase", path(vasePath(r)))]
            b.visual = [disc(P(0.5, 0.78), r.width * 0.5)]
        case .bookStack:
            b.blocks = [("books", rect(0.04, 0, 0.96, 1))]
        case .flyJar:
            b.blocks = [("jar", path(CGPath(roundedRect: CGRect(x: r.minX + r.width * 0.06, y: r.minY, width: r.width * 0.88, height: r.height * 0.84),
                                            cornerWidth: 6 * u, cornerHeight: 6 * u, transform: nil))), ("lid", rect(0.14, 0.82, 0.86, 1))]
        case .trophy:
            b.blocks = [("foot", rect(0.2, 0, 0.8, 0.14)), ("cup", Poly.clockwise([P(0.1, 1), P(0.9, 1), P(0.68, 0.46), P(0.32, 0.46)]))]
            b.bars = [("stem", rect(0.44, 0.12, 0.56, 0.5))]
        case .wallShelf:
            b.blocks = [("shelf", rect(0, 0.62, 1, 1))]
            b.visual = [Poly.clockwise([P(0.12, 0.64), P(0.22, 0.64), P(0.14, 0)]), Poly.clockwise([P(0.88, 0.64), P(0.78, 0.64), P(0.86, 0)])]
            b.ports = platformBase(r, bottom: { _ in 0.62 }) + [HabitatPort("top", .cradle, P(0.5, 1))]
        case .chandelier:
            let ringY = min(0.34, 40 * u / r.height)
            b.sticks = [Stick([P(0.5, 1), P(0.5, ringY)], 2 * u, 2 * u, name: "chain", start: .hang, end: nil)]
            b.bars = [("hoop", rect(0.02, ringY - 3 * u / r.height, 0.98, ringY + 3 * u / r.height))]
            b.visual = (0..<5).map { k in rect(0.06 + CGFloat(k) * 0.2, ringY, 0.14 + CGFloat(k) * 0.2, ringY + 20 * u / r.height) }
        // Building.
        case .floorboards:
            b.blocks = [("floor", rect(0, 0, 1, 1))]
            b.ports = boardPorts(r)
        case .wall:
            b.blocks = [("wall", rect(0, 0, 1, 1))]
            b.ports = uprightPorts(r, V2(r.midX, r.minY), V2(r.midX, r.maxY), half: r.width / 2)
        case .door, .doorClosed, .window, .windowOpen:
            // A length of wall with an opening in it — for a door, from the
            // floor up; for a window, part way up — and what fills it when shut.
            let door = kind == .door || kind == .doorClosed
            let x0 = door ? 0.35 : 0.3, x1 = door ? 0.65 : 0.7
            let (lo, hi) = HabitatShape.opening(kind, r, u)
            if lo > r.minY { b.blocks.append(("sill", Poly.clockwise([V2(r.minX + r.width * x0, r.minY), V2(r.minX + r.width * x1, r.minY),
                                                                      V2(r.minX + r.width * x1, lo), V2(r.minX + r.width * x0, lo)]))) }
            b.blocks.append(("lintel", Poly.clockwise([V2(r.minX + r.width * x0, hi), V2(r.minX + r.width * x1, hi),
                                                       V2(r.minX + r.width * x1, r.maxY), V2(r.minX + r.width * x0, r.maxY)])))
            let leaf = HabitatShape.leaf(kind, r, u)
            if kind == .doorClosed || kind == .window {
                // Shut: the door (a little thinner than the wall), or the glass.
                let e = leaf.edge
                b.blocks.append((door ? "door" : "glass", Poly.clockwise([V2(e.minX, e.minY), V2(e.maxX, e.minY), V2(e.maxX, e.maxY), V2(e.minX, e.maxY)])))
            } else {
                // The door (or the casement) swung open, out beside it: to look at.
                let f = leaf.face
                b.visual.append(Poly.clockwise([V2(f.minX, f.minY), V2(f.maxX, f.minY + f.height * 0.08), V2(f.maxX, f.maxY - f.height * 0.08), V2(f.minX, f.maxY)]))
            }
            b.ports = uprightPorts(r, V2(r.midX, r.minY), V2(r.midX, r.maxY), half: r.width * (x1 - x0) / 2)
            // (Nothing fastens along the opening.)
            b.ports = b.ports.filter { $0.kind != .along }
                + [HabitatPort(name: "along0", kind: .along, pts: [V2(r.midX, hi + 2), V2(r.midX, r.maxY - 2)], half: [r.width * (x1 - x0) / 2, r.width * (x1 - x0) / 2])]
        case .gableRoof:
            // Two slopes up to a ridge: under them, room for an attic.
            let t = min(0.14, 18 * u / r.width), rise = min(0.3, 20 * u / r.height)
            b.blocks = [("roof", Poly.clockwise([P(0, 0), P(0.5, 1), P(1, 0), P(1 - t, 0), P(0.5, 1 - rise), P(t, 0)]))]
            b.ports = [HabitatPort("baseL", .base, P(t * 0.5, 0)), HabitatPort("baseR", .base, P(1 - t * 0.5, 0)),
                       HabitatPort(name: "along0", kind: .along, pts: [P(0.08, 0.16), P(0.5, 1)], half: [4 * u, 4 * u]),
                       HabitatPort(name: "along1", kind: .along, pts: [P(0.5, 1), P(0.92, 0.16)], half: [4 * u, 4 * u])]
        case .stairs:
            let n = 5
            var pts = [P(0, 0), P(1, 0), P(1, 1)]
            for k in 1...n {
                let x = 1 - CGFloat(k) / CGFloat(n)
                pts.append(P(x, 1 - CGFloat(k - 1) / CGFloat(n)))
                if k < n { pts.append(P(x, 1 - CGFloat(k) / CGFloat(n))) }
            }
            b.blocks = [("steps", Poly.clockwise(pts))]
        case .kneeBrace:
            b.bars = [("brace", bar(P(0.06, 0.06), P(0.94, 0.94), 8 * u))]
            b.ports = [HabitatPort("a0", .end, P(0.08, 0.08), half: 4 * u), HabitatPort("b0", .end, P(0.92, 0.92), half: 4 * u)]
        case .fence:
            let n = max(2, Int((r.width - 6 * u) / (22 * u)) + 1)
            for k in 0..<n {
                let x = 3 * u + (r.width - 6 * u) * CGFloat(k) / CGFloat(n - 1) - r.width * 0
                let fx = x / r.width
                let pw = 4.5 * u / r.width
                b.bars.append(("picket", Poly.clockwise([P(fx - pw, 0), P(fx + pw, 0), P(fx + pw, 0.85), P(fx, 1), P(fx - pw, 0.85)])))
            }
            b.bars.append(("rail", rect(0, 0.3, 1, 0.3 + 5 * u / r.height)))
            b.bars.append(("rail", rect(0, 0.66, 1, 0.66 + 5 * u / r.height)))
        // Home.
        case .bed:
            b.blocks = [("box", rect(0, 0, 1, 0.78))]
            b.visual = [rect(0.62, 0.7, 0.96, 1)]
        case .table:
            b.blocks = [("top", rect(0, 0.84, 1, 1))]
            b.bars = [("leg", rect(0.08, 0, 0.16, 0.86)), ("leg", rect(0.84, 0, 0.92, 0.86))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 1))]
        case .chair:
            b.blocks = [("seat", rect(0.04, 0.44, 0.96, 0.54))]
            b.bars = [("back", rect(0.8, 0.5, 0.94, 1)), ("leg", rect(0.08, 0, 0.18, 0.46)), ("leg", rect(0.8, 0, 0.9, 0.46))]
        case .bookshelf:
            b.bars = [("side", rect(0, 0, 0.07, 1)), ("side", rect(0.93, 0, 1, 1)),
                      ("shelf", rect(0, 0, 1, 0.05)), ("shelf", rect(0, 0.47, 1, 0.52)), ("shelf", rect(0, 0.95, 1, 1))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 1))]
        case .sofa:
            b.blocks = [("seat", rect(0.02, 0.1, 0.98, 0.5)), ("back", rect(0.06, 0.45, 0.94, 0.94)),
                        ("arm", rect(0, 0.1, 0.13, 0.7)), ("arm", rect(0.87, 0.1, 1, 0.7))]
        case .fireplace:
            b.blocks = [("side", rect(0.04, 0, 0.2, 0.86)), ("side", rect(0.8, 0, 0.96, 0.86)),
                        ("breast", rect(0.04, 0.62, 0.96, 0.86)), ("mantel", rect(0, 0.86, 1, 0.97))]
            b.ports = [HabitatPort("mantel", .cradle, P(0.5, 0.97))]
        case .floorLamp:
            b.blocks = [("foot", rect(0.2, 0, 0.8, 0.06)),
                        ("shade", Poly.clockwise([P(0.02, 0.72), P(0.98, 0.72), P(0.72, 1), P(0.28, 1)]))]
            b.bars = [("pole", rect(0.45, 0.03, 0.55, 0.74))]
        case .hangingLamp:
            let shadeH = min(0.4, 38 * u / r.height)
            b.sticks = [Stick([P(0.5, 1), P(0.5, shadeH - 0.02)], 2 * u, 2 * u, name: "cord", start: .hang, end: nil)]
            b.blocks = [("shade", Poly.clockwise([P(0.02, 0), P(0.98, 0), P(0.68, shadeH), P(0.32, shadeH)]))]
        case .lantern:
            let bodyH = min(0.45, 44 * u / r.height)
            b.sticks = [Stick([P(0.5, 1), P(0.5, bodyH)], 2 * u, 2 * u, name: "cord", start: .hang, end: nil)]
            b.blocks = [("lantern", path(CGPath(roundedRect: CGRect(x: r.minX + r.width * 0.12, y: r.minY, width: r.width * 0.76, height: r.height * bodyH),
                                                cornerWidth: 4 * u, cornerHeight: 4 * u, transform: nil)))]
        case .candle:
            b.blocks = [("dish", rect(0, 0, 1, 0.12)), ("candle", rect(0.28, 0.1, 0.72, 0.78))]
            b.visual = [disc(P(0.5, 0.9), r.width * 0.18)]
        case .stringLights:
            b.sticks = [Stick([P(0, 0.92), P(0.3, 0.3 + j(1, 0.05)), P(0.7, 0.28 + j(2, 0.05)), P(1, 0.92)], 1.8 * u, 1.8 * u, name: "wire")]
        case .houseplant:
            b.blocks = [("pot", Poly.clockwise([P(0.24, 0), P(0.76, 0), P(0.82, 0.38), P(0.18, 0.38)]))]
            b.visual = [disc(P(0.5, 0.66), r.width * 0.46)]
        case .spool:
            b.blocks = [("flange", rect(0, 0, 1, 0.14)), ("thread", rect(0.14, 0.12, 0.86, 0.88)), ("flange", rect(0, 0.86, 1, 1))]
        case .teacup:
            b.blocks = [("saucer", Poly.clockwise([P(0, 0.06), P(0.1, 0), P(0.9, 0), P(1, 0.06), P(1, 0.14), P(0, 0.14)])),
                        ("cup", Poly.clockwise([P(0.22, 0.12), P(0.7, 0.12), P(0.8, 0.98), P(0.12, 0.98)]))]
            b.visual = [disc(P(0.86, 0.6), r.height * 0.2)]
        case .flowerBox:
            b.blocks = [("box", rect(0, 0, 1, 0.55))]
            b.visual = [rect(0.04, 0.5, 0.96, 1)]
            b.ports = platformBase(r, bottom: { _ in 0 })
        case .sign:
            b.sticks = [Stick([P(0.5, 1), P(0.14, 0.56)], 1.6 * u, 1.6 * u, name: "cord", start: .hang, end: nil),
                        Stick([P(0.5, 1), P(0.86, 0.56)], 1.6 * u, 1.6 * u, name: "cord", start: nil, end: nil)]
            b.blocks = [("board", rect(0, 0, 1, 0.58))]
        case .stake:
            // A straight stick up to a fork (the same size however tall it is).
            let fork = V2(r.midX, r.maxY - min(24 * u, r.height * 0.3))
            b.sticks = [Stick([P(0.5, 0), V2(r.midX + j(1) * r.width, r.minY + (fork.y - r.minY) * 0.5), fork], 9 * u, 7 * u, start: .foot, end: nil),
                        Stick([fork - V2(0, 2 * u), fork + V2(-8 * u, (r.maxY - fork.y) * 0.6), V2(r.midX - 13 * u, r.maxY)], 5 * u, 3.5 * u, start: nil),
                        Stick([fork - V2(0, 2 * u), fork + V2(8 * u, (r.maxY - fork.y) * 0.6), V2(r.midX + 13 * u, r.maxY)], 5 * u, 3.5 * u, start: nil)]
            b.ports = [HabitatPort("fork", .cradle, fork)]
            b.stickPorts = false
            b.ports.append(HabitatPort("a0", .foot, P(0.5, 0), half: 4.5 * u))
        default:
            break
        }
        // Leaves: to look at.
        if leaves {
            for leaf in pieceLeaves(kind, r, s, u) {
                b.visual.append(disc(leaf.at + V2(cos(leaf.angle), sin(leaf.angle)) * leaf.size * 0.5, leaf.size * 0.36))
            }
        }
        // Perches on top of what is flat to sit on.
        if [.corkSlab, .barkLedge, .slateLedge, .beam, .plank, .plywood, .crate, .brick, .woodBlock, .floorboards, .bed, .table, .sofa, .fireplace].contains(kind) {
            b.anchors.append(ObjectAnchor(kind: .perch, point: V2(r.midX, r.maxY), normal: V2(0, 1)))
        }
        return b
    }

    /// Where a platform rests on what holds it: under its middle and near
    /// each end. `bottom` is how high its underside is (0…1) at x (0…1).
    private static func platformBase(_ r: CGRect, bottom: (CGFloat) -> CGFloat) -> [HabitatPort] {
        [("baseL", CGFloat(0.22)), ("base", 0.5), ("baseR", 0.78)].map { name, x in
            HabitatPort(name, .base, V2(r.minX + r.width * x, r.minY + r.height * bottom(x)))
        }
    }

    /// Something upright (a wall): its foot, its top, and along it.
    private static func uprightPorts(_ r: CGRect, _ foot: V2, _ top: V2, half: CGFloat) -> [HabitatPort] {
        [HabitatPort("foot", .foot, foot, half: half), HabitatPort("top", .cradle, top, half: half),
         HabitatPort(name: "along0", kind: .along, pts: [foot + V2(0, 2), top - V2(0, 2)], half: [half, half])]
    }

    /// A straight bar from `a` to `b`, `w` thick, square at the ends.
    static func bar(_ a: V2, _ b: V2, _ w: CGFloat) -> [V2] {
        let d = (b - a).normalized, n = V2(-d.y, d.x) * (w / 2)
        return Poly.clockwise([a + n, b + n, b - n, a - n])
    }

    /// A treasure chest: a box with a domed lid.
    static func chestPath(_ r: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.62))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.62), control: CGPoint(x: r.midX, y: r.maxY + r.height * 0.36))
        p.closeSubpath()
        return p
    }

    /// A round-bellied vase with a narrow neck.
    static func vasePath(_ r: CGRect) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.3, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - r.width * 0.34, y: r.minY + r.height * 0.52), control: CGPoint(x: r.maxX + r.width * 0.1, y: r.minY + r.height * 0.2))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.26, y: r.minY + r.height * 0.6))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.26, y: r.minY + r.height * 0.6))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.34, y: r.minY + r.height * 0.52))
        p.addQuadCurve(to: CGPoint(x: r.minX + r.width * 0.3, y: r.minY), control: CGPoint(x: r.minX - r.width * 0.1, y: r.minY + r.height * 0.2))
        p.closeSubpath()
        return p
    }

    /// A door's (or a window's casement's) leaf, for a door or window
    /// standing in `r` (unflipped): the line it hinges on, its face swung
    /// right open (out to the side, from the hinge), and its edge, shut, in
    /// the opening — a door a little thinner than the wall round it.
    static func leaf(_ kind: HabitatItemKind, _ r: CGRect, _ u: CGFloat) -> (hinge: CGFloat, face: CGRect, edge: CGRect) {
        let door = kind == .door || kind == .doorClosed
        let wall = r.width * (door ? 0.3 : 0.4)
        let (lo, hi) = opening(kind, r, u)
        let thick = wall * (door ? 0.55 : 0.36)
        return (r.midX, CGRect(x: r.midX, y: lo, width: r.maxX - r.midX, height: hi - lo),
                CGRect(x: r.midX - thick / 2, y: lo, width: thick, height: hi - lo))
    }

    /// The opening in a door or a window's wall: its bottom and its top.
    static func opening(_ kind: HabitatItemKind, _ r: CGRect, _ u: CGFloat) -> (CGFloat, CGFloat) {
        if kind == .door || kind == .doorClosed { return (r.minY, r.minY + min(96 * u, r.height * 0.78)) }
        let h = min(60 * u, r.height * 0.5)
        let lo = r.minY + max(r.height * 0.42 - h / 2, r.height * 0.2)
        return (lo, lo + h)
    }

    /// A length of sawn timber or board: its ends, along its middle, and
    /// its underside.
    private static func boardPorts(_ r: CGRect) -> [HabitatPort] {
        let half = r.height / 2
        return [HabitatPort(name: "along0", kind: .along, pts: [V2(r.minX + 2, r.midY), V2(r.maxX - 2, r.midY)], half: [half, half]),
                HabitatPort("a0", .end, V2(r.minX + half * 0.5, r.midY), half: half), HabitatPort("b0", .end, V2(r.maxX - half * 0.5, r.midY), half: half)]
            + platformBase(r, bottom: { _ in 0 })
    }

    /// The U of a bracket, its inside bottom at `c`, `w` across.
    static func bracketCup(_ c: V2, _ w: CGFloat, _ u: CGFloat) -> [V2] {
        let t = 2.6 * u, h = w * 0.62
        return Poly.clockwise([c + V2(-w / 2, h), c + V2(-w / 2, -t * 0.6), c + V2(-w * 0.3, -t), c + V2(w * 0.3, -t), c + V2(w / 2, -t * 0.6),
                               c + V2(w / 2, h), c + V2(w / 2 - t, h), c + V2(w / 2 - t, 0), c + V2(-w / 2 + t, 0), c + V2(-w / 2 + t, h)])
    }

    /// The cup at the top of a brace.
    static func braceCup(_ c: V2, _ u: CGFloat) -> [V2] { bracketCup(c, 16 * u, u) }

    /// An S of a hook, hanging from `top`, `h` long.
    static func hookShape(_ top: V2, _ h: CGFloat, _ u: CGFloat) -> [V2] {
        let w = max(h * 0.45, 5 * u)
        return Poly.clockwise([top + V2(-1.4 * u, 0), top + V2(1.4 * u, 0), top + V2(1.4 * u, -h * 0.55), top + V2(w * 0.5, -h * 0.85),
                               top + V2(w * 0.5, -h * 0.4), top + V2(w * 0.5 + 2.4 * u, -h * 0.4), top + V2(w * 0.5 + 2.4 * u, -h * 0.95),
                               top + V2(0, -h * 1.05), top + V2(-1.4 * u, -h * 0.6)])
    }
}

extension HabitatItemKind {
    /// A board or wall at the back: it doesn't hold up what is in front of
    /// it, but brackets and pictures fastened on it are screwed into it.
    var isBacking: Bool { [.backPanel, .pegboard, .woodBacking, .brickBacking, .stoneBacking, .logBacking, .wallpaper].contains(self) }

    /// A door or a window: whether it is open (nil: neither).
    var leafOpen: Bool? {
        switch self {
        case .door, .windowOpen: return true
        case .doorClosed, .window: return false
        default: return nil
        }
    }

    /// What it becomes opened or shut (a door, a window), if it does.
    var toggled: HabitatItemKind? {
        switch self {
        case .door: return .doorClosed
        case .doorClosed: return .door
        case .window: return .windowOpen
        case .windowOpen: return .window
        default: return nil
        }
    }
}
