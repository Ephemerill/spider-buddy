import AppKit

// MARK: - The natural world, laid out
//
// The branches, roots, shelters, plants and small natural things of the
// tank, each laid out in its rectangle the way the pieces are
// (HabitatPieces.swift): the sticks and solid blocks it is made of, the
// leaf blades it has (slender parts too — the spider walks round the edge
// of a leaf, and along a frond), what is only there to look at, where
// things fasten to it, and — for what later behaviour will want — its
// hollows and the spots that are for something (a way in, a warm top, the
// edge of water). Its picture (HabitatNatureArt.swift) is painted from
// exactly this, so what it walks on is what is drawn.
//
// Shelters are made so that the room in them is really there: a roof over
// a floor it can get to, with a way in at least as tall as the spider (the
// way into a hollow must stay open — shut all round, the room inside is a
// place of its own, cut off). Most of their shells are bulk, so the ground
// runs on up over them and round in through the mouth; the legs of an arch,
// and a root it creeps under, are limbs, which it passes.

extension HabitatShape {
    /// A kind of the natural world, laid out (nil: not one of them).
    static func nature(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat) -> PieceBuild? {
        let k = NatureKit(r: r, s: s, u: u)
        func P(_ x: CGFloat, _ y: CGFloat) -> V2 { k.P(x, y) }
        func j(_ i: Int, _ a: CGFloat = 0.03) -> CGFloat { k.j(i, a) }
        var b = PieceBuild()
        switch kind {
        // MARK: Structures
        case .twistedBranch:
            // Two limbs winding round a middle line, crossing at the ends and
            // twice between.
            let n = 16
            let amp = min(r.height * 0.16, 18 * u)
            let mid = (0...n).map { i -> V2 in
                let t = CGFloat(i) / CGFloat(n)
                return P(0.02 + 0.96 * t, 0.46 + 0.14 * sin(t * .pi * 1.3 + j(1, 0.5)))
            }
            func strand(_ sign: CGFloat) -> [V2] {
                mid.indices.map { i in
                    let t = CGFloat(i) / CGFloat(n)
                    let d = (mid[min(i + 1, n)] - mid[max(i - 1, 0)]).normalized
                    return mid[i] + d.perp * (sign * amp * sin(t * 3 * .pi))
                }
            }
            b.sticks = [Stick(strand(1), 10 * u, 5 * u, name: "strand"), Stick(strand(-1), 9 * u, 4.5 * u, name: "strand")]
            b.stickPorts = false
            b.ports = [Stick(mid, 14 * u, 8 * u).along("along0"),
                       HabitatPort("a0", .end, mid[0], half: 7 * u), HabitatPort("b0", .end, mid[n], half: 4 * u)]
        case .threeFork:
            let fork = P(0.5, 0.44)
            b.sticks = [Stick([P(0.5, 0), P(0.47 + j(1), 0.22), fork], 16 * u, 12 * u, name: "trunk", start: .foot, end: nil),
                        Stick([fork, P(0.32, 0.64 + j(2)), P(0.12 + j(3), 0.98)], 11 * u, 4.5 * u, start: nil),
                        Stick([fork, P(0.53, 0.7), P(0.5 + j(4), 0.99)], 10 * u, 4 * u, start: nil),
                        Stick([fork, P(0.68, 0.62 + j(5)), P(0.9, 0.94)], 11 * u, 4.5 * u, start: nil)]
            b.stickPorts = false
            b.ports = [HabitatPort("a0", .foot, P(0.5, 0), half: 8 * u),
                       HabitatPort("crotchL", .cradle, P(0.42, 0.6)), HabitatPort("crotchR", .cradle, P(0.6, 0.6))]
                + b.sticks.dropFirst().enumerated().map { $0.element.along("along\($0.offset + 1)") }
        case .exposedRoot:
            // Up out of the soil and back into it: room to creep under.
            b.sticks = [Stick([P(-0.02, -0.14), P(0.12, 0.42 + j(1)), P(0.38, 0.84 + j(2)), P(0.66, 0.7 + j(3)), P(0.88, 0.32), P(1.02, -0.14)],
                              18 * u, 11 * u, name: "root", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [b.sticks[0].along("along0")]
        case .rootTangle:
            b.sticks = [Stick([P(0, -0.12), P(0.1, 0.55 + j(1)), P(0.32, 0.78), P(0.55, 0.45 + j(2)), P(0.62, -0.12)], 16 * u, 10 * u, name: "root", start: nil, end: nil),
                        Stick([P(0.22, -0.12), P(0.35, 0.6), P(0.6, 0.95 + j(3)), P(0.82, 0.62), P(0.9, -0.12)], 14 * u, 9 * u, name: "root", start: nil, end: nil),
                        Stick([P(0.55, -0.12), P(0.72, 0.42 + j(4)), P(0.9, 0.5), P(1.0, -0.12)], 12 * u, 8 * u, name: "root", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [b.sticks[1].along("along0")]
        case .stump:
            b.blocks = [("stump", k.path(k.stumpPath()))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 0.9), half: r.width * 0.3)]
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 0.92), normal: V2(0, 1))]
        case .driftwoodRoot:
            let c0 = P(0.29, 0.24)
            b.blocks = [("knot", k.blob(c0, r.width * 0.13, r.height * 0.13, n: 8, seed: 3))]
            b.sticks = [Stick([c0, P(0.14, 0.12), P(0.02, -0.02)], 16 * u, 7 * u, start: nil),
                        Stick([c0, P(0.38 + j(1), 0.55), P(0.3 + j(2), 0.97)], 13 * u, 4 * u, start: nil),
                        Stick([c0, P(0.58, 0.46 + j(3)), P(0.93, 0.72 + j(4))], 13 * u, 4 * u, start: nil),
                        Stick([c0, P(0.14, 0.46 + j(5)), P(0.03, 0.64)], 10 * u, 3.5 * u, start: nil),
                        Stick([c0, P(0.6, 0.2 + j(6)), P(0.98, 0.3 + j(7))], 11 * u, 4 * u, start: nil),
                        Stick([c0, P(0.5, 0.72), P(0.62 + j(8), 0.98)], 9 * u, 3 * u, start: nil)]
        case .driftwoodBranch:
            b.sticks = [Stick([P(0.02, 0.03), P(0.3, 0.32 + j(1)), P(0.64, 0.6 + j(2)), P(0.98, 0.9)], 17 * u, 6 * u, start: .foot),
                        Stick([P(0.56, 0.55), P(0.68, 0.8 + j(3)), P(0.74, 0.99)], 8 * u, 3 * u, start: nil),
                        Stick([P(0.3, 0.33), P(0.37, 0.12)], 8 * u, 7 * u, name: "snag", start: nil, end: nil)]
        case .corkTunnel:
            // Seen from the side, cut away: the roof of the tube and the rims
            // of its two open ends, one arch sunk into the ground — it walks
            // straight through on the floor of the tube, lying on the soil —
            // and the floor, painted.
            let t = min(r.height * 0.2, 15 * u)
            b.bars = [("roof", k.band(from: 0.02, to: 0.98, top: { 0.93 + 0.05 * sin(.pi * $0) }, thick: t))]
            let rimTop = r.maxY - t * 0.5
            b.sticks = [Stick([P(0.04, -0.12), V2(r.minX + r.width * 0.015, (r.minY + rimTop) / 2), V2(r.minX + r.width * 0.04, rimTop)], 5 * u, 5 * u, name: "rim", start: nil, end: nil),
                        Stick([P(0.96, -0.12), V2(r.maxX - r.width * 0.015, (r.minY + rimTop) / 2), V2(r.maxX - r.width * 0.04, rimTop)], 5 * u, 5 * u, name: "rim", start: nil, end: nil)]
            b.visual = [k.trough(from: 0.03, to: 0.97, top: { 0.1 - 0.05 * sin(.pi * $0) })]
            b.stickPorts = false
            b.hollows = [Hollow(cavity: Poly.clockwise([V2(r.minX + 4 * u, r.minY), V2(r.maxX - 4 * u, r.minY), V2(r.maxX - 4 * u, r.maxY - t), V2(r.minX + 4 * u, r.maxY - t)]),
                                mouth: V2(r.minX + 4 * u, r.minY), inward: V2(1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: V2(r.minX + 2 * u, r.minY), normal: V2(-1, 0)),
                         ObjectAnchor(kind: .entrance, point: V2(r.maxX - 2 * u, r.minY), normal: V2(1, 0)),
                         ObjectAnchor(kind: .refuge, point: V2(r.midX, r.minY), normal: V2(0, 1)),
                         ObjectAnchor(kind: .perch, point: P(0.5, 0.98), normal: V2(0, 1))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 0.98), half: r.width * 0.3)]
        case .leaningBark:
            b.sticks = [Stick([P(0.08, -0.02), P(0.3, 0.5 + j(1)), P(0.62, 0.84), P(0.95, 0.98)], 22 * u, 16 * u, name: "sheet", start: .foot, end: .end)]
        case .bambooTipi:
            let tie = P(0.5, 0.82)
            b.sticks = [Stick([P(0.08, 0), tie, P(0.66, 0.99)], 11 * u, 9 * u, name: "cane", start: .foot, end: nil),
                        Stick([P(0.92, 0), tie + V2(1 * u, 0), P(0.34, 0.99)], 11 * u, 9 * u, name: "cane", start: .foot, end: nil),
                        Stick([P(0.46, 0), tie + V2(2 * u, -1 * u), P(0.55, 1)], 9 * u, 8 * u, name: "cane", start: .foot, end: nil)]
            b.visual = [k.disc(tie, 9 * u)]
            b.stickPorts = false
            b.ports = [HabitatPort("a0", .foot, P(0.08, 0), half: 5 * u), HabitatPort("tie", .hook, tie + V2(0, -8 * u)),
                       HabitatPort("fork", .cradle, P(0.5, 0.9))]
        case .hangingBranch:
            // A branch low in its rectangle, on a bridle of twine from the top.
            // (Hung from one cord to its middle; the bridle out to its ends is
            // only drawn — a ring of cord round it would shut its middle off
            // from its ends.)
            func Y(_ x: CGFloat, _ dy: CGFloat) -> V2 { V2(r.minX + r.width * x, r.minY + dy * u) }
            let limb = [Y(0.0, 16 + j(1, 3)), Y(0.35, 10), Y(0.7, 12 + j(2, 3)), Y(1.0, 20)]
            let knot = V2(r.midX, r.minY + min(r.height * 0.45, 70 * u))
            b.sticks = [Stick(limb, 10 * u, 6 * u), Stick([P(0.5, 1), knot, Y(0.5, 12)], 2.4 * u, 2.4 * u, name: "cord", start: nil, end: nil)]
            b.visual = [HabitatShape.bar(knot, Y(0.1, 15), 2 * u), HabitatShape.bar(knot, Y(0.9, 17), 2 * u)]
            b.stickPorts = false
            b.ports = [HabitatPort("top", .hang, P(0.5, 1), half: 1.2 * u), b.sticks[0].along("along0")]
        case .lianaLoop:
            // Down from one end, once round a loop, and up to the other end.
            let c = P(0.55, 0.38)
            let R = min(r.width * 0.18, r.height * 0.22)
            func on(_ deg: CGFloat, _ grow: CGFloat) -> V2 { c + V2.angle(deg * .pi / 180) * (R * grow) }
            let aLoop = stride(from: 240.0, through: 540.0, by: 30.0).map { on(CGFloat($0), 1 + 0.1 * CGFloat(($0 - 240) / 300)) }
            let bLoop = stride(from: 525.0, through: 690.0, by: 30.0).map { on(CGFloat($0), 1.15) }
            b.sticks = [Stick([P(0, 0.92), P(0.16, 0.68 + j(1))] + aLoop, 9 * u, 7 * u, name: "liana", end: nil),
                        Stick(bLoop + [P(0.84, 0.6 + j(2)), P(1, 0.9)], 7 * u, 8 * u, name: "liana", start: nil)]
        case .hangingRoots:
            b.blocks = [("clump", k.blob(P(0.5, 0.97), r.width * 0.46, min(r.height * 0.06, 14 * u), n: 9, seed: 5))]
            let lens: [CGFloat] = [0.95, 0.58, 0.8, 0.5, 0.72]
            for i in 0..<5 {
                let x = 0.14 + CGFloat(i) * 0.18, len = lens[i] + j(10 + i, 0.05)
                b.sticks.append(Stick([P(x, 0.95), P(x + j(20 + i, 0.05), 0.95 - len * 0.35), P(x - j(30 + i, 0.05), 0.95 - len * 0.7), P(x + j(40 + i, 0.04), 0.95 - len)],
                                      5 * u, 2 * u, name: "root", start: nil, end: nil))
            }
            for i in [0, 2] {
                let sp = b.sticks[i].spine()
                let at = sp[sp.count / 2]
                b.sticks.append(Stick([at, at + V2(r.width * 0.07, -r.height * 0.06), at + V2(r.width * 0.1, -r.height * 0.14)], 2.6 * u, 1.2 * u, name: "root", start: nil, end: nil))
            }
            b.stickPorts = false
            b.ports = [HabitatPort("top", .hang, P(0.5, 1), half: r.width * 0.2)]
        case .stickRaft:
            b.blocks = [("raft", k.raft())]
            b.ports = platformBase(r, bottom: { _ in 0.04 })
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
        case .mossPlatform:
            let ledge = CGMutablePath()
            ledge.move(to: P(0.02, 0.1).point)
            ledge.addLine(to: P(0.96, 0.1).point)
            ledge.addQuadCurve(to: P(0.97, 0.6).point, control: P(1.03, 0.3).point)
            ledge.addLine(to: P(0.03, 0.62).point)
            ledge.addQuadCurve(to: P(0.02, 0.1).point, control: P(-0.02, 0.36).point)
            ledge.closeSubpath()
            b.blocks = [("ledge", k.path(ledge)), ("moss", k.mound(from: 0.07, to: 0.9, base: 0.5, height: 0.5, bumps: 5))]
            b.ports = platformBase(r, bottom: { _ in 0.1 })
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
        case .rockSpire:
            // Chunks of rock stacked, each set back or out from the last: ledges.
            let chunks: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0.0, 0.98, -0.02, 0.3), (0.16 + j(1), 0.76 + j(2), 0.27, 0.56),
                                                                  (0.1 + j(3), 0.94, 0.53, 0.8), (0.28, 0.8 + j(4), 0.77, 1)]
            b.blocks = chunks.enumerated().map { i, ch in ("rock", k.chunk(ch.0, ch.1, ch.2, ch.3, seed: 10 + i)) }
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.52, 1), normal: V2(0, 1))]
            b.ports = [HabitatPort("top", .cradle, P(0.52, 0.99), half: r.width * 0.2)]
        case .stoneArch:
            b.sticks = [Stick([P(0.06, -0.1), P(0.11, 0.5), P(0.3, 0.9 + j(1)), P(0.7, 0.92 + j(2)), P(0.89, 0.52), P(0.94, -0.1)],
                              38 * u, 32 * u, name: "arch", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [b.sticks[0].along("along0")]
            b.anchors = [ObjectAnchor(kind: .refuge, point: P(0.5, 0), normal: V2(0, 1))]

        // MARK: Shelters
        case .barkCave:
            let c = V2(r.midX - r.width * 0.02, r.minY - r.height * 0.04)
            let (rx, ry, t) = (r.width * 0.5, r.height, 13 * u)
            let shell = k.shell(c, rx, ry, t, from: .pi + 0.12, to: 0.62)
            b.blocks = [("shell", shell.outline)]
            b.hollows = [Hollow(cavity: shell.inside, mouth: V2(shell.lip.x, r.minY), inward: V2(-1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: V2(shell.lip.x + 6 * u, r.minY), normal: V2(1, 0)),
                         ObjectAnchor(kind: .refuge, point: V2(c.x + rx * 0.05, r.minY), normal: V2(0, 1)),
                         ObjectAnchor(kind: .perch, point: V2(c.x, c.y + ry), normal: V2(0, 1))]
        case .rockCrevice:
            let pts: [V2] = [P(-0.02, -0.04), P(1.0, -0.04), P(1.02, 0.1), P(0.97, 0.2), P(0.62, 0.21), P(0.36, 0.2), P(0.3, 0.27), P(0.29, 0.52),
                             P(0.4, 0.6), P(0.7, 0.59), P(0.93, 0.58), P(1.0, 0.64), P(0.97, 0.82 + j(1)), P(0.8, 0.96), P(0.5, 1.0), P(0.2, 0.95 + j(2)),
                             P(0.04, 0.74), P(-0.02, 0.4)]
            b.blocks = [("rock", Poly.clockwise(k.chaikin(pts, 2)))]
            b.hollows = [Hollow(cavity: Poly.clockwise([P(0.32, 0.22), P(0.97, 0.22), P(0.97, 0.56), P(0.32, 0.56)]), mouth: P(0.97, 0.21), inward: V2(-1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: P(0.98, 0.21), normal: V2(1, 0)),
                         ObjectAnchor(kind: .refuge, point: P(0.5, 0.21), normal: V2(0, 1)),
                         ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
        case .logDen:
            let t = min(r.height * 0.16, 15 * u), capW = r.width * 0.14, lip = r.height * 0.18
            let o = CGMutablePath()
            o.move(to: V2(r.minX + lip, r.minY + t).point)
            o.addLine(to: V2(r.maxX - capW, r.minY + t).point)
            o.addLine(to: V2(r.maxX - capW, r.maxY - t).point)
            o.addLine(to: V2(r.minX + lip, r.maxY - t).point)
            o.addQuadCurve(to: V2(r.minX + lip * 1.6, r.maxY).point, control: V2(r.minX + lip * 0.7, r.maxY - t * 0.2).point)
            o.addLine(to: V2(r.maxX - r.height * 0.5, r.maxY).point)
            o.addArc(center: V2(r.maxX - r.height * 0.5, r.midY).point, radius: r.height * 0.5, startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: true)
            o.addLine(to: V2(r.minX + lip * 1.6, r.minY).point)
            o.addQuadCurve(to: V2(r.minX + lip, r.minY + t).point, control: V2(r.minX + lip * 0.7, r.minY + t * 0.2).point)
            o.closeSubpath()
            b.blocks = [("log", k.path(o))]
            b.hollows = [Hollow(cavity: Poly.clockwise([V2(r.minX + lip, r.minY + t), V2(r.maxX - capW, r.minY + t), V2(r.maxX - capW, r.maxY - t), V2(r.minX + lip, r.maxY - t)]),
                                mouth: V2(r.minX + lip, r.minY + t), inward: V2(1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: V2(r.minX + lip * 0.6, r.minY + t), normal: V2(-1, 0)),
                         ObjectAnchor(kind: .refuge, point: V2(r.maxX - capW - 34 * u, r.minY + t), normal: V2(0, 1)),
                         ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
            b.ports = [HabitatPort("top", .cradle, P(0.5, 1), half: r.width * 0.3)]
        case .curledLeafHide:
            let mid = [P(0.97, 0.03), P(0.62, 0.02), P(0.26, 0.05), P(0.06, 0.3 + j(1)), P(0.1, 0.72), P(0.35, 0.95), P(0.66, 0.94 + j(2)),
                       P(0.87, 0.76), P(0.91, 0.56), P(0.84, 0.49), P(0.77, 0.52)]
            b.blocks = [("leaf", Stick(mid, 6 * u, 5 * u).outline())]
            b.hollows = [Hollow(cavity: Poly.clockwise(k.chaikin([P(0.2, 0.08), P(0.8, 0.08), P(0.84, 0.48), P(0.7, 0.86), P(0.34, 0.88), P(0.14, 0.66)], 2)),
                                mouth: P(0.94, 0.06), inward: V2(-1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: P(0.97, 0.05), normal: V2(1, 0)),
                         ObjectAnchor(kind: .refuge, point: P(0.46, 0.06), normal: V2(0, 1))]
        case .leafCanopy:
            b.sticks = [Stick([P(0.49, 0), P(0.44, 0.4), P(0.36, 0.72)], 6 * u, 4 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.51, 0), P(0.56, 0.42), P(0.64, 0.74)], 6 * u, 4 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.5, 0), P(0.5, 0.5), P(0.52, 0.8)], 5 * u, 3.5 * u, name: "stem", start: nil, end: nil)]
            k.leaf(&b, "leaf", P(0.36, 0.72), angle: .pi + 0.42 + j(1, 0.08), len: r.width * 0.46, wide: r.height * 0.3, bend: -0.12)
            k.leaf(&b, "leaf", P(0.64, 0.74), angle: -0.4 + j(2, 0.08), len: r.width * 0.46, wide: r.height * 0.3, bend: 0.12)
            k.leaf(&b, "leaf", P(0.52, 0.8), angle: .pi / 2 + 0.25, len: r.height * 0.22, wide: r.height * 0.11, bend: 0.06)
            b.stickPorts = false
            b.anchors = [ObjectAnchor(kind: .refuge, point: P(0.24, 0), normal: V2(0, 1)), ObjectAnchor(kind: .refuge, point: P(0.78, 0), normal: V2(0, 1))]
        case .rootHollow:
            b.blocks = [("trunk", Poly.clockwise(k.chaikin([P(0.27, 0.47), P(0.79, 0.47), P(0.82, 0.7), P(0.8, 0.9), P(0.52, 0.97 + j(1)), P(0.27, 0.92), P(0.25, 0.7)], 2))),
                        ("root", Poly.clockwise(k.chaikin([P(-0.02, -0.04), P(0.25, -0.04), P(0.3, 0.3), P(0.33, 0.52), P(0.26, 0.64), P(0.08, 0.2)], 1)))]
            b.sticks = [Stick([P(0.74, 0.55), P(0.9, 0.42), P(0.98, 0.14), P(1.01, -0.12)], 15 * u, 9 * u, name: "root", start: nil, end: nil)]
            b.stickPorts = false
            b.hollows = [Hollow(cavity: Poly.clockwise([P(0.3, 0), P(0.8, 0), P(0.8, 0.46), P(0.3, 0.46)]), mouth: P(0.9, 0), inward: V2(-1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: P(0.9, 0), normal: V2(1, 0)),
                         ObjectAnchor(kind: .refuge, point: P(0.5, 0), normal: V2(0, 1)),
                         ObjectAnchor(kind: .perch, point: P(0.52, 0.96), normal: V2(0, 1))]
            b.ports = [HabitatPort("top", .cradle, P(0.53, 0.94), half: r.width * 0.18)]
        case .mossyHide:
            let c = V2(r.midX - r.width * 0.04, r.minY - r.height * 0.04)
            let shell = k.shell(c, r.width * 0.48, r.height * 0.96, 22 * u, from: .pi + 0.1, to: 0.86)
            b.blocks = [("dome", shell.outline)]
            b.hollows = [Hollow(cavity: shell.inside, mouth: V2(shell.lip.x, r.minY), inward: V2(-1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: V2(shell.lip.x + 6 * u, r.minY), normal: V2(1, 0)),
                         ObjectAnchor(kind: .refuge, point: V2(c.x + r.width * 0.04, r.minY), normal: V2(0, 1)),
                         ObjectAnchor(kind: .perch, point: V2(c.x, c.y + r.height * 0.94), normal: V2(0, 1))]
        case .hangingLeafShelter:
            // The pouch keeps its size however long its thread.
            let ph = min(r.height * 0.56, 110 * u)
            func Q(_ x: CGFloat, _ y: CGFloat) -> V2 { V2(r.minX + r.width * x, r.minY + ph * y) }
            let mid = [Q(0.24, 0.72), Q(0.42, 0.92), Q(0.72, 0.94), Q(0.94, 0.62), Q(0.86, 0.2), Q(0.56, 0.03), Q(0.24, 0.09), Q(0.1, 0.24)]
            b.sticks = [Stick(mid, 6 * u, 5 * u, name: "leaf", start: nil, end: nil),
                        Stick([P(0.5, 1), Q(0.55, 0.93)], 2 * u, 2 * u, name: "thread", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [HabitatPort("top", .hang, P(0.5, 1), half: 1 * u)]
            b.hollows = [Hollow(cavity: Poly.clockwise([Q(0.2, 0.12), Q(0.84, 0.12), Q(0.86, 0.6), Q(0.66, 0.84), Q(0.36, 0.82)]), mouth: Q(0.14, 0.4), inward: V2(1, 0))]
            b.anchors = [ObjectAnchor(kind: .entrance, point: Q(0.12, 0.36), normal: V2(-1, 0)),
                         ObjectAnchor(kind: .refuge, point: Q(0.56, 0.1), normal: V2(0, 1))]
        case .overhang:
            let pts: [V2] = [P(-0.02, -0.04), P(0.44, -0.04), P(0.46, 0.12), P(0.42, 0.3), P(0.45, 0.46), P(0.58, 0.53), P(0.85, 0.55), P(0.99, 0.6),
                             P(1.0, 0.7), P(0.93, 0.8 + j(1)), P(0.72, 0.84), P(0.55, 0.93), P(0.35, 1.0), P(0.12, 0.96 + j(2)), P(0.02, 0.78), P(-0.03, 0.4)]
            b.blocks = [("rock", Poly.clockwise(k.chaikin(pts, 2)))]
            b.hollows = [Hollow(cavity: Poly.clockwise([P(0.46, 0), P(0.98, 0), P(0.98, 0.52), P(0.46, 0.5)]), mouth: P(0.98, 0), inward: V2(-1, 0))]
            b.anchors = [ObjectAnchor(kind: .refuge, point: P(0.66, 0), normal: V2(0, 1)), ObjectAnchor(kind: .perch, point: P(0.36, 1), normal: V2(0, 1))]

        // MARK: Plants
        case .smallFern, .tinyFlowers, .lithops, .airPlant, .creepingCover, .gravel, .pineNeedles, .tinyMushrooms, .glowMushrooms, .lichen,
             .acorn, .seedPod, .fallenLeaf, .curledLeaf, .deadLeaf, .petals, .puddle, .looseLeaf, .petal, .tinyTwig, .feather, .seed, .smallShell, .tinyPebble:
            // Only to look at: roughly where it is drawn.
            b.visual = [k.lookArea(kind)]
        case .largeFern:
            var all: [V2] = []
            for i in 0..<6 {
                let a = -1.2 + 2.4 * CGFloat(i) / 5 + j(i, 0.08)
                let sa = sin(a), W = r.width * 0.5, H = r.height, base = P(0.5, 0)
                let pts = [base, base + V2(sa * 0.18 * W, 0.42 * H), base + V2(sa * 0.6 * W, (0.8 - 0.22 * abs(sa)) * H),
                           base + V2(sa * 0.96 * W, (0.64 - 0.5 * abs(sa)) * H)]
                b.sticks.append(Stick(pts, 3.6 * u, 1.4 * u, name: "frond", start: nil, end: nil))
                all += pts
            }
            b.stickPorts = false
            b.visual = [Poly.hull(all)]
        case .broadLeaf:
            for i in 0..<5 {
                let f = CGFloat(i) - 2
                let a = .pi / 2 + f * 0.36 + j(i, 0.06)
                let base = P(0.5 + f * 0.02, 0), tip = base + V2(cos(a) * r.width * 0.32, sin(a) * r.height * (0.44 - abs(f) * 0.05))
                b.sticks.append(Stick([base, V2.lerp(base, tip, 0.5) + V2(0, r.height * 0.04), tip], 4 * u, 2.6 * u, name: "stem", start: nil, end: nil))
                k.leaf(&b, "leaf", tip, angle: a + f * 0.1, len: r.height * (0.4 - abs(f) * 0.03), wide: r.width * 0.2, bend: f * 0.04)
            }
            b.stickPorts = false
        case .trailingPlant:
            b.blocks = [("pot", Poly.clockwise([P(0.1, 0.72), P(0.46, 0.72), P(0.51, 0.95), P(0.05, 0.95)])), ("rim", k.rectPts(0.02, 0.92, 0.54, 1))]
            b.sticks = [Stick([P(0.44, 0.98), P(0.62, 0.96), P(0.74, 0.72), P(0.7, 0.42 + j(1)), P(0.78, 0.08)], 3 * u, 2 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.38, 0.99), P(0.6, 1.02), P(0.9, 0.84), P(0.96, 0.52), P(0.9, 0.26 + j(2))], 2.6 * u, 1.8 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.12, 0.99), P(0.01, 0.88), P(-0.01, 0.62), P(0.06, 0.4 + j(3))], 2.6 * u, 1.8 * u, name: "stem", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [HabitatPort("base", .base, P(0.28, 0.72))]
        case .climbingVine:
            let pts = [P(0.5, 0)] + (1...8).map { i in P(0.5 + (i % 2 == 0 ? -0.15 : 0.15) + j(i, 0.04), CGFloat(i) / 8 * 0.97) }
            b.sticks = [Stick(pts, 4 * u, 2 * u, name: "stem", start: .foot, end: .end)]
        case .grassClump:
            for i in 0..<7 {
                let f = CGFloat(i) - 3
                let a = .pi / 2 + f * 0.22 + j(i, 0.08)
                k.leaf(&b, "blade", P(0.5 + f * 0.035, -0.03), angle: a, len: r.height * (0.66 + 0.34 * HabitatShape.rnd(s, 90 + i)) * (1 - abs(f) * 0.06),
                       wide: 7 * u, bend: f * 0.035, taper: true)
            }
        case .floweringPlant:
            b.sticks = [Stick([P(0.5, 0), P(0.46 + j(1), 0.4), P(0.52, 0.8)], 4 * u, 3 * u, name: "stem", start: .foot, end: nil)]
            k.leaf(&b, "leaf", P(0.48, 0.24), angle: .pi - 0.55, len: r.width * 0.42, wide: r.width * 0.16, bend: -0.06)
            k.leaf(&b, "leaf", P(0.49, 0.46), angle: 0.5, len: r.width * 0.4, wide: r.width * 0.15, bend: 0.06)
            b.bars.append(("head", k.ellipse(P(0.52, 0.84), r.width * 0.26, min(r.height * 0.045, 8 * u))))
            b.stickPorts = false
            b.visual = [k.disc(P(0.52, 0.86), r.width * 0.46)]
            b.anchors = [ObjectAnchor(kind: .perch, point: V2(r.minX + r.width * 0.52, r.minY + r.height * 0.84 + min(r.height * 0.045, 8 * u)), normal: V2(0, 1))]
        case .aloe:
            for i in 0..<7 {
                let f = CGFloat(i) - 3
                k.leaf(&b, "leaf", P(0.5 + f * 0.02, 0.02), angle: .pi / 2 + f * 0.3 + j(i, 0.05), len: r.height * (0.95 - abs(f) * 0.12),
                       wide: r.width * 0.17, bend: f * 0.05, taper: true)
            }
        case .jadePlant:
            b.sticks = [Stick([P(0.5, 0), P(0.47, 0.3), P(0.5, 0.45)], 12 * u, 9 * u, name: "trunk", start: .foot, end: nil),
                        Stick([P(0.5, 0.44), P(0.3, 0.62 + j(1)), P(0.18, 0.8)], 7 * u, 4 * u, name: "limb", start: nil, end: nil),
                        Stick([P(0.5, 0.45), P(0.56, 0.7), P(0.5 + j(2), 0.88)], 7 * u, 4 * u, name: "limb", start: nil, end: nil),
                        Stick([P(0.5, 0.44), P(0.72, 0.58 + j(3)), P(0.86, 0.72)], 7 * u, 4 * u, name: "limb", start: nil, end: nil)]
            b.bars = [("pad", k.ellipse(P(0.15, 0.84), 11 * u, 6.5 * u, tilt: 0.4)), ("pad", k.ellipse(P(0.5, 0.93), 11 * u, 6.5 * u)),
                      ("pad", k.ellipse(P(0.89, 0.76), 11 * u, 6.5 * u, tilt: -0.4))]
            b.stickPorts = false
            b.visual = [k.disc(P(0.5, 0.72), r.width * 0.44)]
        case .miniPalm:
            let top = P(0.5, 0.58)
            b.sticks = [Stick([P(0.5, 0), P(0.49 + j(1), 0.3), top], 7 * u, 5 * u, name: "trunk", start: .foot, end: nil)]
            var all: [V2] = [top]
            for i in 0..<6 {
                let a = -1.15 + 2.3 * CGFloat(i) / 5 + j(i, 0.06)
                let sa = sin(a), W = r.width * 0.5, H = r.height * 0.42
                let pts = [top, top + V2(sa * 0.22 * W, 0.2 * H + 0.35 * H * cos(a)), top + V2(sa * 0.62 * W, (0.28 + 0.5 * cos(a)) * H * 0.9),
                           top + V2(sa * 0.97 * W, (0.1 + 0.55 * cos(a) - 0.4 * abs(sa)) * H)]
                b.sticks.append(Stick(pts, 2.8 * u, 1 * u, name: "frond", start: nil, end: nil))
                all += pts
            }
            b.stickPorts = false
            b.visual = [Poly.hull(all)]
        case .deadPlant:
            b.sticks = [Stick([P(0.5, 0), P(0.47, 0.45), P(0.52, 0.95)], 3.6 * u, 1.6 * u, name: "stem", start: .foot, end: nil),
                        Stick([P(0.48, 0.3), P(0.3, 0.5), P(0.16 + j(1), 0.72)], 2.4 * u, 1 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.49, 0.5), P(0.7, 0.66), P(0.84, 0.86 + j(2))], 2.4 * u, 1 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.5, 0.68), P(0.36, 0.84), P(0.3 + j(3), 0.98)], 2 * u, 1 * u, name: "stem", start: nil, end: nil),
                        Stick([P(0.48, 0.2), P(0.66, 0.3), P(0.8, 0.38 + j(4))], 2 * u, 1 * u, name: "stem", start: nil, end: nil)]
            b.stickPorts = false
        case .fiddleheads:
            for i in 0..<4 {
                let x = 0.26 + CGFloat(i) * 0.15 + j(i, 0.02)
                let h = 0.52 + HabitatShape.rnd(s, 70 + i) * 0.26
                let side: CGFloat = i % 2 == 0 ? 1 : -1
                let R = (9 + HabitatShape.rnd(s, 80 + i) * 3) * u
                let stemTop = P(x + 0.02 * side, h)
                var pts = [P(x, 0), P(x - 0.02 * side, h * 0.5), stemTop]
                let c = stemTop + V2(R * side, 0)
                // (Not quite a full turn, and not too tight: a coil wound in
                // on itself folds over when the surface is grown round it.
                // Its curled tip is painted.)
                var a: CGFloat = side > 0 ? .pi : 0
                for _ in 0..<10 {
                    a -= 0.55 * side
                    let rr = R * (1 - 0.04 * CGFloat(pts.count - 3))
                    pts.append(c + V2.angle(a) * rr)
                }
                b.sticks.append(Stick(pts, 3.2 * u, 1.8 * u, name: "frond", start: nil, end: nil))
            }
            b.stickPorts = false
        case .hangingFoliage:
            b.blocks = [("clump", k.blob(P(0.5, 0.97), r.width * 0.44, min(r.height * 0.05, 12 * u), n: 9, seed: 7))]
            let lens: [CGFloat] = [0.9, 0.55, 0.75, 0.45, 0.66]
            for i in 0..<5 {
                let x = 0.14 + CGFloat(i) * 0.18, len = lens[i] + j(10 + i, 0.05)
                b.sticks.append(Stick([P(x, 0.95), P(x + j(20 + i, 0.06), 0.95 - len * 0.4), P(x - j(30 + i, 0.06), 0.95 - len * 0.75), P(x, 0.95 - len)],
                                      3 * u, 1.8 * u, name: "strand", start: nil, end: nil))
            }
            b.stickPorts = false
            b.ports = [HabitatPort("top", .hang, P(0.5, 1), half: r.width * 0.2)]
        case .mossCushion:
            b.blocks = [("moss", k.mound(from: 0.02, to: 0.98, base: -0.05, height: 1.05, bumps: 4))]
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]

        // MARK: The ground
        case .sandDrift:
            b.blocks = [("sand", k.mound(from: 0.0, to: 1.0, base: -0.1, height: 1.1, bumps: 0, peak: 0.4))]

        // MARK: Natural details
        case .mushroom:
            b.sticks = [Stick([P(0.5, 0), P(0.47 + j(1), 0.35), P(0.5, 0.62)], 10 * u, 8 * u, name: "stem", start: .foot, end: nil)]
            b.bars = [("cap", k.cap(P(0.5, 0.58), r.width * 0.46, r.height * 0.4))]
            b.stickPorts = false
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 0.98), normal: V2(0, 1)), ObjectAnchor(kind: .tie, point: P(0.3, 0.56), normal: V2(0, -1))]
        case .mushroomCluster:
            b.blocks = [("base", k.mound(from: 0.06, to: 0.98, base: -0.04, height: 0.2, bumps: 3))]
            for (i, m) in NatureKit.cluster.enumerated() {
                let top = 0.1 + m.h * 0.62
                b.sticks.append(Stick([P(m.x, 0.08), P(m.x + j(i, 0.02), 0.08 + (top - 0.08) * 0.5), P(m.x, top)], (3 + m.h * 3.5) * u, (2.6 + m.h * 3) * u,
                                      name: "stem", start: nil, end: nil))
                b.bars.append(("cap", k.cap(P(m.x, top - 0.02), r.width * m.w / 2, r.height * (0.12 + m.h * 0.2))))
            }
            b.stickPorts = false
        case .shelfFungus:
            let big = CGMutablePath()
            big.move(to: P(0, 0.36).point)
            big.addLine(to: P(0, 0.8).point)
            big.addQuadCurve(to: P(0.94, 0.66).point, control: P(0.5, 0.86).point)
            big.addQuadCurve(to: P(0.86, 0.46).point, control: P(1.04, 0.52).point)
            big.addQuadCurve(to: P(0, 0.36).point, control: P(0.4, 0.34).point)
            big.closeSubpath()
            let small = CGMutablePath()
            small.move(to: P(0, 0.0).point)
            small.addLine(to: P(0, 0.34).point)
            small.addQuadCurve(to: P(0.62, 0.24).point, control: P(0.34, 0.36).point)
            small.addQuadCurve(to: P(0.56, 0.08).point, control: P(0.7, 0.12).point)
            small.addQuadCurve(to: P(0, 0).point, control: P(0.28, -0.02).point)
            small.closeSubpath()
            b.blocks = [("bracket", k.path(big)), ("bracket", k.path(small))]
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.45, 0.8), normal: V2(0, 1))]
        case .pineCone:
            b.blocks = [("cone", k.pineCone())]
        case .seaShell:
            b.blocks = [("shell", k.path(k.conch()))]
        case .snailShell:
            b.blocks = [("shell", k.blob(P(0.46, 0.5), r.width * 0.44, r.height * 0.5, n: 10, seed: 0, wobble: 0.04))]
        case .leafHeap:
            b.blocks = [("leaves", k.mound(from: 0.0, to: 1.0, base: -0.06, height: 1.06, bumps: 7))]
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
        case .pebblePile:
            b.blocks = [("pebbles", k.mound(from: 0.0, to: 1.0, base: -0.06, height: 1.06, bumps: 6))]
        case .smoothStones:
            b.blocks = [("stone", k.ellipse(P(0.5, 0.19), r.width * 0.48, r.height * 0.21)),
                        ("stone", k.ellipse(P(0.48 + j(1), 0.5), r.width * 0.36, r.height * 0.16)),
                        ("stone", k.ellipse(P(0.52 + j(2), 0.79), r.width * 0.25, r.height * 0.14))]
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.52, 0.93), normal: V2(0, 1))]
        case .crystalCluster:
            b.blocks = [("geode", k.mound(from: 0.02, to: 0.98, base: -0.06, height: 0.34, bumps: 3))]
            for (i, c) in NatureKit.crystals.enumerated() {
                b.bars.append(("crystal", k.prism(P(c.x, 0.18), angle: .pi / 2 + c.lean + j(i, 0.05), len: r.height * c.len, wide: r.width * c.w)))
            }
        case .shedBark:
            // (Solid: too low to get under, it is a hump to walk over.)
            b.blocks = [("bark", Stick([P(0.02, 0.06), P(0.3, 0.84), P(0.7, 0.9 + j(1)), P(0.94, 0.42), P(0.84, 0.22)], 6 * u, 5 * u).outline())]
        case .twigPile:
            for (i, t) in NatureKit.twigs.enumerated() {
                b.sticks.append(Stick([P(t.0, t.1), P((t.0 + t.2) / 2 + j(i, 0.02), (t.1 + t.3) / 2 + j(i + 9, 0.04)), P(t.2, t.3)], (3.6 - CGFloat(i) * 0.15) * u, 2 * u,
                                      name: "twig", start: nil, end: nil))
            }
            b.stickPorts = false

        // MARK: Functional
        case .rockPool:
            let p = CGMutablePath()
            p.move(to: P(-0.02, -0.04).point)
            p.addLine(to: P(1.02, -0.04).point)
            p.addQuadCurve(to: P(0.9, 0.96).point, control: P(1.04, 0.7).point)
            p.addQuadCurve(to: P(0.8, 0.84).point, control: P(0.84, 0.98).point)
            p.addLine(to: P(0.2, 0.84).point)
            p.addQuadCurve(to: P(0.1, 0.96).point, control: P(0.16, 0.98).point)
            p.addQuadCurve(to: P(-0.02, -0.04).point, control: P(-0.04, 0.7).point)
            p.closeSubpath()
            b.blocks = [("basin", k.path(p))]
            b.anchors = [ObjectAnchor(kind: .drink, point: P(0.22, 0.84), normal: V2(0, 1)), ObjectAnchor(kind: .drink, point: P(0.78, 0.84), normal: V2(0, 1))]
        case .feedingPlatform:
            b.blocks = [("tray", Poly.clockwise([P(0.02, 0.84), P(0.98, 0.84), P(1, 0.98), P(0.9, 0.98), P(0.88, 0.92), P(0.12, 0.92), P(0.1, 0.98), P(0, 0.98)]))]
            b.sticks = [Stick([P(0.5, 0.02), P(0.48 + j(1), 0.45), P(0.5, 0.86)], 8 * u, 6 * u, name: "stand", start: nil, end: nil),
                        Stick([P(0.49, 0.14), P(0.3, 0.05), P(0.14, -0.02)], 5 * u, 3 * u, name: "stand", start: nil, end: nil),
                        Stick([P(0.51, 0.14), P(0.7, 0.05), P(0.86, -0.02)], 5 * u, 3 * u, name: "stand", start: nil, end: nil)]
            b.stickPorts = false
            b.ports = [HabitatPort("a0", .foot, P(0.5, 0), half: r.width * 0.4)]
            b.anchors = [ObjectAnchor(kind: .feed, point: P(0.5, 0.92), normal: V2(0, 1))]
        case .baskingStone:
            let pts = [P(-0.02, -0.04), P(1.02, -0.04), P(1.03, 0.4), P(0.95, 0.84), P(0.8, 0.95), P(0.2, 0.98 + j(1)), P(0.05, 0.86), P(-0.03, 0.4)]
            b.blocks = [("stone", Poly.clockwise(k.chaikin(pts, 2)))]
            b.anchors = [ObjectAnchor(kind: .bask, point: P(0.5, 0.97), normal: V2(0, 1)), ObjectAnchor(kind: .perch, point: P(0.5, 0.97), normal: V2(0, 1))]
        case .lookout:
            let deck = min(12 * u, r.height * 0.06)
            b.sticks = [Stick([P(0.5, 0), P(0.44 + j(1), 0.4), P(0.55 + j(2), 0.75), V2(r.midX, r.maxY - deck)], 14 * u, 8 * u, name: "snag", start: .foot, end: nil),
                        Stick([P(0.46, 0.42), P(0.2, 0.52 + j(3))], 6 * u, 3 * u, name: "snag", start: nil, end: nil),
                        Stick([P(0.54, 0.7), P(0.82, 0.78 + j(4))], 6 * u, 3 * u, name: "snag", start: nil, end: nil)]
            b.blocks = [("deck", Poly.clockwise(k.chaikin([V2(r.minX, r.maxY - deck), V2(r.maxX, r.maxY - deck * 1.2), V2(r.maxX - 2 * u, r.maxY), V2(r.minX + 2 * u, r.maxY)], 1)))]
            b.stickPorts = false
            b.ports = [HabitatPort("a0", .foot, P(0.5, 0), half: 7 * u), HabitatPort("top", .cradle, P(0.5, 1), half: r.width * 0.3)]
            b.anchors = [ObjectAnchor(kind: .lookout, point: P(0.5, 1), normal: V2(0, 1)), ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
        case .silkFrame:
            b.sticks = [Stick([P(0.1, 0), P(0.12 + j(1), 0.5), P(0.1, 1)], 7 * u, 5 * u, name: "post", start: .foot, end: .end),
                        Stick([P(0.9, 0), P(0.88 + j(2), 0.5), P(0.9, 0.98)], 7 * u, 5 * u, name: "post", start: .foot, end: .end),
                        Stick([P(0.02, 0.9), P(0.5, 0.92 + j(3)), P(0.98, 0.88)], 6 * u, 5 * u, name: "bar"),
                        // (One rung is left short of the far post: shut all round, the pane
                        // above it would be a place of its own, cut off.)
                        Stick([P(0.04, 0.42), P(0.36, 0.4 + j(4)), P(0.6, 0.43)], 5 * u, 4 * u, name: "bar")]
            b.visual = [P(0.11, 0.9), P(0.89, 0.88), P(0.11, 0.42)].map { k.disc($0, 6 * u) }
            b.anchors = [P(0.16, 0.85), P(0.84, 0.84), P(0.16, 0.47), P(0.84, 0.48), P(0.16, 0.37), P(0.84, 0.38), P(0.16, 0.06), P(0.84, 0.06)]
                .map { ObjectAnchor(kind: .tie, point: $0, normal: V2(0, 0)) }
        case .climbingBark:
            b.blocks = [("bark", k.climbingPanel())]
        case .moistMoss:
            b.blocks = [("saucer", Poly.clockwise([P(0.02, 0.42), P(0.98, 0.42), P(0.9, -0.04), P(0.1, -0.04)])),
                        ("moss", k.mound(from: 0.05, to: 0.95, base: 0.36, height: 0.64, bumps: 6))]
            b.anchors = [ObjectAnchor(kind: .perch, point: P(0.5, 1), normal: V2(0, 1))]
        case .shelterCanopy:
            b.sticks = [Stick([P(0.12, 0), P(0.14, 0.5), P(0.13, 0.8)], 6 * u, 5 * u, name: "leg", start: .foot, end: nil),
                        Stick([P(0.86, 0), P(0.85, 0.4), P(0.87, 0.6)], 6 * u, 5 * u, name: "leg", start: .foot, end: nil)]
            b.bars = [("roof", Stick([P(-0.02, 0.86), P(0.5, 0.8 + j(1)), P(1.02, 0.63)], 13 * u, 11 * u).outline())]
            b.visual = [HabitatShape.bar(P(0.13, 0.78), P(0.06, 0.9), 3 * u), HabitatShape.bar(P(0.13, 0.78), P(0.2, 0.9), 3 * u),
                        HabitatShape.bar(P(0.87, 0.58), P(0.8, 0.7), 3 * u), HabitatShape.bar(P(0.87, 0.58), P(0.94, 0.68), 3 * u)]
            b.stickPorts = false
            b.anchors = [ObjectAnchor(kind: .refuge, point: P(0.5, 0), normal: V2(0, 1)), ObjectAnchor(kind: .perch, point: P(0.3, 0.9), normal: V2(0, 1))]
        default:
            return nil
        }
        return b
    }
}

// MARK: - Shapes

/// Laying out one thing in its rectangle `r`: points by fraction of it,
/// and the shapes the natural things are made of.
struct NatureKit {
    let r: CGRect, s: Int, u: CGFloat

    func P(_ x: CGFloat, _ y: CGFloat) -> V2 { V2(r.minX + r.width * x, r.minY + r.height * y) }
    /// A little give or take, so no two are the same.
    func j(_ i: Int, _ a: CGFloat = 0.03) -> CGFloat { (HabitatShape.rnd(s, 60 + i) - 0.5) * 2 * a }

    func path(_ p: CGPath) -> [V2] { Poly.clockwise(Poly.outlines(p).first ?? []) }
    func disc(_ c: V2, _ rad: CGFloat) -> [V2] { path(CGPath(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2), transform: nil)) }
    func rectPts(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [V2] { Poly.clockwise([P(x0, y0), P(x1, y0), P(x1, y1), P(x0, y1)]) }

    /// An ellipse, `rx` by `ry`, turned by `tilt`.
    func ellipse(_ c: V2, _ rx: CGFloat, _ ry: CGFloat, tilt: CGFloat = 0) -> [V2] {
        Poly.clockwise((0..<24).map { i in
            let a = CGFloat(i) / 24 * 2 * .pi
            return c + V2(cos(a) * rx, sin(a) * ry).rotated(by: tilt)
        })
    }

    /// Corners cut, `n` times over: a polygon smoothed into a rounded one.
    func chaikin(_ pts: [V2], _ n: Int) -> [V2] {
        var p = pts
        for _ in 0..<n {
            var q: [V2] = []
            for i in p.indices {
                let a = p[i], b = p[(i + 1) % p.count]
                q.append(V2.lerp(a, b, 0.25))
                q.append(V2.lerp(a, b, 0.75))
            }
            p = q
        }
        return p
    }

    /// A rounded lump round `c`, `rx` by `ry`, a little uneven.
    func blob(_ c: V2, _ rx: CGFloat, _ ry: CGFloat, n: Int, seed: Int, wobble: CGFloat = 0.12) -> [V2] {
        let pts = (0..<n).map { i -> V2 in
            let a = CGFloat(i) / CGFloat(n) * 2 * .pi + 0.3
            let k = 1 - HabitatShape.rnd(s + seed, i) * wobble
            return c + V2(cos(a) * rx * k, sin(a) * ry * k)
        }
        return Poly.clockwise(chaikin(pts, 2))
    }

    /// A mound on a flat base: from `from` to `to` across, its base at
    /// `base` up, rising `height` (fractions of the rectangle), with
    /// `bumps` little rises along its top. `peak`: where its top is highest.
    func mound(from x0: CGFloat, to x1: CGFloat, base: CGFloat, height: CGFloat, bumps: Int, peak: CGFloat = 0.5) -> [V2] {
        let n = 28
        var top: [V2] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            // A dome, leaning toward its peak.
            let skew = t < peak ? t / peak * 0.5 : 0.5 + (t - peak) / (1 - peak) * 0.5
            var y = sin(skew * .pi)
            y = pow(max(y, 0), 0.7)
            // (Rounded rises: no sharp notches between them, which the
            // surfaces grown round them would fold over.)
            if bumps > 0 { y *= 1 - 0.08 * pow(sin(t * .pi * CGFloat(bumps) + CGFloat(s % 7)), 2) }
            top.append(P(x0 + (x1 - x0) * t, base + height * y))
        }
        return Poly.clockwise([P(x1, base), P(x0, base)] + top)
    }

    /// A band along the top of the rectangle (a tube's roof, seen from the
    /// side): its top at `top(x)` (x 0…1 of the band), `thick` deep, rounded at the ends.
    func band(from x0: CGFloat, to x1: CGFloat, top: (CGFloat) -> CGFloat, thick: CGFloat) -> [V2] {
        let n = 16
        var upper: [V2] = [], lower: [V2] = []
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let x = r.minX + r.width * (x0 + (x1 - x0) * t)
            let y = r.minY + r.height * top(t)
            upper.append(V2(x, y))
            lower.append(V2(x, y - thick + thick * 0.2 * sin(.pi * t)))
        }
        return Poly.clockwise(chaikin(upper + lower.reversed(), 1))
    }

    /// A floor lying on the ground (a tube's), its top at `top(x)`.
    func trough(from x0: CGFloat, to x1: CGFloat, top: (CGFloat) -> CGFloat) -> [V2] {
        let n = 14
        let upper = (0...n).map { i -> V2 in
            let t = CGFloat(i) / CGFloat(n)
            return V2(r.minX + r.width * (x0 + (x1 - x0) * t), r.minY + r.height * top(t))
        }
        return Poly.clockwise([P(x1, -0.06), P(x0, -0.06)] + upper)
    }

    /// A shell of an ellipse round `c` (a cave's roof, seen from its open
    /// end): `rx` by `ry` outside, `t` thick, from angle `a0` over the top
    /// to `a1`, rounded at the lip. Its outline, the room inside it (down to
    /// the ground), and the lip.
    func shell(_ c: V2, _ rx: CGFloat, _ ry: CGFloat, _ t: CGFloat, from a0: CGFloat, to a1: CGFloat) -> (outline: [V2], inside: [V2], lip: V2) {
        let n = 30
        func at(_ a: CGFloat, _ k: CGFloat) -> V2 { c + V2(cos(a) * (rx - k), sin(a) * (ry - k)) }
        let angles = (0...n).map { a0 + (a1 - a0) * CGFloat($0) / CGFloat(n) }
        let outer = angles.map { at($0, 0) }
        let inner = angles.reversed().map { at($0, t) }
        // Round the lip: half way round from the outside to the inside.
        let lipC = at(a1, t / 2)
        let out = (outer[n] - lipC).normalized
        let cap = (1...6).map { i in lipC + out.rotated(by: -CGFloat(i) / 7 * .pi) * (t / 2) }
        let inside = angles.map { at($0, t) } + [V2(at(a1, t).x, r.minY), V2(at(a0, t).x, r.minY)]
        return (Poly.clockwise(outer + cap + inner), Poly.clockwise(inside), lipC)
    }

    /// A leaf blade from `base`, `len` long heading `angle`, `wide` across
    /// at its widest, its midrib bowed by `bend` (a fraction of its length,
    /// + to the left of its heading). `taper`: widest at its base (a blade
    /// of grass, an aloe's leaf), not a third of the way along.
    func blade(_ base: V2, angle: CGFloat, len: CGFloat, wide: CGFloat, bend: CGFloat = 0, taper: Bool = false) -> [V2] {
        Poly.clockwise(NatureKit.blade(base, angle: angle, len: len, wide: wide, bend: bend, taper: taper).outline)
    }

    /// A leaf blade (see `blade`) added to a layout, with its midrib.
    func leaf(_ b: inout PieceBuild, _ name: String, _ base: V2, angle: CGFloat, len: CGFloat, wide: CGFloat, bend: CGFloat = 0, taper: Bool = false) {
        let l = NatureKit.blade(base, angle: angle, len: len, wide: wide, bend: bend, taper: taper)
        b.ribs[b.bars.count] = l.rib
        b.bars.append((name, Poly.clockwise(l.outline)))
    }

    static func blade(_ base: V2, angle: CGFloat, len: CGFloat, wide: CGFloat, bend: CGFloat = 0, taper: Bool = false) -> (outline: [V2], rib: [V2]) {
        let d = V2.angle(angle), n = d.perp
        let m = 14
        var left: [V2] = [], right: [V2] = [], rib: [V2] = []
        for i in 0...m {
            let t = CGFloat(i) / CGFloat(m)
            let mid = base + d * (t * len) + n * (bend * len * 4 * t * (1 - t))
            // Which way the midrib runs here, for the sides square to it.
            let dd = (d + n * (bend * 4 * (1 - 2 * t))).normalized
            let hw: CGFloat = taper ? wide / 2 * pow(1 - t, 0.85) * min(1, t * 12 + 0.35)
                                    : wide / 2 * 3.3 * pow(t, 0.75) * (1 - t)
            left.append(mid + dd.perp * hw)
            right.append(mid - dd.perp * hw)
            rib.append(mid)
        }
        return (Poly.dedupe(left + Array(right.reversed().dropFirst())), rib)
    }

    /// A mushroom's cap, its gills' middle at `c`, `half` wide each side, `tall` high.
    func cap(_ c: V2, _ half: CGFloat, _ tall: CGFloat) -> [V2] {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x - half, y: c.y))
        p.addCurve(to: CGPoint(x: c.x + half, y: c.y), control1: CGPoint(x: c.x - half * 1.02, y: c.y + tall * 1.3),
                   control2: CGPoint(x: c.x + half * 1.02, y: c.y + tall * 1.3))
        p.addQuadCurve(to: CGPoint(x: c.x - half, y: c.y), control: CGPoint(x: c.x, y: c.y - tall * 0.22))
        p.closeSubpath()
        return path(p)
    }

    /// A crystal: a prism with a point, from `base` along `angle`.
    func prism(_ base: V2, angle: CGFloat, len: CGFloat, wide: CGFloat) -> [V2] {
        let d = V2.angle(angle), n = d.perp * (wide / 2)
        return Poly.clockwise([base - n, base + n, base + n + d * (len * 0.78), base + d * len, base - n + d * (len * 0.78)])
    }

    /// A tree stump: a sawn trunk flaring into its roots at the ground.
    func stumpPath() -> CGPath {
        let p = CGMutablePath()
        p.move(to: P(-0.03, -0.04).point)
        p.addLine(to: P(1.03, -0.04).point)
        p.addQuadCurve(to: P(0.86, 0.3).point, control: P(0.88, 0.02).point)
        p.addLine(to: P(0.85, 0.86 + j(1, 0.02)).point)
        p.addQuadCurve(to: P(0.15, 0.87 + j(2, 0.02)).point, control: P(0.5, 0.96).point)
        p.addLine(to: P(0.14, 0.3).point)
        p.addQuadCurve(to: P(-0.03, -0.04).point, control: P(0.1, 0.02).point)
        p.closeSubpath()
        return p
    }

    /// A chunk of rock between `x0`–`x1` across and `y0`–`y1` up, its corners worn.
    func chunk(_ x0: CGFloat, _ x1: CGFloat, _ y0: CGFloat, _ y1: CGFloat, seed: Int) -> [V2] {
        let w = HabitatShape.rnd(s + seed, 1) * 0.04
        return Poly.clockwise(chaikin([P(x0, y0), P(x1, y0), P(x1 + w, (y0 + y1) / 2), P(x1 - 0.02, y1), P(x0 + 0.04, y1 - w), P(x0 - w, (y0 + y1) / 2)], 2))
    }

    /// A raft of sticks, seen end on: a row of round ends on crossbars.
    func raft() -> [V2] {
        let rr = min(r.height * 0.32, 8 * u)
        let n = max(4, Int((r.width - 2 * rr) / (rr * 1.9)))
        let cy = r.maxY - rr
        var top: [V2] = []
        for i in (0..<n).reversed() {
            let cx = r.minX + rr + (r.width - 2 * rr) * CGFloat(i) / CGFloat(n - 1)
            for k in 0...6 { top.append(V2(cx, cy) + V2.angle(CGFloat(k) / 6 * .pi) * rr) }
        }
        return Poly.clockwise(Poly.dedupe([V2(r.minX, r.minY + r.height * 0.04), V2(r.maxX, r.minY + r.height * 0.04), V2(r.maxX, cy)] + top + [V2(r.minX, cy)]))
    }

    /// A pine cone, stood on its base: widest low down, drawing in to its
    /// tip. (Its scales are painted: a toothed outline, grown round, folds.)
    func pineCone() -> [V2] {
        var left: [V2] = [], right: [V2] = []
        let n = 8
        for i in 0...n {
            let t = CGFloat(i) / CGFloat(n)
            let half = r.width * 0.5 * (0.55 + 0.45 * sin(min(1, t * 1.6 + 0.25) * .pi * 0.5)) * (1 - t * 0.72)
            let y = r.minY + r.height * (0.02 + 0.94 * t)
            left.append(V2(r.midX - half, y))
            right.append(V2(r.midX + half, y))
        }
        return Poly.clockwise(chaikin(right + [V2(r.midX, r.maxY)] + left.reversed() + [V2(r.midX, r.minY)], 2))
    }

    /// A conch lying on its side: a round body tapering to a spire.
    func conch() -> CGPath {
        let p = CGMutablePath()
        p.move(to: P(0.02, 0.4).point)
        p.addCurve(to: P(0.46, 0.98).point, control1: P(0.0, 0.8).point, control2: P(0.22, 1.02).point)
        p.addCurve(to: P(0.99, 0.5).point, control1: P(0.7, 0.92).point, control2: P(0.9, 0.62).point)
        p.addCurve(to: P(0.5, 0.02).point, control1: P(0.86, 0.34).point, control2: P(0.72, 0.04).point)
        p.addCurve(to: P(0.02, 0.4).point, control1: P(0.24, -0.02).point, control2: P(0.04, 0.12).point)
        p.closeSubpath()
        return p
    }

    /// A panel of bark up the back wall, with ledges of bark sticking out
    /// of its sides every so often: footholds.
    func climbingPanel() -> [V2] {
        let step = 44 * u
        let n = max(2, Int(r.height / step))
        var right: [V2] = [], left: [V2] = []
        for i in 0..<n {
            let y0 = r.minY + r.height * CGFloat(i) / CGFloat(n), y1 = r.minY + r.height * CGFloat(i + 1) / CGFloat(n)
            let out = (8 + HabitatShape.rnd(s, i) * 6) * u
            let rx = r.maxX - 12 * u, lx = r.minX + 12 * u
            // Out from the panel to a ledge, then back in.
            right += [V2(rx, y0), V2(rx + out * 0.2, y0 + (y1 - y0) * 0.45), V2(rx + out, y0 + (y1 - y0) * 0.62), V2(rx + out * 0.6, y0 + (y1 - y0) * 0.72)]
            let off = (y1 - y0) * 0.5
            left += [V2(lx, y0), V2(lx - out * 0.2, y0 + off * 0.3), V2(lx - out * 0.9, y0 + off * 0.9), V2(lx - out * 0.5, y0 + off * 1.1)]
        }
        right.append(V2(r.maxX - 12 * u, r.maxY))
        left.append(V2(r.minX + 12 * u, r.maxY))
        return Poly.clockwise(right + left.reversed())
    }

    /// Where something only to look at is drawn, roughly.
    func lookArea(_ kind: HabitatItemKind) -> [V2] {
        switch kind {
        case .airPlant, .smallFern, .glowMushrooms, .tinyMushrooms, .acorn, .lichen:
            return ellipse(P(0.5, 0.45), r.width * 0.48, r.height * 0.5)
        default:
            return Poly.outlines(CGPath(roundedRect: r, cornerWidth: min(r.width, r.height) * 0.45, cornerHeight: min(r.width, r.height) * 0.45, transform: nil)).first ?? []
        }
    }

    // A mushroom cluster's mushrooms: across, how tall (0…1), and how wide.
    static let cluster: [(x: CGFloat, h: CGFloat, w: CGFloat)] = [(0.2, 0.62, 0.3), (0.42, 1, 0.36), (0.62, 0.72, 0.3), (0.8, 0.46, 0.26), (0.93, 0.28, 0.16)]
    // A crystal cluster's crystals: across, leaning, how long, how wide.
    static let crystals: [(x: CGFloat, lean: CGFloat, len: CGFloat, w: CGFloat)] = [(0.22, 0.55, 0.55, 0.13), (0.36, 0.22, 0.8, 0.15), (0.5, -0.04, 0.95, 0.17),
                                                                                   (0.64, -0.3, 0.72, 0.14), (0.78, -0.62, 0.5, 0.12), (0.44, 0.7, 0.36, 0.1)]
    // A twig pile's twigs: from (x, y) to (x, y).
    static let twigs: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0.0, 0.1, 0.9, 0.3), (0.1, 0.5, 0.95, 0.12), (0.2, 0.05, 0.6, 0.95), (0.45, 0.9, 0.98, 0.35),
                                                                (0.05, 0.28, 0.5, 0.7), (0.6, 0.06, 0.8, 0.72), (0.3, 0.3, 1.0, 0.55)]
}
