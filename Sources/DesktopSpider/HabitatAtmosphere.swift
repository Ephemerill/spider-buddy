import AppKit
import QuartzCore

// MARK: - What moves in the tank's air
//
// Built once per biome and size out of small painted pictures, and set
// going with Core Animation: the window server moves it all, so a tank
// full of drifting cloud, snow and fireflies costs the app next to nothing.
// Three layers deep: behind the scenery (sky things), in front of it
// (mist, birds, butterflies), and in front of everything (snow, leaves,
// fireflies — which fade out as they reach the ground).

enum HabitatAtmosphere {
    static func build(_ b: Biome, size: CGSize, back: CALayer, mid: CALayer, front: CALayer) {
        guard size.width > 100, size.height > 100 else { return }
        let f = HabitatArt.Frame(rect: CGRect(origin: .zero, size: size))
        let u = f.u
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { HabitatArt.c(r, g, b, a) }
        switch b {
        case .forest:
            sunGlow(b, f, into: back)
            clouds(3, f, seed: 1, top: 0.95, bottom: 0.6, dark: false, into: back)
            shafts(f, seed: 3, colour: c(1, 0.96, 0.8, 1), into: mid)
            mist(f, seed: 5, height: 0.22, at: 0.06, colour: c(1, 1, 1, 1), density: 0.8, into: mid)
            leaves(f, colours: [c(0.86, 0.56, 0.22), c(0.74, 0.4, 0.16), c(0.9, 0.72, 0.28)], rate: 0.4, into: front)
            motes(f, colour: c(1, 0.98, 0.85, 0.55), rate: 1.2, rect: CGRect(x: 0, y: f.groundY, width: size.width, height: f.air * 0.8), into: front)
        case .jungle:
            clouds(2, f, seed: 2, top: 0.98, bottom: 0.8, dark: false, into: back, alpha: 0.6)
            shafts(f, seed: 7, colour: c(0.9, 1, 0.8, 1), into: mid)
            mist(f, seed: 9, height: 0.3, at: 0.05, colour: c(0.9, 1, 0.95, 1), density: 1.1, into: mid)
            mist(f, seed: 11, height: 0.25, at: 0.45, colour: c(0.9, 1, 0.95, 1), density: 0.6, into: mid)
            for (k, col) in [c(0.25, 0.55, 0.98), c(0.98, 0.55, 0.2)].enumerated() {
                butterfly(f, colour: col, seed: 20 + k, area: CGRect(x: 0, y: f.y(0.15), width: size.width, height: f.air * 0.6), into: mid)
            }
            motes(f, colour: c(0.86, 1, 0.8, 0.5), rate: 1.4, rect: CGRect(x: 0, y: f.groundY, width: size.width, height: f.air), into: front)
        case .desert:
            sunGlow(b, f, into: back)
            clouds(2, f, seed: 3, top: 0.95, bottom: 0.75, dark: false, into: back, alpha: 0.55)
            hawk(f, into: back)
            tumbleweed(f, into: mid)
            sand(f, into: front)
        case .meadow:
            sunGlow(b, f, into: back)
            clouds(4, f, seed: 4, top: 0.95, bottom: 0.5, dark: false, into: back)
            for (k, col) in [c(0.99, 0.84, 0.28), c(1, 1, 1), c(0.98, 0.6, 0.25)].enumerated() {
                butterfly(f, colour: col, seed: 30 + k, area: CGRect(x: 0, y: f.y(0.05), width: size.width, height: f.air * 0.45), into: mid)
            }
            motes(f, colour: c(1, 0.95, 0.6, 0.7), rate: 2, rect: CGRect(x: 0, y: f.groundY, width: size.width, height: f.air * 0.6), into: front)
        case .cave:
            for spot in HabitatArt.crystalSpots(f) {
                glow(at: spot.point, radius: spot.size * 2.2, colour: HabitatArt.alpha(spot.colour, 0.55), period: 3 + Double(spot.size.truncatingRemainder(dividingBy: 2)), into: back)
            }
            beam(f, into: back)
            drips(f, into: mid)
            motes(f, colour: c(1, 1, 0.95, 0.5), rate: 1.5, rect: CGRect(x: f.x(0.36), y: f.groundY, width: f.rect.width * 0.34, height: f.air * 0.9), into: front)
        case .beach:
            sunGlow(b, f, into: back)
            clouds(3, f, seed: 6, top: 0.95, bottom: 0.62, dark: false, into: back)
            sailboat(f, into: back)
            for k in 0..<2 { gull(f, seed: 40 + k, into: back) }
            waves(f, into: mid)
            sparkle(f, into: mid)
        case .tundra:
            aurora(f, into: back)
            twinkles(14, f, into: back)
            snow(f, radius: 2.2 * u, rate: 14, speed: 22, into: mid)
            snow(f, radius: 3.6 * u, rate: 5, speed: 34, into: front)
        case .night:
            sunGlow(b, f, into: back)
            twinkles(34, f, into: back)
            shootingStar(f, into: back)
            mist(f, seed: 13, height: 0.2, at: 0.04, colour: c(0.6, 0.7, 1, 1), density: 0.7, into: mid)
            for k in 0..<12 { firefly(f, seed: 50 + k, into: front) }
        }
        fadeAtGround(front, f)
    }

    // MARK: Pieces

    private static func rnd(_ s: Int, _ i: Int) -> CGFloat { HabitatArt.rnd(s, i) }

    private static func sprite(_ img: CGImage?, _ frame: CGRect) -> CALayer {
        let l = CALayer()
        l.contents = img
        l.frame = frame
        return l
    }

    /// Loops a basic animation for ever, starting partway through.
    private static func loop(_ a: CAAnimation, _ duration: CFTimeInterval, phase: CGFloat = 0, reverse: Bool = false) -> CAAnimation {
        a.duration = duration
        a.repeatCount = .infinity
        a.autoreverses = reverse
        a.timeOffset = CFTimeInterval(phase) * duration * (reverse ? 2 : 1)
        return a
    }

    private static func basic(_ key: String, _ from: Any, _ to: Any, ease: Bool = true) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        if ease { a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut) }
        return a
    }

    /// The glow round the sun (or the moon), breathing a little.
    private static func sunGlow(_ b: Biome, _ f: HabitatArt.Frame, into parent: CALayer) {
        guard let s = HabitatArt.sun(b, f) else { return }
        let r = s.radius * 3.2
        let col = b == .night ? HabitatArt.c(0.75, 0.82, 1, 0.45) : HabitatArt.c(1, 0.95, 0.75, 0.55)
        let l = sprite(HabitatArt.softDot(r, col, core: 0.25), CGRect(x: s.point.x - r, y: s.point.y - r, width: r * 2, height: r * 2))
        l.compositingFilter = "screenBlendMode"
        parent.addSublayer(l)
        let g = CAAnimationGroup()
        g.animations = [basic("transform.scale", 0.94, 1.06), basic("opacity", 0.7, 1)]
        l.add(loop(g, 5, reverse: true), forKey: "breathe")
    }

    private static func glow(at p: CGPoint, radius r: CGFloat, colour: CGColor, period: CFTimeInterval, into parent: CALayer) {
        let l = sprite(HabitatArt.softDot(r, colour, core: 0.15), CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        l.compositingFilter = "screenBlendMode"
        parent.addSublayer(l)
        l.add(loop(basic("opacity", 0.4, 1), period, phase: rnd(Int(p.x), 1), reverse: true), forKey: "breathe")
    }

    private static func clouds(_ n: Int, _ f: HabitatArt.Frame, seed: Int, top: CGFloat, bottom: CGFloat, dark: Bool, into parent: CALayer, alpha: Float = 1) {
        for k in 0..<n {
            let w = (130 + rnd(seed, k) * 130) * f.u
            guard let img = HabitatArt.cloud(seed: seed * 10 + k, width: w, dark: dark) else { continue }
            let h = w * 0.42
            let y = f.y(bottom + (top - bottom) * rnd(seed + 1, k))
            let l = sprite(img, CGRect(x: -w, y: y - h / 2, width: w, height: h))
            l.opacity = alpha * Float(0.75 + rnd(seed + 2, k) * 0.25)
            parent.addSublayer(l)
            let drift = basic("position.x", -w / 2, f.rect.width + w / 2, ease: false)
            l.add(loop(drift, CFTimeInterval(170 + rnd(seed + 3, k) * 140), phase: (CGFloat(k) + rnd(seed + 4, k) * 0.6) / CGFloat(n)), forKey: "drift")
        }
    }

    private static func shafts(_ f: HabitatArt.Frame, seed: Int, colour: CGColor, into parent: CALayer) {
        let size = CGSize(width: f.rect.width, height: f.rect.height)
        let l = sprite(HabitatArt.lightShafts(size, seed: seed, colour: colour), CGRect(origin: .zero, size: size))
        l.compositingFilter = "screenBlendMode"
        parent.addSublayer(l)
        l.add(loop(basic("opacity", 0.35, 0.95), 7.5, reverse: true), forKey: "shimmer")
    }

    private static func beam(_ f: HabitatArt.Frame, into parent: CALayer) {
        // One broad shaft from a hole in the roof.
        let w = f.rect.width * 0.4, h = f.rect.height
        guard let img = HabitatArt.image(CGSize(width: w, height: h), scale: 0.5, { ctx in
            let p = CGMutablePath()
            p.move(to: CGPoint(x: w * 0.35, y: h))
            p.addLine(to: CGPoint(x: w * 0.6, y: h))
            p.addLine(to: CGPoint(x: w * 0.95, y: 0))
            p.addLine(to: CGPoint(x: w * 0.1, y: 0))
            p.closeSubpath()
            HabitatArt.fill(ctx, p, [HabitatArt.c(0.85, 0.92, 1, 0.3), HabitatArt.c(0.85, 0.92, 1, 0.08), HabitatArt.c(0.85, 0.92, 1, 0)], [0, 0.6, 1],
                            from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.05))
        }) else { return }
        let l = sprite(img, CGRect(x: f.x(0.33), y: 0, width: w, height: h))
        l.compositingFilter = "screenBlendMode"
        parent.addSublayer(l)
        l.add(loop(basic("opacity", 0.55, 1), 6, reverse: true), forKey: "shimmer")
    }

    private static func mist(_ f: HabitatArt.Frame, seed: Int, height: CGFloat, at: CGFloat, colour: CGColor, density: CGFloat, into parent: CALayer) {
        let size = CGSize(width: f.rect.width * 1.8, height: f.air * height)
        let l = sprite(HabitatArt.mist(size, seed: seed, colour: colour, density: density),
                       CGRect(x: 0, y: f.y(at) - size.height * 0.3, width: size.width, height: size.height))
        parent.addSublayer(l)
        let drift = basic("position.x", size.width / 2 - f.rect.width * 0.1, size.width / 2 - f.rect.width * 0.7)
        l.add(loop(drift, CFTimeInterval(38 + rnd(seed, 1) * 20), phase: rnd(seed, 2), reverse: true), forKey: "drift")
    }

    /// A random wander through `area` that comes back to where it began.
    private static func wanderPath(_ area: CGRect, seed: Int, points n: Int) -> CGPath {
        let p = CGMutablePath()
        var pts: [CGPoint] = []
        for k in 0..<n {
            pts.append(CGPoint(x: area.minX + rnd(seed, k) * area.width, y: area.minY + rnd(seed + 1, k) * area.height))
        }
        p.move(to: pts[0])
        for k in 0..<n {
            let a = pts[k], b = pts[(k + 1) % n]
            p.addQuadCurve(to: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2), control: a)
        }
        p.addLine(to: pts[0])
        return p
    }

    private static func butterfly(_ f: HabitatArt.Frame, colour: CGColor, seed: Int, area: CGRect, into parent: CALayer) {
        let s = 26 * f.u
        let l = sprite(HabitatArt.butterfly(colour, size: s), CGRect(x: 0, y: 0, width: s, height: s))
        parent.addSublayer(l)
        let path = CAKeyframeAnimation(keyPath: "position")
        path.path = wanderPath(area, seed: seed, points: 7)
        path.calculationMode = .cubicPaced
        l.add(loop(path, CFTimeInterval(26 + rnd(seed, 9) * 14), phase: rnd(seed, 10)), forKey: "fly")
        l.add(loop(basic("transform.scale.x", 1, 0.2, ease: false), 0.11, phase: rnd(seed, 11), reverse: true), forKey: "flap")
    }

    private static func firefly(_ f: HabitatArt.Frame, seed: Int, into parent: CALayer) {
        let r = 14 * f.u
        let l = sprite(HabitatArt.softDot(r, HabitatArt.c(0.88, 1, 0.5, 1), core: 0.22), CGRect(x: 0, y: 0, width: r * 2, height: r * 2))
        l.compositingFilter = "screenBlendMode"
        parent.addSublayer(l)
        let area = CGRect(x: 0, y: f.groundY + 10 * f.u, width: f.rect.width, height: f.air * 0.55)
        let path = CAKeyframeAnimation(keyPath: "position")
        path.path = wanderPath(area, seed: seed, points: 6)
        path.calculationMode = .cubicPaced
        l.add(loop(path, CFTimeInterval(30 + rnd(seed, 9) * 25), phase: rnd(seed, 10)), forKey: "wander")
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0.05, 1, 0.7, 1, 0.05, 0.05]
        blink.keyTimes = [0, 0.15, 0.3, 0.45, 0.65, 1]
        l.add(loop(blink, CFTimeInterval(3.5 + rnd(seed, 12) * 3), phase: rnd(seed, 13)), forKey: "blink")
    }

    private static func twinkles(_ n: Int, _ f: HabitatArt.Frame, into parent: CALayer) {
        for k in 0..<n {
            let r = (3 + rnd(901, k) * 3) * f.u
            let p = CGPoint(x: rnd(902, k) * f.rect.width, y: f.y(0.4 + rnd(903, k) * 0.58))
            let l = sprite(HabitatArt.softDot(r, HabitatArt.c(1, 1, 0.95, 1), core: 0.12), CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            parent.addSublayer(l)
            l.add(loop(basic("opacity", 0.15, 1), CFTimeInterval(1.4 + rnd(904, k) * 2.6), phase: rnd(905, k), reverse: true), forKey: "twinkle")
        }
    }

    private static func shootingStar(_ f: HabitatArt.Frame, into parent: CALayer) {
        let len = 90 * f.u
        let l = sprite(HabitatArt.streak(length: len), CGRect(x: 0, y: 0, width: len, height: 3))
        l.anchorPoint = CGPoint(x: 1, y: 0.5)
        l.transform = CATransform3DMakeRotation(-0.42, 0, 0, 1)
        l.opacity = 0
        parent.addSublayer(l)
        let start = CGPoint(x: f.x(0.25), y: f.y(0.92)), end = CGPoint(x: f.x(0.55), y: f.y(0.78))
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = [start, end, end].map { NSValue(point: $0) }
        move.keyTimes = [0, 0.06, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0, 0]
        fade.keyTimes = [0, 0.015, 0.06, 1]
        let g = CAAnimationGroup()
        g.animations = [move, fade]
        l.add(loop(g, 16, phase: 0.6), forKey: "shoot")
    }

    private static func aurora(_ f: HabitatArt.Frame, into parent: CALayer) {
        func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { HabitatArt.c(r, g, b, a) }
        for (k, cols) in [[c(0.3, 1, 0.65), c(0.3, 0.85, 1)], [c(0.5, 1, 0.55), c(0.75, 0.45, 1)]].enumerated() {
            let size = CGSize(width: f.rect.width * 1.3, height: f.air * (0.55 - CGFloat(k) * 0.1))
            let l = sprite(HabitatArt.aurora(size, seed: 60 + k * 7, colours: cols),
                           CGRect(x: -f.rect.width * 0.15, y: f.y(0.4 + CGFloat(k) * 0.08), width: size.width, height: size.height))
            l.compositingFilter = "screenBlendMode"
            l.opacity = k == 0 ? 0.9 : 0.6
            parent.addSublayer(l)
            l.add(loop(basic("opacity", k == 0 ? 0.45 : 0.25, k == 0 ? 1 : 0.7), CFTimeInterval(6 + k * 3), phase: CGFloat(k) * 0.5, reverse: true), forKey: "glow")
            l.add(loop(basic("position.x", l.position.x - 40 * f.u, l.position.x + 40 * f.u), CFTimeInterval(22 + k * 9), phase: 0.3, reverse: true), forKey: "drift")
        }
    }

    private static func hawk(_ f: HabitatArt.Frame, into parent: CALayer) {
        let s = 26 * f.u
        let l = sprite(HabitatArt.gull(size: s, colour: HabitatArt.c(0.3, 0.22, 0.2, 0.7)), CGRect(x: 0, y: 0, width: s, height: s * 0.4))
        parent.addSublayer(l)
        let circle = CAKeyframeAnimation(keyPath: "position")
        circle.path = CGPath(ellipseIn: CGRect(x: f.x(0.2), y: f.y(0.62), width: f.rect.width * 0.26, height: f.air * 0.12), transform: nil)
        circle.calculationMode = .paced
        l.add(loop(circle, 26), forKey: "circle")
    }

    private static func gull(_ f: HabitatArt.Frame, seed: Int, into parent: CALayer) {
        let s = (16 + rnd(seed, 1) * 8) * f.u
        let l = sprite(HabitatArt.gull(size: s, colour: HabitatArt.c(0.25, 0.3, 0.38, 0.85)), CGRect(x: 0, y: 0, width: s, height: s * 0.4))
        parent.addSublayer(l)
        let y = f.y(0.62 + rnd(seed, 2) * 0.25)
        let fly = CAKeyframeAnimation(keyPath: "position")
        let x0 = -s, x1 = f.rect.width + s
        fly.values = (0...8).map { i -> NSValue in
            let t = CGFloat(i) / 8
            return NSValue(point: CGPoint(x: x0 + (x1 - x0) * t, y: y + sin(t * .pi * 3) * 14 * f.u))
        }
        fly.calculationMode = .cubic
        l.add(loop(fly, CFTimeInterval(34 + rnd(seed, 3) * 20), phase: rnd(seed, 4)), forKey: "fly")
        l.add(loop(basic("transform.scale.y", 1, 0.45), 0.5, phase: rnd(seed, 5), reverse: true), forKey: "flap")
    }

    private static func sailboat(_ f: HabitatArt.Frame, into parent: CALayer) {
        let s = 26 * f.u
        let seaTop = f.y(0.34)
        let l = sprite(HabitatArt.sailboat(size: s), CGRect(x: 0, y: 0, width: s, height: s))
        l.anchorPoint = CGPoint(x: 0.5, y: 0.15)
        parent.addSublayer(l)
        l.position = CGPoint(x: f.x(0.45), y: seaTop - 3 * f.u)
        l.add(loop(basic("position.x", f.x(0.38), f.x(0.56)), 90, phase: 0.2, reverse: true), forKey: "sail")
        l.add(loop(basic("transform.rotation.z", -0.05, 0.05), 2.6, reverse: true), forKey: "bob")
    }

    private static func waves(_ f: HabitatArt.Frame, into parent: CALayer) {
        let seaTop = f.y(0.34)
        for k in 0..<4 {
            let w = f.rect.width * 1.3
            let y = f.groundY + 26 * f.u + (seaTop - f.groundY - 30 * f.u) * CGFloat(k) / 4
            let l = sprite(HabitatArt.waveLine(width: w, u: f.u * (1 - CGFloat(k) * 0.15)), CGRect(x: -f.rect.width * 0.15, y: y, width: w, height: 6 * f.u))
            l.opacity = Float(0.9 - CGFloat(k) * 0.15)
            parent.addSublayer(l)
            l.add(loop(basic("position.x", l.position.x - 30 * f.u, l.position.x + 30 * f.u), CFTimeInterval(5 + CGFloat(k) * 1.3), phase: CGFloat(k) * 0.3, reverse: true), forKey: "roll")
        }
    }

    private static func sparkle(_ f: HabitatArt.Frame, into parent: CALayer) {
        let seaTop = f.y(0.34)
        let cell = CAEmitterCell()
        cell.contents = HabitatArt.softDot(4, HabitatArt.c(1, 1, 1, 1), core: 0.2)
        cell.birthRate = 7
        cell.lifetime = 1.1
        cell.alphaSpeed = -0.9
        cell.scale = 0.9 * f.u
        cell.scaleRange = 0.4 * f.u
        addEmitter(to: parent, emitter([cell], shape: .rectangle, at: CGPoint(x: f.rect.midX, y: (seaTop + f.groundY + 30 * f.u) / 2),
                                       size: CGSize(width: f.rect.width, height: seaTop - f.groundY - 30 * f.u), frame: f.rect))
    }

    /// Things falling through the air, each its own little layer on a
    /// loop from above the tank to below the ground, started partway
    /// through — so the air is evenly full from the moment it opens.
    private static func fallers(_ images: [CGImage?], count: Int, size: CGFloat, speed: CGFloat, drift: CGFloat, spin: Bool,
                                _ f: HabitatArt.Frame, seed: Int, into parent: CALayer) {
        let top = f.rect.maxY + size, bottom = f.groundY - size
        for k in 0..<count {
            let s = size * (0.7 + rnd(seed, k) * 0.6)
            let l = sprite(images[k % images.count], CGRect(x: 0, y: 0, width: s, height: s * (spin ? 0.6 : 1)))
            l.opacity = Float(0.7 + rnd(seed + 1, k) * 0.3)
            let x = rnd(seed + 2, k) * f.rect.width
            l.position = CGPoint(x: x, y: top)
            parent.addSublayer(l)
            let v = speed * (0.75 + rnd(seed + 3, k) * 0.5)
            let period = CFTimeInterval((top - bottom) / v)
            let phase = rnd(seed + 4, k)
            l.add(loop(basic("position.y", top, bottom, ease: false), period, phase: phase), forKey: "fall")
            // A lazy side-to-side as it goes.
            let sway = basic("position.x", x - drift, x + drift)
            l.add(loop(sway, CFTimeInterval(2.5 + rnd(seed + 5, k) * 3), phase: rnd(seed + 6, k), reverse: true), forKey: "sway")
            if spin {
                let turn = basic("transform.rotation.z", 0, CGFloat.pi * 2 * (rnd(seed + 7, k) > 0.5 ? 1 : -1), ease: false)
                l.add(loop(turn, CFTimeInterval(3 + rnd(seed + 8, k) * 5), phase: rnd(seed + 9, k)), forKey: "spin")
            }
        }
    }

    private static func leaves(_ f: HabitatArt.Frame, colours: [CGColor], rate: Float, into parent: CALayer) {
        let images = colours.map { HabitatArt.leaf($0, size: 14 * f.u) }
        fallers(images, count: max(6, Int(rate * 22)), size: 13 * f.u, speed: 26 * f.u, drift: 26 * f.u, spin: true, f, seed: 950, into: parent)
    }

    private static func snow(_ f: HabitatArt.Frame, radius: CGFloat, rate: Float, speed: CGFloat, into parent: CALayer) {
        let img = HabitatArt.snowflake(radius)
        fallers([img], count: Int(rate * 7), size: radius * 2, speed: speed * f.u, drift: 10 * f.u, spin: false, f, seed: 960 + Int(radius * 10), into: parent)
    }

    /// Specks drifting in the light: dust, pollen, spores.
    private static func motes(_ f: HabitatArt.Frame, colour: CGColor, rate: Float, rect: CGRect, into parent: CALayer) {
        let cell = CAEmitterCell()
        cell.contents = HabitatArt.softDot(3, colour, core: 0.35)
        cell.birthRate = rate
        cell.lifetime = 16
        cell.lifetimeRange = 4
        cell.velocity = 5 * f.u
        cell.velocityRange = 4 * f.u
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 0.6 * f.u
        cell.xAcceleration = 0.4 * f.u
        cell.scale = f.u
        cell.scaleRange = 0.5 * f.u
        cell.alphaSpeed = -0.05
        addEmitter(to: parent, emitter([cell], shape: .rectangle, at: CGPoint(x: rect.midX, y: rect.midY), size: rect.size, frame: f.rect))
    }

    private static func sand(_ f: HabitatArt.Frame, into parent: CALayer) {
        let cell = CAEmitterCell()
        cell.contents = HabitatArt.softDot(2, HabitatArt.c(0.98, 0.88, 0.66, 0.7), core: 0.4)
        cell.birthRate = 6
        cell.lifetime = Float(f.rect.width / (70 * f.u)) + 2
        cell.velocity = 70 * f.u
        cell.velocityRange = 30 * f.u
        cell.emissionLongitude = 0
        cell.emissionRange = .pi / 16
        cell.yAcceleration = -1 * f.u
        cell.scale = f.u
        cell.scaleRange = 0.5 * f.u
        cell.alphaSpeed = -0.06
        addEmitter(to: parent, emitter([cell], shape: .line, at: CGPoint(x: -6, y: f.groundY + 30 * f.u),
                                   size: CGSize(width: 1, height: 60 * f.u), frame: f.rect))
    }

    private static func drips(_ f: HabitatArt.Frame, into parent: CALayer) {
        for k in 0..<3 {
            let x = f.x(0.2 + CGFloat(k) * 0.28 + rnd(910, k) * 0.08)
            let top = f.rect.maxY - f.air * (0.2 + rnd(911, k) * 0.08)
            let s = 5 * f.u
            let drop = sprite(HabitatArt.drop(size: s), CGRect(x: x - s / 2, y: top, width: s, height: s * 1.5))
            drop.opacity = 0
            parent.addSublayer(drop)
            let period = CFTimeInterval(6 + rnd(912, k) * 5)
            let fall = CAKeyframeAnimation(keyPath: "position.y")
            fall.values = [top, top, f.groundY + 2 * f.u, f.groundY + 2 * f.u]
            fall.keyTimes = [0, 0.72, 0.84, 1]
            fall.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .linear)]
            let show = CAKeyframeAnimation(keyPath: "opacity")
            show.values = [0, 0.9, 0.9, 0, 0]
            show.keyTimes = [0, 0.3, 0.83, 0.84, 1]
            let swell = CAKeyframeAnimation(keyPath: "transform.scale")
            swell.values = [0.2, 1, 1, 1]
            swell.keyTimes = [0, 0.7, 0.72, 1]
            let g = CAAnimationGroup()
            g.animations = [fall, show, swell]
            drop.add(loop(g, period, phase: rnd(913, k)), forKey: "drip")
            // A ring where it lands.
            let ring = sprite(HabitatArt.ring(size: 18 * f.u, colour: HabitatArt.c(0.8, 0.9, 1, 0.8)), CGRect(x: x - 9 * f.u, y: f.groundY - 2 * f.u, width: 18 * f.u, height: 7.2 * f.u))
            ring.opacity = 0
            parent.addSublayer(ring)
            let rs = CAKeyframeAnimation(keyPath: "transform.scale")
            rs.values = [0.2, 0.2, 1.3, 1.3]
            rs.keyTimes = [0, 0.84, 0.95, 1]
            let ro = CAKeyframeAnimation(keyPath: "opacity")
            ro.values = [0, 0, 0.9, 0, 0]
            ro.keyTimes = [0, 0.84, 0.86, 0.96, 1]
            let rg = CAAnimationGroup()
            rg.animations = [rs, ro]
            ring.add(loop(rg, period, phase: rnd(913, k)), forKey: "splash")
        }
    }

    private static func tumbleweed(_ f: HabitatArt.Frame, into parent: CALayer) {
        let s = 30 * f.u
        let l = sprite(HabitatArt.tumbleweed(size: s), CGRect(x: -s * 2, y: 0, width: s, height: s))
        parent.addSublayer(l)
        let base = f.groundY + 8 * f.u + s / 2
        let x = CAKeyframeAnimation(keyPath: "position.x")
        x.values = [-s, f.rect.width + s, f.rect.width + s]
        x.keyTimes = [0, 0.32, 1]
        let y = CAKeyframeAnimation(keyPath: "position.y")
        var ys: [CGFloat] = []
        var ts: [NSNumber] = []
        for i in 0...12 {
            ys.append(base + (i % 2 == 1 ? (22 - CGFloat(i) * 1.2) * f.u : 0))
            ts.append(NSNumber(value: Double(i) / 12 * 0.32))
        }
        ys.append(base)
        ts.append(1)
        y.values = ys
        y.keyTimes = ts
        let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        spin.values = [0, -CGFloat.pi * 8, -CGFloat.pi * 8]
        spin.keyTimes = [0, 0.32, 1]
        let g = CAAnimationGroup()
        g.animations = [x, y, spin]
        l.add(loop(g, 30, phase: 0.85), forKey: "tumble")
    }

    // MARK: Emitters

    private static func emitter(_ cells: [CAEmitterCell], shape: CAEmitterLayerEmitterShape, at p: CGPoint, size: CGSize, frame: CGRect) -> CAEmitterLayer {
        let e = CAEmitterLayer()
        e.frame = frame
        e.emitterShape = shape
        e.emitterMode = shape == .line ? .outline : .volume
        e.emitterPosition = p
        e.emitterSize = size
        e.emitterCells = cells
        e.renderMode = .unordered
        return e
    }

    private static func addEmitter(to parent: CALayer, _ e: CAEmitterLayer) {
        e.seed = UInt32.random(in: 1...UInt32.max)
        parent.addSublayer(e)
    }

    /// Whatever falls through the front of the tank fades as it gets to
    /// the ground rather than falling into it.
    private static func fadeAtGround(_ layer: CALayer, _ f: HabitatArt.Frame) {
        let m = CAGradientLayer()
        m.frame = f.rect
        m.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)]
        let g0 = (f.groundY - 4 * f.u) / f.rect.height, g1 = (f.groundY + 26 * f.u) / f.rect.height
        m.startPoint = CGPoint(x: 0.5, y: g0)
        m.endPoint = CGPoint(x: 0.5, y: g1)
        layer.mask = m
    }
}
