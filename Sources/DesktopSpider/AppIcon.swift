import AppKit

/// The app's own art: the spider of the menu bar icon, and the icon it wears
/// in the Dock, in Finder and on the .dmg. Needs nothing but AppKit, so
/// tools/art.sh can draw the bundle's icon and the .dmg's backdrop from it.
enum AppArt {
    /// The menu bar spider, head up, centred on the origin, in its own units
    /// (46 across). The caller translates and scales.
    static func drawGlyph(in ctx: CGContext, colour: CGColor) {
        ctx.rotate(by: .pi / 2)
        ctx.setFillColor(colour)
        ctx.setStrokeColor(colour)
        ctx.setLineCap(.round)
        // Legs
        for side in [CGFloat(1), CGFloat(-1)] {
            let feet: [(CGPoint, CGPoint)] = [
                (CGPoint(x: 8, y: side * 5), CGPoint(x: 21, y: side * 15)),
                (CGPoint(x: 4, y: side * 6), CGPoint(x: 12, y: side * 23)),
                (CGPoint(x: 0, y: side * 6), CGPoint(x: -6, y: side * 24)),
                (CGPoint(x: -4, y: side * 5), CGPoint(x: -19, y: side * 17)),
            ]
            for (h, f) in feet {
                let knee = CGPoint(x: (h.x + f.x) / 2, y: (h.y + f.y) / 2 + side * 5)
                ctx.setLineWidth(4.4)
                ctx.beginPath()
                ctx.move(to: h); ctx.addLine(to: knee); ctx.addLine(to: f)
                ctx.strokePath()
            }
        }
        ctx.fillEllipse(in: CGRect(x: -24, y: -13, width: 27, height: 26))
        ctx.fillEllipse(in: CGRect(x: -5, y: -11.5, width: 24, height: 23))
    }

    // MARK: Palette

    static let cream = CGColor(red: 1.0, green: 0.972, blue: 0.9, alpha: 1)
    static let apricot = CGColor(red: 0.98, green: 0.8, blue: 0.56, alpha: 1)
    static let ink = CGColor(red: 0.12, green: 0.1, blue: 0.1, alpha: 1)
    static let silk = CGColor(red: 1, green: 1, blue: 1, alpha: 0.6)
    static let bark = CGColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1)

    // MARK: Icon

    /// The icon, `side` points square, drawn into `ctx` (y up): the menu bar
    /// spider on a sunny tile with a web in its corner.
    static func drawIcon(in ctx: CGContext, side: CGFloat) {
        ctx.saveGState()
        ctx.scaleBy(x: side / 1024, y: side / 1024)
        // Apple's icon grid: an 824-in-1024 tile, a little above its shadow.
        let tile = CGRect(x: 100, y: 110, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
        ctx.addPath(shape)
        ctx.setFillColor(apricot)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        let sun = CGGradient(colorsSpace: nil, colors: [cream, apricot] as CFArray, locations: [0.1, 1])!
        ctx.drawRadialGradient(sun, startCenter: CGPoint(x: 380, y: 820), startRadius: 0,
                               endCenter: CGPoint(x: 380, y: 820), endRadius: 900, options: [.drawsAfterEndLocation])
        drawWeb(in: ctx, hub: CGPoint(x: tile.maxX - 40, y: tile.maxY - 40), radius: 520,
                from: .pi * 0.98, to: .pi * 1.52, spokes: 7, rings: 7, width: 5, colour: silk)
        // A soft rim of light along the top edge.
        ctx.addPath(shape)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
        ctx.setLineWidth(6)
        ctx.strokePath()
        ctx.restoreGState()

        // The spider itself, as in the menu bar.
        ctx.saveGState()
        // (One shadow for the whole of it, not one part's on another.)
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: CGColor(red: 0.45, green: 0.25, blue: 0.05, alpha: 0.35))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.translateBy(x: tile.midX, y: tile.midY - 4)
        ctx.scaleBy(x: 11.4, y: 11.4)
        drawGlyph(in: ctx, colour: ink)
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        ctx.restoreGState()
    }

    /// Part of an orb web: `spokes` threads fanning out from `hub` between the
    /// angles `from` and `to`, with a sagging spiral across them. The spokes
    /// run on `reach` times as far as the spiral.
    static func drawWeb(in ctx: CGContext, hub: CGPoint, radius: CGFloat, from: CGFloat, to: CGFloat,
                        spokes: Int, rings: Int, width: CGFloat, colour: CGColor, reach: CGFloat = 1.4) {
        ctx.saveGState()
        ctx.setStrokeColor(colour)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let angles = (0..<spokes).map { from + (to - from) * CGFloat($0) / CGFloat(spokes - 1) }
        func point(_ a: CGFloat, _ r: CGFloat) -> CGPoint { CGPoint(x: hub.x + cos(a) * r, y: hub.y + sin(a) * r) }
        ctx.setLineWidth(width)
        for a in angles {
            ctx.move(to: hub)
            ctx.addLine(to: point(a, radius * reach))
        }
        ctx.strokePath()
        ctx.setLineWidth(width * 0.75)
        for ring in 1...rings {
            let r = radius * CGFloat(ring) / CGFloat(rings) * (0.95 + 0.05 * CGFloat(ring % 2))
            ctx.move(to: point(angles[0], r))
            for (a0, a1) in zip(angles, angles.dropFirst()) {
                // Each strand sags a little towards the hub.
                let mid = (a0 + a1) / 2
                ctx.addQuadCurve(to: point(a1, r), control: point(mid, r * 0.9))
            }
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
