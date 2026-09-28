import AppKit
import QuartzCore

// MARK: - The weather, drawn
//
// The tank's weather is a set of layers the scene slots in among its own:
// sky things behind the scenery (cloud decks, a rainbow, the night sky and
// its shows, lightning far off), mist and distant rain in front of the
// scenery, what lies on the ground (puddles, snow, hail, splashes,
// footprints), snow on the furniture, the light, and what falls in front
// of everything. They are built for each size and scenery; the weather
// only turns them up and down and tips them with the wind, so Core
// Animation does all the moving and it costs the app next to nothing.

final class WeatherLayers {
    /// The scene's slots for it, back to front: behind the scenery, in
    /// front of it, on the ground, on the furniture, the light, what falls,
    /// and the flash of lightning (see `HabitatSceneView`).
    let back = CALayer(), mid = CALayer(), ground = CALayer(), caps = CALayer()
    let shade = CALayer(), front = CALayer(), flash = CALayer()

    /// Thunder, a moment after a flash: where the lightning came down, in
    /// the scene, and how loud (1: right overhead).
    var onThunder: ((CGPoint, CGFloat) -> Void)?

    /// How much snow is lying, and how wet the ground is, 0…1: it builds
    /// up while it snows or rains, and goes again after.
    private(set) var groundSnow: CGFloat = 0
    private(set) var groundWet: CGFloat = 0

    private var size = CGSize.zero
    private var biome: Biome = .forest
    private var f = HabitatArt.Frame(rect: .zero)
    private var built = false

    // Behind the scenery.
    private let nightSky = CALayer()
    private let auroraBox = CALayer()
    private let meteors = CALayer()
    private let deck = CALayer()
    private let stormDeck = CALayer()
    private let glare = CALayer()
    private let rainbow = CALayer()
    private let skyFlash = CALayer()
    private let farBolt = CAShapeLayer()
    // In front of the scenery.
    private let farBox = CALayer()
    private var farSheet = CALayer()
    private let shafts = CALayer()
    private let fogLow = CALayer(), fogHigh = CALayer()
    private let dustBank = CALayer()
    private let haze = CALayer()
    private let nearBolt = CAShapeLayer()
    // On the ground.
    private let wetDark = CALayer()
    private let wetMask = CALayer()
    private let puddles = CALayer()
    private var ripples: [CAEmitterLayer] = []
    private let dusting = CALayer(), blanket = CALayer()
    private let prints = CAShapeLayer()
    private let splashes = CAEmitterLayer()
    private let hailFloor = CAEmitterLayer()
    // On the furniture.
    private let capsThin = CALayer(), capsThick = CALayer()
    // The light.
    private let dim = CALayer(), warm = CALayer()
    // In front of everything.
    private let precip = CALayer()
    private let precipMask = CAGradientLayer()
    /// Rain and hail: sheets of streaks and stones sliding down on a loop,
    /// in a box leant over with the wind. (Not emitters: fast ones, born
    /// above the tank, never got far down it.)
    private let rainBox = CALayer()
    private var rainSheets: [CALayer] = [], hailSheets: [CALayer] = []
    private let snowE = CAEmitterLayer(), sideE = CAEmitterLayer()
    private let fogFront = CALayer()
    private let veil = CALayer()
    private let flashFill = CALayer()

    /// Where the cloud decks have drifted to.
    private var deckOff: CGFloat = 0
    private var stormOff: CGFloat = 0
    private var strikeIn: CGFloat = 5
    /// Which side the wind blows in from (+1 from the left), as the side
    /// emitter is set up.
    private var sideFrom: CGFloat = 0
    private var lastSnowAim: CGFloat = 99
    private var lastSideSpeed: CGFloat = -1
    private var marks: [(p: CGPoint, t: CFTimeInterval)] = []
    private var itemsKey = ""
    /// Ticks in a row with nothing at all to show: past a second of it,
    /// the layers are all put away and it stops looking.
    private var stillTicks = 0
    /// What was last set, so nothing is set again unchanged (every set is
    /// an animation for the window server).
    private var lastLean: CGFloat = 99
    private var lastDim: [CGFloat] = [], lastVeil: [CGFloat] = []
    private var sideRates: [String: CGFloat] = [:]

    init() {
        for l in [back, mid, ground, caps, shade, front, flash] {
            l.masksToBounds = false
            l.anchorPoint = .zero
        }
        for l in [nightSky, auroraBox, deck, stormDeck, glare, rainbow, skyFlash] as [CALayer] { back.addSublayer(l) }
        back.insertSublayer(meteors, above: nightSky)
        back.addSublayer(farBolt)
        for l in [farBox, shafts, fogHigh, dustBank, fogLow, haze, nearBolt] as [CALayer] { mid.addSublayer(l) }
        for l in [wetDark, puddles, dusting, blanket, prints, splashes, hailFloor] as [CALayer] { ground.addSublayer(l) }
        caps.addSublayer(capsThin)
        caps.addSublayer(capsThick)
        shade.addSublayer(dim)
        shade.addSublayer(warm)
        front.addSublayer(precip)
        precip.addSublayer(rainBox)
        precip.addSublayer(snowE)
        precip.addSublayer(sideE)
        front.addSublayer(fogFront)
        front.addSublayer(veil)
        flash.addSublayer(flashFill)
        precip.mask = precipMask
        wetDark.mask = wetMask
        // (No blend modes: the tank is drawn by the window server, which
        // ignores them. Plain tints, light or dark, do the same job.)
        for b in [farBolt, nearBolt] {
            b.fillColor = nil
            b.strokeColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
            b.lineJoin = .round
            b.lineCap = .round
            b.shadowColor = CGColor(red: 0.7, green: 0.8, blue: 1, alpha: 1)
            b.shadowOpacity = 1
            b.shadowRadius = 6
            b.shadowOffset = .zero
            b.opacity = 0
        }
        prints.fillColor = CGColor(red: 0.6, green: 0.67, blue: 0.8, alpha: 0.75)
        for l in [meteors, nightSky, auroraBox, deck, stormDeck, glare, rainbow, skyFlash, shafts, fogLow, fogHigh, dustBank, haze,
                  wetDark, puddles, dusting, blanket, prints, capsThin, capsThick, dim, warm, fogFront, veil, flashFill] as [CALayer] {
            l.opacity = 0
            l.isHidden = true
        }
        skyFlash.isHidden = false
        flashFill.isHidden = false
        for e in [splashes, hailFloor, snowE, sideE] { e.birthRate = 0 }
    }

    // MARK: Building

    /// Sets everything up for a scene this size, in this scenery. `groundImage`
    /// is the substrate's picture (what gets darker when it is wet).
    func build(size s: CGSize, biome b: Biome, groundImage: Any?) {
        guard s.width > 100, s.height > 100 else { return }
        size = s
        biome = b
        f = HabitatArt.Frame(rect: CGRect(origin: .zero, size: s))
        built = true
        itemsKey = ""
        stillTicks = 0
        lastLean = 99
        lastDim = []
        lastVeil = []
        sideRates = [:]
        let u = f.u, W = s.width, H = s.height, G = f.groundY, air = f.air
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        for l in [back, mid, ground, caps, shade, front, flash, precip, dim, warm, veil, flashFill] {
            l.frame = CGRect(origin: .zero, size: s)
        }
        for l in [snowE, sideE, splashes, hailFloor, meteors] as [CALayer] { l.frame = CGRect(origin: .zero, size: s) }

        // The night sky, and what shows in it.
        nightSky.frame = CGRect(x: 0, y: G - 30 * u, width: W, height: air + 30 * u)
        nightSky.contents = WeatherArt.nightSky(CGSize(width: W, height: air + 30 * u), u: u)
        auroraBox.frame = CGRect(origin: .zero, size: s)
        auroraBox.sublayers?.forEach { $0.removeFromSuperlayer() }
        for (k, cols) in [[HabitatArt.c(0.3, 1, 0.65), HabitatArt.c(0.3, 0.85, 1)], [HabitatArt.c(0.5, 1, 0.55), HabitatArt.c(0.75, 0.45, 1)]].enumerated() {
            let sz = CGSize(width: W * 1.3, height: air * (0.55 - CGFloat(k) * 0.1))
            let l = CALayer()
            l.contents = HabitatArt.aurora(sz, seed: 160 + k * 7, colours: cols)
            l.frame = CGRect(x: -W * 0.15, y: f.y(0.42 + CGFloat(k) * 0.08), width: sz.width, height: sz.height)
            l.opacity = k == 0 ? 0.95 : 0.65
            auroraBox.addSublayer(l)
            l.add(loop(basic("opacity", k == 0 ? 0.5 : 0.3, k == 0 ? 1 : 0.75), 6 + Double(k) * 3, reverse: true), forKey: "glow")
            l.add(loop(basic("position.x", l.position.x - 40 * u, l.position.x + 40 * u), 22 + Double(k) * 9, reverse: true), forKey: "drift")
        }
        // Shooting stars: a few, each streaking across now and then.
        meteors.sublayers?.forEach { $0.removeFromSuperlayer() }
        let streakImg = WeatherArt.meteor(length: 110 * u, angle: 0.42)
        for k in 0..<6 {
            let l = CALayer()
            l.contents = streakImg
            l.bounds = CGRect(x: 0, y: 0, width: 110 * u * cos(0.42) + 6, height: 110 * u * sin(0.42) + 6)
            l.anchorPoint = CGPoint(x: 1, y: 0)
            l.opacity = 0
            meteors.addSublayer(l)
            let start = CGPoint(x: W * (0.2 + HabitatArt.rnd(71, k) * 0.7), y: f.y(0.72 + HabitatArt.rnd(72, k) * 0.25))
            let travel = (200 + HabitatArt.rnd(73, k) * 180) * u
            let end = CGPoint(x: start.x + travel * cos(0.42), y: start.y - travel * sin(0.42))
            let period = 2.5 + Double(HabitatArt.rnd(74, k)) * 4.5
            let dash = 0.45 / period
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [start, end, end].map { NSValue(point: $0) }
            move.keyTimes = [0, NSNumber(value: dash), 1]
            let show = CAKeyframeAnimation(keyPath: "opacity")
            show.values = [0, 1, 0, 0]
            show.keyTimes = [0, NSNumber(value: dash * 0.15), NSNumber(value: dash), 1]
            let g = CAAnimationGroup()
            g.animations = [move, show]
            g.duration = period
            g.repeatCount = .infinity
            g.timeOffset = Double(HabitatArt.rnd(75, k)) * period
            l.add(g, forKey: "streak")
        }

        // Cloud: a grey deck over the sky, and a darker one under it for
        // storms — each twice the width of the tank and the same every
        // tank-width along, so it can drift round for ever.
        let deckH = air * 0.8
        deck.contents = WeatherArt.cloudDeck(width: W, height: deckH, u: u, seed: 3,
                                             light: HabitatArt.c(0.93, 0.94, 0.96), dark: HabitatArt.c(0.66, 0.69, 0.75))
        deck.bounds = CGRect(x: 0, y: 0, width: W * 2, height: deckH)
        deck.position = CGPoint(x: W * 0.5 + deckOff, y: H - deckH / 2 + 6 * u)
        let stormH = air * 0.66
        stormDeck.contents = WeatherArt.cloudDeck(width: W, height: stormH, u: u, seed: 9,
                                                  light: HabitatArt.c(0.5, 0.52, 0.6), dark: HabitatArt.c(0.24, 0.26, 0.33))
        stormDeck.bounds = CGRect(x: 0, y: 0, width: W * 2, height: stormH)
        stormDeck.position = CGPoint(x: W * 0.5 + stormOff, y: H - stormH / 2 + 10 * u)

        // The sun blazing: a great glare where it is (up at the right,
        // where there is none), breathing.
        let sun = HabitatArt.sun(b, f)?.point ?? CGPoint(x: f.x(0.8), y: f.y(0.84))
        let gr = 200 * u
        glare.contents = HabitatArt.softDot(gr, HabitatArt.c(1, 0.94, 0.72, 0.8), core: 0.1)
        glare.frame = CGRect(x: sun.x - gr, y: sun.y - gr, width: gr * 2, height: gr * 2)
        glare.removeAllAnimations()
        let breathe = CAAnimationGroup()
        breathe.animations = [basic("transform.scale", 0.93, 1.07), basic("opacity", 0.8, 1)]
        glare.add(loop(breathe, 4.5, reverse: true), forKey: "breathe")

        let rbSize = CGSize(width: W, height: air)
        rainbow.contents = WeatherArt.rainbow(rbSize, u: u)
        rainbow.frame = CGRect(x: 0, y: G, width: W, height: air)
        skyFlash.contents = WeatherArt.skyFlash(CGSize(width: W, height: air), u: u)
        skyFlash.frame = CGRect(x: 0, y: G, width: W, height: air)
        skyFlash.opacity = 0

        // Rain far off, falling behind the ground; and the rain and hail
        // in front, in a box that leans with the wind about the ground line.
        func box(_ l: CALayer) {
            l.bounds = CGRect(origin: .zero, size: s)
            l.anchorPoint = CGPoint(x: 0.5, y: G / H)
            l.position = CGPoint(x: W / 2, y: G)
            l.transform = CATransform3DIdentity
            l.sublayers?.forEach { $0.removeFromSuperlayer() }
        }
        box(farBox)
        box(rainBox)
        let spare = H * 0.45
        let period = (H * 0.5).rounded()
        func sheet(_ img: CGImage?, speed v: CGFloat, phase: CGFloat, into parent: CALayer) -> CALayer {
            let l = CALayer()
            l.contents = img
            l.anchorPoint = CGPoint(x: 0.5, y: 0)
            l.bounds = CGRect(x: 0, y: 0, width: W + spare * 2, height: H + period)
            l.position = CGPoint(x: W / 2, y: 0)
            l.opacity = 0
            l.isHidden = true
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.fromValue = 0
            fall.toValue = -period
            fall.duration = Double(period / v)
            fall.repeatCount = .infinity
            fall.timeOffset = Double(phase) * fall.duration
            l.add(fall, forKey: "fall")
            parent.addSublayer(l)
            return l
        }
        let sheetSize = CGSize(width: W + spare * 2, height: H + period)
        farSheet = sheet(WeatherArt.rainSheet(sheetSize, period: period, count: 110, length: 15 * u, width: 0.8 * u, alpha: 0.4, seed: 31),
                         speed: 620 * u, phase: 0, into: farBox)

        shafts.contents = HabitatArt.lightShafts(s, seed: 23, colour: HabitatArt.c(1, 0.95, 0.76))
        shafts.frame = CGRect(origin: .zero, size: s)
        shafts.removeAllAnimations()
        shafts.add(loop(basic("opacity", 0.55, 1), 7, reverse: true), forKey: "shimmer")
        // Fog in banks, drifting: low along the ground and higher up; and
        // dust, filling the air.
        func bank(_ l: CALayer, height: CGFloat, at y: CGFloat, seed: Int, colour: CGColor, density: CGFloat, period: Double) {
            let sz = CGSize(width: W * 1.8, height: height)
            l.contents = HabitatArt.mist(sz, seed: seed, colour: colour, density: density)
            l.frame = CGRect(x: 0, y: y, width: sz.width, height: sz.height)
            l.removeAllAnimations()
            l.add(loop(basic("position.x", sz.width / 2 - W * 0.1, sz.width / 2 - W * 0.7), period, reverse: true), forKey: "drift")
        }
        bank(fogLow, height: air * 0.5, at: G - 30 * u, seed: 41, colour: HabitatArt.c(0.96, 0.97, 1), density: 1.7, period: 46)
        bank(fogHigh, height: air * 0.45, at: G + air * 0.3, seed: 43, colour: HabitatArt.c(0.94, 0.95, 0.98), density: 1.3, period: 61)
        bank(dustBank, height: air * 0.95, at: G - 30 * u, seed: 47, colour: HabitatArt.c(0.86, 0.7, 0.5), density: 1.9, period: 23)
        bank(fogFront, height: air * 0.38, at: G - 36 * u, seed: 53, colour: HabitatArt.c(0.97, 0.98, 1), density: 1.2, period: 38)
        haze.contents = WeatherArt.heatHaze(CGSize(width: W * 1.2, height: 60 * u), u: u)
        haze.frame = CGRect(x: -W * 0.1, y: G - 6 * u, width: W * 1.2, height: 60 * u)
        haze.removeAllAnimations()
        haze.add(loop(basic("position.x", haze.position.x - 8 * u, haze.position.x + 8 * u), 1.7, reverse: true), forKey: "waver")
        haze.add(loop(basic("transform.scale.y", 0.9, 1.12), 1.1, reverse: true), forKey: "rise")

        // The ground: darker wet, with puddles; a dusting of snow, then a
        // blanket; hail lying about; splashes.
        let gh = G + HabitatArt.groundOverhang(f)
        wetDark.frame = CGRect(x: 0, y: 0, width: W, height: gh)
        wetDark.backgroundColor = CGColor(red: 0.1, green: 0.09, blue: 0.12, alpha: 1)
        wetMask.frame = wetDark.bounds
        wetMask.contents = groundImage
        wetMask.contentsGravity = .resize
        let band = CGSize(width: W, height: G + 10 * u)
        dusting.contents = WeatherArt.snowGround(band, f: f, thick: false)
        blanket.contents = WeatherArt.snowGround(band, f: f, thick: true)
        for l in [dusting, blanket, puddles] { l.frame = CGRect(origin: .zero, size: band) }
        prints.frame = CGRect(origin: .zero, size: s)

        let drop = CAEmitterCell()
        drop.name = "drop"
        drop.contents = HabitatArt.softDot(1.6 * u, HabitatArt.c(0.85, 0.92, 1, 0.95), core: 0.5)
        drop.birthRate = Float(170 * W / 860)
        drop.lifetime = 0.26
        drop.velocity = 70 * u
        drop.velocityRange = 45 * u
        drop.emissionLongitude = .pi / 2
        drop.emissionRange = 0.9
        drop.yAcceleration = -700 * u
        drop.alphaSpeed = -2.5
        drop.scaleRange = 0.4
        let ring = CAEmitterCell()
        ring.name = "ring"
        ring.contents = HabitatArt.ring(size: 12 * u, colour: HabitatArt.c(0.85, 0.92, 1, 0.9))
        ring.birthRate = Float(70 * W / 860)
        ring.lifetime = 0.3
        ring.scale = 0.25
        ring.scaleSpeed = 2.6
        ring.alphaSpeed = -3
        setEmitter(splashes, [drop, ring], shape: .rectangle, at: CGPoint(x: W / 2, y: G - 4 * u), size: CGSize(width: W, height: 12 * u))

        let stone = WeatherArt.hailstone(2.2 * u)
        let bounce = CAEmitterCell()
        bounce.name = "bounce"
        bounce.contents = stone
        bounce.birthRate = Float(60 * W / 860)
        bounce.lifetime = 0.34
        bounce.velocity = 110 * u
        bounce.velocityRange = 50 * u
        bounce.emissionLongitude = .pi / 2
        bounce.emissionRange = 0.7
        bounce.yAcceleration = -1000 * u
        bounce.spin = 3
        bounce.spinRange = 6
        let lying = CAEmitterCell()
        lying.name = "lying"
        lying.contents = stone
        lying.birthRate = Float(16 * W / 860)
        lying.lifetime = 5
        lying.lifetimeRange = 2
        lying.alphaSpeed = -0.18
        lying.scaleRange = 0.3
        setEmitter(hailFloor, [bounce, lying], shape: .rectangle, at: CGPoint(x: W / 2, y: G - 4 * u), size: CGSize(width: W, height: 10 * u))

        // The light: dimmed under cloud (a dark wash over the whole scene),
        // warmed in the sun.
        dim.backgroundColor = CGColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1)
        warm.backgroundColor = CGColor(red: 1, green: 0.8, blue: 0.45, alpha: 1)

        // What falls in front of everything, fading out at the ground.
        precipMask.frame = CGRect(origin: .zero, size: s)
        precipMask.colors = [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 1)]
        precipMask.startPoint = CGPoint(x: 0.5, y: (G - 8 * u) / H)
        precipMask.endPoint = CGPoint(x: 0.5, y: (G + 4 * u) / H)

        rainSheets = [
            sheet(WeatherArt.rainSheet(sheetSize, period: period, count: 75, length: 30 * u, width: 1.3 * u, alpha: 0.6, seed: 41),
                  speed: 1050 * u, phase: 0, into: rainBox),
            sheet(WeatherArt.rainSheet(sheetSize, period: period, count: 95, length: 38 * u, width: 1.5 * u, alpha: 0.55, seed: 43),
                  speed: 1250 * u, phase: 0.5, into: rainBox),
        ]
        hailSheets = [
            sheet(WeatherArt.stoneSheet(sheetSize, period: period, count: 26, radius: 2.6 * u, seed: 47), speed: 820 * u, phase: 0.2, into: rainBox),
            sheet(WeatherArt.stoneSheet(sheetSize, period: period, count: 22, radius: 2 * u, seed: 53), speed: 660 * u, phase: 0.7, into: rainBox),
        ]

        let flake = CAEmitterCell()
        flake.name = "flake"
        flake.contents = HabitatArt.snowflake(2.4 * u)
        flake.birthRate = Float(64 * W / 860)
        flake.velocity = 42 * u
        flake.velocityRange = 14 * u
        flake.emissionLongitude = -.pi / 2
        flake.emissionRange = 0.35
        flake.yAcceleration = -3 * u
        flake.lifetime = Float((H + 40 * u) / (34 * u))
        flake.scaleRange = 0.4
        flake.alphaRange = 0.25
        let big = CAEmitterCell()
        big.name = "big"
        big.contents = HabitatArt.snowflake(3.8 * u)
        big.birthRate = Float(20 * W / 860)
        big.velocity = 58 * u
        big.velocityRange = 16 * u
        big.emissionLongitude = -.pi / 2
        big.emissionRange = 0.3
        big.lifetime = Float((H + 40 * u) / (46 * u))
        big.scaleRange = 0.3
        setEmitter(snowE, [flake, big], shape: .line, at: CGPoint(x: W / 2, y: H + 12 * u), size: CGSize(width: W * 2.4, height: 1))
        lastSnowAim = 99

        // Blown in from the side: sand, dust, snow on a gale, streaks of
        // wind, and whatever loose bits the scenery has (leaves, petals).
        func sideCell(_ name: String, _ img: CGImage?, velocity v: CGFloat, range: CGFloat = 0.12, lifetime: CGFloat, spin: CGFloat = 0,
                      ay: CGFloat = 0, alpha: Float = 1) -> CAEmitterCell {
            let c = CAEmitterCell()
            c.name = name
            c.contents = img
            c.birthRate = 0
            c.velocity = v
            c.velocityRange = v * 0.3
            c.emissionRange = range
            c.lifetime = Float(lifetime)
            c.spinRange = spin
            c.yAcceleration = ay
            c.color = CGColor(red: 1, green: 1, blue: 1, alpha: CGFloat(alpha))
            c.scaleRange = 0.35
            return c
        }
        let debris = WeatherArt.debris(b, u: u)
        var side = [
            sideCell("grain", HabitatArt.softDot(1.7 * u, HabitatArt.c(0.9, 0.76, 0.54), core: 0.5), velocity: 540 * u, lifetime: W / (380 * u), ay: -24 * u),
            sideCell("dust", HabitatArt.softDot(18 * u, HabitatArt.c(0.86, 0.7, 0.5, 0.3), core: 0.1), velocity: 260 * u, range: 0.2, lifetime: W / (190 * u), alpha: 0.9),
            sideCell("gale", HabitatArt.snowflake(2.2 * u), velocity: 420 * u, range: 0.2, lifetime: W / (300 * u), ay: -40 * u),
            sideCell("streak", WeatherArt.windStreak(length: 80 * u, u: u), velocity: 760 * u, range: 0.05, lifetime: W / (560 * u), alpha: 0.26),
        ]
        for (k, img) in debris.enumerated() {
            side.append(sideCell("leaf\(k)", img, velocity: 330 * u, range: 0.4, lifetime: W / (230 * u), spin: 9, ay: -30 * u))
        }
        setEmitter(sideE, side, shape: .rectangle, at: CGPoint(x: -14 * u, y: G + air * 0.5), size: CGSize(width: 2, height: air * 1.05))
        sideE.birthRate = 1
        sideFrom = 1
        lastSideSpeed = -1

        veil.backgroundColor = CGColor(red: 0.9, green: 0.92, blue: 0.95, alpha: 1)
        flashFill.backgroundColor = CGColor(red: 0.92, green: 0.95, blue: 1, alpha: 1)
        flashFill.opacity = 0
        for e in [splashes, hailFloor, snowE] { e.birthRate = 0 }
        marks = []
        prints.path = nil
    }

    /// The furniture: snow on top of it, and where the puddles form.
    func layoutItems(_ h: Habitat, toView: (CGRect) -> CGRect) {
        guard built else { return }
        let key = "\(Int(size.width))x\(Int(size.height))-" + h.items.map { "\($0.id):\(Int($0.x)),\(Int($0.y)),\(Int($0.w)),\(Int($0.h)),\($0.flipped),\($0.front)" }.joined(separator: ";")
        guard key != itemsKey else { return }
        itemsKey = key
        let u = f.u
        let sx = size.width / HabitatLayout.width, sy = size.height / HabitatLayout.height
        let point: (V2) -> CGPoint = { CGPoint(x: $0.x * sx, y: $0.y * sy) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        capsThin.frame = CGRect(origin: .zero, size: size)
        capsThick.frame = CGRect(origin: .zero, size: size)
        capsThin.contents = WeatherArt.snowCaps(h.items, size: size, u: u, thick: false, toView: toView, point: point)
        capsThick.contents = WeatherArt.snowCaps(h.items, size: size, u: u, thick: true, toView: toView, point: point)
        // Puddles, in the open stretches of ground.
        let spots = WeatherArt.puddleSpots(h)
        puddles.contents = WeatherArt.puddles(CGSize(width: size.width, height: f.groundY + 10 * u), f: f, spots: spots)
        for r in ripples { r.removeFromSuperlayer() }
        ripples = spots.map { s in
            let e = CAEmitterLayer()
            let c = CAEmitterCell()
            c.name = "ripple"
            c.contents = HabitatArt.ring(size: 12 * u, colour: HabitatArt.c(0.9, 0.95, 1, 0.85))
            c.birthRate = 7
            c.lifetime = 0.5
            c.scale = 0.3
            c.scaleSpeed = 2
            c.alphaSpeed = -2
            e.frame = CGRect(origin: .zero, size: size)
            setEmitter(e, [c], shape: .line, at: CGPoint(x: s.x * sx, y: f.groundY - 5 * u), size: CGSize(width: s.w * sx * 0.7, height: 1))
            e.birthRate = 0
            ground.insertSublayer(e, above: puddles)
            return e
        }
    }

    // MARK: The weather, as it is

    /// Turns everything up or down for the weather now; `dt` is how long
    /// since the last time.
    func update(_ c: WeatherConditions, dt: CGFloat) {
        guard built else { return }
        let m = c.mix
        let u = f.u, W = size.width
        let wind = c.windNow
        // Clear skies and nothing lying about: once all is put away, there
        // is nothing to do.
        if m == WeatherRecipe(), groundSnow == 0, groundWet == 0, marks.isEmpty {
            stillTicks += 1
            if stillTicks > 20 { return }
        } else {
            stillTicks = 0
        }

        // What lies on the ground builds up while it comes down, and goes
        // after — snow slowly (never quite, in the snowfall), puddles
        // drying quicker in the sun and the wind.
        if m.snow > 0.05 {
            groundSnow = min(1, groundSnow + m.snow * dt / 50)
        } else if groundSnow > 0 {
            let melt = (1 / 260 + m.heat / 30 + m.sun / 50 + m.rain / 60) * (biome == .tundra ? 0.3 : 1)
            groundSnow = max(0, groundSnow - melt * dt)
            groundWet = min(1, groundWet + melt * dt * 0.6)
        }
        if m.rain > 0.05 {
            groundWet = min(1, groundWet + m.rain * dt / 28)
        } else if groundWet > 0 {
            groundWet = max(0, groundWet - (1 / 220 + m.sun / 50 + m.heat / 40 + abs(wind) / 160 + m.sand / 30) * dt)
        }
        if groundSnow < 0.12, !marks.isEmpty { marks = []; prints.path = nil }
        // New snow fills footprints in.
        if !marks.isEmpty {
            let now = CACurrentMediaTime()
            let keep: CFTimeInterval = m.snow > 0.3 ? 45 : 240
            let n = marks.count
            marks.removeAll { now - $0.t > keep }
            if marks.count != n { rebuildPrints() }
        }

        // The decks drift with the wind (and a little on a still day).
        let drift = (wind * 16 + (wind >= 0 ? 3 : -3)) * u * dt
        deckOff = wrap(deckOff + drift, W)
        stormOff = wrap(stormOff + drift * 1.4, W)

        if !deck.isHidden || !stormDeck.isHidden || m.cloud > 0 || m.storm > 0 {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            deck.position.x = W * 0.5 + deckOff
            stormDeck.position.x = W * 0.5 + stormOff
            CATransaction.commit()
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.35)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        fade(nightSky, m.night * 0.95)
        fade(auroraBox, m.aurora)
        fade(meteors, m.stars)
        fade(deck, m.cloud * 0.93)
        fade(stormDeck, m.storm * 0.96)
        fade(glare, m.sun)
        fade(rainbow, m.rainbow * 0.8)
        fade(farSheet, min(1, m.rain * 0.9 + m.hail * 0.4))
        fade(shafts, m.sun * 0.7 + m.rainbow * 0.25)
        fade(fogLow, m.fog * 0.85)
        fade(fogHigh, m.fog * 0.6)
        fade(dustBank, m.sand * 0.9)
        fade(haze, m.heat * 0.75)
        fade(wetDark, groundWet * 0.3)
        fade(puddles, smoothstep(min(groundWet * 1.4, 1)))
        let ripple = m.rain * min(1, groundWet * 2)
        for r in ripples { rate(r, ripple) }
        fade(dusting, smoothstep(min(groundSnow * 3, 1)))
        fade(blanket, smoothstep(clamp((groundSnow - 0.25) / 0.5, 0, 1)))
        fade(prints, smoothstep(min(groundSnow * 2, 1)))
        fade(capsThin, smoothstep(min(groundSnow * 3, 1)))
        fade(capsThick, smoothstep(clamp((groundSnow - 0.3) / 0.5, 0, 1)))
        rate(splashes, m.rain)
        rate(hailFloor, m.hail)
        // The light: cloud and storms dim it, blue-grey; a sandstorm
        // browns it; the night sky blues it.
        let wStorm = max(m.dark - m.night * 0.35 - m.sand * 0.3, 0), wSand = m.sand, wNight = m.night
        let wt = max(wStorm + wSand + wNight, 0.0001)
        let dimRGB = [(0.06 * wStorm + 0.42 * wSand + 0.02 * wNight) / wt, (0.08 * wStorm + 0.28 * wSand + 0.03 * wNight) / wt,
                      (0.16 * wStorm + 0.12 * wSand + 0.14 * wNight) / wt]
        if m.dark > 0, changed(dimRGB, &lastDim) {
            dim.backgroundColor = CGColor(red: dimRGB[0], green: dimRGB[1], blue: dimRGB[2], alpha: 1)
        }
        fade(dim, m.dark * 0.62)
        fade(warm, m.sun * 0.1 + m.heat * 0.04)
        if rainSheets.count == 2, hailSheets.count == 2 {
            fade(rainSheets[0], min(1, m.rain * 2.5))
            fade(rainSheets[1], clamp((m.rain - 0.45) * 2.2, 0, 1))
            fade(hailSheets[0], m.hail)
            fade(hailSheets[1], m.hail * 0.8)
        }
        // Coming down at a slant in the wind: the boxes lean about the
        // ground line (falling to the right, blown to the right).
        let slant = -clamp(wind * 0.3, -0.4, 0.4)
        if m.rain + m.hail > 0, abs(slant - lastLean) > 0.003 {
            lastLean = slant
            var lean = CATransform3DIdentity
            lean.m21 = slant
            rainBox.transform = lean
            lean.m21 *= 0.6
            farBox.transform = lean
        }
        rate(snowE, m.snow)
        fade(fogFront, m.fog * 0.5)
        // A white-out in a blizzard, a brown-out in a sandstorm, a grey
        // wash in fog.
        let whiteout = m.snow * min(abs(wind), 1.5) * 0.14
        let veilSand = m.sand * 0.28
        let veilFog = m.fog * 0.28
        let vt = max(whiteout + veilSand + veilFog, 0.0001)
        let veilRGB = [(0.95 * whiteout + 0.88 * veilSand + 0.9 * veilFog) / vt, (0.97 * whiteout + 0.74 * veilSand + 0.92 * veilFog) / vt,
                       (1 * whiteout + 0.56 * veilSand + 0.95 * veilFog) / vt]
        if whiteout + veilSand + veilFog > 0, changed(veilRGB, &lastVeil) {
            veil.backgroundColor = CGColor(red: veilRGB[0], green: veilRGB[1], blue: veilRGB[2], alpha: 1)
        }
        fade(veil, whiteout + veilSand + veilFog)
        CATransaction.commit()

        aimSnow(wind)
        blowSide(m, wind: wind, u: u)
        lightning(m, dt: dt)
    }

    /// Snow drifts with the wind: new flakes set off at a slant, from
    /// upwind of the tank so none of it is left bare.
    private func aimSnow(_ wind: CGFloat) {
        let aim = clamp(wind * 0.55, -1.0, 1.0)
        guard abs(aim - lastSnowAim) > 0.03 else { return }
        lastSnowAim = aim
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snowE.setValue(-CGFloat.pi / 2 + aim, forKeyPath: "emitterCells.flake.emissionLongitude")
        snowE.setValue(-CGFloat.pi / 2 + aim, forKeyPath: "emitterCells.big.emissionLongitude")
        snowE.emitterPosition = CGPoint(x: size.width / 2 - aim * size.width * 0.5, y: size.height + 12 * f.u)
        CATransaction.commit()
    }

    /// What blows in from the side: which side, how fast and how much.
    private func blowSide(_ m: WeatherRecipe, wind: CGFloat, u: CGFloat) {
        let from: CGFloat = wind >= 0 ? 1 : -1
        let strong = abs(wind)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let names = ["grain", "dust", "gale", "streak"] + (0..<3).map { "leaf\($0)" }
        if from != sideFrom {
            sideFrom = from
            sideE.emitterPosition = CGPoint(x: from > 0 ? -14 * u : size.width + 14 * u, y: sideE.emitterPosition.y)
            for n in names { sideE.setValue(from > 0 ? 0 : CGFloat.pi, forKeyPath: "emitterCells.\(n).emissionLongitude") }
        }
        let k = size.width / 860
        let gusty = 0.5 + m.gust
        func birth(_ name: String, _ v: CGFloat) {
            guard abs((sideRates[name] ?? -1) - v) > 0.05 else { return }
            sideRates[name] = v
            sideE.setValue(v, forKeyPath: "emitterCells.\(name).birthRate")
        }
        birth("grain", 260 * m.sand * k)
        birth("dust", 16 * m.sand * k)
        birth("gale", 220 * m.snow * max(0, strong - 0.55) * 2 * k)
        birth("streak", 14 * max(0, strong - 0.35) * k)
        for i in 0..<3 { birth("leaf\(i)", 3.5 * max(0, strong - 0.4) * gusty * k * (1 - m.sand)) }
        // Faster in a stronger wind.
        let speed = (strong * 10).rounded() / 10
        if speed != lastSideSpeed {
            lastSideSpeed = speed
            sideE.setValue((380 + 330 * speed) * u, forKeyPath: "emitterCells.streak.velocity")
            sideE.setValue((260 + 220 * speed) * u, forKeyPath: "emitterCells.gale.velocity")
            sideE.setValue((330 + 280 * speed) * u, forKeyPath: "emitterCells.grain.velocity")
            for i in 0..<3 { sideE.setValue((170 + 190 * speed) * u, forKeyPath: "emitterCells.leaf\(i).velocity") }
        }
    }

    // MARK: Lightning

    private func lightning(_ m: WeatherRecipe, dt: CGFloat) {
        guard m.lightning > 0.05 else { strikeIn = max(strikeIn, 2.5); return }
        strikeIn -= dt
        guard strikeIn <= 0 else { return }
        strikeIn = CGFloat.random(in: 3.5...12) / max(m.lightning, 0.25)
        strike(near: CGFloat.random(in: 0...1) < 0.3 * m.lightning + 0.05)
    }

    /// A bolt — far off behind the hills, or right down to the ground in
    /// front of them — the sky lighting up with it, and thunder after.
    func strike(near: Bool) {
        guard built else { return }
        let u = f.u
        let x = CGFloat.random(in: 0.08...0.92) * size.width
        let top = CGPoint(x: x + CGFloat.random(in: -40...40) * u, y: size.height + 4)
        let bottom = CGPoint(x: x + CGFloat.random(in: -70...70) * u, y: near ? f.groundY + 2 * u : f.y(0.2))
        let bolt = near ? nearBolt : farBolt
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bolt.frame = CGRect(origin: .zero, size: size)
        bolt.path = WeatherArt.bolt(from: top, to: bottom, u: u)
        bolt.lineWidth = (near ? 2.6 : 1.5) * u
        CATransaction.commit()
        flicker(bolt, [1, 0.2, 0.95], over: 0.5)
        flicker(skyFlash, near ? [1, 0.25, 0.85] : [0.7, 0.1, 0.5], over: 0.55)
        flicker(flashFill, near ? [0.5, 0.06, 0.34] : [0.13, 0, 0.09], over: 0.5)
        let delay = near ? Double.random(in: 0.12...0.4) : Double.random(in: 0.9...2.4)
        let at = CGPoint(x: bottom.x, y: near ? f.groundY : f.y(0.35))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.onThunder?(at, near ? 1 : 0.4) }
    }

    private func flicker(_ l: CALayer, _ peaks: [CGFloat], over d: CFTimeInterval) {
        let a = CAKeyframeAnimation(keyPath: "opacity")
        a.values = [0, peaks[0], peaks[1], peaks[2], 0]
        a.keyTimes = [0, 0.05, 0.15, 0.25, 1]
        a.duration = d
        l.add(a, forKey: "flash")
    }

    /// Tools only: this much snow lying, and this wet a ground, at once.
    func debugGround(snow: CGFloat, wet: CGFloat) {
        groundSnow = snow
        groundWet = wet
        stillTicks = 0
    }

    // MARK: Footprints

    /// Tracks in the snow: whoever walks through it leaves a line of little
    /// prints (a foot down at `p`, in the scene), which new snow fills in.
    var wantsFootprints: Bool { groundSnow > 0.3 }

    func footDown(at p: CGPoint) {
        guard wantsFootprints else { return }
        if marks.contains(where: { abs($0.p.x - p.x) < 4.5 && abs($0.p.y - p.y) < 3 }) { return }
        marks.append((p, CACurrentMediaTime()))
        if marks.count > 260 { marks.removeFirst(marks.count - 260) }
        rebuildPrints()
    }

    private func rebuildPrints() {
        let u = f.u
        let path = CGMutablePath()
        for m in marks {
            path.addEllipse(in: CGRect(x: m.p.x - 1.8 * u, y: m.p.y - 1.4 * u, width: 3.6 * u, height: 1.5 * u))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        prints.path = path
        CATransaction.commit()
    }

    // MARK: Helpers

    /// Opacity, with the layer left out altogether while it is nothing —
    /// once it has faded all the way out.
    private func fade(_ l: CALayer, _ v: CGFloat) {
        let o = Float(clamp(v, 0, 1))
        if o > 0.002 {
            if l.isHidden {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                l.opacity = 0
                l.isHidden = false
                CATransaction.commit()
            }
            if abs(l.opacity - o) > 0.002 { l.opacity = o }
        } else if !l.isHidden {
            if l.opacity != 0 {
                l.opacity = 0
            } else if (l.presentation()?.opacity ?? 0) <= 0.002 {
                l.isHidden = true
            }
        }
    }

    /// An emitter's rate, set only when it changes.
    private func rate(_ e: CAEmitterLayer, _ v: CGFloat) {
        let r = Float(clamp(v, 0, 1))
        if abs(e.birthRate - r) > 0.002 || (r == 0 && e.birthRate != 0) { e.birthRate = r }
    }

    /// Whether `now` differs from `was` (and keeps it if so).
    private func changed(_ now: [CGFloat], _ was: inout [CGFloat]) -> Bool {
        guard was.count != now.count || zip(now, was).contains(where: { abs($0 - $1) > 0.003 }) else { return false }
        was = now
        return true
    }

    private func wrap(_ v: CGFloat, _ period: CGFloat) -> CGFloat {
        guard period > 1 else { return 0 }
        var x = v.truncatingRemainder(dividingBy: period)
        if x < 0 { x += period }
        return x
    }

    private func setEmitter(_ e: CAEmitterLayer, _ cells: [CAEmitterCell], shape: CAEmitterLayerEmitterShape, at p: CGPoint, size s: CGSize) {
        e.emitterShape = shape
        e.emitterMode = shape == .line ? .outline : .volume
        e.emitterPosition = p
        e.emitterSize = s
        e.emitterCells = cells
        e.renderMode = .unordered
        e.seed = UInt32.random(in: 1...UInt32.max)
    }

    private func loop(_ a: CAAnimation, _ duration: CFTimeInterval, reverse: Bool = false) -> CAAnimation {
        a.duration = duration
        a.repeatCount = .infinity
        a.autoreverses = reverse
        return a
    }

    private func basic(_ key: String, _ from: Any, _ to: Any) -> CABasicAnimation {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = from
        a.toValue = to
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return a
    }
}

// MARK: - Pictures

enum WeatherArt {
    private static func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { HabitatArt.c(r, g, b, a) }
    private static func rnd(_ s: Int, _ i: Int) -> CGFloat { HabitatArt.rnd(s, i) }

    /// A sheet of rain, the same every `period` down (so it can slide down
    /// for ever): streaks clear at the top and bright at the bottom.
    static func rainSheet(_ s: CGSize, period: CGFloat, count n: Int, length l: CGFloat, width w: CGFloat, alpha a: CGFloat, seed: Int) -> CGImage? {
        HabitatArt.image(s, scale: 1) { ctx in
            ctx.setLineCap(.round)
            ctx.setLineWidth(max(w, 0.7))
            for k in 0..<n {
                let x = rnd(seed, k) * s.width
                let len = l * (0.7 + 0.6 * rnd(seed + 2, k))
                let al = a * (0.5 + 0.5 * rnd(seed + 3, k))
                var y = rnd(seed + 1, k) * period - period
                while y < s.height {
                    for i in 0..<5 {
                        let t0 = CGFloat(i) / 5, t1 = CGFloat(i + 1) / 5
                        ctx.setStrokeColor(c(0.86, 0.91, 1, al * (1 - t0)))
                        ctx.beginPath()
                        ctx.move(to: CGPoint(x: x, y: y + len * t0))
                        ctx.addLine(to: CGPoint(x: x, y: y + len * t1))
                        ctx.strokePath()
                    }
                    y += period
                }
            }
        }
    }

    /// A sheet of hailstones, the same every `period` down.
    static func stoneSheet(_ s: CGSize, period: CGFloat, count n: Int, radius r: CGFloat, seed: Int) -> CGImage? {
        HabitatArt.image(s, scale: 1) { ctx in
            for k in 0..<n {
                let x = rnd(seed, k) * s.width
                let rr = r * (0.7 + 0.6 * rnd(seed + 2, k))
                var y = rnd(seed + 1, k) * period - period
                while y < s.height + rr {
                    let rect = CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)
                    // (A faint trail above it.)
                    HabitatArt.fill(ctx, CGPath(rect: CGRect(x: x - rr * 0.35, y: y, width: rr * 0.7, height: rr * 6), transform: nil),
                                    [c(1, 1, 1, 0.35), c(1, 1, 1, 0)], from: CGPoint(x: x, y: y), to: CGPoint(x: x, y: y + rr * 6))
                    HabitatArt.fill(ctx, CGPath(ellipseIn: rect, transform: nil), [c(1, 1, 1), c(0.8, 0.88, 0.98)],
                                    from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
                    ctx.setStrokeColor(c(0.55, 0.65, 0.8, 0.8))
                    ctx.setLineWidth(max(0.5, rr * 0.2))
                    ctx.strokeEllipse(in: rect)
                    y += period
                }
            }
        }
    }

    static func hailstone(_ r: CGFloat) -> CGImage? {
        HabitatArt.image(CGSize(width: r * 2 + 1, height: r * 2 + 1), scale: 2) { ctx in
            let rect = CGRect(x: 0.5, y: 0.5, width: r * 2, height: r * 2)
            HabitatArt.fill(ctx, CGPath(ellipseIn: rect, transform: nil), [c(1, 1, 1), c(0.8, 0.88, 0.98)],
                            from: CGPoint(x: rect.minX, y: rect.maxY), to: CGPoint(x: rect.maxX, y: rect.minY))
            ctx.setStrokeColor(c(0.55, 0.65, 0.8, 0.8))
            ctx.setLineWidth(max(0.5, r * 0.2))
            ctx.strokeEllipse(in: rect)
        }
    }

    /// A streak of wind: a long, faint line, thickest in the middle.
    static func windStreak(length l: CGFloat, u: CGFloat) -> CGImage? {
        let h = max(1.6 * u, 1)
        return HabitatArt.image(CGSize(width: l, height: h), scale: 2) { ctx in
            HabitatArt.linear(ctx, [c(1, 1, 1, 0), c(1, 1, 1, 1), c(1, 1, 1, 0)], [0, 0.6, 1], from: .zero, to: CGPoint(x: l, y: 0))
            ctx.setBlendMode(.destinationIn)
            HabitatArt.linear(ctx, [c(1, 1, 1, 0), c(1, 1, 1, 1), c(1, 1, 1, 0)], from: .zero, to: CGPoint(x: 0, y: h))
        }
    }

    /// A shooting star, heading down to the right at `angle`: its bright
    /// head at the lower right, its tail trailing up behind.
    static func meteor(length l: CGFloat, angle a: CGFloat) -> CGImage? {
        let w = l * cos(a), h = l * sin(a)
        return HabitatArt.image(CGSize(width: w + 6, height: h + 6), scale: 2) { ctx in
            ctx.setLineCap(.round)
            let tail = CGPoint(x: 3, y: h + 3), head = CGPoint(x: w + 3, y: 3)
            for k in 0..<12 {
                let t0 = CGFloat(k) / 12, t1 = CGFloat(k + 1) / 12
                ctx.setStrokeColor(c(1, 1, 0.95, t1 * t1))
                ctx.setLineWidth(0.4 + 1.8 * t1)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: tail.x + (head.x - tail.x) * t0, y: tail.y + (head.y - tail.y) * t0))
                ctx.addLine(to: CGPoint(x: tail.x + (head.x - tail.x) * t1, y: tail.y + (head.y - tail.y) * t1))
                ctx.strokePath()
            }
            HabitatArt.glow(ctx, at: head, radius: 3, c(1, 1, 1, 1))
        }
    }

    /// A deck of cloud, `width` × 2 across and the same every `width`
    /// along, so it can slide round for ever: soft heaps, lit on top and
    /// darker underneath, thick along the top of the sky.
    static func cloudDeck(width W: CGFloat, height h: CGFloat, u: CGFloat, seed: Int, light: CGColor, dark: CGColor) -> CGImage? {
        HabitatArt.image(CGSize(width: W * 2, height: h), scale: 0.5) { ctx in
            // A flat grey over the whole sky, thickest at the top, then heaps.
            HabitatArt.linear(ctx, [HabitatArt.alpha(HabitatArt.mix(light, dark, 0.3), 1), HabitatArt.alpha(HabitatArt.mix(light, dark, 0.15), 0.85),
                                    HabitatArt.alpha(light, 0)],
                              [0, 0.6, 1], from: CGPoint(x: 0, y: h), to: CGPoint(x: 0, y: h * 0.05))
            let n = max(16, Int(W / (26 * u)))
            for k in 0..<n {
                let x = rnd(seed, k) * W
                let v = rnd(seed + 1, k)
                let y = h * (0.25 + v * 0.7)
                let r = (50 + rnd(seed + 2, k) * 80) * u
                let col = HabitatArt.mix(light, dark, clamp(0.55 - v * 0.55 + rnd(seed + 3, k) * 0.25, 0, 1))
                for dx in [-W, 0, W, W * 2] {
                    HabitatArt.glow(ctx, at: CGPoint(x: x + dx, y: y), radius: r, HabitatArt.alpha(col, 0.95), strength: 1)
                }
            }
        }
    }

    /// The sky at night: dark, and full of stars.
    static func nightSky(_ s: CGSize, u: CGFloat) -> CGImage? {
        HabitatArt.image(s, scale: 1) { ctx in
            HabitatArt.linear(ctx, [c(0.02, 0.03, 0.1), c(0.06, 0.08, 0.2), c(0.13, 0.15, 0.33)], [0, 0.55, 1],
                              from: CGPoint(x: 0, y: s.height), to: CGPoint(x: 0, y: 0))
            for k in 0..<160 {
                let x = rnd(501, k) * s.width
                let v = rnd(502, k)
                let y = s.height * (0.2 + v * 0.8)
                let r = (0.4 + rnd(503, k) * rnd(504, k) * 1.4) * u
                ctx.setFillColor(c(1, 1, 0.95, 0.2 + 0.7 * v))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    /// A rainbow across the sky, its feet fading into the distance.
    static func rainbow(_ s: CGSize, u: CGFloat) -> CGImage? {
        HabitatArt.image(s, scale: 1) { ctx in
            let centre = CGPoint(x: s.width * 0.56, y: -s.height * 0.18)
            let outer = s.height * 0.98
            let band = 5.5 * u
            let bands: [CGColor] = [c(0.95, 0.25, 0.25), c(0.99, 0.6, 0.18), c(0.98, 0.9, 0.3), c(0.35, 0.8, 0.4),
                                    c(0.3, 0.6, 1), c(0.35, 0.35, 0.9), c(0.6, 0.35, 0.85)]
            ctx.setLineCap(.butt)
            for (k, col) in bands.enumerated() {
                ctx.setStrokeColor(HabitatArt.alpha(col, 0.55))
                ctx.setLineWidth(band + 0.6)
                ctx.beginPath()
                ctx.addArc(center: centre, radius: outer - CGFloat(k) * band, startAngle: 0, endAngle: .pi, clockwise: false)
                ctx.strokePath()
            }
            // A glow inside the bow.
            ctx.setStrokeColor(c(1, 1, 1, 0.1))
            ctx.setLineWidth(band * 4)
            ctx.beginPath()
            ctx.addArc(center: centre, radius: outer - band * 9, startAngle: 0, endAngle: .pi, clockwise: false)
            ctx.strokePath()
            // Its feet fade into the haze.
            ctx.setBlendMode(.destinationIn)
            HabitatArt.linear(ctx, [c(1, 1, 1, 0), c(1, 1, 1, 1)], from: CGPoint(x: 0, y: s.height * 0.08), to: CGPoint(x: 0, y: s.height * 0.55))
        }
    }

    /// The sky lit up from inside the cloud.
    static func skyFlash(_ s: CGSize, u: CGFloat) -> CGImage? {
        HabitatArt.image(s, scale: 0.5) { ctx in
            HabitatArt.linear(ctx, [c(0.85, 0.9, 1, 0.9), c(0.7, 0.78, 1, 0.35), c(0.7, 0.78, 1, 0)], [0, 0.5, 1],
                              from: CGPoint(x: 0, y: s.height), to: CGPoint(x: 0, y: 0))
        }
    }

    /// Air wavering over hot ground.
    static func heatHaze(_ s: CGSize, u: CGFloat) -> CGImage? {
        HabitatArt.image(s, scale: 1) { ctx in
            HabitatArt.linear(ctx, [c(1, 0.9, 0.7, 0), c(1, 0.9, 0.7, 0.16), c(1, 0.9, 0.7, 0)], [0, 0.35, 1],
                              from: .zero, to: CGPoint(x: 0, y: s.height))
            ctx.setLineWidth(1.1 * u)
            for k in 0..<7 {
                let y = s.height * (0.12 + CGFloat(k) * 0.11)
                ctx.setStrokeColor(c(1, 0.97, 0.88, 0.1 + 0.06 * CGFloat(k % 2)))
                ctx.beginPath()
                var x: CGFloat = 0
                ctx.move(to: CGPoint(x: 0, y: y))
                while x < s.width {
                    x += 6 * u
                    ctx.addLine(to: CGPoint(x: x, y: y + sin(x / (13 * u) + CGFloat(k) * 1.7) * 2.2 * u))
                }
                ctx.strokePath()
            }
        }
    }

    /// Snow lying on the ground: a dusting (`thick` false) or a blanket.
    static func snowGround(_ s: CGSize, f: HabitatArt.Frame, thick: Bool) -> CGImage? {
        let u = f.u, g = f.groundY
        return HabitatArt.image(s, scale: 1) { ctx in
            if thick {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: g - 30 * u))
                var x: CGFloat = 0
                while x <= s.width + 4 * u {
                    let y = g + 2.6 * u + HabitatArt.wave(x / (70 * u), 5) * 1.6 * u
                    p.addLine(to: CGPoint(x: x, y: y))
                    x += 4 * u
                }
                p.addLine(to: CGPoint(x: s.width, y: g - 30 * u))
                p.closeSubpath()
                HabitatArt.fill(ctx, p, [c(1, 1, 1), c(0.93, 0.96, 1), c(0.86, 0.91, 0.99, 0)], [0, 0.55, 1],
                                from: CGPoint(x: 0, y: g + 4 * u), to: CGPoint(x: 0, y: g - 30 * u))
                // A crisp, bright top edge, and a sparkle here and there.
                ctx.setStrokeColor(c(1, 1, 1, 0.9))
                ctx.setLineWidth(1 * u)
                ctx.beginPath()
                x = 0
                while x <= s.width {
                    let y = g + 2.6 * u + HabitatArt.wave(x / (70 * u), 5) * 1.6 * u
                    if x == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
                    x += 4 * u
                }
                ctx.strokePath()
                for k in 0..<Int(s.width / (18 * u)) {
                    let px = rnd(611, k) * s.width, py = g - rnd(612, k) * 18 * u
                    ctx.setFillColor(c(1, 1, 1, 0.9))
                    ctx.fillEllipse(in: CGRect(x: px - 0.8 * u, y: py - 0.8 * u, width: 1.6 * u, height: 1.6 * u))
                }
            } else {
                ctx.setFillColor(c(1, 1, 1, 0.85))
                ctx.fill(CGRect(x: 0, y: g - 0.6 * u, width: s.width, height: 1.4 * u))
                for k in 0..<Int(s.width / (3 * u)) {
                    let px = rnd(621, k) * s.width, py = g + 1 * u - pow(rnd(622, k), 1.6) * 16 * u
                    let r = (0.6 + rnd(623, k) * 1.4) * u
                    ctx.setFillColor(c(1, 1, 1, 0.55 + rnd(624, k) * 0.4))
                    ctx.fillEllipse(in: CGRect(x: px - r * 1.4, y: py - r * 0.6, width: r * 2.8, height: r * 1.2))
                }
            }
        }
    }

    /// Where puddles form: open stretches of the ground, clear of anything
    /// standing on it (in scene units: the middle, and how wide).
    static func puddleSpots(_ h: Habitat) -> [(x: CGFloat, w: CGFloat)] {
        let blocked = h.items.filter { !$0.kind.hangs && $0.onGround && ($0.kind.climbable || $0.kind == .moss || $0.kind == .leafPile) }
            .map { ($0.x - $0.w * 0.5 - 12, $0.x + $0.w * 0.5 + 12) }
        var spots: [(x: CGFloat, w: CGFloat)] = []
        let widths: [CGFloat] = [84, 60, 70]
        var seed = h.items.reduce(7) { ($0 &* 31 &+ $1.id &* 17 &+ Int($1.x)) % 9973 }
        for w in widths {
            var best: (x: CGFloat, score: CGFloat)?
            for step in 0..<40 {
                let x = 70 + CGFloat(step) / 39 * (HabitatLayout.width - 140)
                let lo = x - w / 2, hi = x + w / 2
                if blocked.contains(where: { $0.0 < hi && $0.1 > lo }) { continue }
                if spots.contains(where: { abs($0.x - x) < ($0.w + w) / 2 + 40 }) { continue }
                seed = (seed * 7919 + 13) % 9973
                let score = CGFloat(seed % 100)
                if best == nil || score > best!.score { best = (x, score) }
            }
            if let b = best { spots.append((b.x, w)) }
        }
        return spots
    }

    static func puddles(_ s: CGSize, f: HabitatArt.Frame, spots: [(x: CGFloat, w: CGFloat)]) -> CGImage? {
        let u = f.u, g = f.groundY
        return HabitatArt.image(s, scale: 1) { ctx in
            for sp in spots {
                let w = sp.w * u, cx = sp.x * u
                let r = CGRect(x: cx - w / 2, y: g - 8 * u, width: w, height: 6.5 * u)
                let p = CGPath(ellipseIn: r, transform: nil)
                HabitatArt.fill(ctx, p, [c(0.72, 0.8, 0.9, 0.85), c(0.42, 0.52, 0.66, 0.75)],
                                from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: r.minY))
                ctx.setStrokeColor(c(0.18, 0.15, 0.12, 0.25))
                ctx.setLineWidth(1 * u)
                ctx.addPath(p)
                ctx.strokePath()
                // The sky caught in it.
                ctx.setStrokeColor(c(1, 1, 1, 0.55))
                ctx.setLineWidth(0.8 * u)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: r.minX + w * 0.2, y: r.midY + 1.2 * u))
                ctx.addLine(to: CGPoint(x: r.minX + w * 0.45, y: r.midY + 1.2 * u))
                ctx.move(to: CGPoint(x: r.minX + w * 0.56, y: r.midY - 0.6 * u))
                ctx.addLine(to: CGPoint(x: r.minX + w * 0.68, y: r.midY - 0.6 * u))
                ctx.strokePath()
            }
        }
    }

    /// Snow on top of the furniture: along the tops of logs and stones,
    /// down the length of a branch, on the leaves of a plant; a sprinkle on
    /// the low plants.
    static func snowCaps(_ items: [HabitatItem], size: CGSize, u: CGFloat, thick: Bool,
                         toView: (CGRect) -> CGRect, point: (V2) -> CGPoint) -> CGImage? {
        HabitatArt.image(size, scale: 1) { ctx in
            let depth: CGFloat = (thick ? 4.6 : 1.7) * u
            for it in items where !it.inFront {
                let r = toView(it.rect)
                let solid = Habitat.solidRect(it).map(toView)
                var line: [CGPoint] = []
                var t = depth
                switch it.kind {
                case .branch:
                    let pts = Habitat.branchPoints(it.rect, flipped: it.flipped).map(point)
                    for i in 0..<(pts.count - 1) {
                        for k in 0..<6 {
                            let a = CGFloat(k) / 6
                            line.append(CGPoint(x: pts[i].x + (pts[i + 1].x - pts[i].x) * a, y: pts[i].y + (pts[i + 1].y - pts[i].y) * a))
                        }
                    }
                    line.append(pts[pts.count - 1])
                    t *= 0.75
                case .rock, .boulder:
                    guard let s = solid else { continue }
                    for k in 0...14 {
                        let q = -0.86 + 1.72 * CGFloat(k) / 14
                        line.append(CGPoint(x: s.midX + q * s.width / 2, y: s.minY + s.height * (0.52 + 0.48 * (1 - q * q).squareRoot())))
                    }
                case .log, .driftwood, .hide, .corkBark, .cactus, .bamboo:
                    guard let s = solid else { continue }
                    let inset = s.width * (it.kind == .cactus || it.kind == .bamboo ? 0.05 : 0.03)
                    for k in 0...12 {
                        line.append(CGPoint(x: s.minX + inset + (s.width - inset * 2) * CGFloat(k) / 12, y: s.maxY))
                    }
                    if it.kind == .corkBark || it.kind == .cactus || it.kind == .bamboo { t *= 0.8 }
                case .plant:
                    // Along the leafy top, drooping at the edges.
                    for k in 0...10 {
                        let q = CGFloat(k) / 10
                        line.append(CGPoint(x: r.minX + r.width * (0.2 + 0.6 * q), y: r.maxY - r.height * (0.08 + abs(q - 0.5) * 0.16)))
                    }
                    t *= 0.8
                case .mushrooms, .crystal, .succulent, .fern, .grass, .flower, .twigs, .leafPile, .moss, .pebbles:
                    // A sprinkle over the top of it.
                    let n = Int(r.width / (4 * u))
                    ctx.setFillColor(c(1, 1, 1, thick ? 0.95 : 0.8))
                    for k in 0..<n {
                        let x = r.minX + rnd(it.seed, k) * r.width
                        let y = r.minY + r.height * (0.35 + rnd(it.seed + 1, k) * 0.65)
                        let rr = (thick ? 1.3 : 0.8) * u * (0.6 + rnd(it.seed + 2, k))
                        ctx.fillEllipse(in: CGRect(x: x - rr * 1.3, y: y - rr * 0.6, width: rr * 2.6, height: rr * 1.2))
                    }
                    continue
                case .vine, .waterDish:
                    continue
                }
                cap(ctx, along: line, depth: t, seed: it.seed, u: u)
            }
        }
    }

    /// A lumpy white cap along the top of `line`, thinning to nothing at
    /// its ends.
    private static func cap(_ ctx: CGContext, along line: [CGPoint], depth: CGFloat, seed: Int, u: CGFloat) {
        guard line.count >= 2 else { return }
        var top: [CGPoint] = [], under: [CGPoint] = []
        for (i, p) in line.enumerated() {
            let q = CGFloat(i) / CGFloat(line.count - 1)
            let taper = smoothstep(min(q, 1 - q) / 0.22)
            let lump = 1 + 0.25 * sin(q * 17 + CGFloat(seed)) + 0.12 * sin(q * 41 + CGFloat(seed) * 1.7)
            top.append(CGPoint(x: p.x, y: p.y + depth * taper * lump))
            under.append(CGPoint(x: p.x, y: p.y - 1.2 * u * taper))
        }
        let path = CGMutablePath()
        path.addLines(between: top + under.reversed())
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(c(0.97, 0.98, 1))
        ctx.fillPath()
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addLines(between: under)
        ctx.setStrokeColor(c(0.7, 0.78, 0.92, 0.9))
        ctx.setLineWidth(1 * u)
        ctx.strokePath()
        ctx.addLines(between: top)
        ctx.setStrokeColor(c(0.6, 0.68, 0.82, 0.55))
        ctx.setLineWidth(0.7 * u)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// A lightning bolt: jagged, with a fork or two.
    static func bolt(from a: CGPoint, to b: CGPoint, u: CGFloat) -> CGPath {
        func jag(_ from: CGPoint, _ to: CGPoint, passes: Int, rough: CGFloat) -> [CGPoint] {
            var pts = [from, to]
            var off = rough
            for _ in 0..<passes {
                var next = [pts[0]]
                for i in 0..<(pts.count - 1) {
                    let p = pts[i], q = pts[i + 1]
                    let d = CGPoint(x: q.x - p.x, y: q.y - p.y)
                    let len = max(hypot(d.x, d.y), 0.001)
                    let n = CGPoint(x: -d.y / len, y: d.x / len)
                    let k = CGFloat.random(in: -1...1) * off
                    next.append(CGPoint(x: (p.x + q.x) / 2 + n.x * k, y: (p.y + q.y) / 2 + n.y * k))
                    next.append(q)
                }
                pts = next
                off *= 0.52
            }
            return pts
        }
        let main = jag(a, b, passes: 5, rough: abs(b.y - a.y) * 0.16)
        let path = CGMutablePath()
        path.addLines(between: main)
        for _ in 0..<Int.random(in: 1...2) {
            let i = Int.random(in: main.count / 5...main.count * 3 / 5)
            let s = main[i]
            let len = abs(b.y - a.y) * CGFloat.random(in: 0.18...0.35)
            let side: CGFloat = Bool.random() ? 1 : -1
            let e = CGPoint(x: s.x + side * len * CGFloat.random(in: 0.4...0.8), y: s.y - len)
            path.addLines(between: jag(s, e, passes: 3, rough: len * 0.2))
        }
        return path
    }

    /// Whatever loose bits the scenery has for the wind to catch.
    static func debris(_ b: Biome, u: CGFloat) -> [CGImage?] {
        let cols: [CGColor]
        switch b {
        case .forest: cols = [c(0.86, 0.56, 0.22), c(0.74, 0.4, 0.16), c(0.9, 0.72, 0.28)]
        case .jungle: cols = [c(0.3, 0.6, 0.25), c(0.45, 0.72, 0.3), c(0.25, 0.5, 0.3)]
        case .desert: cols = [c(0.82, 0.7, 0.46), c(0.72, 0.6, 0.4), c(0.88, 0.8, 0.6)]
        case .meadow: cols = [c(1, 1, 1), c(0.98, 0.82, 0.3), c(0.98, 0.7, 0.8)]
        case .cave: cols = [c(0.62, 0.6, 0.64), c(0.5, 0.48, 0.52), c(0.7, 0.68, 0.72)]
        case .beach: cols = [c(0.5, 0.66, 0.36), c(0.9, 0.84, 0.66), c(0.62, 0.72, 0.4)]
        case .tundra: cols = [c(0.34, 0.48, 0.4), c(0.95, 0.97, 1), c(0.44, 0.52, 0.46)]
        case .night: cols = [c(0.26, 0.32, 0.36), c(0.36, 0.4, 0.44), c(0.3, 0.36, 0.3)]
        }
        return cols.map { HabitatArt.leaf($0, size: 11 * u) }
    }

    // MARK: Tiles

    /// A tile for the weather picker: the scenery, with the weather on it.
    static func thumbnail(_ kind: WeatherKind, biome b: Biome, size s: CGSize) -> NSImage {
        let img = HabitatArt.image(s, scale: 2) { ctx in
            let r = CGRect(origin: .zero, size: s)
            HabitatArt.paintSky(b, in: r, ctx)
            HabitatArt.paintScenery(b, in: r, ctx)
            HabitatArt.paintGround(b, in: r, ctx)
            paintStill(kind, biome: b, in: r, ctx)
        }
        return NSImage(cgImage: img!, size: s)
    }

    /// The weather, stopped: for a tile.
    static func paintStill(_ kind: WeatherKind, biome b: Biome, in r: CGRect, _ ctx: CGContext) {
        let f = HabitatArt.Frame(rect: r)
        let u = f.u
        let m = kind.recipe
        ctx.saveGState()
        ctx.clip(to: r)
        if m.night > 0 {
            if let sky = nightSky(CGSize(width: r.width, height: f.air), u: u) {
                ctx.saveGState()
                ctx.setAlpha(0.9)
                ctx.draw(sky, in: CGRect(x: 0, y: f.groundY + f.air * 0.3, width: r.width, height: f.air * 0.7))
                ctx.restoreGState()
            }
        }
        if m.aurora > 0 {
            if let a = HabitatArt.aurora(CGSize(width: r.width * 1.1, height: f.air * 0.5), seed: 160, colours: [c(0.3, 1, 0.65), c(0.6, 0.5, 1)]) {
                ctx.saveGState()
                ctx.setBlendMode(.screen)
                ctx.draw(a, in: CGRect(x: -r.width * 0.05, y: f.y(0.45), width: r.width * 1.1, height: f.air * 0.5))
                ctx.restoreGState()
            }
        }
        if m.stars > 0 {
            ctx.setLineCap(.round)
            for k in 0..<3 {
                let x = r.width * (0.2 + CGFloat(k) * 0.25), y = f.y(0.9 - CGFloat(k) * 0.08)
                let l = 26 * u
                HabitatArt.linear(ctx, [c(1, 1, 1, 0), c(1, 1, 0.9, 0.95)], from: CGPoint(x: x, y: y), to: CGPoint(x: x + l, y: y - l * 0.45))
                ctx.setStrokeColor(c(1, 1, 0.92, 0.9))
                ctx.setLineWidth(1.4 * u)
                ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + l, y: y - l * 0.45)); ctx.strokePath()
            }
        }
        if m.sun > 0 {
            let sun = HabitatArt.sun(b, f)?.point ?? CGPoint(x: f.x(0.8), y: f.y(0.84))
            HabitatArt.glow(ctx, at: sun, radius: 160 * u, c(1, 0.93, 0.7, 0.7 * m.sun))
            HabitatArt.glow(ctx, at: sun, radius: 40 * u, c(1, 1, 0.9, 0.9 * m.sun))
        }
        if m.cloud > 0 || m.storm > 0 {
            let dark = m.storm
            HabitatArt.linear(ctx, [c(0.8 - 0.45 * dark, 0.82 - 0.45 * dark, 0.86 - 0.4 * dark, 0.92 * max(m.cloud, dark)), c(0.8, 0.82, 0.86, 0)],
                              from: CGPoint(x: 0, y: r.maxY), to: CGPoint(x: 0, y: f.y(0.45)))
            for k in 0..<7 {
                let x = r.width * (CGFloat(k) + 0.5) / 7
                HabitatArt.glow(ctx, at: CGPoint(x: x, y: r.maxY - f.air * 0.12), radius: (26 + rnd(71, k) * 16) * u,
                                c(0.86 - 0.5 * dark, 0.88 - 0.5 * dark, 0.92 - 0.45 * dark, 0.9 * max(m.cloud, dark)))
            }
        }
        if m.rainbow > 0 {
            let cx = r.width * 0.56, cy = f.groundY - f.air * 0.15
            for (k, col) in [c(0.95, 0.25, 0.25), c(0.99, 0.6, 0.18), c(0.98, 0.9, 0.3), c(0.35, 0.8, 0.4), c(0.3, 0.6, 1), c(0.6, 0.35, 0.85)].enumerated() {
                ctx.setStrokeColor(HabitatArt.alpha(col, 0.55))
                ctx.setLineWidth(5 * u)
                ctx.beginPath()
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: f.air * 0.95 - CGFloat(k) * 5 * u, startAngle: 0.1, endAngle: .pi - 0.1, clockwise: false)
                ctx.strokePath()
            }
        }
        if m.lightning > 0.5 {
            let path = bolt(from: CGPoint(x: r.width * 0.3, y: r.maxY), to: CGPoint(x: r.width * 0.36, y: f.groundY + 2), u: u)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 6 * u, color: c(0.7, 0.8, 1))
            ctx.setStrokeColor(c(1, 1, 1))
            ctx.setLineWidth(2.4 * u)
            ctx.addPath(path)
            ctx.strokePath()
            ctx.restoreGState()
        }
        if m.dark > 0 {
            ctx.setFillColor(c(0.1, 0.12, 0.2, m.dark * 0.35))
            ctx.fill(r)
        }
        if m.fog > 0 {
            HabitatArt.linear(ctx, [c(0.95, 0.96, 0.98, 0.8 * m.fog), c(0.95, 0.96, 0.98, 0.25 * m.fog)],
                              from: CGPoint(x: 0, y: f.groundY), to: CGPoint(x: 0, y: f.y(0.8)))
        }
        if m.sand > 0 {
            ctx.setFillColor(c(0.86, 0.7, 0.48, 0.45 * m.sand))
            ctx.fill(r)
            ctx.setStrokeColor(c(0.95, 0.85, 0.65, 0.6))
            ctx.setLineWidth(1.2 * u)
            for k in 0..<14 {
                let y = f.groundY + rnd(81, k) * f.air * 0.8, x = rnd(82, k) * r.width
                ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x + 40 * u, y: y - 3 * u)); ctx.strokePath()
            }
        }
        if m.rain > 0 {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(c(0.85, 0.9, 1, 0.75))
            ctx.setLineWidth(1.4 * u)
            let n = Int(40 * m.rain) + 6
            for k in 0..<n {
                let x = rnd(91, k) * r.width, y = f.groundY + rnd(92, k) * f.air
                ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x - 4 * u, y: y - 20 * u)); ctx.strokePath()
            }
        }
        if m.snow > 0 {
            ctx.setFillColor(c(1, 1, 1, 0.95))
            let n = Int(60 * m.snow) + 10
            for k in 0..<n {
                let x = rnd(101, k) * r.width, y = f.groundY + rnd(102, k) * f.air
                let rr = (2 + rnd(103, k) * 2.6) * u
                ctx.fillEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
            }
            ctx.fill(CGRect(x: 0, y: f.groundY - 12 * u, width: r.width, height: 15 * u))
        }
        if m.hail > 0 {
            for k in 0..<30 {
                let x = rnd(111, k) * r.width, y = f.groundY - 10 * u + rnd(112, k) * f.air
                let rr = 3 * u
                let rect = CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)
                ctx.setFillColor(c(0.95, 0.98, 1))
                ctx.fillEllipse(in: rect)
                ctx.setStrokeColor(c(0.5, 0.6, 0.78, 0.8))
                ctx.setLineWidth(0.8 * u)
                ctx.strokeEllipse(in: rect)
            }
        }
        if m.wind > 0.6 {
            ctx.setStrokeColor(c(1, 1, 1, 0.75))
            ctx.setLineWidth(2.4 * u)
            ctx.setLineCap(.round)
            for k in 0..<3 {
                let y = f.y(0.3 + CGFloat(k) * 0.2), x = r.width * (0.12 + CGFloat(k % 2) * 0.2)
                let l = r.width * 0.45
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addCurve(to: CGPoint(x: x + l, y: y + 6 * u), control1: CGPoint(x: x + l * 0.4, y: y + 14 * u), control2: CGPoint(x: x + l * 0.7, y: y - 10 * u))
                ctx.addArc(center: CGPoint(x: x + l, y: y + 14 * u), radius: 8 * u, startAngle: -.pi / 2, endAngle: .pi * 0.9, clockwise: false)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}
