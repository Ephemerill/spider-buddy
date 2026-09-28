import AppKit

// MARK: - Painting a home
//
// The pieces a house is built from (floors, walls, doors, windows, a roof,
// stairs), the walls at the back of its rooms, and what goes in them:
// furniture, lamps, pictures, little things. Painted from their layouts
// (HabitatPieces.swift) like everything else, in warm, cosy colours —
// this is somewhere to live, not a diagram of one.
//
// Things fixed to the back wall are fixed to whatever is there: over a
// backing wall they are screwed or nailed into it; over nothing but the
// glass at the back, they hold on with suction cups.

extension HabitatArt {
    /// Cosy fabric colours, one per seed.
    static func fabric(_ s: Int, _ k: Int = 0) -> CGColor {
        let all = [c(0.74, 0.32, 0.28), c(0.3, 0.46, 0.68), c(0.38, 0.58, 0.4), c(0.86, 0.66, 0.3),
                   c(0.56, 0.38, 0.62), c(0.9, 0.56, 0.5), c(0.3, 0.6, 0.62), c(0.78, 0.46, 0.2)]
        return all[abs(s * 7 + k * 3) % all.count]
    }

    static func roundRect(_ r: CGRect, _ rad: CGFloat) -> CGPath {
        let k = max(0, min(rad, r.width / 2, r.height / 2))
        return CGPath(roundedRect: r, cornerWidth: k, cornerHeight: k, transform: nil)
    }

    /// A shape filled with a colour, lit from above, and outlined.
    static func solid(_ ctx: CGContext, _ p: CGPath, _ col: CGColor, _ u: CGFloat, light: CGFloat = 0.14, line: Bool = true) {
        let b = p.boundingBox
        fill(ctx, p, [shade(col, light), col, shade(col, -light * 1.4)], [0, 0.5, 1],
             from: CGPoint(x: b.midX, y: b.maxY), to: CGPoint(x: b.midX, y: b.minY))
        if line { outline(ctx, p, col, u) }
    }

    static func label(_ ctx: CGContext, _ text: String, in r: CGRect, size: CGFloat, colour: CGColor, weight: NSFont.Weight = .heavy) {
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: colour) ?? .white]))
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: r.midX - CGFloat(w) / 2, y: r.midY - size * 0.35)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// How something on the back wall holds on at `p`: a nail (over a
    /// backing wall) or a little suction cup on the glass.
    static func hangPoint(_ ctx: CGContext, at p: V2, backed: Bool, _ u: CGFloat) {
        if backed {
            ctx.setFillColor(c(0.5, 0.5, 0.52))
            ctx.fillEllipse(in: CGRect(x: p.x - 1.6 * u, y: p.y - 1.6 * u, width: 3.2 * u, height: 3.2 * u))
        } else {
            suction(ctx, at: p, 4.5 * u, u)
        }
    }

    /// A clear suction cup pressed on the glass at the back.
    static func suction(_ ctx: CGContext, at p: V2, _ rad: CGFloat, _ u: CGFloat) {
        let r = CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2)
        ctx.saveGState()
        radial(ctx, [c(0.95, 0.98, 1, 0.5), c(0.85, 0.9, 0.95, 0.28), c(0.85, 0.9, 0.95, 0.12)], [0, 0.7, 1], at: p.point, radius: rad)
        ctx.setStrokeColor(c(1, 1, 1, 0.65))
        ctx.setLineWidth(0.8 * u)
        ctx.strokeEllipse(in: r)
        ctx.setFillColor(c(1, 1, 1, 0.7))
        ctx.fillEllipse(in: CGRect(x: p.x - rad * 0.55, y: p.y + rad * 0.2, width: rad * 0.45, height: rad * 0.3))
        // Its little stem.
        ctx.setFillColor(c(0.8, 0.84, 0.88, 0.7))
        ctx.fillEllipse(in: CGRect(x: p.x - rad * 0.28, y: p.y - rad * 0.28, width: rad * 0.56, height: rad * 0.56))
        ctx.restoreGState()
    }

    /// A little flame, its foot at `p`, `h` tall.
    static func flame(_ ctx: CGContext, at p: CGPoint, _ h: CGFloat) {
        radial(ctx, [c(1, 0.85, 0.4, 0.55), c(1, 0.7, 0.3, 0)], at: CGPoint(x: p.x, y: p.y + h * 0.5), radius: h * 1.3)
        let outer = CGMutablePath()
        outer.move(to: p)
        outer.addQuadCurve(to: CGPoint(x: p.x, y: p.y + h), control: CGPoint(x: p.x - h * 0.55, y: p.y + h * 0.35))
        outer.addQuadCurve(to: p, control: CGPoint(x: p.x + h * 0.55, y: p.y + h * 0.35))
        ctx.addPath(outer)
        ctx.setFillColor(c(1, 0.6, 0.15))
        ctx.fillPath()
        ctx.setFillColor(c(1, 0.92, 0.55))
        ctx.fillEllipse(in: CGRect(x: p.x - h * 0.14, y: p.y + h * 0.08, width: h * 0.28, height: h * 0.45))
    }

    /// A lit bulb: bright, with a halo.
    static func bulb(_ ctx: CGContext, at p: CGPoint, _ rad: CGFloat, _ col: CGColor) {
        radial(ctx, [alpha(col, 0.55), alpha(col, 0)], at: p, radius: rad * 3.2)
        ctx.setFillColor(shade(col, 0.35))
        ctx.fillEllipse(in: CGRect(x: p.x - rad, y: p.y - rad, width: rad * 2, height: rad * 2))
        ctx.setFillColor(c(1, 1, 0.95, 0.9))
        ctx.fillEllipse(in: CGRect(x: p.x - rad * 0.4, y: p.y - rad * 0.1, width: rad * 0.6, height: rad * 0.6))
    }

    /// Glass: pale and see-through, with a glint.
    static func glass(_ ctx: CGContext, _ r: CGRect, _ u: CGFloat) {
        ctx.setFillColor(c(0.78, 0.9, 0.98, 0.35))
        ctx.fill(r)
        ctx.saveGState()
        ctx.clip(to: r)
        ctx.setStrokeColor(c(1, 1, 1, 0.55))
        ctx.setLineWidth(max(1.2 * u, r.width * 0.12))
        ctx.move(to: CGPoint(x: r.minX + r.width * 0.2, y: r.minY + r.height * 0.3))
        ctx.addLine(to: CGPoint(x: r.minX + r.width * 0.6, y: r.maxY - r.height * 0.1))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A picture's subject, one of several by its seed, in `r`.
    static func scene(_ ctx: CGContext, _ r: CGRect, _ s: Int, _ u: CGFloat) {
        ctx.saveGState()
        ctx.clip(to: r)
        switch abs(s) % 6 {
        case 0:
            // Hills under a sky.
            linear(ctx, [c(0.55, 0.75, 0.95), c(0.9, 0.92, 0.85)], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
            ctx.setFillColor(c(1, 0.92, 0.6)); ctx.fillEllipse(in: CGRect(x: r.maxX - r.width * 0.32, y: r.maxY - r.height * 0.4, width: r.height * 0.24, height: r.height * 0.24))
            for (k, col) in [c(0.45, 0.62, 0.4), c(0.32, 0.5, 0.32)].enumerated() {
                let p = CGMutablePath()
                let y = r.minY + r.height * (0.45 - CGFloat(k) * 0.15)
                p.move(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX, y: y))
                p.addQuadCurve(to: CGPoint(x: r.maxX, y: y - r.height * 0.05), control: CGPoint(x: r.midX + (CGFloat(k) - 0.5) * r.width * 0.6, y: y + r.height * 0.3))
                p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.closeSubpath()
                ctx.addPath(p); ctx.setFillColor(col); ctx.fillPath()
            }
        case 1:
            // A sunset over the sea.
            linear(ctx, [c(0.4, 0.3, 0.6), c(0.98, 0.55, 0.35), c(1, 0.85, 0.5)], [0, 0.6, 1], from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.midY))
            ctx.setFillColor(c(1, 0.8, 0.4)); ctx.fillEllipse(in: CGRect(x: r.midX - r.height * 0.16, y: r.midY - r.height * 0.1, width: r.height * 0.32, height: r.height * 0.32))
            ctx.setFillColor(c(0.2, 0.3, 0.5)); ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height * 0.45))
            ctx.setStrokeColor(c(1, 0.75, 0.45, 0.8)); ctx.setLineWidth(1 * u)
            for k in 0..<3 { let y = r.minY + r.height * (0.36 - CGFloat(k) * 0.1); ctx.move(to: CGPoint(x: r.midX - r.width * 0.15, y: y)); ctx.addLine(to: CGPoint(x: r.midX + r.width * 0.15, y: y)) }
            ctx.strokePath()
        case 2:
            // A portrait of a fly, very distinguished.
            ctx.setFillColor(c(0.36, 0.22, 0.16)); ctx.fill(r)
            let cx = r.midX, cy = r.midY
            ctx.setFillColor(c(0.82, 0.88, 0.95, 0.8))
            ctx.fillEllipse(in: CGRect(x: cx - r.width * 0.3, y: cy, width: r.width * 0.26, height: r.height * 0.3))
            ctx.fillEllipse(in: CGRect(x: cx + r.width * 0.04, y: cy, width: r.width * 0.26, height: r.height * 0.3))
            ctx.setFillColor(c(0.12, 0.14, 0.12)); ctx.fillEllipse(in: CGRect(x: cx - r.width * 0.14, y: r.minY + r.height * 0.1, width: r.width * 0.28, height: r.height * 0.55))
            ctx.setFillColor(c(0.7, 0.12, 0.1))
            ctx.fillEllipse(in: CGRect(x: cx - r.width * 0.15, y: r.minY + r.height * 0.55, width: r.width * 0.12, height: r.width * 0.12))
            ctx.fillEllipse(in: CGRect(x: cx + r.width * 0.03, y: r.minY + r.height * 0.55, width: r.width * 0.12, height: r.width * 0.12))
        case 3:
            // Bold shapes.
            ctx.setFillColor(c(0.95, 0.92, 0.84)); ctx.fill(r)
            ctx.setFillColor(c(0.86, 0.3, 0.25)); ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.1, y: r.minY + r.height * 0.35, width: r.width * 0.4, height: r.width * 0.4))
            ctx.setFillColor(c(0.2, 0.4, 0.7)); ctx.fill(CGRect(x: r.midX, y: r.minY + r.height * 0.1, width: r.width * 0.35, height: r.height * 0.5))
            ctx.setFillColor(c(0.95, 0.75, 0.2)); ctx.fill(CGRect(x: r.minX + r.width * 0.3, y: r.minY + r.height * 0.1, width: r.width * 0.5, height: r.height * 0.12))
        case 4:
            // Flowers in a jug.
            ctx.setFillColor(c(0.3, 0.4, 0.36)); ctx.fill(r)
            ctx.setFillColor(c(0.8, 0.7, 0.5)); ctx.fill(CGRect(x: r.midX - r.width * 0.12, y: r.minY + r.height * 0.08, width: r.width * 0.24, height: r.height * 0.36))
            for k in 0..<6 {
                let a = CGFloat(k) / 6 * .pi + 0.2
                let p = CGPoint(x: r.midX + cos(a) * r.width * 0.25, y: r.minY + r.height * 0.5 + sin(a) * r.height * 0.3)
                ctx.setFillColor([c(0.95, 0.5, 0.5), c(0.98, 0.85, 0.4), c(0.9, 0.9, 0.95)][k % 3])
                ctx.fillEllipse(in: CGRect(x: p.x - r.width * 0.07, y: p.y - r.width * 0.07, width: r.width * 0.14, height: r.width * 0.14))
            }
        default:
            // A web at night.
            ctx.setFillColor(c(0.12, 0.14, 0.24)); ctx.fill(r)
            ctx.setFillColor(c(0.95, 0.95, 0.85)); ctx.fillEllipse(in: CGRect(x: r.maxX - r.width * 0.28, y: r.maxY - r.height * 0.34, width: r.height * 0.2, height: r.height * 0.2))
            ctx.setStrokeColor(c(0.9, 0.92, 1, 0.8)); ctx.setLineWidth(0.6 * u)
            let cc = CGPoint(x: r.minX + r.width * 0.4, y: r.midY)
            for k in 0..<8 {
                let a = CGFloat(k) / 8 * 2 * .pi
                ctx.move(to: cc); ctx.addLine(to: CGPoint(x: cc.x + cos(a) * r.width, y: cc.y + sin(a) * r.width))
            }
            for k in 1...4 { let rr = r.height * 0.1 * CGFloat(k); ctx.addEllipse(in: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2)) }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    /// A frame round `r`, `t` thick: gilt, or wood.
    static func frame(_ ctx: CGContext, _ r: CGRect, _ t: CGFloat, gilt: Bool, _ u: CGFloat) {
        let outer = r.insetBy(dx: -t, dy: -t)
        let p = CGMutablePath()
        p.addRect(outer)
        p.addRect(r)
        ctx.saveGState()
        ctx.addPath(p)
        ctx.clip(using: .evenOdd)
        let col = gilt ? c(0.86, 0.68, 0.3) : c(0.45, 0.3, 0.18)
        linear(ctx, [shade(col, 0.3), col, shade(col, -0.35)], [0, 0.5, 1], from: CGPoint(x: outer.minX, y: outer.maxY), to: CGPoint(x: outer.maxX, y: outer.minY))
        ctx.restoreGState()
        ctx.setStrokeColor(alpha(shade(col, -0.5), 0.8))
        ctx.setLineWidth(0.8 * u)
        ctx.stroke(outer)
        ctx.stroke(r)
    }

    /// Paints a piece of a home (true), or leaves it (false: not one).
    /// A door's face (or a casement's), seen swung open, filling `r`.
    static func paintLeafFace(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        if kind == .door || kind == .doorClosed {
            let col = fabric(s, 1)
            solid(ctx, roundRect(r, 1.5 * u), col, u, light: 0.1)
            ctx.setStrokeColor(alpha(shade(col, -0.4), 0.6))
            ctx.setLineWidth(0.8 * u)
            let inset = r.insetBy(dx: r.width * 0.18, dy: r.height * 0.08)
            ctx.stroke(CGRect(x: inset.minX, y: inset.midY + 2 * u, width: inset.width, height: inset.height / 2 - 2 * u))
            ctx.stroke(CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: inset.height / 2 - 2 * u))
            ctx.setFillColor(c(0.95, 0.78, 0.35))
            ctx.fillEllipse(in: CGRect(x: r.maxX - max(r.width * 0.26, 4 * u), y: r.minY + r.height * 0.45, width: 3.4 * u, height: 3.4 * u))
        } else {
            solid(ctx, CGPath(rect: r, transform: nil), c(0.95, 0.93, 0.88), u, light: 0.08)
            glass(ctx, r.insetBy(dx: max(2 * u, r.width * 0.16), dy: max(2 * u, r.height * 0.1)), u)
        }
    }

    /// A door (or a window's glass) shut: its edge, in the opening.
    static func paintLeafEdge(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat, _ ctx: CGContext) {
        if kind == .door || kind == .doorClosed {
            solid(ctx, roundRect(r, 1 * u), shade(fabric(s, 1), -0.05), u * 0.8, light: 0.1)
            ctx.setFillColor(c(0.95, 0.78, 0.35))
            for x in [r.minX - 2.2 * u, r.maxX - 0.6 * u] { ctx.fillEllipse(in: CGRect(x: x, y: r.minY + r.height * 0.45, width: 2.8 * u, height: 2.8 * u)) }
        } else {
            glass(ctx, r, u)
            ctx.setFillColor(c(1, 1, 1, 0.5))
            ctx.fill(CGRect(x: r.minX, y: r.midY - 0.8 * u, width: r.width, height: 1.6 * u))
        }
    }

    static func paintHome(_ kind: HabitatItemKind, _ r: CGRect, _ s: Int, _ u: CGFloat, _ biome: Biome, backed: Bool, leaf: Bool = true, _ ctx: CGContext) -> Bool {
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + r.width * x, y: r.minY + r.height * y) }
        func R(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> CGRect {
            CGRect(x: r.minX + r.width * x0, y: r.minY + r.height * y0, width: r.width * (x1 - x0), height: r.height * (y1 - y0))
        }
        let b = HabitatShape.piece(kind, r, s, u, leaves: false)
        let (light, mid, dark) = woodColours(s)
        // (A wall at the back is painted to its edges and no further.)
        if kind.isBacking {
            ctx.saveGState()
            ctx.clip(to: r)
        }
        defer { if kind.isBacking { ctx.restoreGState() } }
        switch kind {
        // MARK: Building
        case .floorboards:
            paintBoard(ctx, r, s, u, upright: false, pale: -0.04)
            ctx.setStrokeColor(c(0.3, 0.2, 0.12, 0.55))
            ctx.setLineWidth(0.9 * u)
            var x = r.minX + (30 + rnd(s, 1) * 20) * u
            var k = 0
            while x < r.maxX - 8 * u {
                ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY))
                x += (44 + rnd(s, k) * 30) * u
                k += 1
            }
            ctx.strokePath()
        case .wall:
            paintBoard(ctx, r, s, u, upright: true, pale: -0.08)
            for y in stride(from: r.minY + 20 * u, to: r.maxY - 6 * u, by: 46 * u) { screw(ctx, at: V2(r.midX, y), u * 0.7, wood: true) }
        case .door, .doorClosed, .window, .windowOpen:
            let isDoor = kind == .door || kind == .doorClosed
            let (lo, hi) = HabitatShape.opening(kind, r, u)
            let x0 = r.minX + r.width * (isDoor ? 0.35 : 0.3), x1 = r.minX + r.width * (isDoor ? 0.65 : 0.7)
            // Through the opening, the frame's lining: the doorway is solid
            // all round, never a slit onto the air behind.
            let reveal = CGRect(x: x0, y: lo, width: x1 - x0, height: hi - lo)
            fill(ctx, CGPath(rect: reveal, transform: nil), [shade(mid, -0.45), shade(mid, -0.25), shade(mid, -0.45)], [0, 0.5, 1],
                 from: CGPoint(x: reveal.minX, y: 0), to: CGPoint(x: reveal.maxX, y: 0))
            ctx.setFillColor(c(0, 0, 0, 0.18))
            ctx.fill(CGRect(x: reveal.minX, y: reveal.maxY - 3 * u, width: reveal.width, height: 3 * u))
            for blk in b.blocks where blk.name == "sill" || blk.name == "lintel" {
                paintBoard(ctx, Poly.bounds(blk.outline), s, u, upright: true, pale: -0.08)
            }
            // The frame round the opening.
            ctx.setFillColor(c(0.94, 0.9, 0.82))
            ctx.fill(CGRect(x: x0 - 1.5 * u, y: hi - 2.5 * u, width: x1 - x0 + 3 * u, height: 3 * u))
            if !isDoor { ctx.fill(CGRect(x: x0 - 3 * u, y: lo - 1 * u, width: x1 - x0 + 6 * u, height: 3 * u)) }
            if leaf {
                let g = HabitatShape.leaf(kind, r, u)
                if kind.leafOpen == true {
                    paintLeafFace(kind, CGRect(x: g.face.minX, y: g.face.minY, width: g.face.width * 0.86, height: g.face.height), s, u, ctx)
                } else {
                    paintLeafEdge(kind, g.edge, s, u, ctx)
                }
            }
        case .gableRoof:
            guard let blk = b.blocks.first else { break }
            // The gable end under it, planked: the back of the attic.
            let t = min(0.14, 18 * u / r.width), rise = min(0.3, 20 * u / r.height)
            let gable = CGMutablePath()
            gable.move(to: P(t * 0.6, 0)); gable.addLine(to: P(0.5, 1 - rise * 0.6)); gable.addLine(to: P(1 - t * 0.6, 0)); gable.closeSubpath()
            ctx.saveGState()
            ctx.addPath(gable)
            ctx.clip()
            paintBoard(ctx, gable.boundingBox, s + 9, u, upright: true, pale: -0.16)
            ctx.setFillColor(c(0, 0, 0, 0.18))
            ctx.fill(gable.boundingBox)
            // A little round vent.
            let v = P(0.5, 0.42), vr = min(r.height * 0.1, 9 * u)
            ctx.setFillColor(c(0.12, 0.08, 0.05))
            ctx.fillEllipse(in: CGRect(x: v.x - vr, y: v.y - vr, width: vr * 2, height: vr * 2))
            ctx.restoreGState()
            let p = polyPath(blk.outline)
            let tile = [c(0.62, 0.28, 0.22), c(0.36, 0.4, 0.46), c(0.3, 0.44, 0.34), c(0.52, 0.36, 0.26)][abs(s) % 4]
            solid(ctx, p, tile, u, light: 0.12, line: false)
            ctx.saveGState()
            ctx.addPath(p)
            ctx.clip()
            // Rows of shingles, and the joints between them.
            let row = 9 * u
            var y = r.minY + row, k = 0
            while y < r.maxY {
                ctx.setStrokeColor(alpha(shade(tile, -0.45), 0.7))
                ctx.setLineWidth(1 * u)
                ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y)); ctx.strokePath()
                var x = r.minX + (k % 2 == 0 ? 0 : 7 * u)
                ctx.setLineWidth(0.7 * u)
                while x < r.maxX {
                    ctx.move(to: CGPoint(x: x, y: y - row)); ctx.addLine(to: CGPoint(x: x, y: y)); x += 14 * u
                }
                ctx.strokePath()
                y += row; k += 1
            }
            ctx.restoreGState()
            outline(ctx, p, tile, u * 1.3)
        case .stairs:
            guard let blk = b.blocks.first else { break }
            let p = polyPath(blk.outline)
            solid(ctx, p, mid, u, light: 0.08)
            let n = 5
            for k in 0..<n {
                let top = r.minY + r.height * CGFloat(n - k) / CGFloat(n), x0 = r.minX + r.width * CGFloat(n - k - 1) / CGFloat(n)
                ctx.setFillColor(c(1, 1, 1, 0.22))
                ctx.fill(CGRect(x: x0, y: top - 2.5 * u, width: r.width / CGFloat(n), height: 2.5 * u))
                ctx.setFillColor(c(0, 0, 0, 0.12))
                ctx.fill(CGRect(x: x0, y: r.minY, width: 1.2 * u, height: top - r.minY))
            }
        case .kneeBrace:
            if let bar = b.bars.first {
                let p = polyPath(bar.outline)
                solid(ctx, p, mid, u)
                for q in [P(0.14, 0.14), P(0.86, 0.86)] { screw(ctx, at: V2(q), u * 0.8, wood: true) }
            }
        case .fence:
            let paint = abs(s) % 2 == 0 ? c(0.95, 0.94, 0.9) : shade(mid, 0.1)
            for bar in b.bars { solid(ctx, polyPath(bar.outline), paint, u * 0.8, light: 0.08) }
        // MARK: Backing walls
        case .woodBacking, .logBacking:
            let base = kind == .logBacking ? c(0.5, 0.34, 0.2) : c(0.58, 0.42, 0.27)
            ctx.setFillColor(base)
            ctx.fill(r)
            let plank = (kind == .logBacking ? 22 : 16) * u
            var y = r.minY, k = 0
            while y < r.maxY {
                let row = CGRect(x: r.minX, y: y, width: r.width, height: min(plank, r.maxY - y))
                let tone = shade(base, (rnd(s, k) - 0.5) * 0.16)
                if kind == .logBacking {
                    // A log lying along: round, lit on top, its end showing
                    // at each side.
                    let log = row.insetBy(dx: -row.height, dy: 0.6 * u)
                    if log.height > 1 {
                        ctx.saveGState()
                        ctx.addPath(roundRect(log, log.height / 2))
                        ctx.clip()
                        linear(ctx, [shade(tone, 0.16), tone, shade(tone, -0.32)], [0, 0.45, 1], from: CGPoint(x: log.midX, y: log.maxY), to: CGPoint(x: log.midX, y: log.minY))
                        ctx.restoreGState()
                        ctx.setStrokeColor(c(0.2, 0.12, 0.06, 0.5))
                        ctx.setLineWidth(0.8 * u)
                        ctx.move(to: CGPoint(x: r.minX, y: log.midY + (rnd(s, k) - 0.5) * 3 * u))
                        ctx.addLine(to: CGPoint(x: r.maxX, y: log.midY + (rnd(s, k + 7) - 0.5) * 3 * u))
                        ctx.strokePath()
                    }
                } else {
                    ctx.setFillColor(tone)
                    ctx.fill(row)
                    ctx.setFillColor(c(0, 0, 0, 0.35))
                    ctx.fill(CGRect(x: r.minX, y: y, width: r.width, height: 1 * u))
                    var x = r.minX + rnd(s, k + 30) * 80 * u
                    while x < r.maxX {
                        ctx.fill(CGRect(x: x, y: y, width: 1 * u, height: row.height))
                        screw(ctx, at: V2(x + 4 * u, y + row.height / 2), u * 0.55, wood: true)
                        x += (70 + rnd(s, Int(x)) * 40) * u
                    }
                }
                y += plank; k += 1
            }
            // (A touch darker at the back.)
            ctx.setFillColor(c(0, 0, 0, 0.12))
            ctx.fill(r)
        case .brickBacking:
            let base = [c(0.64, 0.32, 0.24), c(0.56, 0.36, 0.3), c(0.82, 0.78, 0.72)][abs(s) % 3]
            ctx.setFillColor(c(0.72, 0.68, 0.62))
            ctx.fill(r)
            let bh = 9 * u, bw = 24 * u
            var y = r.minY, k = 0
            while y < r.maxY {
                var x = r.minX - (k % 2 == 0 ? 0 : bw / 2)
                var j = 0
                while x < r.maxX {
                    ctx.setFillColor(shade(base, (rnd(s + k, j) - 0.5) * 0.2))
                    ctx.fill(CGRect(x: x + 0.8 * u, y: y + 0.8 * u, width: bw - 1.6 * u, height: bh - 1.6 * u))
                    x += bw; j += 1
                }
                y += bh; k += 1
            }
            ctx.setFillColor(c(0, 0, 0, 0.14))
            ctx.fill(r)
        case .stoneBacking:
            ctx.setFillColor(c(0.36, 0.36, 0.38))
            ctx.fill(r)
            var y = r.minY, k = 0
            while y < r.maxY {
                let h = (14 + rnd(s, k) * 8) * u
                var x = r.minX - rnd(s, k + 9) * 20 * u
                var j = 0
                while x < r.maxX {
                    let w = (22 + rnd(s + k, j) * 20) * u
                    let tone = c(0.56 + rnd(s + 2, j + k) * 0.12, 0.55 + rnd(s + 2, j + k) * 0.1, 0.52 + rnd(s + 2, j + k) * 0.1)
                    solid(ctx, roundRect(CGRect(x: x + 1 * u, y: y + 1 * u, width: w - 2 * u, height: h - 2 * u), 4 * u), tone, u * 0.6, light: 0.1, line: false)
                    x += w; j += 1
                }
                y += h; k += 1
            }
            ctx.setFillColor(c(0, 0, 0, 0.14))
            ctx.fill(r)
        case .wallpaper:
            let base = shade(fabric(s, 2), 0.3)
            ctx.setFillColor(base)
            ctx.fill(r)
            ctx.saveGState()
            ctx.clip(to: r)
            switch abs(s / 3) % 3 {
            case 0:
                ctx.setFillColor(alpha(shade(base, -0.2), 0.5))
                var x = r.minX
                while x < r.maxX { ctx.fill(CGRect(x: x, y: r.minY, width: 5 * u, height: r.height)); x += 14 * u }
            case 1:
                ctx.setFillColor(alpha(c(1, 1, 1), 0.35))
                var y = r.minY + 6 * u, k = 0
                while y < r.maxY {
                    var x = r.minX + (k % 2 == 0 ? 6 : 15) * u
                    while x < r.maxX { ctx.fillEllipse(in: CGRect(x: x - 2 * u, y: y - 2 * u, width: 4 * u, height: 4 * u)); x += 18 * u }
                    y += 14 * u; k += 1
                }
            default:
                var y = r.minY + 10 * u, k = 0
                while y < r.maxY {
                    var x = r.minX + (k % 2 == 0 ? 10 : 24) * u
                    while x < r.maxX {
                        for q in 0..<5 {
                            let a = CGFloat(q) / 5 * 2 * .pi
                            ctx.setFillColor(alpha(c(1, 1, 1), 0.4))
                            ctx.fillEllipse(in: CGRect(x: x + cos(a) * 2.6 * u - 1.8 * u, y: y + sin(a) * 2.6 * u - 1.8 * u, width: 3.6 * u, height: 3.6 * u))
                        }
                        ctx.setFillColor(c(0.98, 0.85, 0.4, 0.7))
                        ctx.fillEllipse(in: CGRect(x: x - 1.4 * u, y: y - 1.4 * u, width: 2.8 * u, height: 2.8 * u))
                        x += 28 * u
                    }
                    y += 22 * u; k += 1
                }
            }
            // A wooden dado rail, and panelling under it.
            let dado = r.minY + min(r.height * 0.3, 40 * u)
            ctx.setFillColor(shade(mid, -0.05))
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: dado - r.minY))
            ctx.setFillColor(shade(mid, 0.2))
            ctx.fill(CGRect(x: r.minX, y: dado - 2.5 * u, width: r.width, height: 3 * u))
            ctx.restoreGState()
            ctx.setFillColor(c(0, 0, 0, 0.1))
            ctx.fill(r)
        case .backWindow:
            let pane = r.insetBy(dx: 6 * u, dy: 6 * u)
            let p = palette(biome)
            linear(ctx, [p.skyTop, p.skyMid, p.skyLow], [0, 0.6, 1], from: CGPoint(x: 0, y: pane.maxY), to: CGPoint(x: 0, y: pane.minY))
            ctx.setFillColor(alpha(p.far, 0.9))
            ctx.fill(CGRect(x: pane.minX, y: pane.minY, width: pane.width, height: pane.height * 0.3))
            glass(ctx, pane, u)
            ctx.setFillColor(c(0.95, 0.93, 0.88))
            ctx.fill(CGRect(x: pane.midX - 1.5 * u, y: pane.minY, width: 3 * u, height: pane.height))
            ctx.fill(CGRect(x: pane.minX, y: pane.midY - 1.5 * u, width: pane.width, height: 3 * u))
            frame(ctx, pane, 5 * u, gilt: false, u)
            ctx.setFillColor(c(0.95, 0.93, 0.88))
            ctx.fill(CGRect(x: r.minX, y: r.minY, width: r.width, height: 4 * u))
            hangPoint(ctx, at: V2(r.midX, r.maxY - 3 * u), backed: backed, u)
        // MARK: Home
        case .bed:
            let box = R(0, 0, 1, 0.78)
            solid(ctx, roundRect(box, 2 * u), c(0.9, 0.84, 0.7), u)
            // The matchbox's label down its side.
            ctx.setFillColor(fabric(s))
            ctx.fill(box.insetBy(dx: box.width * 0.08, dy: box.height * 0.22))
            ctx.setFillColor(c(1, 0.95, 0.85))
            ctx.fillEllipse(in: CGRect(x: box.midX - box.height * 0.16, y: box.midY - box.height * 0.16, width: box.height * 0.32, height: box.height * 0.32))
            // A patchwork blanket, and a pillow.
            let blanket = R(0.02, 0.66, 0.66, 0.86)
            solid(ctx, roundRect(blanket, 4 * u), fabric(s, 3), u)
            ctx.setStrokeColor(c(1, 1, 1, 0.35)); ctx.setLineWidth(0.7 * u)
            for k in 1..<4 { let x = blanket.minX + blanket.width * CGFloat(k) / 4; ctx.move(to: CGPoint(x: x, y: blanket.minY)); ctx.addLine(to: CGPoint(x: x, y: blanket.maxY)) }
            ctx.strokePath()
            solid(ctx, roundRect(R(0.64, 0.72, 0.96, 0.96), 6 * u), c(0.97, 0.96, 0.93), u)
        case .table, .desk:
            for bar in b.bars { solid(ctx, polyPath(bar.outline), mid, u) }
            for blk in b.blocks {
                let bb = Poly.bounds(blk.outline)
                if blk.name == "drawers" {
                    paintBoard(ctx, bb, s + 2, u, upright: true, pale: -0.04)
                    for k in 0..<3 {
                        let y = bb.minY + bb.height * (CGFloat(k) + 0.5) / 3
                        ctx.setFillColor(c(0, 0, 0, 0.3)); ctx.fill(CGRect(x: bb.minX + 2 * u, y: bb.minY + bb.height * CGFloat(k) / 3, width: bb.width - 4 * u, height: 0.8 * u))
                        ctx.setFillColor(c(0.95, 0.8, 0.4)); ctx.fillEllipse(in: CGRect(x: bb.midX - 2 * u, y: y - 1.5 * u, width: 4 * u, height: 3 * u))
                    }
                } else {
                    paintBoard(ctx, bb, s, u, upright: false)
                }
            }
            if kind == .table, abs(s) % 2 == 0 {
                // A checked cloth over it.
                let cloth = R(0.06, 0.66, 0.94, 1)
                ctx.setFillColor(c(0.95, 0.94, 0.9)); ctx.fill(cloth)
                ctx.setFillColor(alpha(fabric(s), 0.8))
                var x = cloth.minX
                while x < cloth.maxX { ctx.fill(CGRect(x: x, y: cloth.minY, width: 4 * u, height: cloth.height)); x += 8 * u }
            }
        case .chair:
            for bar in b.bars { solid(ctx, polyPath(bar.outline), mid, u) }
            if let seat = b.blocks.first { solid(ctx, polyPath(seat.outline), shade(mid, 0.1), u) }
            solid(ctx, roundRect(R(0.08, 0.53, 0.8, 0.6), 2 * u), fabric(s), u)
        case .bookshelf:
            ctx.setFillColor(shade(mid, -0.35))
            ctx.fill(R(0.05, 0.03, 0.95, 0.97))
            // Books along each shelf.
            for (k, shelfY) in [(0, CGFloat(0.05)), (1, 0.52)].map({ ($0.0, $0.1) }) {
                var x = r.minX + r.width * 0.08
                var j = 0
                let top = k == 0 ? 0.47 : 0.95
                while x < r.minX + r.width * 0.9 {
                    let w = (5 + rnd(s + k, j) * 5) * u
                    let h = r.height * (top - shelfY) * (0.55 + rnd(s + 3, j + k * 9) * 0.35)
                    if rnd(s + 5, j + k) < 0.12 { x += w; j += 1; continue }
                    let book = CGRect(x: x, y: r.minY + r.height * shelfY, width: min(w, r.minX + r.width * 0.92 - x), height: h)
                    solid(ctx, CGPath(rect: book, transform: nil), fabric(s + j * 3, k + j), u * 0.5, light: 0.08)
                    ctx.setFillColor(c(1, 0.9, 0.6, 0.6)); ctx.fill(CGRect(x: book.minX, y: book.maxY - h * 0.25, width: book.width, height: 1 * u))
                    x += w + 0.6 * u; j += 1
                }
            }
            for bar in b.bars { paintBoard(ctx, Poly.bounds(bar.outline), s, u, upright: bar.name == "side", pale: -0.02) }
        case .sofa, .armchair:
            let col = fabric(s)
            for blk in b.blocks.sorted(by: { $0.name == "back" && $1.name != "back" }) {
                solid(ctx, roundRect(Poly.bounds(blk.outline), 6 * u), blk.name == "arm" ? shade(col, -0.08) : col, u)
            }
            ctx.setStrokeColor(alpha(shade(col, -0.4), 0.5)); ctx.setLineWidth(0.8 * u)
            let cushions = kind == .sofa ? 2 : 1
            for k in 1..<(cushions + 1) where cushions > 1 {
                let x = r.minX + r.width * CGFloat(k) / CGFloat(cushions + 1) * 1.0
                ctx.move(to: CGPoint(x: x, y: r.minY + r.height * 0.14)); ctx.addLine(to: CGPoint(x: x, y: r.minY + r.height * 0.9))
            }
            ctx.strokePath()
            ctx.setFillColor(shade(mid, -0.3))
            for x in [0.06, 0.88] { ctx.fill(R(CGFloat(x), 0, CGFloat(x) + 0.06, 0.1)) }
        case .fireplace:
            let stone = c(0.62, 0.58, 0.54)
            ctx.setFillColor(c(0.06, 0.04, 0.03)); ctx.fill(R(0.2, 0, 0.8, 0.62))
            // Logs and the fire on them.
            for (x0, x1) in [(0.26, 0.6), (0.4, 0.74)] {
                solid(ctx, roundRect(R(CGFloat(x0), 0.02, CGFloat(x1), 0.1), 3 * u), c(0.4, 0.26, 0.16), u * 0.6)
            }
            for (k, x) in [0.38, 0.5, 0.62].enumerated() { flame(ctx, at: P(CGFloat(x), 0.08), (22 + rnd(s, k) * 10) * u) }
            for blk in b.blocks where blk.name != "mantel" {
                let bb = Poly.bounds(blk.outline)
                solid(ctx, CGPath(rect: bb, transform: nil), stone, u, light: 0.08)
                ctx.setStrokeColor(c(0.4, 0.37, 0.34, 0.6)); ctx.setLineWidth(0.7 * u)
                var y = bb.minY + 8 * u
                while y < bb.maxY { ctx.move(to: CGPoint(x: bb.minX, y: y)); ctx.addLine(to: CGPoint(x: bb.maxX, y: y)); y += 8 * u }
                ctx.strokePath()
            }
            if let m = b.blocks.first(where: { $0.name == "mantel" }) { paintBoard(ctx, Poly.bounds(m.outline), s, u, upright: false, pale: -0.1) }
        case .floorLamp:
            ctx.setFillColor(c(0.78, 0.62, 0.3))
            for bar in b.bars { ctx.addPath(polyPath(bar.outline)); ctx.fillPath() }
            for blk in b.blocks where blk.name == "foot" { solid(ctx, polyPath(blk.outline), c(0.7, 0.55, 0.26), u) }
            bulb(ctx, at: P(0.5, 0.74), 4 * u, c(1, 0.85, 0.5))
            if let shade0 = b.blocks.first(where: { $0.name == "shade" }) { solid(ctx, polyPath(shade0.outline), c(0.96, 0.88, 0.7), u, light: 0.06) }
        case .hangingLamp:
            for st in b.sticks { paintStick(st, look: .cord, seed: s, u: u, ctx) }
            if let sh = b.blocks.first {
                bulb(ctx, at: P(0.5, 0.02), 5 * u, c(1, 0.86, 0.5))
                solid(ctx, polyPath(sh.outline), [c(0.28, 0.46, 0.36), c(0.7, 0.24, 0.2), c(0.95, 0.92, 0.85)][abs(s) % 3], u)
            }
        case .lantern:
            for st in b.sticks { paintStick(st, look: .cord, seed: s, u: u, ctx) }
            if let body = b.blocks.first {
                let bb = Poly.bounds(body.outline)
                ctx.setFillColor(c(1, 0.85, 0.5, 0.35)); ctx.fill(bb.insetBy(dx: 2 * u, dy: 3 * u))
                flame(ctx, at: CGPoint(x: bb.midX, y: bb.minY + bb.height * 0.2), bb.height * 0.45)
                let metal = c(0.22, 0.2, 0.18)
                ctx.setStrokeColor(metal); ctx.setLineWidth(2 * u)
                ctx.addPath(roundRect(bb, 4 * u)); ctx.strokePath()
                ctx.move(to: CGPoint(x: bb.midX, y: bb.minY)); ctx.addLine(to: CGPoint(x: bb.midX, y: bb.maxY)); ctx.strokePath()
                ctx.setFillColor(metal)
                ctx.fill(CGRect(x: bb.minX - 1 * u, y: bb.maxY - 3 * u, width: bb.width + 2 * u, height: 4 * u))
                ctx.fill(CGRect(x: bb.minX - 1 * u, y: bb.minY, width: bb.width + 2 * u, height: 3 * u))
            }
        case .candle:
            solid(ctx, roundRect(R(0, 0, 1, 0.12), 2 * u), c(0.85, 0.68, 0.3), u)
            solid(ctx, CGPath(rect: R(0.28, 0.1, 0.72, 0.78), transform: nil), c(0.97, 0.94, 0.86), u, light: 0.06)
            flame(ctx, at: P(0.5, 0.78), r.height * 0.22)
        case .stringLights:
            if let st = b.sticks.first {
                paintStick(st, look: .greenVine, seed: s, u: u, ctx)
                let sp = st.spine(step: 3)
                var run: CGFloat = 0, k = 0
                for i in 1..<sp.count {
                    run += sp[i].distance(to: sp[i - 1])
                    guard run > 18 * u else { continue }
                    run = 0
                    let col = [c(1, 0.8, 0.4), c(1, 0.5, 0.45), c(0.55, 0.85, 1), c(0.7, 1, 0.6)][abs(s + k) % 4]
                    bulb(ctx, at: CGPoint(x: sp[i].x, y: sp[i].y - 3.5 * u), 2.6 * u, col)
                    k += 1
                }
            }
        case .rug:
            let col = fabric(s)
            solid(ctx, roundRect(r, 2 * u), col, u * 0.6, light: 0.06)
            ctx.saveGState(); ctx.clip(to: r)
            for (k, y) in [0.25, 0.5, 0.75].enumerated() {
                ctx.setFillColor(k == 1 ? c(0.98, 0.9, 0.7, 0.8) : alpha(fabric(s, 2), 0.8))
                ctx.fill(CGRect(x: r.minX, y: r.minY + r.height * CGFloat(y) - 0.8 * u, width: r.width, height: 1.6 * u))
            }
            ctx.restoreGState()
            ctx.setStrokeColor(c(0.95, 0.9, 0.75)); ctx.setLineWidth(0.7 * u)
            for x in [r.minX, r.maxX] {
                for k in 0..<4 { let y = r.minY + r.height * (CGFloat(k) + 0.5) / 4; ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + (x == r.minX ? -3 : 3) * u, y: y)) }
            }
            ctx.strokePath()
        case .picture, .painting:
            let t = (kind == .painting ? 6 : 4) * u
            let inner = r.insetBy(dx: t, dy: t)
            scene(ctx, inner, s, u)
            frame(ctx, inner, t, gilt: kind == .painting || abs(s) % 2 == 0, u)
            hangPoint(ctx, at: V2(r.midX, r.maxY + (backed ? 1 : 0) * u), backed: backed, u)
        case .poster:
            let paper = r.insetBy(dx: 1 * u, dy: 1 * u)
            ctx.setFillColor(c(0.96, 0.94, 0.88)); ctx.fill(paper)
            scene(ctx, CGRect(x: paper.minX + 4 * u, y: paper.minY + paper.height * 0.26, width: paper.width - 8 * u, height: paper.height * 0.68), s + 3, u)
            ctx.setFillColor(alpha(fabric(s), 0.9))
            ctx.fill(CGRect(x: paper.minX + 6 * u, y: paper.minY + 5 * u, width: paper.width - 12 * u, height: 3 * u))
            ctx.fill(CGRect(x: paper.minX + 10 * u, y: paper.minY + 11 * u, width: paper.width - 20 * u, height: 2 * u))
            // Tape (or tacks) at its corners.
            for q in [CGPoint(x: paper.minX + 2 * u, y: paper.maxY - 2 * u), CGPoint(x: paper.maxX - 2 * u, y: paper.maxY - 2 * u)] {
                if backed { ctx.setFillColor(c(0.85, 0.2, 0.2)); ctx.fillEllipse(in: CGRect(x: q.x - 1.8 * u, y: q.y - 1.8 * u, width: 3.6 * u, height: 3.6 * u)) }
                else { ctx.setFillColor(c(1, 1, 0.9, 0.55)); ctx.fill(CGRect(x: q.x - 4 * u, y: q.y - 2 * u, width: 8 * u, height: 4 * u)) }
            }
        case .mirror:
            let inner = r.insetBy(dx: 4 * u, dy: 4 * u)
            let oval = CGPath(ellipseIn: inner, transform: nil)
            ctx.saveGState(); ctx.addPath(oval); ctx.clip()
            linear(ctx, [c(0.78, 0.86, 0.9), c(0.55, 0.64, 0.7), c(0.82, 0.88, 0.92)], [0, 0.5, 1], from: CGPoint(x: inner.minX, y: inner.maxY), to: CGPoint(x: inner.maxX, y: inner.minY))
            ctx.setStrokeColor(c(1, 1, 1, 0.6)); ctx.setLineWidth(3 * u)
            ctx.move(to: CGPoint(x: inner.minX + inner.width * 0.2, y: inner.midY)); ctx.addLine(to: CGPoint(x: inner.minX + inner.width * 0.5, y: inner.maxY)); ctx.strokePath()
            ctx.restoreGState()
            ctx.setStrokeColor(c(0.86, 0.68, 0.3)); ctx.setLineWidth(4 * u)
            ctx.addPath(oval); ctx.strokePath()
            hangPoint(ctx, at: V2(r.midX, r.maxY), backed: backed, u)
        case .curtains:
            let col = fabric(s)
            let rodY = r.maxY - 3 * u
            for side in [0, 1] {
                let x0 = side == 0 ? r.minX + 2 * u : r.maxX - r.width * 0.3
                let x1 = side == 0 ? r.minX + r.width * 0.3 : r.maxX - 2 * u
                let p = CGMutablePath()
                let tie = r.minY + r.height * 0.38
                p.move(to: CGPoint(x: x0, y: rodY))
                p.addLine(to: CGPoint(x: x1, y: rodY))
                p.addQuadCurve(to: CGPoint(x: side == 0 ? x0 + (x1 - x0) * 0.45 : x1 - (x1 - x0) * 0.45, y: tie),
                               control: CGPoint(x: side == 0 ? x1 : x0, y: tie + (rodY - tie) * 0.4))
                p.addQuadCurve(to: CGPoint(x: side == 0 ? x1 : x0, y: r.minY), control: CGPoint(x: side == 0 ? x0 : x1, y: tie - (tie - r.minY) * 0.3))
                p.addLine(to: CGPoint(x: side == 0 ? x0 : x1, y: r.minY))
                p.closeSubpath()
                solid(ctx, p, col, u, light: 0.1)
                ctx.setStrokeColor(alpha(shade(col, -0.35), 0.5)); ctx.setLineWidth(0.8 * u)
                for k in 1..<4 {
                    let x = x0 + (x1 - x0) * CGFloat(k) / 4
                    ctx.move(to: CGPoint(x: x, y: rodY)); ctx.addLine(to: CGPoint(x: x + (side == 0 ? 1 : -1) * 3 * u, y: r.minY + r.height * 0.45))
                }
                ctx.strokePath()
                ctx.setFillColor(c(0.95, 0.8, 0.4))
                ctx.fill(CGRect(x: side == 0 ? x0 + (x1 - x0) * 0.3 : x1 - (x1 - x0) * 0.7, y: tie - 1.5 * u, width: (x1 - x0) * 0.4, height: 3 * u))
            }
            ctx.setFillColor(c(0.72, 0.56, 0.28))
            ctx.fill(CGRect(x: r.minX, y: rodY - 1.2 * u, width: r.width, height: 2.6 * u))
            for x in [r.minX + 3 * u, r.maxX - 3 * u] { hangPoint(ctx, at: V2(x, rodY), backed: backed, u * 0.8) }
        case .dartboard:
            let cc = P(0.5, 0.5), rr = min(r.width, r.height) * 0.48
            for (k, f) in [1.0, 0.82, 0.62, 0.42, 0.2, 0.08].enumerated() {
                let q = rr * CGFloat(f)
                ctx.setFillColor([c(0.12, 0.12, 0.12), c(0.8, 0.2, 0.18), c(0.95, 0.9, 0.78), c(0.2, 0.5, 0.3), c(0.95, 0.9, 0.78), c(0.8, 0.2, 0.18)][k])
                ctx.fillEllipse(in: CGRect(x: cc.x - q, y: cc.y - q, width: q * 2, height: q * 2))
            }
            ctx.setStrokeColor(c(0.7, 0.7, 0.7, 0.6)); ctx.setLineWidth(0.5 * u)
            for k in 0..<10 { let a = CGFloat(k) / 10 * .pi * 2; ctx.move(to: cc); ctx.addLine(to: CGPoint(x: cc.x + cos(a) * rr * 0.82, y: cc.y + sin(a) * rr * 0.82)) }
            ctx.strokePath()
            ctx.setStrokeColor(c(0.3, 0.3, 0.32)); ctx.setLineWidth(1.4 * u)
            ctx.move(to: CGPoint(x: cc.x + rr * 0.3, y: cc.y + rr * 0.1)); ctx.addLine(to: CGPoint(x: cc.x + rr * 0.75, y: cc.y + rr * 0.35)); ctx.strokePath()
            hangPoint(ctx, at: V2(cc.x, cc.y + rr), backed: backed, u)
        case .clock:
            let cc = P(0.5, 0.5), rr = min(r.width, r.height) * 0.46
            solid(ctx, CGPath(ellipseIn: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2), transform: nil), mid, u)
            ctx.setFillColor(c(0.97, 0.95, 0.9))
            ctx.fillEllipse(in: CGRect(x: cc.x - rr * 0.82, y: cc.y - rr * 0.82, width: rr * 1.64, height: rr * 1.64))
            ctx.setFillColor(c(0.2, 0.2, 0.2))
            for k in 0..<12 { let a = CGFloat(k) / 12 * .pi * 2; ctx.fillEllipse(in: CGRect(x: cc.x + cos(a) * rr * 0.68 - 0.8 * u, y: cc.y + sin(a) * rr * 0.68 - 0.8 * u, width: 1.6 * u, height: 1.6 * u)) }
            ctx.setStrokeColor(c(0.15, 0.15, 0.15)); ctx.setLineCap(.round)
            ctx.setLineWidth(1.6 * u); ctx.move(to: cc); ctx.addLine(to: CGPoint(x: cc.x + rr * 0.3, y: cc.y + rr * 0.35)); ctx.strokePath()
            ctx.setLineWidth(1 * u); ctx.move(to: cc); ctx.addLine(to: CGPoint(x: cc.x - rr * 0.1, y: cc.y + rr * 0.6)); ctx.strokePath()
            hangPoint(ctx, at: V2(cc.x, cc.y + rr * 0.9), backed: backed, u)
        case .houseplant:
            let pot = b.blocks[0]
            solid(ctx, polyPath(pot.outline), c(0.78, 0.46, 0.3), u)
            ctx.setFillColor(c(0.86, 0.55, 0.38)); ctx.fill(R(0.16, 0.34, 0.84, 0.42))
            for k in 0..<7 {
                let a = CGFloat(k - 3) * 0.36 + (rnd(s, k) - 0.5) * 0.2
                leafShape(ctx, at: P(0.5, 0.4), length: r.height * (0.42 + rnd(s + 1, k) * 0.18), angle: .pi / 2 - a,
                          colour: k % 2 == 0 ? c(0.3, 0.56, 0.3) : c(0.4, 0.66, 0.36), u: u)
            }
        case .spool:
            let thread = fabric(s)
            solid(ctx, CGPath(rect: R(0.14, 0.12, 0.86, 0.88), transform: nil), thread, u)
            ctx.setStrokeColor(alpha(shade(thread, 0.35), 0.5)); ctx.setLineWidth(0.6 * u)
            var y = r.minY + r.height * 0.14
            while y < r.minY + r.height * 0.86 { ctx.move(to: CGPoint(x: r.minX + r.width * 0.14, y: y)); ctx.addLine(to: CGPoint(x: r.minX + r.width * 0.86, y: y + 1 * u)); y += 2.4 * u }
            ctx.strokePath()
            for y0 in [0.0, 0.86] { solid(ctx, roundRect(R(0, CGFloat(y0), 1, CGFloat(y0) + 0.14), 2 * u), c(0.86, 0.72, 0.5), u) }
        case .teacup:
            ctx.setStrokeColor(c(0.96, 0.95, 0.93)); ctx.setLineWidth(3 * u)
            ctx.strokeEllipse(in: CGRect(x: r.minX + r.width * 0.74, y: r.minY + r.height * 0.36, width: r.width * 0.24, height: r.height * 0.4))
            for blk in b.blocks { solid(ctx, polyPath(blk.outline), c(0.97, 0.96, 0.94), u, light: 0.05) }
            ctx.setFillColor(alpha(fabric(s, 1), 0.9)); ctx.fill(R(0.16, 0.6, 0.76, 0.7))
            ctx.setFillColor(c(0.55, 0.34, 0.18)); ctx.fillEllipse(in: R(0.14, 0.9, 0.78, 1.02))
        case .flowerBox:
            for k in 0..<7 {
                let x = 0.1 + CGFloat(k) * 0.13
                let top = P(x, 0.78 + rnd(s, k) * 0.2)
                ctx.setStrokeColor(c(0.3, 0.52, 0.28)); ctx.setLineWidth(1.4 * u)
                ctx.move(to: P(x, 0.5)); ctx.addLine(to: top); ctx.strokePath()
                ctx.setFillColor([c(0.95, 0.45, 0.5), c(0.98, 0.85, 0.35), c(0.8, 0.55, 0.95)][abs(s + k) % 3])
                for q in 0..<5 { let a = CGFloat(q) / 5 * .pi * 2; ctx.fillEllipse(in: CGRect(x: top.x + cos(a) * 2.6 * u - 2 * u, y: top.y + sin(a) * 2.6 * u - 2 * u, width: 4 * u, height: 4 * u)) }
                ctx.setFillColor(c(1, 0.9, 0.5)); ctx.fillEllipse(in: CGRect(x: top.x - 1.4 * u, y: top.y - 1.4 * u, width: 2.8 * u, height: 2.8 * u))
            }
            paintBoard(ctx, R(0, 0, 1, 0.55), s, u, upright: false, pale: -0.06)
        case .sign:
            for st in b.sticks { paintStick(st, look: .cord, seed: s, u: u, ctx) }
            let board = R(0, 0, 1, 0.58)
            paintBoard(ctx, board, s, u, upright: false, pale: -0.05)
            label(ctx, "HOME", in: board, size: board.height * 0.5, colour: c(0.98, 0.95, 0.88))
            ctx.setFillColor(c(0.85, 0.3, 0.32))
            let hc = CGPoint(x: board.maxX - board.width * 0.12, y: board.maxY - board.height * 0.28)
            ctx.fillEllipse(in: CGRect(x: hc.x - 3 * u, y: hc.y - 1 * u, width: 3.4 * u, height: 3.4 * u))
            ctx.fillEllipse(in: CGRect(x: hc.x - 0.4 * u, y: hc.y - 1 * u, width: 3.4 * u, height: 3.4 * u))
        case .dresser, .wardrobe, .chest:
            let body = kind == .chest ? HabitatShape.chestPath(r) : roundRect(R(0, 0.04, 1, 1), 2 * u)
            let bb = body.boundingBox
            ctx.saveGState(); ctx.addPath(body); ctx.clip()
            paintBoard(ctx, bb, s, u, upright: kind == .wardrobe, pale: kind == .chest ? -0.1 : 0)
            ctx.restoreGState()
            outline(ctx, body, mid, u)
            ctx.setFillColor(c(0.95, 0.78, 0.35))
            switch kind {
            case .dresser:
                for k in 0..<3 {
                    let y = bb.minY + bb.height * CGFloat(k) / 3
                    ctx.setFillColor(c(0, 0, 0, 0.3)); ctx.fill(CGRect(x: bb.minX + 3 * u, y: y + 1 * u, width: bb.width - 6 * u, height: 0.9 * u))
                    ctx.setFillColor(c(0.95, 0.78, 0.35))
                    for x in [0.3, 0.7] { ctx.fillEllipse(in: CGRect(x: bb.minX + bb.width * CGFloat(x) - 2 * u, y: y + bb.height / 6 - 2 * u, width: 4 * u, height: 4 * u)) }
                }
            case .wardrobe:
                ctx.setFillColor(c(0, 0, 0, 0.35)); ctx.fill(CGRect(x: bb.midX - 0.5 * u, y: bb.minY + 4 * u, width: 1 * u, height: bb.height - 12 * u))
                ctx.setFillColor(c(0.95, 0.78, 0.35))
                for x in [bb.midX - 5 * u, bb.midX + 2 * u] { ctx.fillEllipse(in: CGRect(x: x, y: bb.midY, width: 3 * u, height: 3 * u)) }
                ctx.setFillColor(shade(mid, -0.2)); ctx.fill(CGRect(x: bb.minX - 1 * u, y: bb.maxY - 5 * u, width: bb.width + 2 * u, height: 5 * u))
            default:
                // Iron bands and a lock.
                ctx.setFillColor(c(0.3, 0.28, 0.26))
                for x in [0.18, 0.78] { ctx.fill(CGRect(x: bb.minX + bb.width * CGFloat(x), y: bb.minY, width: 4 * u, height: bb.height)) }
                ctx.fill(CGRect(x: bb.minX, y: bb.minY + bb.height * 0.55, width: bb.width, height: 3 * u))
                ctx.setFillColor(c(0.95, 0.78, 0.35)); ctx.fill(CGRect(x: bb.midX - 4 * u, y: bb.minY + bb.height * 0.4, width: 8 * u, height: 9 * u))
            }
        case .bunkBed:
            for bar in b.bars { paintBoard(ctx, Poly.bounds(bar.outline), s, u, upright: true) }
            for (k, blk) in b.blocks.enumerated() {
                let bb = Poly.bounds(blk.outline)
                paintBoard(ctx, CGRect(x: bb.minX, y: bb.minY, width: bb.width, height: bb.height * 0.45), s + k, u, upright: false)
                solid(ctx, roundRect(CGRect(x: bb.minX + 2 * u, y: bb.minY + bb.height * 0.45, width: bb.width - 4 * u, height: bb.height * 0.55), 3 * u), fabric(s, k + 1), u)
            }
            for v in b.visual { solid(ctx, roundRect(Poly.bounds(v), 4 * u), c(0.97, 0.96, 0.93), u) }
        case .piano:
            let case0 = R(0.02, 0.1, 0.72, 1)
            solid(ctx, roundRect(case0, 2 * u), abs(s) % 2 == 0 ? c(0.12, 0.1, 0.1) : shade(mid, -0.2), u, light: 0.12)
            ctx.setFillColor(c(0.97, 0.96, 0.92)); ctx.fill(R(0, 0.46, 1, 0.58))
            ctx.setFillColor(c(0.1, 0.1, 0.1))
            var x = r.minX + 3 * u
            var k = 0
            while x < r.maxX - 3 * u {
                ctx.fill(CGRect(x: x, y: r.minY + r.height * 0.46, width: 0.6 * u, height: r.height * 0.12))
                if k % 7 != 2 && k % 7 != 6 { ctx.fill(CGRect(x: x + 2 * u, y: r.minY + r.height * 0.52, width: 2.4 * u, height: r.height * 0.06)) }
                x += 5 * u; k += 1
            }
            ctx.setFillColor(c(0.95, 0.94, 0.88)); ctx.fill(R(0.2, 0.7, 0.5, 0.88))
            solid(ctx, CGPath(rect: R(0.88, 0, 0.95, 0.5), transform: nil), c(0.12, 0.1, 0.1), u)
        case .stove:
            let body = R(0, 0, 1, 0.82)
            solid(ctx, roundRect(body, 3 * u), [c(0.92, 0.9, 0.84), c(0.6, 0.8, 0.78), c(0.85, 0.35, 0.3)][abs(s) % 3], u, light: 0.08)
            let door = body.insetBy(dx: body.width * 0.14, dy: body.height * 0.18).offsetBy(dx: 0, dy: -body.height * 0.06)
            ctx.setFillColor(c(0.2, 0.18, 0.18)); ctx.fill(door)
            glass(ctx, door.insetBy(dx: 3 * u, dy: 3 * u), u)
            ctx.setFillColor(c(0.2, 0.2, 0.22))
            for k in 0..<4 { ctx.fillEllipse(in: CGRect(x: body.minX + body.width * (0.2 + CGFloat(k) * 0.2) - 2 * u, y: body.maxY - 8 * u, width: 4 * u, height: 4 * u)) }
            // A pot on the hob.
            solid(ctx, roundRect(R(0.3, 0.82, 0.7, 1), 2 * u), c(0.35, 0.4, 0.45), u)
        case .fridge:
            let col = [c(0.95, 0.94, 0.9), c(0.62, 0.84, 0.8), c(0.95, 0.72, 0.7)][abs(s) % 3]
            solid(ctx, roundRect(r, 6 * u), col, u, light: 0.06)
            ctx.setFillColor(alpha(shade(col, -0.3), 0.6)); ctx.fill(R(0.04, 0.66, 0.96, 0.675))
            ctx.setFillColor(c(0.75, 0.75, 0.76))
            ctx.fill(R(0.8, 0.72, 0.86, 0.9)); ctx.fill(R(0.8, 0.36, 0.86, 0.6))
            for k in 0..<3 { ctx.setFillColor(fabric(s + k, k)); ctx.fillEllipse(in: CGRect(x: r.minX + r.width * (0.2 + CGFloat(k) * 0.16), y: r.minY + r.height * (0.8 - CGFloat(k % 2) * 0.05), width: 5 * u, height: 5 * u)) }
        case .counter:
            let body = R(0, 0, 1, 0.82)
            paintBoard(ctx, body, s, u, upright: true, pale: -0.02)
            ctx.setStrokeColor(c(0, 0, 0, 0.35)); ctx.setLineWidth(0.8 * u)
            for x in [0.33, 0.66] { ctx.move(to: P(CGFloat(x), 0.04)); ctx.addLine(to: P(CGFloat(x), 0.72)) }
            ctx.strokePath()
            ctx.setFillColor(c(0.95, 0.78, 0.35))
            for x in [0.28, 0.38, 0.61, 0.71] { ctx.fillEllipse(in: CGRect(x: r.minX + r.width * CGFloat(x) - 1.5 * u, y: r.minY + r.height * 0.5, width: 3 * u, height: 3 * u)) }
            solid(ctx, CGPath(rect: R(-0.0, 0.72, 1, 0.82), transform: nil), c(0.86, 0.86, 0.84), u, light: 0.1)
            // A tap over the sink.
            ctx.setStrokeColor(c(0.78, 0.78, 0.8)); ctx.setLineWidth(2.4 * u); ctx.setLineCap(.round)
            ctx.move(to: P(0.72, 0.82)); ctx.addLine(to: P(0.72, 0.98)); ctx.addLine(to: P(0.62, 0.98)); ctx.addLine(to: P(0.62, 0.92)); ctx.strokePath()
        case .bathtub:
            for bar in b.bars { solid(ctx, polyPath(bar.outline), c(0.9, 0.74, 0.35), u) }
            if let tub = b.blocks.first {
                // The inside of the tub, seen over its near rim, then the tub.
                let basin = CGMutablePath()
                basin.move(to: P(0.04, 1)); basin.addLine(to: P(0.96, 1)); basin.addLine(to: P(0.9, 0.3)); basin.addLine(to: P(0.78, 0.2))
                basin.addLine(to: P(0.22, 0.2)); basin.addLine(to: P(0.1, 0.3)); basin.closeSubpath()
                fill(ctx, basin, [c(0.86, 0.88, 0.9), c(0.78, 0.82, 0.86)], from: P(0.5, 1), to: P(0.5, 0.2))
                ctx.setFillColor(c(0.55, 0.78, 0.95, 0.55)); ctx.fill(R(0.1, 0.26, 0.9, 0.62))
                solid(ctx, polyPath(tub.outline), c(0.97, 0.97, 0.95), u, light: 0.06)
                // A duck.
                ctx.setFillColor(c(1, 0.84, 0.2))
                ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.56, y: r.minY + r.height * 0.6, width: 10 * u, height: 7 * u))
                ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.56 + 6 * u, y: r.minY + r.height * 0.6 + 5 * u, width: 6 * u, height: 6 * u))
                ctx.setFillColor(c(1, 0.5, 0.2)); ctx.fill(CGRect(x: r.minX + r.width * 0.56 + 11.5 * u, y: r.minY + r.height * 0.6 + 7 * u, width: 2.5 * u, height: 1.5 * u))
            }
        case .coatRack:
            for bar in b.bars { solid(ctx, polyPath(bar.outline), mid, u) }
            for blk in b.blocks { solid(ctx, polyPath(blk.outline), shade(mid, -0.1), u) }
            // A scarf, and a hat on top.
            let scarf = R(0.62, 0.36, 0.84, 0.88)
            solid(ctx, roundRect(scarf, 3 * u), fabric(s), u)
            ctx.setFillColor(alpha(c(1, 1, 1), 0.4))
            var y = scarf.minY + 3 * u
            while y < scarf.maxY { ctx.fill(CGRect(x: scarf.minX, y: y, width: scarf.width, height: 1.4 * u)); y += 5 * u }
            solid(ctx, roundRect(R(0.2, 0.95, 0.8, 1.05), 2 * u), c(0.25, 0.22, 0.2), u)
            solid(ctx, roundRect(R(0.32, 1.0, 0.68, 1.14), 3 * u), c(0.25, 0.22, 0.2), u)
        case .beanbag:
            if let bag = b.blocks.first {
                let p = polyPath(bag.outline)
                solid(ctx, p, fabric(s), u, light: 0.12)
                ctx.saveGState(); ctx.addPath(p); ctx.clip()
                ctx.setStrokeColor(alpha(shade(fabric(s), -0.4), 0.4)); ctx.setLineWidth(0.8 * u)
                for k in 1..<4 { let x = r.minX + r.width * CGFloat(k) / 4; ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addQuadCurve(to: CGPoint(x: x + 6 * u, y: r.maxY), control: CGPoint(x: x - 8 * u, y: r.midY)) }
                ctx.strokePath()
                ctx.restoreGState()
            }
        // MARK: Decor
        case .tv:
            for st in b.sticks { paintStick(st, look: .metal, seed: s, u: u, ctx) }
            let set = R(0.04, 0, 0.96, 0.78)
            solid(ctx, roundRect(set, 5 * u), shade(mid, -0.1), u)
            let screen = CGRect(x: set.minX + set.width * 0.08, y: set.minY + set.height * 0.14, width: set.width * 0.66, height: set.height * 0.72)
            let sp = roundRect(screen, 6 * u)
            fill(ctx, sp, [c(0.55, 0.8, 0.95), c(0.3, 0.5, 0.7)], from: CGPoint(x: screen.minX, y: screen.maxY), to: CGPoint(x: screen.maxX, y: screen.minY))
            ctx.saveGState(); ctx.addPath(sp); ctx.clip()
            ctx.setFillColor(c(1, 1, 1, 0.12))
            var y = screen.minY
            while y < screen.maxY { ctx.fill(CGRect(x: screen.minX, y: y, width: screen.width, height: 0.8 * u)); y += 2.4 * u }
            ctx.setFillColor(c(0.2, 0.6, 0.3, 0.8)); ctx.fillEllipse(in: CGRect(x: screen.minX + screen.width * 0.1, y: screen.minY - screen.height * 0.3, width: screen.width * 0.9, height: screen.height * 0.6))
            ctx.restoreGState()
            ctx.setStrokeColor(c(0.15, 0.13, 0.12)); ctx.setLineWidth(2 * u); ctx.addPath(sp); ctx.strokePath()
            ctx.setFillColor(c(0.85, 0.8, 0.7))
            for k in 0..<2 { ctx.fillEllipse(in: CGRect(x: set.minX + set.width * 0.8, y: set.minY + set.height * (0.55 - CGFloat(k) * 0.28), width: 5 * u, height: 5 * u)) }
        case .radio:
            let body = R(0, 0, 1, 0.82)
            solid(ctx, roundRect(body, 6 * u), shade(mid, 0.05), u)
            let grille = CGRect(x: body.minX + body.width * 0.08, y: body.minY + body.height * 0.14, width: body.width * 0.46, height: body.height * 0.72)
            ctx.setFillColor(c(0.9, 0.84, 0.7)); ctx.fill(grille)
            ctx.setStrokeColor(c(0.4, 0.3, 0.2, 0.7)); ctx.setLineWidth(0.8 * u)
            var x = grille.minX + 2 * u
            while x < grille.maxX { ctx.move(to: CGPoint(x: x, y: grille.minY)); ctx.addLine(to: CGPoint(x: x, y: grille.maxY)); x += 3 * u }
            ctx.strokePath()
            ctx.setFillColor(c(0.95, 0.9, 0.7)); ctx.fillEllipse(in: CGRect(x: body.minX + body.width * 0.64, y: body.midY - 1 * u, width: body.width * 0.24, height: body.width * 0.24))
            ctx.setStrokeColor(c(0.3, 0.26, 0.22)); ctx.setLineWidth(2 * u)
            ctx.move(to: P(0.3, 0.82)); ctx.addQuadCurve(to: P(0.7, 0.82), control: P(0.5, 1.08)); ctx.strokePath()
        case .laptop:
            if let lid = b.bars.first {
                solid(ctx, polyPath(lid.outline), c(0.75, 0.76, 0.78), u)
                let lp = lid.outline
                ctx.setStrokeColor(c(0.5, 0.8, 1, 0.9)); ctx.setLineWidth(1.4 * u)
                ctx.move(to: V2.lerp(lp[0], lp[1], 0.1).point); ctx.addLine(to: V2.lerp(lp[0], lp[1], 0.85).point); ctx.strokePath()
            }
            solid(ctx, roundRect(R(0, 0, 1, 0.1), 1.5 * u), c(0.8, 0.81, 0.83), u)
        case .recordPlayer:
            solid(ctx, roundRect(r, 3 * u), shade(mid, 0.05), u)
            ctx.setFillColor(c(0.08, 0.08, 0.08)); ctx.fillEllipse(in: R(0.1, 0.78, 0.64, 1.06))
            ctx.setFillColor(fabric(s)); ctx.fillEllipse(in: R(0.32, 0.86, 0.42, 0.98))
            ctx.setStrokeColor(c(0.75, 0.75, 0.78)); ctx.setLineWidth(1.6 * u)
            ctx.move(to: P(0.86, 0.9)); ctx.addLine(to: P(0.6, 1.02)); ctx.strokePath()
            ctx.setFillColor(c(0.9, 0.84, 0.7)); ctx.fillEllipse(in: CGRect(x: r.minX + r.width * 0.8, y: r.minY + r.height * 0.3, width: 5 * u, height: 5 * u))
        case .globe:
            for bar in b.bars { solid(ctx, polyPath(bar.outline), c(0.8, 0.62, 0.3), u) }
            for blk in b.blocks where blk.name == "foot" { solid(ctx, polyPath(blk.outline), c(0.7, 0.54, 0.26), u) }
            if let g = b.blocks.first(where: { $0.name == "globe" }) {
                let p = polyPath(g.outline)
                solid(ctx, p, c(0.35, 0.6, 0.85), u, light: 0.16)
                ctx.saveGState(); ctx.addPath(p); ctx.clip()
                ctx.setFillColor(c(0.45, 0.72, 0.4))
                let bb = p.boundingBox
                for k in 0..<4 { ctx.fillEllipse(in: CGRect(x: bb.minX + bb.width * rnd(s, k) * 0.7, y: bb.minY + bb.height * rnd(s + 1, k) * 0.7, width: bb.width * 0.3, height: bb.height * 0.2)) }
                ctx.restoreGState()
                ctx.setStrokeColor(c(0.8, 0.62, 0.3)); ctx.setLineWidth(1.4 * u)
                ctx.addArc(center: p.boundingBox.center, radius: p.boundingBox.width * 0.56, startAngle: -1.2, endAngle: 1.9, clockwise: false)
                ctx.strokePath()
            }
        case .vase:
            for k in 0..<5 {
                let a = CGFloat(k - 2) * 0.35
                let top = CGPoint(x: r.midX + sin(a) * r.width * 0.5, y: r.minY + r.height * (0.86 + cos(a) * 0.1))
                ctx.setStrokeColor(c(0.3, 0.52, 0.28)); ctx.setLineWidth(1.3 * u)
                ctx.move(to: P(0.5, 0.56)); ctx.addLine(to: top); ctx.strokePath()
                ctx.setFillColor([c(0.95, 0.45, 0.5), c(0.98, 0.85, 0.35), c(0.8, 0.55, 0.95), c(0.98, 0.98, 0.95)][abs(s + k) % 4])
                for q in 0..<5 { let aa = CGFloat(q) / 5 * .pi * 2; ctx.fillEllipse(in: CGRect(x: top.x + cos(aa) * 3 * u - 2.4 * u, y: top.y + sin(aa) * 3 * u - 2.4 * u, width: 4.8 * u, height: 4.8 * u)) }
            }
            solid(ctx, HabitatShape.vasePath(r), [c(0.3, 0.46, 0.7), c(0.85, 0.5, 0.4), c(0.4, 0.62, 0.55)][abs(s) % 3], u, light: 0.18)
        case .bookStack:
            let n = 4
            for k in 0..<n {
                let h = r.height / CGFloat(n)
                let inset = (rnd(s, k) - 0.5) * 6 * u
                let book = CGRect(x: r.minX + r.width * 0.04 + inset, y: r.minY + h * CGFloat(k), width: r.width * 0.92 - abs(inset), height: h - 0.6 * u)
                solid(ctx, roundRect(book, 1.2 * u), fabric(s + k * 5, k), u * 0.7, light: 0.08)
                ctx.setFillColor(c(0.97, 0.95, 0.88)); ctx.fill(CGRect(x: book.maxX - 3 * u, y: book.minY + 1 * u, width: 2.4 * u, height: book.height - 2 * u))
            }
        case .flyJar:
            let jar = roundRect(R(0.06, 0, 0.94, 0.84), 6 * u)
            ctx.saveGState(); ctx.addPath(jar); ctx.clip()
            ctx.setFillColor(c(0.8, 0.9, 0.85, 0.3)); ctx.fill(r)
            for k in 0..<6 {
                let p = P(0.2 + rnd(s, k) * 0.6, 0.12 + rnd(s + 1, k) * 0.6)
                ctx.setFillColor(c(0.8, 0.9, 1, 0.8))
                ctx.fillEllipse(in: CGRect(x: p.x - 3 * u, y: p.y, width: 3 * u, height: 2 * u))
                ctx.fillEllipse(in: CGRect(x: p.x, y: p.y, width: 3 * u, height: 2 * u))
                ctx.setFillColor(c(0.15, 0.15, 0.15)); ctx.fillEllipse(in: CGRect(x: p.x - 1.6 * u, y: p.y - 1.4 * u, width: 3.2 * u, height: 2.4 * u))
            }
            ctx.restoreGState()
            ctx.setStrokeColor(c(1, 1, 1, 0.7)); ctx.setLineWidth(1 * u); ctx.addPath(jar); ctx.strokePath()
            glass(ctx, R(0.12, 0.1, 0.3, 0.7), u)
            solid(ctx, roundRect(R(0.14, 0.82, 0.86, 1), 2 * u), c(0.85, 0.3, 0.28), u)
            ctx.setFillColor(c(0.97, 0.94, 0.85)); ctx.fill(R(0.2, 0.3, 0.8, 0.5))
        case .trophy:
            let gold = c(0.95, 0.76, 0.3)
            for bar in b.bars { solid(ctx, polyPath(bar.outline), gold, u) }
            ctx.setStrokeColor(gold); ctx.setLineWidth(2 * u)
            ctx.strokeEllipse(in: R(0.0, 0.62, 0.28, 0.92)); ctx.strokeEllipse(in: R(0.72, 0.62, 1.0, 0.92))
            for blk in b.blocks { solid(ctx, polyPath(blk.outline), blk.name == "foot" ? shade(mid, -0.2) : gold, u, light: 0.2) }
        case .wallShelf:
            for v in b.visual {
                if backed { solid(ctx, polyPath(v), c(0.25, 0.24, 0.23), u * 0.7) } else { solid(ctx, polyPath(v), c(0.85, 0.9, 0.95), u * 0.7, light: 0.05) }
            }
            if let sh = b.blocks.first { paintBoard(ctx, Poly.bounds(sh.outline), s, u, upright: false) }
            for x in [0.17, 0.83] { hangPoint(ctx, at: V2(P(CGFloat(x), 0.2)), backed: backed, u * 0.8) }
        case .sconce:
            ctx.setFillColor(c(0.8, 0.62, 0.3)); ctx.fill(R(0.36, 0, 0.64, 0.5))
            ctx.setStrokeColor(c(0.8, 0.62, 0.3)); ctx.setLineWidth(2 * u)
            ctx.move(to: P(0.5, 0.3)); ctx.addLine(to: P(0.5, 0.62)); ctx.strokePath()
            bulb(ctx, at: P(0.5, 0.66), 3.6 * u, c(1, 0.86, 0.5))
            let shadeP = CGMutablePath()
            shadeP.move(to: P(0.08, 0.62)); shadeP.addLine(to: P(0.92, 0.62)); shadeP.addLine(to: P(0.72, 1)); shadeP.addLine(to: P(0.28, 1)); shadeP.closeSubpath()
            solid(ctx, shadeP, c(0.96, 0.88, 0.7), u, light: 0.06)
            hangPoint(ctx, at: V2(P(0.5, 0.25)), backed: backed, u * 0.8)
        case .chandelier:
            for st in b.sticks { paintStick(st, look: .metal, seed: s, u: u, ctx) }
            for bar in b.bars { solid(ctx, polyPath(bar.outline), c(0.86, 0.68, 0.3), u) }
            for v in b.visual {
                let bb = Poly.bounds(v)
                solid(ctx, CGPath(rect: bb, transform: nil), c(0.97, 0.94, 0.86), u * 0.6, light: 0.05)
                flame(ctx, at: CGPoint(x: bb.midX, y: bb.maxY), 9 * u)
            }
        case .stake:
            let look = StickLook.wood(light: light, mid: mid, dark: dark)
            for st in b.sticks.reversed() { paintStick(st, look: look, seed: s, u: u, ctx) }
        default:
            return false
        }
        return true
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
