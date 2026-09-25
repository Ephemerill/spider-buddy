import AppKit

// MARK: - Painting the habitat
//
// Everything in the tank is painted here, once, into images the scene's
// layers show: the backdrop (sky, the far distance, the near scenery and
// the substrate seen through the glass), the glass itself, and the little
// pictures the moving parts are made of (clouds, leaves, fireflies…). What
// moves is moved by Core Animation, so the tank costs next to nothing to
// keep alive.
//
// Everything is laid out on the 900 × 540 scene and scaled to whatever
// rect it is painted into, so the same code paints the tank and the
// thumbnails in the picker.

enum HabitatArt {
    // MARK: Helpers

    static func rnd(_ seed: Int, _ i: Int) -> CGFloat {
        let x = sin(CGFloat(seed) * 12.9898 + CGFloat(i) * 78.233) * 43758.5453
        return x - floor(x)
    }

    static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    static func rgba(_ col: CGColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        let conv = col.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? col
        let k = conv.components ?? [0, 0, 0, 1]
        if k.count >= 4 { return (k[0], k[1], k[2], k[3]) }
        if k.count == 2 { return (k[0], k[0], k[0], k[1]) }
        return (0, 0, 0, 1)
    }

    static func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
        let (r1, g1, b1, a1) = rgba(a), (r2, g2, b2, a2) = rgba(b)
        return c(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t, a1 + (a2 - a1) * t)
    }

    static func alpha(_ col: CGColor, _ a: CGFloat) -> CGColor { col.copy(alpha: a) ?? col }
    static func shade(_ col: CGColor, _ k: CGFloat) -> CGColor {
        k >= 0 ? mix(col, c(1, 1, 1, rgba(col).3), k) : mix(col, c(0, 0, 0, rgba(col).3), -k)
    }

    /// A smooth wobble in -1…1, different for every seed.
    static func wave(_ x: CGFloat, _ seed: Int) -> CGFloat {
        let s = CGFloat(seed)
        return (sin(x * 1.0 + s * 1.7) * 0.5 + sin(x * 2.3 + s * 3.1) * 0.3 + sin(x * 5.1 + s * 0.7) * 0.2)
    }

    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    /// An image `size` points across, painted at `scale` pixels a point,
    /// y up, with the origin at the bottom left.
    static func image(_ size: CGSize, scale: CGFloat, _ paint: (CGContext) -> Void) -> CGImage? {
        let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.interpolationQuality = .high
        paint(ctx)
        return ctx.makeImage()
    }

    static func linear(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat]? = nil, from a: CGPoint, to b: CGPoint) {
        guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs) else { return }
        ctx.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    static func radial(_ ctx: CGContext, _ colors: [CGColor], _ locs: [CGFloat]? = nil, at p: CGPoint, radius: CGFloat) {
        guard let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs) else { return }
        ctx.drawRadialGradient(g, startCenter: p, startRadius: 0, endCenter: p, endRadius: radius, options: [])
    }

    /// Fills `path` with a gradient running from `a` to `b`.
    static func fill(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], _ locs: [CGFloat]? = nil, from a: CGPoint, to b: CGPoint) {
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        linear(ctx, colors, locs, from: a, to: b)
        ctx.restoreGState()
    }

    /// A soft round blur of colour: `radius` to nothing.
    static func glow(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, _ col: CGColor, strength: CGFloat = 1) {
        let (r, g, b, a) = rgba(col)
        radial(ctx, [c(r, g, b, a * strength), c(r, g, b, a * strength * 0.35), c(r, g, b, 0)], [0, 0.35, 1], at: p, radius: radius)
    }

    /// A closed path along the top of a silhouette: `y(x)` across `rect`,
    /// down to the bottom of it.
    static func silhouette(_ rect: CGRect, step: CGFloat, _ y: (CGFloat) -> CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: rect.minX - 2, y: rect.minY))
        var x = rect.minX - 2
        while x <= rect.maxX + step {
            p.addLine(to: CGPoint(x: x, y: y(x)))
            x += step
        }
        p.addLine(to: CGPoint(x: rect.maxX + 2, y: rect.minY))
        p.closeSubpath()
        return p
    }

    // MARK: The scene's measurements

    struct Frame {
        let rect: CGRect
        /// Points per scene point.
        var u: CGFloat { rect.width / HabitatLayout.width }
        var groundY: CGFloat { rect.minY + HabitatLayout.ground * rect.height / HabitatLayout.height }
        var air: CGFloat { rect.maxY - groundY }
        func x(_ f: CGFloat) -> CGFloat { rect.minX + rect.width * f }
        /// A height a fraction of the way up the air.
        func y(_ f: CGFloat) -> CGFloat { groundY + air * f }
    }

    // MARK: Palettes

    struct Palette {
        var skyTop: CGColor, skyMid: CGColor, skyLow: CGColor
        var far: CGColor, mid: CGColor, near: CGColor
        /// The top layer of the substrate, and the soil under it.
        var surface: CGColor, surfaceHi: CGColor, soil: CGColor, deep: CGColor, gravel: CGColor
        /// What the furniture is washed with to sit in the light of the place.
        var tint: CGColor, tintAmount: CGFloat
    }

    static func palette(_ b: Biome) -> Palette {
        switch b {
        case .forest:
            return Palette(skyTop: c(0.42, 0.66, 0.86), skyMid: c(0.70, 0.83, 0.90), skyLow: c(0.95, 0.92, 0.80),
                           far: c(0.56, 0.69, 0.72), mid: c(0.33, 0.50, 0.44), near: c(0.20, 0.36, 0.29),
                           surface: c(0.48, 0.36, 0.22), surfaceHi: c(0.62, 0.50, 0.30), soil: c(0.29, 0.20, 0.13), deep: c(0.20, 0.14, 0.09),
                           gravel: c(0.58, 0.53, 0.48), tint: c(1, 0.96, 0.86), tintAmount: 0.06)
        case .jungle:
            return Palette(skyTop: c(0.46, 0.74, 0.70), skyMid: c(0.70, 0.88, 0.78), skyLow: c(0.90, 0.96, 0.84),
                           far: c(0.46, 0.68, 0.58), mid: c(0.27, 0.52, 0.41), near: c(0.12, 0.34, 0.25),
                           surface: c(0.29, 0.44, 0.22), surfaceHi: c(0.42, 0.60, 0.28), soil: c(0.24, 0.18, 0.12), deep: c(0.16, 0.12, 0.08),
                           gravel: c(0.50, 0.46, 0.40), tint: c(0.86, 1, 0.9), tintAmount: 0.06)
        case .desert:
            return Palette(skyTop: c(0.30, 0.52, 0.84), skyMid: c(0.62, 0.74, 0.90), skyLow: c(0.99, 0.87, 0.68),
                           far: c(0.82, 0.60, 0.52), mid: c(0.93, 0.75, 0.53), near: c(0.88, 0.66, 0.42),
                           surface: c(0.93, 0.80, 0.58), surfaceHi: c(0.98, 0.89, 0.70), soil: c(0.80, 0.62, 0.42), deep: c(0.66, 0.48, 0.32),
                           gravel: c(0.72, 0.58, 0.46), tint: c(1, 0.9, 0.76), tintAmount: 0.1)
        case .meadow:
            return Palette(skyTop: c(0.32, 0.60, 0.92), skyMid: c(0.60, 0.80, 0.96), skyLow: c(0.88, 0.94, 0.98),
                           far: c(0.60, 0.77, 0.62), mid: c(0.46, 0.69, 0.38), near: c(0.32, 0.56, 0.28),
                           surface: c(0.38, 0.60, 0.26), surfaceHi: c(0.52, 0.74, 0.32), soil: c(0.33, 0.23, 0.15), deep: c(0.23, 0.16, 0.10),
                           gravel: c(0.60, 0.56, 0.50), tint: c(1, 1, 0.94), tintAmount: 0.04)
        case .cave:
            return Palette(skyTop: c(0.10, 0.09, 0.13), skyMid: c(0.17, 0.15, 0.20), skyLow: c(0.26, 0.22, 0.27),
                           far: c(0.24, 0.21, 0.27), mid: c(0.31, 0.27, 0.32), near: c(0.20, 0.17, 0.21),
                           surface: c(0.38, 0.35, 0.36), surfaceHi: c(0.50, 0.46, 0.46), soil: c(0.25, 0.22, 0.23), deep: c(0.17, 0.15, 0.16),
                           gravel: c(0.45, 0.42, 0.44), tint: c(0.2, 0.17, 0.28), tintAmount: 0.3)
        case .beach:
            return Palette(skyTop: c(0.30, 0.62, 0.92), skyMid: c(0.58, 0.82, 0.96), skyLow: c(0.90, 0.96, 0.98),
                           far: c(0.22, 0.56, 0.72), mid: c(0.30, 0.68, 0.76), near: c(0.44, 0.62, 0.58),
                           surface: c(0.95, 0.87, 0.68), surfaceHi: c(0.99, 0.94, 0.80), soil: c(0.86, 0.74, 0.54), deep: c(0.72, 0.60, 0.42),
                           gravel: c(0.80, 0.72, 0.60), tint: c(1, 0.97, 0.9), tintAmount: 0.05)
        case .tundra:
            return Palette(skyTop: c(0.08, 0.11, 0.28), skyMid: c(0.25, 0.27, 0.50), skyLow: c(0.86, 0.68, 0.72),
                           far: c(0.66, 0.70, 0.86), mid: c(0.36, 0.42, 0.58), near: c(0.18, 0.25, 0.35),
                           surface: c(0.92, 0.94, 0.99), surfaceHi: c(1, 1, 1), soil: c(0.36, 0.34, 0.40), deep: c(0.25, 0.24, 0.30),
                           gravel: c(0.55, 0.56, 0.62), tint: c(0.62, 0.66, 0.92), tintAmount: 0.18)
        case .night:
            return Palette(skyTop: c(0.03, 0.04, 0.13), skyMid: c(0.07, 0.10, 0.26), skyLow: c(0.16, 0.20, 0.40),
                           far: c(0.12, 0.16, 0.31), mid: c(0.08, 0.11, 0.22), near: c(0.05, 0.07, 0.14),
                           surface: c(0.17, 0.22, 0.22), surfaceHi: c(0.24, 0.32, 0.30), soil: c(0.12, 0.11, 0.12), deep: c(0.08, 0.07, 0.08),
                           gravel: c(0.30, 0.31, 0.36), tint: c(0.22, 0.28, 0.58), tintAmount: 0.46)
        }
    }

    /// Where the sun, or the moon, hangs in the sky, if there is one.
    static func sun(_ b: Biome, _ f: Frame) -> (point: CGPoint, radius: CGFloat)? {
        switch b {
        case .forest: return (CGPoint(x: f.x(0.8), y: f.y(0.8)), 30 * f.u)
        case .desert: return (CGPoint(x: f.x(0.72), y: f.y(0.72)), 42 * f.u)
        case .meadow: return (CGPoint(x: f.x(0.18), y: f.y(0.82)), 32 * f.u)
        case .beach: return (CGPoint(x: f.x(0.62), y: f.y(0.56)), 36 * f.u)
        case .night: return (CGPoint(x: f.x(0.8), y: f.y(0.8)), 30 * f.u)
        default: return nil
        }
    }

    // MARK: The sky

    static func paintSky(_ b: Biome, in rect: CGRect, _ ctx: CGContext) {
        let f = Frame(rect: rect)
        let p = palette(b)
        ctx.saveGState()
        ctx.clip(to: rect)
        linear(ctx, [p.skyTop, p.skyMid, p.skyLow], [0, 0.55, 1], from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: f.groundY + f.air * 0.12))
        switch b {
        case .night, .tundra:
            // Stars, fainter toward the horizon; the bright ones twinkle
            // on a layer of their own.
            let n = b == .night ? 170 : 90
            for k in 0..<n {
                let x = rect.minX + rnd(301, k) * rect.width
                let v = rnd(302, k)
                let y = f.y(0.3 + v * 0.7)
                let r = (0.4 + rnd(303, k) * rnd(304, k) * 1.3) * f.u
                ctx.setFillColor(c(1, 1, 0.95, (0.25 + 0.6 * v) * (b == .night ? 1 : 0.7)))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
            if b == .night {
                // A faint band of the Milky Way.
                ctx.saveGState()
                ctx.translateBy(x: f.x(0.35), y: f.y(0.6))
                ctx.rotate(by: -0.45)
                for k in 0..<120 {
                    let x = (rnd(311, k) - 0.5) * rect.width * 1.1
                    let y = (rnd(312, k) - 0.5) * (rnd(313, k) * 70) * f.u
                    glow(ctx, at: CGPoint(x: x, y: y), radius: (10 + rnd(314, k) * 26) * f.u, c(0.75, 0.78, 1, 0.05))
                }
                ctx.restoreGState()
                glow(ctx, at: CGPoint(x: f.x(0.5), y: f.groundY), radius: rect.width * 0.55, c(0.3, 0.36, 0.7, 0.35))
            }
        case .cave:
            // The back of the cave: rock, lit a little from a hole above.
            glow(ctx, at: CGPoint(x: f.x(0.56), y: rect.maxY), radius: rect.width * 0.5, c(0.55, 0.52, 0.62, 0.35))
        default:
            // The low sun warms the sky around it.
            if let s = sun(b, f) {
                glow(ctx, at: s.point, radius: rect.width * 0.55, c(1, 0.97, 0.85, 0.45))
            }
        }
        if let s = sun(b, f) {
            if b == .night {
                moon(ctx, at: s.point, radius: s.radius, u: f.u)
            } else {
                glow(ctx, at: s.point, radius: s.radius * 2.6, c(1, 0.96, 0.8, 0.6))
                ctx.setFillColor(b == .desert ? c(1, 0.96, 0.84) : c(1, 0.98, 0.9))
                ctx.fillEllipse(in: CGRect(x: s.point.x - s.radius, y: s.point.y - s.radius, width: s.radius * 2, height: s.radius * 2))
            }
        }
        ctx.restoreGState()
    }

    static func moon(_ ctx: CGContext, at p: CGPoint, radius r: CGFloat, u: CGFloat) {
        glow(ctx, at: p, radius: r * 4, c(0.8, 0.85, 1, 0.35))
        let disc = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.addEllipse(in: disc)
        ctx.clip()
        radial(ctx, [c(1, 0.99, 0.93), c(0.93, 0.92, 0.84)], at: CGPoint(x: p.x - r * 0.3, y: p.y + r * 0.3), radius: r * 1.4)
        for k in 0..<6 {
            let cx = p.x + (rnd(321, k) - 0.5) * r * 1.3, cy = p.y + (rnd(322, k) - 0.5) * r * 1.3
            let cr = (0.1 + rnd(323, k) * 0.18) * r
            ctx.setFillColor(c(0.78, 0.78, 0.72, 0.45))
            ctx.fillEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))
        }
        ctx.restoreGState()
    }

    // MARK: The distance

    /// The far scenery and the near: hills, woods, dunes, the sea — all
    /// the way down to the back of the substrate.
    static func paintScenery(_ b: Biome, in rect: CGRect, _ ctx: CGContext) {
        let f = Frame(rect: rect)
        let p = palette(b)
        let u = f.u
        ctx.saveGState()
        ctx.clip(to: rect)
        let horizon = f.y(0.2)
        switch b {
        case .forest:
            mountains(ctx, f, base: horizon, height: f.air * 0.42, seed: 3, colour: mix(p.far, p.skyLow, 0.35), snow: nil, shade: 0.05)
            mountains(ctx, f, base: horizon, height: f.air * 0.3, seed: 8, colour: p.far, snow: nil, shade: 0.06)
            haze(ctx, f, below: f.y(0.45), p.skyLow, 0.35)
            forestRow(ctx, f, base: f.y(0.12), height: f.air * 0.44, count: 26, seed: 5, colour: mix(p.mid, p.far, 0.45), pine: 0.8)
            haze(ctx, f, below: f.y(0.3), p.skyLow, 0.22)
            forestRow(ctx, f, base: f.groundY + 4 * u, height: f.air * 0.62, count: 14, seed: 9, colour: p.mid, pine: 0.7)
            forestRow(ctx, f, base: f.groundY, height: f.air * 0.4, count: 9, seed: 12, colour: p.near, pine: 0.5)
        case .jungle:
            canopy(ctx, f, base: f.y(0.34), height: f.air * 0.34, seed: 2, colour: mix(p.far, p.skyLow, 0.35))
            haze(ctx, f, below: f.y(0.5), p.skyLow, 0.3)
            canopy(ctx, f, base: f.y(0.18), height: f.air * 0.38, seed: 6, colour: p.far)
            haze(ctx, f, below: f.y(0.36), p.skyLow, 0.22)
            canopy(ctx, f, base: f.groundY, height: f.air * 0.36, seed: 9, colour: p.mid)
            for (k, x) in [0.07, 0.93, 0.36].enumerated() {
                palm(ctx, x: f.x(CGFloat(x)), base: f.groundY, height: f.air * (0.78 - CGFloat(k) * 0.12), lean: x > 0.5 ? -0.12 : 0.1, colour: p.near, u: u, seed: 40 + k)
            }
            for k in 0..<5 {
                bigLeaf(ctx, at: CGPoint(x: f.x(k < 3 ? 0.02 + CGFloat(k) * 0.05 : 0.9 + CGFloat(k - 3) * 0.07), y: f.groundY),
                        length: (110 + rnd(55, k) * 70) * u, angle: k < 3 ? 0.9 - CGFloat(k) * 0.35 : 2.2 + CGFloat(k - 3) * 0.4,
                        colour: shade(p.near, -0.1), u: u)
            }
            // Lianas hanging from the canopy.
            ctx.setStrokeColor(alpha(shade(p.near, 0.05), 0.85))
            for k in 0..<7 {
                let x = f.x(0.08 + rnd(61, k) * 0.84)
                let len = f.air * (0.2 + rnd(62, k) * 0.35)
                ctx.setLineWidth((1.5 + rnd(63, k) * 1.5) * u)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: rect.maxY + 2))
                ctx.addCurve(to: CGPoint(x: x + (rnd(64, k) - 0.5) * 30 * u, y: rect.maxY - len),
                             control1: CGPoint(x: x + 20 * u, y: rect.maxY - len * 0.3), control2: CGPoint(x: x - 20 * u, y: rect.maxY - len * 0.7))
                ctx.strokePath()
            }
        case .desert:
            mesas(ctx, f, base: f.y(0.24), colour: mix(p.far, p.skyLow, 0.3), u: u)
            haze(ctx, f, below: f.y(0.38), p.skyLow, 0.3)
            dunes(ctx, f, base: f.y(0.2), height: f.air * 0.12, seed: 4, light: shade(p.mid, 0.12), dark: p.mid)
            dunes(ctx, f, base: f.groundY + 10 * u, height: f.air * 0.16, seed: 11, light: shade(p.near, 0.14), dark: p.near)
            for k in 0..<3 {
                cactusSilhouette(ctx, x: f.x(0.15 + CGFloat(k) * 0.33 + rnd(71, k) * 0.1), base: f.y(0.12), h: (46 + rnd(72, k) * 30) * u, colour: alpha(shade(p.near, -0.35), 0.6), u: u)
            }
        case .meadow:
            hills(ctx, f, base: f.y(0.32), height: f.air * 0.16, seed: 3, colour: mix(p.far, p.skyLow, 0.3))
            treeClumps(ctx, f, base: f.y(0.3), seed: 5, colour: mix(p.near, p.far, 0.55), size: 26 * u, count: 9)
            hills(ctx, f, base: f.y(0.18), height: f.air * 0.18, seed: 7, colour: p.far)
            treeClumps(ctx, f, base: f.y(0.2), seed: 9, colour: mix(p.near, p.far, 0.3), size: 38 * u, count: 5)
            hills(ctx, f, base: f.groundY + 6 * u, height: f.air * 0.2, seed: 12, colour: p.mid)
            // Flowers dotted over the near hill.
            let cols = [c(1, 0.85, 0.3), c(1, 1, 1), c(0.95, 0.5, 0.6), c(0.75, 0.6, 1)]
            for k in 0..<140 {
                let x = rect.minX + rnd(81, k) * rect.width
                let y = f.groundY + rnd(82, k) * f.air * 0.16
                ctx.setFillColor(alpha(cols[k % cols.count], 0.85))
                let r = (1.2 + rnd(83, k) * 1.6) * u
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        case .cave:
            caveWalls(ctx, f, p, u: u)
        case .beach:
            // The sea to the horizon, an island, a palm on the near shore.
            let seaTop = f.y(0.34)
            let sea = CGRect(x: rect.minX, y: f.groundY, width: rect.width, height: seaTop - f.groundY)
            ctx.saveGState()
            ctx.clip(to: sea)
            linear(ctx, [shade(p.far, 0.1), p.far, p.mid], [0, 0.4, 1], from: CGPoint(x: 0, y: seaTop), to: CGPoint(x: 0, y: f.groundY))
            ctx.restoreGState()
            if let s = sun(b, f) {
                // The sun's path on the water.
                for k in 0..<18 {
                    let y = seaTop - CGFloat(k) * (seaTop - f.groundY) / 18
                    let w = (18 + CGFloat(k) * 5) * u * (0.6 + rnd(91, k) * 0.6)
                    ctx.setFillColor(c(1, 0.97, 0.85, 0.45 - CGFloat(k) * 0.02))
                    ctx.fill(CGRect(x: s.point.x - w / 2 + (rnd(92, k) - 0.5) * 20 * u, y: y - 1.2 * u, width: w, height: 1.6 * u))
                }
            }
            island(ctx, x: f.x(0.2), base: seaTop, u: u, colour: mix(p.near, p.skyLow, 0.45))
            ctx.setFillColor(alpha(c(1, 1, 1), 0.6))
            ctx.fill(CGRect(x: rect.minX, y: seaTop - 0.8 * u, width: rect.width, height: 1.2 * u))
            // The wet sand at the water's edge.
            let shore = silhouette(rect.insetBy(dx: 0, dy: 0).divided(atDistance: f.groundY - rect.minY + 26 * u, from: .minYEdge).slice, step: 6) {
                f.groundY + (14 + wave($0 / (80 * u), 5) * 8) * u
            }
            fill(ctx, shore, [shade(p.surface, -0.12), p.surface], from: CGPoint(x: 0, y: f.groundY + 26 * u), to: CGPoint(x: 0, y: f.groundY))
            palm(ctx, x: f.x(0.9), base: f.groundY, height: f.air * 0.74, lean: -0.22, colour: shade(p.near, -0.25), u: u, seed: 7)
        case .tundra:
            mountains(ctx, f, base: f.y(0.22), height: f.air * 0.5, seed: 21, colour: mix(p.far, p.skyLow, 0.25), snow: c(0.96, 0.95, 1), shade: 0.2)
            mountains(ctx, f, base: f.y(0.14), height: f.air * 0.34, seed: 24, colour: p.far, snow: c(1, 1, 1), shade: 0.22)
            haze(ctx, f, below: f.y(0.3), p.skyLow, 0.25)
            forestRow(ctx, f, base: f.y(0.08), height: f.air * 0.3, count: 28, seed: 25, colour: p.mid, pine: 1, snow: c(0.92, 0.94, 1))
            forestRow(ctx, f, base: f.groundY, height: f.air * 0.46, count: 10, seed: 27, colour: p.near, pine: 1, snow: c(0.95, 0.96, 1))
            // Snow drifts at the back.
            hills(ctx, f, base: f.groundY + 2 * u, height: 24 * u, seed: 29, colour: c(0.86, 0.89, 0.97))
        case .night:
            hills(ctx, f, base: f.y(0.3), height: f.air * 0.2, seed: 31, colour: p.far)
            cabin(ctx, x: f.x(0.3), base: f.y(0.36), u: u, colour: p.far)
            forestRow(ctx, f, base: f.y(0.14), height: f.air * 0.4, count: 20, seed: 33, colour: mix(p.mid, p.far, 0.4), pine: 0.6)
            haze(ctx, f, below: f.y(0.28), c(0.25, 0.3, 0.55), 0.25)
            forestRow(ctx, f, base: f.groundY, height: f.air * 0.6, count: 12, seed: 35, colour: p.mid, pine: 0.6)
            forestRow(ctx, f, base: f.groundY, height: f.air * 0.36, count: 8, seed: 37, colour: p.near, pine: 0.4)
        }
        ctx.restoreGState()
    }

    /// Lifts the colour toward the sky's at the bottom of the distance.
    static func haze(_ ctx: CGContext, _ f: Frame, below y: CGFloat, _ col: CGColor, _ a: CGFloat) {
        linear(ctx, [alpha(col, a), alpha(col, 0)], from: CGPoint(x: 0, y: f.groundY), to: CGPoint(x: 0, y: y))
    }

    static func mountains(_ ctx: CGContext, _ f: Frame, base: CGFloat, height: CGFloat, seed: Int, colour: CGColor, snow: CGColor?, shade k: CGFloat) {
        let r = f.rect
        // Peaks and saddles, left to right.
        var pts: [CGPoint] = [CGPoint(x: r.minX - 20, y: base + height * 0.3)]
        var x = r.minX - 20
        var i = 0
        while x < r.maxX + 40 {
            x += (60 + rnd(seed, i) * 110) * f.u
            let up = i % 2 == 0
            let y = base + height * (up ? 0.55 + rnd(seed + 1, i) * 0.45 : 0.15 + rnd(seed + 2, i) * 0.3)
            pts.append(CGPoint(x: x, y: y))
            i += 1
        }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: r.minX - 20, y: f.groundY))
        for p in pts { path.addLine(to: p) }
        path.addLine(to: CGPoint(x: x, y: f.groundY))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.setFillColor(colour)
        ctx.fillPath()
        // The shaded side of each peak.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setFillColor(shade(colour, -k))
        for j in 1..<(pts.count - 1) where pts[j].y > pts[j - 1].y && pts[j].y > pts[j + 1].y {
            let s = CGMutablePath()
            s.move(to: pts[j])
            s.addLine(to: pts[j + 1])
            s.addLine(to: CGPoint(x: pts[j + 1].x, y: f.groundY))
            s.addLine(to: CGPoint(x: pts[j].x + (pts[j + 1].x - pts[j].x) * 0.15, y: f.groundY))
            s.closeSubpath()
            ctx.addPath(s)
            ctx.fillPath()
        }
        if let snow {
            for j in 1..<(pts.count - 1) where pts[j].y > pts[j - 1].y && pts[j].y > pts[j + 1].y {
                let top = pts[j]
                let drop = (top.y - base) * 0.3
                let cap = CGMutablePath()
                let l = CGPoint(x: top.x + (pts[j - 1].x - top.x) * drop / max(top.y - pts[j - 1].y, 1), y: top.y - drop)
                let rr = CGPoint(x: top.x + (pts[j + 1].x - top.x) * drop / max(top.y - pts[j + 1].y, 1), y: top.y - drop)
                cap.move(to: top)
                cap.addLine(to: rr)
                for q in 0..<4 {
                    let t = 1 - CGFloat(q + 1) / 5
                    cap.addLine(to: CGPoint(x: l.x + (rr.x - l.x) * t, y: top.y - drop * (q % 2 == 0 ? 1.25 : 0.85)))
                }
                cap.addLine(to: l)
                cap.closeSubpath()
                ctx.addPath(cap)
                ctx.setFillColor(snow)
                ctx.fillPath()
            }
        }
        ctx.restoreGState()
    }

    static func hills(_ ctx: CGContext, _ f: Frame, base: CGFloat, height: CGFloat, seed: Int, colour: CGColor) {
        let path = silhouette(CGRect(x: f.rect.minX, y: f.groundY, width: f.rect.width, height: base - f.groundY), step: 4) {
            base + height * (0.5 + 0.5 * wave($0 / (140 * f.u), seed))
        }
        fill(ctx, path, [shade(colour, 0.06), colour, shade(colour, -0.06)], [0, 0.4, 1], from: CGPoint(x: 0, y: base + height), to: CGPoint(x: 0, y: f.groundY))
    }

    static func dunes(_ ctx: CGContext, _ f: Frame, base: CGFloat, height: CGFloat, seed: Int, light: CGColor, dark: CGColor) {
        let path = silhouette(CGRect(x: f.rect.minX, y: f.groundY, width: f.rect.width, height: base - f.groundY), step: 4) {
            let w = wave($0 / (120 * f.u), seed)
            return base + height * (0.5 + 0.5 * w * abs(w))
        }
        fill(ctx, path, [light, dark], from: CGPoint(x: 0, y: base + height), to: CGPoint(x: 0, y: f.groundY))
        // Ripples in the sand.
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setStrokeColor(alpha(shade(dark, -0.2), 0.25))
        ctx.setLineWidth(0.8 * f.u)
        for k in 0..<10 {
            let y = f.groundY + (base - f.groundY) * CGFloat(k) / 10
            ctx.beginPath()
            ctx.move(to: CGPoint(x: f.rect.minX, y: y))
            var x = f.rect.minX
            while x < f.rect.maxX {
                x += 8 * f.u
                ctx.addLine(to: CGPoint(x: x, y: y + wave(x / (30 * f.u), seed + k) * 3 * f.u))
            }
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    static func mesas(_ ctx: CGContext, _ f: Frame, base: CGFloat, colour: CGColor, u: CGFloat) {
        for k in 0..<3 {
            let cx = f.x([0.14, 0.52, 0.86][k])
            let w = (120 + rnd(141, k) * 90) * u, h = (60 + rnd(142, k) * 60) * u
            let path = CGMutablePath()
            path.move(to: CGPoint(x: cx - w / 2 - 30 * u, y: f.groundY))
            path.addLine(to: CGPoint(x: cx - w / 2, y: base + h * 0.7))
            path.addLine(to: CGPoint(x: cx - w / 2 + 8 * u, y: base + h))
            path.addLine(to: CGPoint(x: cx + w / 2 - 6 * u, y: base + h))
            path.addLine(to: CGPoint(x: cx + w / 2, y: base + h * 0.75))
            path.addLine(to: CGPoint(x: cx + w / 2 + 34 * u, y: f.groundY))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.setFillColor(colour)
            ctx.fillPath()
            // Bands of rock.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            for q in 0..<4 {
                ctx.setFillColor(alpha(shade(colour, q % 2 == 0 ? -0.08 : 0.06), 0.7))
                ctx.fill(CGRect(x: cx - w, y: base + h * (0.15 + CGFloat(q) * 0.2), width: w * 2, height: h * 0.07))
            }
            ctx.setFillColor(alpha(shade(colour, -0.12), 0.8))
            ctx.fill(CGRect(x: cx + w * 0.1, y: f.groundY, width: w, height: base + h))
            ctx.restoreGState()
        }
    }

    static func cactusSilhouette(_ ctx: CGContext, x: CGFloat, base: CGFloat, h: CGFloat, colour: CGColor, u: CGFloat) {
        ctx.setFillColor(colour)
        let w = h * 0.16
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - w / 2, y: base, width: w, height: h), cornerWidth: w / 2, cornerHeight: w / 2, transform: nil))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - w * 1.6, y: base + h * 0.4, width: w * 0.8, height: h * 0.35), cornerWidth: w * 0.4, cornerHeight: w * 0.4, transform: nil))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - w * 1.6, y: base + h * 0.4, width: w * 1.4, height: w * 0.7), cornerWidth: w * 0.35, cornerHeight: w * 0.35, transform: nil))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x + w * 0.8, y: base + h * 0.5, width: w * 0.8, height: h * 0.3), cornerWidth: w * 0.4, cornerHeight: w * 0.4, transform: nil))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x + w * 0.2, y: base + h * 0.5, width: w * 1.4, height: w * 0.7), cornerWidth: w * 0.35, cornerHeight: w * 0.35, transform: nil))
        ctx.fillPath()
    }

    /// A row of trees along `base`: pines, round-topped, or a mix
    /// (`pine` is the share of pines).
    static func forestRow(_ ctx: CGContext, _ f: Frame, base: CGFloat, height: CGFloat, count: Int, seed: Int, colour: CGColor, pine: CGFloat, snow: CGColor? = nil) {
        for k in 0..<count {
            let x = f.rect.minX + (CGFloat(k) + rnd(seed, k) * 0.9 - 0.2) / CGFloat(count) * f.rect.width
            let h = height * (0.6 + rnd(seed + 1, k) * 0.45)
            let col = shade(colour, (rnd(seed + 2, k) - 0.5) * 0.12)
            if rnd(seed + 3, k) < pine {
                pineTree(ctx, x: x, base: base, h: h, w: h * (0.34 + rnd(seed + 4, k) * 0.1), colour: col, snow: snow, u: f.u)
            } else {
                roundTree(ctx, x: x, base: base, h: h * 0.8, colour: col, seed: seed * 31 + k, u: f.u)
            }
        }
    }

    static func pineTree(_ ctx: CGContext, x: CGFloat, base: CGFloat, h: CGFloat, w: CGFloat, colour: CGColor, snow: CGColor?, u: CGFloat) {
        ctx.setFillColor(shade(colour, -0.15))
        ctx.fill(CGRect(x: x - w * 0.05, y: base - 2, width: w * 0.1, height: h * 0.2))
        let tiers = 4
        for i in 0..<tiers {
            let t = CGFloat(i) / CGFloat(tiers)
            let yb = base + h * (0.1 + t * 0.62)
            let yt = base + h * (0.42 + t * 0.58)
            let hw = w / 2 * (1 - t * 0.62)
            let tier = CGMutablePath()
            tier.move(to: CGPoint(x: x - hw, y: yb))
            tier.addQuadCurve(to: CGPoint(x: x, y: yt), control: CGPoint(x: x - hw * 0.3, y: yb + (yt - yb) * 0.4))
            tier.addQuadCurve(to: CGPoint(x: x + hw, y: yb), control: CGPoint(x: x + hw * 0.3, y: yb + (yt - yb) * 0.4))
            tier.addQuadCurve(to: CGPoint(x: x - hw, y: yb), control: CGPoint(x: x, y: yb + (yt - yb) * 0.12))
            ctx.addPath(tier)
            ctx.setFillColor(colour)
            ctx.fillPath()
            if let snow {
                ctx.saveGState()
                ctx.addPath(tier)
                ctx.clip()
                let cap = CGMutablePath()
                cap.move(to: CGPoint(x: x - hw, y: yt))
                cap.addLine(to: CGPoint(x: x + hw, y: yt))
                cap.addLine(to: CGPoint(x: x + hw, y: yt - (yt - yb) * 0.42))
                for q in 0..<5 {
                    let qx = x + hw - CGFloat(q + 1) * hw * 2 / 6
                    cap.addLine(to: CGPoint(x: qx, y: yt - (yt - yb) * (q % 2 == 0 ? 0.62 : 0.4)))
                }
                cap.addLine(to: CGPoint(x: x - hw, y: yt - (yt - yb) * 0.42))
                cap.closeSubpath()
                ctx.addPath(cap)
                ctx.setFillColor(snow)
                ctx.fillPath()
                ctx.restoreGState()
            }
        }
    }

    static func roundTree(_ ctx: CGContext, x: CGFloat, base: CGFloat, h: CGFloat, colour: CGColor, seed: Int, u: CGFloat) {
        ctx.setFillColor(shade(colour, -0.2))
        ctx.fill(CGRect(x: x - h * 0.03, y: base - 2, width: h * 0.06, height: h * 0.5))
        let r = h * 0.28
        for k in 0..<6 {
            let a = CGFloat(k) / 6 * .pi * 2
            let cx = x + cos(a) * r * 0.55, cy = base + h * 0.62 + sin(a) * r * 0.5
            let cr = r * (0.6 + rnd(seed, k) * 0.3)
            ctx.setFillColor(colour)
            ctx.fillEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))
        }
        // A little light on the sunny side of the crown.
        ctx.setFillColor(alpha(shade(colour, 0.05), 0.35))
        ctx.fillEllipse(in: CGRect(x: x - r * 0.8, y: base + h * 0.72, width: r * 0.9, height: r * 0.5))
    }

    static func treeClumps(_ ctx: CGContext, _ f: Frame, base: CGFloat, seed: Int, colour: CGColor, size: CGFloat, count: Int) {
        for k in 0..<count {
            let x = f.rect.minX + rnd(seed, k) * f.rect.width
            let n = 1 + Int(rnd(seed + 1, k) * 3)
            for j in 0..<n {
                roundTree(ctx, x: x + CGFloat(j) * size * 0.7, base: base + wave(x / 100, seed) * 4, h: size * (1 + rnd(seed + 2, k * 5 + j) * 0.8), colour: colour, seed: seed + k * 7 + j, u: f.u)
            }
        }
    }

    /// Rainforest seen from afar: a bumpy line of crowns.
    static func canopy(_ ctx: CGContext, _ f: Frame, base: CGFloat, height: CGFloat, seed: Int, colour: CGColor) {
        ctx.setFillColor(colour)
        ctx.fill(CGRect(x: f.rect.minX, y: f.groundY, width: f.rect.width, height: base - f.groundY + height * 0.3))
        var x = f.rect.minX - 20
        var k = 0
        while x < f.rect.maxX + 30 {
            let r = (22 + rnd(seed, k) * 34) * f.u
            let y = base + height * (0.2 + rnd(seed + 1, k) * 0.6)
            ctx.setFillColor(shade(colour, (rnd(seed + 2, k) - 0.5) * 0.1))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6))
            // Down to the base below it.
            ctx.fill(CGRect(x: x - r * 0.9, y: f.groundY, width: r * 1.8, height: y - f.groundY))
            ctx.setFillColor(alpha(shade(colour, 0.12), 0.8))
            ctx.fillEllipse(in: CGRect(x: x - r * 0.6, y: y + r * 0.1, width: r * 0.9, height: r * 0.55))
            x += r * 1.2
            k += 1
        }
    }

    static func palm(_ ctx: CGContext, x: CGFloat, base: CGFloat, height h: CGFloat, lean: CGFloat, colour: CGColor, u: CGFloat, seed: Int) {
        let top = CGPoint(x: x + lean * h, y: base + h)
        ctx.setStrokeColor(colour)
        ctx.setLineWidth(9 * u)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: x, y: base - 4))
        ctx.addQuadCurve(to: top, control: CGPoint(x: x - lean * h * 0.4, y: base + h * 0.55))
        ctx.strokePath()
        ctx.setFillColor(colour)
        for k in 0..<7 {
            let a = CGFloat(k) / 7 * .pi * 1.3 - 0.15 + (rnd(seed, k) - 0.5) * 0.2
            let len = h * (0.34 + rnd(seed + 1, k) * 0.12)
            let dir = CGPoint(x: cos(a), y: sin(a))
            let tip = CGPoint(x: top.x + dir.x * len, y: top.y + dir.y * len * 0.55 - len * 0.35)
            let leaf = CGMutablePath()
            leaf.move(to: top)
            leaf.addQuadCurve(to: tip, control: CGPoint(x: top.x + dir.x * len * 0.5, y: top.y + len * 0.3))
            leaf.addQuadCurve(to: top, control: CGPoint(x: top.x + dir.x * len * 0.6, y: top.y + len * 0.02))
            ctx.addPath(leaf)
            ctx.fillPath()
        }
    }

    static func bigLeaf(_ ctx: CGContext, at p: CGPoint, length: CGFloat, angle: CGFloat, colour: CGColor, u: CGFloat) {
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        let leaf = CGMutablePath()
        leaf.move(to: .zero)
        leaf.addCurve(to: CGPoint(x: length, y: 0), control1: CGPoint(x: length * 0.3, y: length * 0.32), control2: CGPoint(x: length * 0.8, y: length * 0.22))
        leaf.addCurve(to: .zero, control1: CGPoint(x: length * 0.8, y: -length * 0.2), control2: CGPoint(x: length * 0.3, y: -length * 0.3))
        ctx.addPath(leaf)
        ctx.setFillColor(colour)
        ctx.fillPath()
        ctx.setStrokeColor(shade(colour, 0.12))
        ctx.setLineWidth(1.5 * u)
        ctx.beginPath()
        ctx.move(to: .zero)
        ctx.addQuadCurve(to: CGPoint(x: length * 0.95, y: 0), control: CGPoint(x: length * 0.5, y: length * 0.04))
        ctx.strokePath()
        ctx.restoreGState()
    }

    static func island(_ ctx: CGContext, x: CGFloat, base: CGFloat, u: CGFloat, colour: CGColor) {
        let w = 150 * u, h = 26 * u
        let p = CGMutablePath()
        p.move(to: CGPoint(x: x - w / 2, y: base))
        p.addCurve(to: CGPoint(x: x + w / 2, y: base), control1: CGPoint(x: x - w * 0.25, y: base + h * 1.4), control2: CGPoint(x: x + w * 0.2, y: base + h * 0.9))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(colour)
        ctx.fillPath()
        palm(ctx, x: x - w * 0.12, base: base + h * 0.7, height: 34 * u, lean: 0.15, colour: colour, u: u * 0.35, seed: 3)
    }

    static func cabin(_ ctx: CGContext, x: CGFloat, base: CGFloat, u: CGFloat, colour: CGColor) {
        let w = 22 * u, h = 14 * u
        ctx.setFillColor(shade(colour, -0.2))
        ctx.fill(CGRect(x: x - w / 2, y: base, width: w, height: h))
        let roof = CGMutablePath()
        roof.move(to: CGPoint(x: x - w * 0.62, y: base + h))
        roof.addLine(to: CGPoint(x: x, y: base + h + 10 * u))
        roof.addLine(to: CGPoint(x: x + w * 0.62, y: base + h))
        roof.closeSubpath()
        ctx.addPath(roof)
        ctx.fillPath()
        glow(ctx, at: CGPoint(x: x + 3 * u, y: base + h * 0.5), radius: 16 * u, c(1, 0.8, 0.4, 0.5))
        ctx.setFillColor(c(1, 0.85, 0.5))
        ctx.fill(CGRect(x: x + 1 * u, y: base + h * 0.3, width: 4 * u, height: 4 * u))
    }

    static func caveWalls(_ ctx: CGContext, _ f: Frame, _ p: Palette, u: CGFloat) {
        let r = f.rect
        // Layers of rock from far to near, each a jagged mass from the
        // sides and the roof, leaving the middle open.
        for (layer, col) in [(0, p.far), (1, p.mid), (2, p.near)] {
            let inset = CGFloat(2 - layer) * 0.08
            let roof = silhouette(CGRect(x: r.minX, y: r.maxY, width: r.width, height: 0), step: 5) { x in
                r.maxY - f.air * (0.08 + inset * 0.3 + 0.07 * (1 + wave(x / (60 * u), 50 + layer)))
            }
            // The roof: from the top down to its ragged edge.
            ctx.addPath(roof)
            ctx.setFillColor(col)
            ctx.fillPath()
            for side in [0, 1] {
                let w = r.width * (0.1 + CGFloat(layer) * 0.05 + inset)
                let path = CGMutablePath()
                let x0 = side == 0 ? r.minX : r.maxX
                path.move(to: CGPoint(x: x0, y: f.groundY - 4))
                var y = f.groundY - 4
                var k = 0
                while y < r.maxY + 10 {
                    let reach = w * (0.6 + 0.4 * wave(y / (50 * u), 60 + layer * 3 + side))
                    path.addLine(to: CGPoint(x: side == 0 ? x0 + reach : x0 - reach, y: y))
                    y += (14 + rnd(61 + layer, k) * 20) * u
                    k += 1
                }
                path.addLine(to: CGPoint(x: x0, y: r.maxY + 10))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.setFillColor(col)
                ctx.fillPath()
            }
            // Stalactites off the roof.
            for k in 0..<(8 + layer * 3) {
                let x = r.minX + rnd(70 + layer, k) * r.width
                let top = r.maxY - f.air * 0.1
                let len = (20 + rnd(71 + layer, k) * 60) * u * (0.6 + CGFloat(layer) * 0.25)
                let w = (6 + rnd(72 + layer, k) * 10) * u
                let s = CGMutablePath()
                s.move(to: CGPoint(x: x - w, y: top + 20 * u))
                s.addLine(to: CGPoint(x: x - w * 0.6, y: top - len * 0.5))
                s.addQuadCurve(to: CGPoint(x: x + w * 0.6, y: top - len * 0.5), control: CGPoint(x: x, y: top - len * 1.1))
                s.addLine(to: CGPoint(x: x + w, y: top + 20 * u))
                s.closeSubpath()
                fill(ctx, s, [col, shade(col, 0.1)], from: CGPoint(x: x - w, y: 0), to: CGPoint(x: x + w, y: 0))
            }
            // Stalagmites at the back of the floor.
            if layer < 2 {
                for k in 0..<6 {
                    let x = r.minX + rnd(80 + layer, k) * r.width
                    let len = (26 + rnd(81 + layer, k) * 50) * u
                    let w = (10 + rnd(82 + layer, k) * 10) * u
                    let s = CGMutablePath()
                    s.move(to: CGPoint(x: x - w, y: f.groundY - 2))
                    s.addQuadCurve(to: CGPoint(x: x, y: f.groundY + len), control: CGPoint(x: x - w * 0.3, y: f.groundY + len * 0.5))
                    s.addQuadCurve(to: CGPoint(x: x + w, y: f.groundY - 2), control: CGPoint(x: x + w * 0.3, y: f.groundY + len * 0.5))
                    s.closeSubpath()
                    ctx.addPath(s)
                    ctx.setFillColor(shade(col, 0.04))
                    ctx.fillPath()
                }
            }
        }
        // Crystals set in the rock, softly lit (their glow breathes on a
        // layer of its own).
        for (k, spot) in crystalSpots(f).enumerated() {
            crystalCluster(ctx, at: spot.point, size: spot.size, hue: k % 2 == 0 ? c(0.45, 0.85, 1) : c(0.78, 0.55, 1), u: u)
        }
    }

    /// Where the glowing crystals in the cave's walls are.
    static func crystalSpots(_ f: Frame) -> [(point: CGPoint, size: CGFloat, colour: CGColor)] {
        [(CGPoint(x: f.x(0.07), y: f.y(0.42)), 34 * f.u, c(0.45, 0.85, 1)),
         (CGPoint(x: f.x(0.9), y: f.y(0.3)), 44 * f.u, c(0.78, 0.55, 1)),
         (CGPoint(x: f.x(0.95), y: f.y(0.66)), 26 * f.u, c(0.45, 0.85, 1)),
         (CGPoint(x: f.x(0.04), y: f.y(0.72)), 22 * f.u, c(0.78, 0.55, 1))]
    }

    static func crystalCluster(_ ctx: CGContext, at p: CGPoint, size: CGFloat, hue: CGColor, u: CGFloat) {
        for k in 0..<4 {
            let a = -0.6 + CGFloat(k) * 0.4
            let len = size * (0.6 + rnd(91, k) * 0.5)
            let w = size * 0.16
            ctx.saveGState()
            ctx.translateBy(x: p.x, y: p.y)
            ctx.rotate(by: a)
            let s = CGMutablePath()
            s.move(to: CGPoint(x: -w, y: 0))
            s.addLine(to: CGPoint(x: -w, y: len * 0.8))
            s.addLine(to: CGPoint(x: 0, y: len))
            s.addLine(to: CGPoint(x: w, y: len * 0.8))
            s.addLine(to: CGPoint(x: w, y: 0))
            s.closeSubpath()
            fill(ctx, s, [shade(hue, 0.35), hue, shade(hue, -0.3)], [0, 0.45, 1], from: CGPoint(x: -w, y: 0), to: CGPoint(x: w, y: 0))
            ctx.restoreGState()
        }
    }

    // MARK: The substrate

    /// How far above the ground line the ground image reaches: the back of
    /// the substrate, with its tufts and stones.
    static func groundOverhang(_ f: Frame) -> CGFloat { 30 * f.u }

    /// The substrate through the front of the tank: drainage stones at the
    /// bottom, soil, and the biome's own top layer, with the top of it seen
    /// a little from above as a band the spider walks along.
    static func paintGround(_ b: Biome, in rect: CGRect, _ ctx: CGContext) {
        let f = Frame(rect: rect)
        let p = palette(b)
        let u = f.u
        let g = f.groundY
        let depth = g - rect.minY
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: depth + groundOverhang(f)))

        // The back edge of the ground: low tufts and stones, a shade darker.
        backRow(ctx, b, f, p)

        // The top surface, seen from a little above.
        let topBand = CGRect(x: rect.minX, y: g - 12 * u, width: rect.width, height: 18 * u)
        let top = silhouette(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0), step: 5) {
            g + (4 + wave($0 / (26 * u), 3) * 1.6) * u
        }
        fill(ctx, top, [p.surfaceHi, p.surface], from: CGPoint(x: 0, y: topBand.maxY), to: CGPoint(x: 0, y: topBand.minY))

        // The front cross-section, below the top.
        let front = silhouette(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0), step: 5) {
            g - (9 + wave($0 / (40 * u), 8) * 2.4) * u
        }
        ctx.saveGState()
        ctx.addPath(front)
        ctx.clip()
        linear(ctx, [p.soil, p.deep], from: CGPoint(x: 0, y: g - 10 * u), to: CGPoint(x: 0, y: rect.minY))
        // Drainage stones along the bottom.
        let stoneTop = rect.minY + depth * 0.32
        ctx.setFillColor(alpha(shade(p.gravel, -0.35), 0.9))
        ctx.fill(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: stoneTop - rect.minY))
        var x = rect.minX - 6 * u
        var k = 0
        while x < rect.maxX + 10 {
            for row in 0..<2 {
                let rr = (5 + rnd(401, k * 3 + row) * 5) * u
                let cx = x + CGFloat(row) * 5 * u, cy = rect.minY + CGFloat(row) * rr * 1.3 + rr * 0.7
                let col = shade(p.gravel, (rnd(402, k * 3 + row) - 0.5) * 0.3)
                let stone = CGPath(ellipseIn: CGRect(x: cx - rr * 1.15, y: cy - rr * 0.85, width: rr * 2.3, height: rr * 1.7), transform: nil)
                fill(ctx, stone, [shade(col, 0.22), col, shade(col, -0.25)], [0, 0.45, 1], from: CGPoint(x: cx - rr, y: cy + rr), to: CGPoint(x: cx + rr, y: cy - rr))
            }
            x += (9 + rnd(403, k) * 6) * u
            k += 1
        }
        // A fine line where the stones meet the soil (the mesh).
        ctx.setFillColor(alpha(c(0, 0, 0), 0.25))
        ctx.fill(CGRect(x: rect.minX, y: stoneTop, width: rect.width, height: 1.2 * u))
        // The soil: specks, bits of root, the odd pebble against the glass.
        for k in 0..<Int(rect.width / (4 * u)) {
            let sx = rect.minX + rnd(411, k) * rect.width
            let sy = stoneTop + 3 * u + rnd(412, k) * (g - stoneTop - 10 * u)
            let r = (0.5 + rnd(413, k) * 1.3) * u
            ctx.setFillColor(k % 3 == 0 ? alpha(shade(p.soil, 0.25), 0.7) : alpha(shade(p.soil, -0.35), 0.7))
            ctx.fillEllipse(in: CGRect(x: sx - r, y: sy - r * 0.7, width: r * 2, height: r * 1.4))
        }
        ctx.setStrokeColor(alpha(shade(p.soil, 0.18), 0.55))
        ctx.setLineWidth(0.9 * u)
        for k in 0..<Int(rect.width / (90 * u)) + 2 {
            let sx = rect.minX + rnd(421, k) * rect.width
            let sy = g - 12 * u
            ctx.beginPath()
            ctx.move(to: CGPoint(x: sx, y: sy))
            ctx.addCurve(to: CGPoint(x: sx + (rnd(422, k) - 0.5) * 30 * u, y: sy - (10 + rnd(423, k) * 16) * u),
                         control1: CGPoint(x: sx + 8 * u, y: sy - 5 * u), control2: CGPoint(x: sx - 6 * u, y: sy - 10 * u))
            ctx.strokePath()
        }
        for k in 0..<Int(rect.width / (60 * u)) {
            let sx = rect.minX + rnd(431, k) * rect.width
            let sy = stoneTop + 6 * u + rnd(432, k) * (g - stoneTop - 22 * u)
            let rr = (2.5 + rnd(433, k) * 3.5) * u
            let col = shade(p.gravel, (rnd(434, k) - 0.5) * 0.3)
            fill(ctx, CGPath(ellipseIn: CGRect(x: sx - rr * 1.2, y: sy - rr, width: rr * 2.4, height: rr * 2), transform: nil),
                 [shade(col, 0.2), shade(col, -0.2)], from: CGPoint(x: sx, y: sy + rr), to: CGPoint(x: sx, y: sy - rr))
        }
        // The top layer, in section: litter, moss, sand or snow, down to
        // a wavy line a little below the top.
        let under: (CGFloat) -> CGFloat = { g - (21 + wave($0 / (24 * u), 17) * 3) * u }
        let layer = CGMutablePath()
        layer.move(to: CGPoint(x: rect.minX - 2, y: g + 4 * u))
        layer.addLine(to: CGPoint(x: rect.maxX + 2, y: g + 4 * u))
        var lx = rect.maxX + 2
        while lx >= rect.minX - 7 {
            layer.addLine(to: CGPoint(x: lx, y: under(lx)))
            lx -= 5
        }
        layer.closeSubpath()
        ctx.saveGState()
        ctx.addPath(layer)
        ctx.clip()
        linear(ctx, [shade(p.surface, -0.08), shade(p.surface, -0.2)], from: CGPoint(x: 0, y: g - 9 * u), to: CGPoint(x: 0, y: g - 24 * u))
        surfaceDetail(ctx, b, f, p, from: g - 24 * u, to: g - 8 * u)
        ctx.restoreGState()
        // Shade toward the bottom, and a soft line of light along the top.
        linear(ctx, [alpha(c(0, 0, 0), 0), alpha(c(0, 0, 0), 0.28)], from: CGPoint(x: 0, y: g - 14 * u), to: CGPoint(x: 0, y: rect.minY))
        ctx.restoreGState()

        // The lip of the front, where the top meets the section.
        ctx.saveGState()
        ctx.addPath(front)
        ctx.setStrokeColor(alpha(shade(p.surfaceHi, 0.1), 0.55))
        ctx.setLineWidth(1.2 * u)
        ctx.strokePath()
        ctx.restoreGState()

        // Bits lying on the top: a scatter of the biome's own litter.
        topLitter(ctx, b, f, p)
        ctx.restoreGState()
    }

    static func backRow(_ ctx: CGContext, _ b: Biome, _ f: Frame, _ p: Palette) {
        let u = f.u, g = f.groundY
        let col = shade(p.surface, b == .tundra ? -0.06 : -0.18)
        // A low bank at the back.
        let bank = silhouette(CGRect(x: f.rect.minX, y: g - 2 * u, width: f.rect.width, height: 0), step: 5) {
            g + (5 + wave($0 / (50 * u), 23) * 3) * u
        }
        ctx.addPath(bank)
        ctx.setFillColor(col)
        ctx.fillPath()
        switch b {
        case .forest, .jungle, .meadow, .night:
            let green = b == .night ? c(0.12, 0.2, 0.2) : (b == .meadow ? shade(p.near, 0.1) : shade(p.mid, -0.05))
            ctx.setStrokeColor(green)
            for k in 0..<Int(f.rect.width / (7 * u)) {
                let x = f.rect.minX + rnd(501, k) * f.rect.width
                let h = (6 + rnd(502, k) * (b == .meadow ? 20 : 13)) * u
                ctx.setLineWidth((1 + rnd(503, k)) * u)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: g + 2 * u))
                ctx.addQuadCurve(to: CGPoint(x: x + (rnd(504, k) - 0.5) * 8 * u, y: g + h), control: CGPoint(x: x, y: g + h * 0.6))
                ctx.strokePath()
            }
        case .desert, .beach:
            for k in 0..<18 {
                let x = f.rect.minX + rnd(511, k) * f.rect.width
                let r = (2 + rnd(512, k) * 4) * u
                ctx.setFillColor(shade(p.gravel, (rnd(513, k) - 0.5) * 0.3))
                ctx.fillEllipse(in: CGRect(x: x - r * 1.3, y: g + 2 * u, width: r * 2.6, height: r * 1.6))
            }
        case .cave:
            for k in 0..<22 {
                let x = f.rect.minX + rnd(521, k) * f.rect.width
                let r = (2 + rnd(522, k) * 6) * u
                ctx.setFillColor(shade(p.gravel, -0.2 + (rnd(523, k) - 0.5) * 0.2))
                ctx.fillEllipse(in: CGRect(x: x - r * 1.3, y: g + 1 * u, width: r * 2.6, height: r * 1.7))
            }
        case .tundra:
            break
        }
    }

    static func surfaceDetail(_ ctx: CGContext, _ b: Biome, _ f: Frame, _ p: Palette, from y0: CGFloat, to y1: CGFloat) {
        let u = f.u
        let n = Int(f.rect.width / (5 * u))
        for k in 0..<n {
            let x = f.rect.minX + rnd(601, k) * f.rect.width
            let y = y0 + rnd(602, k) * (y1 - y0)
            switch b {
            case .forest, .night:
                // Leaf litter, broken up.
                let cols = b == .night ? [c(0.2, 0.22, 0.24), c(0.15, 0.2, 0.18)] : [c(0.66, 0.42, 0.2), c(0.52, 0.34, 0.18), c(0.42, 0.5, 0.26)]
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: (rnd(603, k) - 0.5) * 1.4)
                ctx.setFillColor(alpha(cols[k % cols.count], 0.85))
                ctx.fillEllipse(in: CGRect(x: -3 * u, y: -1.4 * u, width: 6 * u, height: 2.8 * u))
                ctx.restoreGState()
            case .jungle, .meadow:
                ctx.setFillColor(alpha(k % 2 == 0 ? shade(p.surface, 0.15) : shade(p.surface, -0.15), 0.8))
                let r = (1.2 + rnd(604, k) * 2) * u
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.6, width: r * 2, height: r * 1.2))
            case .desert, .beach:
                ctx.setFillColor(alpha(k % 2 == 0 ? shade(p.surface, 0.12) : shade(p.surface, -0.14), 0.7))
                let r = (0.5 + rnd(605, k) * 0.9) * u
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            case .cave:
                ctx.setFillColor(alpha(shade(p.gravel, (rnd(606, k) - 0.5) * 0.4), 0.9))
                let r = (0.8 + rnd(607, k) * 1.8) * u
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4))
            case .tundra:
                ctx.setFillColor(alpha(c(0.8, 0.86, 1), 0.5))
                let r = (0.6 + rnd(608, k) * 1.2) * u
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    static func topLitter(_ ctx: CGContext, _ b: Biome, _ f: Frame, _ p: Palette) {
        let u = f.u, g = f.groundY
        let n = Int(f.rect.width / (22 * u))
        for k in 0..<n {
            let x = f.rect.minX + rnd(701, k) * f.rect.width
            let y = g - 8 * u + rnd(702, k) * 12 * u
            switch b {
            case .forest, .night:
                let cols = b == .night ? [c(0.22, 0.26, 0.3)] : [c(0.8, 0.5, 0.2), c(0.66, 0.36, 0.16), c(0.86, 0.66, 0.26)]
                ctx.saveGState()
                ctx.translateBy(x: x, y: y)
                ctx.rotate(by: (rnd(703, k) - 0.5) * 2)
                ctx.setFillColor(cols[k % cols.count])
                let leaf = CGMutablePath()
                leaf.move(to: CGPoint(x: -5 * u, y: 0))
                leaf.addQuadCurve(to: CGPoint(x: 5 * u, y: 0), control: CGPoint(x: 0, y: 4 * u))
                leaf.addQuadCurve(to: CGPoint(x: -5 * u, y: 0), control: CGPoint(x: 0, y: -4 * u))
                ctx.addPath(leaf)
                ctx.fillPath()
                ctx.restoreGState()
            case .jungle, .meadow:
                ctx.setStrokeColor(shade(p.surfaceHi, 0.1))
                ctx.setLineWidth(1 * u)
                for j in 0..<3 {
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: x + CGFloat(j) * 2 * u, y: y))
                    ctx.addLine(to: CGPoint(x: x + CGFloat(j - 1) * 3 * u, y: y + (4 + rnd(704, k * 3 + j) * 5) * u))
                    ctx.strokePath()
                }
            case .desert, .beach, .cave:
                let r = (1.5 + rnd(705, k) * 2.5) * u
                let col = b == .beach && k % 4 == 0 ? c(0.98, 0.9, 0.86) : shade(p.gravel, (rnd(706, k) - 0.5) * 0.3)
                fill(ctx, CGPath(ellipseIn: CGRect(x: x - r * 1.3, y: y - r * 0.8, width: r * 2.6, height: r * 1.6), transform: nil),
                     [shade(col, 0.2), shade(col, -0.2)], from: CGPoint(x: x, y: y + r), to: CGPoint(x: x, y: y - r))
            case .tundra:
                ctx.setFillColor(c(1, 1, 1, 0.7))
                let r = (3 + rnd(707, k) * 5) * u
                ctx.fillEllipse(in: CGRect(x: x - r * 1.5, y: y - r * 0.5, width: r * 3, height: r))
            }
        }
    }

    // MARK: The glass

    /// Over everything: the glass, with its edges in shadow, a faint
    /// reflection or two across it, and a line of light down its edge.
    static func paintGlass(in rect: CGRect, _ ctx: CGContext, dark: Bool) {
        let u = rect.width / HabitatLayout.width
        let edge = 26 * u
        let shadow = c(0, 0, 0, dark ? 0.4 : 0.28)
        let clear = c(0, 0, 0, 0)
        linear(ctx, [shadow, clear], from: CGPoint(x: rect.minX, y: 0), to: CGPoint(x: rect.minX + edge, y: 0))
        linear(ctx, [shadow, clear], from: CGPoint(x: rect.maxX, y: 0), to: CGPoint(x: rect.maxX - edge, y: 0))
        linear(ctx, [shadow, clear], from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.maxY - edge * 1.2))
        linear(ctx, [alpha(shadow, 0.2), clear], from: CGPoint(x: 0, y: rect.minY), to: CGPoint(x: 0, y: rect.minY + edge * 0.5))
        // Reflections: two soft diagonal streaks.
        ctx.saveGState()
        ctx.clip(to: rect)
        for (x0, w, a) in [(0.1, 0.07, 0.05), (0.2, 0.025, 0.04), (0.74, 0.05, 0.025)] {
            let x = rect.minX + rect.width * CGFloat(x0)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.width * CGFloat(w), y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.width * CGFloat(w) - rect.height * 0.55, y: rect.minY))
            p.addLine(to: CGPoint(x: x - rect.height * 0.55, y: rect.minY))
            p.closeSubpath()
            fill(ctx, p, [c(1, 1, 1, CGFloat(a)), c(1, 1, 1, 0)], from: CGPoint(x: 0, y: rect.maxY), to: CGPoint(x: 0, y: rect.minY + rect.height * 0.2))
        }
        ctx.restoreGState()
        // The polished edge of the glass.
        ctx.setStrokeColor(c(1, 1, 1, 0.16))
        ctx.setLineWidth(1)
        ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }

    // MARK: Pictures for the moving parts

    static func cloud(seed: Int, width w: CGFloat, dark: Bool) -> CGImage? {
        let h = w * 0.42
        return image(CGSize(width: w, height: h), scale: 1) { ctx in
            let base = dark ? c(0.8, 0.82, 0.92, 0.5) : c(1, 1, 1, 0.9)
            let shadow = dark ? c(0.6, 0.62, 0.75, 0.4) : c(0.84, 0.88, 0.95, 0.9)
            let bumps = 5 + seed % 3
            ctx.setShadow(offset: .zero, blur: w * 0.03, color: alpha(base, 0.5))
            for k in 0..<bumps {
                let t = (CGFloat(k) + 0.5) / CGFloat(bumps)
                let r = h * (0.24 + rnd(seed, k) * 0.2) * (1 - abs(t - 0.5) * 0.9)
                let cx = w * (0.12 + t * 0.76)
                let cy = h * 0.3 + r * 0.55
                ctx.setFillColor(base)
                ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
            }
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            ctx.setFillColor(base)
            ctx.addPath(CGPath(roundedRect: CGRect(x: w * 0.08, y: h * 0.12, width: w * 0.84, height: h * 0.26), cornerWidth: h * 0.13, cornerHeight: h * 0.13, transform: nil))
            ctx.fillPath()
            // The underside in shade.
            ctx.saveGState()
            ctx.setBlendMode(.sourceAtop)
            linear(ctx, [alpha(shadow, 0), shadow], from: CGPoint(x: 0, y: h * 0.5), to: CGPoint(x: 0, y: h * 0.1))
            ctx.restoreGState()
        }
    }

    static func softDot(_ radius: CGFloat, _ col: CGColor, core: CGFloat = 0.3) -> CGImage? {
        image(CGSize(width: radius * 2, height: radius * 2), scale: 2) { ctx in
            let (r, g, b, a) = rgba(col)
            radial(ctx, [c(r, g, b, a), c(r, g, b, a * 0.8), c(r, g, b, a * 0.15), c(r, g, b, 0)], [0, core * 0.5, core, 1],
                   at: CGPoint(x: radius, y: radius), radius: radius)
        }
    }

    static func leaf(_ col: CGColor, size s: CGFloat) -> CGImage? {
        image(CGSize(width: s, height: s * 0.6), scale: 2) { ctx in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 0, y: s * 0.3))
            p.addQuadCurve(to: CGPoint(x: s, y: s * 0.3), control: CGPoint(x: s * 0.45, y: s * 0.62))
            p.addQuadCurve(to: CGPoint(x: 0, y: s * 0.3), control: CGPoint(x: s * 0.55, y: -s * 0.02))
            fill(ctx, p, [shade(col, 0.15), shade(col, -0.15)], from: CGPoint(x: 0, y: s * 0.6), to: CGPoint(x: 0, y: 0))
            ctx.setStrokeColor(shade(col, -0.3))
            ctx.setLineWidth(max(0.5, s * 0.05))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: s * 0.05, y: s * 0.3))
            ctx.addLine(to: CGPoint(x: s * 0.92, y: s * 0.3))
            ctx.strokePath()
        }
    }

    static func snowflake(_ r: CGFloat) -> CGImage? {
        image(CGSize(width: r * 2, height: r * 2), scale: 2) { ctx in
            radial(ctx, [c(1, 1, 1, 1), c(1, 1, 1, 0.85), c(1, 1, 1, 0)], [0, 0.5, 1], at: CGPoint(x: r, y: r), radius: r)
        }
    }

    /// Beams of light slanting down from the top.
    static func lightShafts(_ size: CGSize, seed: Int, colour: CGColor) -> CGImage? {
        image(size, scale: 0.5) { ctx in
            for k in 0..<4 {
                let x = size.width * (0.1 + rnd(seed, k) * 0.7)
                let w = size.width * (0.04 + rnd(seed + 1, k) * 0.07)
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + w, y: size.height))
                p.addLine(to: CGPoint(x: x + w * 2.4 + size.height * 0.35, y: 0))
                p.addLine(to: CGPoint(x: x + size.height * 0.35, y: 0))
                p.closeSubpath()
                fill(ctx, p, [alpha(colour, 0.35), alpha(colour, 0.12), alpha(colour, 0)], [0, 0.5, 1],
                     from: CGPoint(x: 0, y: size.height), to: CGPoint(x: 0, y: size.height * 0.05))
            }
        }
    }

    /// A band of soft mist, wider than the tank, to drift across it.
    static func mist(_ size: CGSize, seed: Int, colour: CGColor, density: CGFloat) -> CGImage? {
        image(size, scale: 0.5) { ctx in
            for k in 0..<Int(22 * density) {
                let x = rnd(seed, k) * size.width
                let y = size.height * (0.25 + rnd(seed + 1, k) * 0.5)
                let r = size.height * (0.3 + rnd(seed + 2, k) * 0.4)
                glow(ctx, at: CGPoint(x: x, y: y), radius: r, alpha(colour, 0.22 * density))
            }
        }
    }

    /// A curtain of the northern lights.
    static func aurora(_ size: CGSize, seed: Int, colours: [CGColor]) -> CGImage? {
        image(size, scale: 1) { ctx in
            let steps = Int(size.width / 1.5)
            for i in 0..<steps {
                let x = CGFloat(i) / CGFloat(steps) * size.width
                let base = size.height * (0.25 + 0.2 * wave(x / size.width * 5, seed))
                // Tall and short rays, but no step from one to the next.
                let h = size.height * (0.4 + 0.22 * (0.5 + 0.5 * wave(x / size.width * 4, seed + 3)) + 0.06 * sin(x * 0.35))
                let fade = min(1, min(x, size.width - x) / (size.width * 0.15))
                let col = mix(colours[0], colours[1], 0.5 + 0.5 * wave(x / size.width * 4, seed + 7))
                let (r, g, b, _) = rgba(col)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: x, y: 0, width: size.width / CGFloat(steps) + 0.5, height: size.height))
                linear(ctx, [c(r, g, b, 0), c(r, g, b, 0.55 * fade), c(r, g, b, 0.08 * fade), c(r, g, b, 0)], [0, 0.08, 0.7, 1],
                       from: CGPoint(x: 0, y: base - 4), to: CGPoint(x: 0, y: base + h))
                ctx.restoreGState()
            }
        }
    }

    static func butterfly(_ col: CGColor, size s: CGFloat) -> CGImage? {
        image(CGSize(width: s, height: s), scale: 2) { ctx in
            let m = s / 2
            for side in [-1.0, 1.0] as [CGFloat] {
                let upper = CGPath(ellipseIn: CGRect(x: m + (side > 0 ? 0 : -s * 0.46), y: m - s * 0.04, width: s * 0.46, height: s * 0.4), transform: nil)
                let lower = CGPath(ellipseIn: CGRect(x: m + (side > 0 ? 0 : -s * 0.32), y: m - s * 0.36, width: s * 0.32, height: s * 0.34), transform: nil)
                fill(ctx, upper, [shade(col, 0.3), col], from: CGPoint(x: m, y: m), to: CGPoint(x: m + side * s * 0.46, y: m + s * 0.3))
                fill(ctx, lower, [shade(col, 0.1), shade(col, -0.2)], from: CGPoint(x: m, y: m), to: CGPoint(x: m + side * s * 0.3, y: m - s * 0.3))
                ctx.setFillColor(c(1, 1, 1, 0.7))
                ctx.fillEllipse(in: CGRect(x: m + side * s * 0.3 - s * 0.04, y: m + s * 0.18, width: s * 0.08, height: s * 0.08))
            }
            ctx.setFillColor(c(0.15, 0.1, 0.08))
            ctx.fill(CGRect(x: m - s * 0.03, y: m - s * 0.3, width: s * 0.06, height: s * 0.58))
        }
    }

    static func gull(size s: CGFloat, colour: CGColor) -> CGImage? {
        image(CGSize(width: s, height: s * 0.4), scale: 2) { ctx in
            ctx.setStrokeColor(colour)
            ctx.setLineWidth(max(1, s * 0.07))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: s * 0.04, y: s * 0.28))
            ctx.addQuadCurve(to: CGPoint(x: s * 0.5, y: s * 0.1), control: CGPoint(x: s * 0.28, y: s * 0.38))
            ctx.addQuadCurve(to: CGPoint(x: s * 0.96, y: s * 0.28), control: CGPoint(x: s * 0.72, y: s * 0.38))
            ctx.strokePath()
        }
    }

    static func tumbleweed(size s: CGFloat) -> CGImage? {
        image(CGSize(width: s, height: s), scale: 2) { ctx in
            ctx.setStrokeColor(c(0.62, 0.48, 0.3, 0.9))
            ctx.setLineWidth(max(0.7, s * 0.025))
            for k in 0..<22 {
                let a0 = rnd(801, k) * .pi * 2, a1 = a0 + 1.4 + rnd(802, k) * 2
                let r = s * (0.25 + rnd(803, k) * 0.22)
                ctx.addArc(center: CGPoint(x: s / 2 + (rnd(804, k) - 0.5) * s * 0.1, y: s / 2 + (rnd(805, k) - 0.5) * s * 0.1),
                           radius: r, startAngle: a0, endAngle: a1, clockwise: false)
                ctx.strokePath()
            }
        }
    }

    static func waveLine(width w: CGFloat, u: CGFloat) -> CGImage? {
        image(CGSize(width: w, height: 6 * u), scale: 1) { ctx in
            ctx.setStrokeColor(c(1, 1, 1, 0.55))
            ctx.setLineWidth(1.3 * u)
            var x: CGFloat = 0
            var k = 0
            while x < w {
                let len = (20 + rnd(811, k) * 40) * u
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: 3 * u))
                ctx.addQuadCurve(to: CGPoint(x: x + len, y: 3 * u), control: CGPoint(x: x + len / 2, y: 5 * u))
                ctx.strokePath()
                x += len + (30 + rnd(812, k) * 60) * u
                k += 1
            }
        }
    }

    static func streak(length l: CGFloat) -> CGImage? {
        image(CGSize(width: l, height: 4), scale: 2) { ctx in
            linear(ctx, [c(1, 1, 1, 0), c(1, 1, 1, 0.9)], from: .zero, to: CGPoint(x: l, y: 0))
            ctx.setBlendMode(.destinationIn)
            linear(ctx, [c(1, 1, 1, 0), c(1, 1, 1, 1), c(1, 1, 1, 0)], from: .zero, to: CGPoint(x: 0, y: 4))
        }
    }

    static func sailboat(size s: CGFloat) -> CGImage? {
        image(CGSize(width: s, height: s), scale: 2) { ctx in
            ctx.setFillColor(c(0.35, 0.3, 0.3))
            let hull = CGMutablePath()
            hull.move(to: CGPoint(x: s * 0.1, y: s * 0.22))
            hull.addLine(to: CGPoint(x: s * 0.9, y: s * 0.22))
            hull.addLine(to: CGPoint(x: s * 0.75, y: s * 0.08))
            hull.addLine(to: CGPoint(x: s * 0.25, y: s * 0.08))
            hull.closeSubpath()
            ctx.addPath(hull)
            ctx.fillPath()
            ctx.setFillColor(c(1, 1, 1))
            let sail = CGMutablePath()
            sail.move(to: CGPoint(x: s * 0.5, y: s * 0.26))
            sail.addLine(to: CGPoint(x: s * 0.5, y: s * 0.95))
            sail.addLine(to: CGPoint(x: s * 0.82, y: s * 0.26))
            sail.closeSubpath()
            ctx.addPath(sail)
            ctx.fillPath()
            ctx.setFillColor(c(0.95, 0.5, 0.4))
            let jib = CGMutablePath()
            jib.move(to: CGPoint(x: s * 0.46, y: s * 0.3))
            jib.addLine(to: CGPoint(x: s * 0.46, y: s * 0.8))
            jib.addLine(to: CGPoint(x: s * 0.2, y: s * 0.3))
            jib.closeSubpath()
            ctx.addPath(jib)
            ctx.fillPath()
        }
    }

    static func drop(size s: CGFloat) -> CGImage? {
        image(CGSize(width: s, height: s * 1.5), scale: 2) { ctx in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: s / 2, y: s * 1.5))
            p.addQuadCurve(to: CGPoint(x: s, y: s * 0.5), control: CGPoint(x: s * 0.95, y: s))
            p.addArc(center: CGPoint(x: s / 2, y: s * 0.5), radius: s / 2, startAngle: 0, endAngle: .pi, clockwise: true)
            p.addQuadCurve(to: CGPoint(x: s / 2, y: s * 1.5), control: CGPoint(x: s * 0.05, y: s))
            fill(ctx, p, [c(0.8, 0.95, 1, 0.95), c(0.5, 0.75, 0.95, 0.8)], from: CGPoint(x: 0, y: s * 1.5), to: .zero)
        }
    }

    static func ring(size s: CGFloat, colour: CGColor) -> CGImage? {
        image(CGSize(width: s, height: s * 0.4), scale: 2) { ctx in
            ctx.setStrokeColor(colour)
            ctx.setLineWidth(max(0.8, s * 0.04))
            ctx.strokeEllipse(in: CGRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.3))
        }
    }
}
