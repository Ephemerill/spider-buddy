import AppKit

// MARK: - Prey

/// Something to hunt. Released from the menu, it lives on the desktop until
/// the spider catches and eats it.
enum PreyKind: Int, CaseIterable {
    case cricket, worm, fruitFly

    var label: String {
        switch self {
        case .cricket: return "Cricket"
        case .worm: return "Worm"
        case .fruitFly: return "Fruit Fly"
        }
    }
    var flies: Bool { self == .fruitFly }
    /// How close the spider's mouth has to come, in world px at scale 1.
    var catchRadius: CGFloat {
        switch self {
        case .cricket: return 22
        case .worm: return 24
        case .fruitFly: return 20
        }
    }
    /// How long it takes to eat, in seconds.
    var mealTime: CGFloat {
        switch self {
        case .cricket: return 5.5
        case .worm: return 6.5
        case .fruitFly: return 3.2
        }
    }
    /// How much it fills the spider up.
    var nourishment: CGFloat {
        switch self {
        case .cricket: return 0.55
        case .worm: return 0.6
        case .fruitFly: return 0.3
        }
    }
    /// Height of the creature's belly above the edge it sits on, in units.
    var clearance: CGFloat {
        switch self {
        case .cricket: return 4
        case .worm: return 2.5
        case .fruitFly: return 3
        }
    }
}

final class Prey {
    enum State { case loose, caught, eaten }

    let kind: PreyKind
    let id: Int
    var scale: CGFloat
    var pos: V2
    var vel: V2 = .zero
    /// Angle the sprite's +x maps to; `facing` mirrors it.
    var heading: CGFloat = 0
    var facing: CGFloat = 1
    var phase: CGFloat = 0
    var state: State = .loose
    /// On a surface: which edge, and where along it.
    var anchor: Anchor?
    private var surfaceNormal = V2(0, 1)
    /// How frightened of the spider it is, 0..1.
    var fear: CGFloat = 0
    /// How much of it has been eaten, 0..1 — it shrinks away.
    var eaten: CGFloat = 0
    var alpha: CGFloat = 1
    private var nextMove: CGFloat = 0
    private var restUntil: CGFloat = 0
    private var wanderDir: CGFloat = 1
    private var airFor: CGFloat = 0
    private var perchTarget: (point: V2, anchor: Anchor)?
    private var moveDir: CGFloat = 1
    private var stepBurst: CGFloat = 0
    var age: CGFloat = 0
    private var lastSpider = V2.zero
    private var lastSpiderPos = V2.zero
    private var frozenUntil: CGFloat = 0
    /// On the pointer.
    var held = false
    /// A fly keeps to this area, if set (the spider's box).
    var home: CGRect?

    init(kind: PreyKind, id: Int, at p: V2, scale: CGFloat) {
        self.kind = kind
        self.id = id
        self.pos = p
        self.scale = scale
        nextMove = randRange(0.5, 2)
        wanderDir = chance(0.5) ? 1 : -1
        moveDir = wanderDir
        facing = wanderDir
    }

    var onSurface: Bool { anchor != nil }
    var airborne: Bool { anchor == nil && state == .loose && !held }
    /// Drawn size: the creatures are a good deal bigger than life so they
    /// can be seen.
    var drawScale: CGFloat { scale * 1.7 }

    /// Let go of the pointer: falls (or flies off) from wherever it is.
    func drop() {
        anchor = nil
        airFor = 0
        perchTarget = nil
        if kind.flies { nextMove = randRange(1, 3) }
    }

    /// Where the spider has to get its fangs to.
    var mouthPoint: V2 { pos }

    /// Puts it on the edge nearest its position, if one is close enough.
    @discardableResult
    private func settle(on map: SurfaceMap, reach: CGFloat) -> Bool {
        guard let spot = map.nearestSpot(to: pos, within: reach + map.standoff) else { return false }
        // Ground creatures only ever sit on top of things; a fly perches anywhere.
        guard kind.flies || spot.seg.facing == .up else { return false }
        let edge = spot.point - spot.seg.normal * map.standoff
        guard pos.distance(to: edge) < reach, (edge - pos).dot(vel) >= -40 || vel.length < 40 else { return false }
        anchor = spot.anchor
        anchor?.dir = moveDir
        surfaceNormal = spot.seg.normal
        vel = .zero
        airFor = 0
        placeOnSurface(map)
        return true
    }

    private func placeOnSurface(_ map: SurfaceMap) {
        guard let a = anchor, let loop = map.loop(a.loopID), a.segIdx < loop.segs.count else {
            anchor = nil
            return
        }
        let seg = loop.segs[a.segIdx]
        // The loop's line stands off the edge by the spider's body height;
        // this creature sits its own height above the edge itself.
        let lift = map.standoff - kind.clearance * drawScale
        pos = seg.point(at: a.t) - seg.normal * lift
        surfaceNormal = seg.normal
        heading = seg.angle
    }

    /// Moves `d` along its edge; turns round at the ends or at anything in
    /// the way. Returns false if there was no room.
    @discardableResult
    private func slide(_ d: CGFloat, map: SurfaceMap) -> Bool {
        guard var a = anchor, let loop = map.loop(a.loopID), a.segIdx < loop.segs.count else { return false }
        let seg = loop.segs[a.segIdx]
        let nt = a.t + d
        let margin: CGFloat = 8
        guard nt > margin, nt < seg.len - margin, seg.isOpen(at: nt) else {
            moveDir = -moveDir
            facing = moveDir
            return false
        }
        a.t = nt
        anchor = a
        placeOnSurface(map)
        return true
    }

    func update(dt: CGFloat, t: CGFloat, map: SurfaceMap, spider: V2) {
        age += dt
        phase += dt
        lastSpider = spider
        switch state {
        case .eaten:
            alpha = max(0, alpha - dt * 3)
            return
        case .caught:
            return
        case .loose:
            break
        }
        if held {
            // Dangling from the pointer: wriggling, upright.
            heading = approach(heading, sin(phase * 8) * 0.25, 8, dt)
            fear = min(1, fear + dt * 2)
            return
        }

        // Fear of the spider: something big moving fast nearby is alarming;
        // something creeping up slowly is not noticed until it is very close.
        // That is what makes stalking work.
        let dSpider = spider.distance(to: pos)
        let spiderSpeed = dt > 0 ? (spider - lastSpiderPos).length / dt : 0
        lastSpiderPos = spider
        let near = dSpider < 130 * scale
        let veryNear = dSpider < 45 * scale
        if near && (spiderSpeed > 70 || veryNear) {
            fear = min(1, fear + dt * 3)
        } else if near {
            fear = min(1, fear + dt * 0.25)
        } else {
            fear = max(0, fear - dt * 0.4)
        }

        // Its surface may have gone (a window closed) — then it falls.
        if let a = anchor, map.loop(a.loopID) == nil { anchor = nil; vel = .zero }

        switch kind {
        case .cricket: updateCricket(dt: dt, t: t, map: map, spider: spider)
        case .worm: updateWorm(dt: dt, t: t, map: map)
        case .fruitFly: updateFly(dt: dt, t: t, map: map, spider: spider)
        }

        // Nothing lives off the edge of the world: back onto the floor.
        let world = map.worldBounds
        if !world.insetBy(dx: -40, dy: -40).contains(pos.point) {
            let f = map.screenFrame(containing: pos)
            pos = V2(clamp(pos.x, f.minX + 60, f.maxX - 60), f.minY + 40)
            vel = .zero
            anchor = nil
        }
    }

    // MARK: Ground creatures

    private func fall(dt: CGFloat, map: SurfaceMap) {
        airFor += dt
        vel.y -= 1500 * dt
        vel *= exp(-0.3 * dt)
        pos += vel * dt
        heading = approach(heading, 0, 6, dt)
        // Landing: any edge it comes down onto.
        if airFor > 0.08 { settle(on: map, reach: 10 * scale + 4) }
    }

    private func updateCricket(dt: CGFloat, t: CGFloat, map: SurfaceMap, spider: V2) {
        guard anchor != nil else { fall(dt: dt, map: map); return }
        placeOnSurface(map)
        nextMove -= dt * (1 + fear * 3)
        // A little walk now and then, in short bursts.
        if stepBurst > 0 {
            stepBurst -= dt
            slide(moveDir * 26 * scale * dt, map: map)
        }
        guard nextMove <= 0 else { return }
        nextMove = randRange(0.7, 3.2)
        let away: CGFloat = (pos - spider).dot(V2.angle(heading)) >= 0 ? 1 : -1
        // A frightened cricket as often as not freezes and hopes.
        if fear > 0.3, t < frozenUntil { return }
        if fear > 0.3, chance(0.5) { frozenUntil = t + randRange(1.2, 2.6); nextMove = 0.3; return }
        if fear > 0.3 || chance(0.55) {
            // A hop, away from the spider if it is about.
            moveDir = fear > 0.3 ? away : (chance(0.5) ? 1 : -1)
            facing = moveDir
            let along = V2.angle(heading) * moveDir
            let up = surfaceNormal
            let power = fear > 0.3 ? randRange(1.0, 1.4) : randRange(0.6, 1.0)
            vel = (up * 230 + along * 150) * power * scale.squareRoot()
            anchor = nil
            airFor = 0
        } else {
            stepBurst = randRange(0.3, 0.8)
            moveDir = chance(0.7) ? moveDir : -moveDir
            facing = moveDir
        }
    }

    private func updateWorm(dt: CGFloat, t: CGFloat, map: SurfaceMap) {
        guard anchor != nil else { fall(dt: dt, map: map); return }
        placeOnSurface(map)
        // Inches along: a pulse of movement, then a pause, a little quicker
        // when something big is close.
        let pulse = max(0, sin(phase * 2.2))
        let speed = (9 + fear * 14) * scale
        slide(moveDir * speed * pulse * dt, map: map)
        nextMove -= dt
        if nextMove <= 0 {
            nextMove = randRange(3, 9)
            if chance(0.35) { moveDir = -moveDir; facing = moveDir }
        }
    }

    // MARK: Fruit fly

    private func updateFly(dt: CGFloat, t: CGFloat, map: SurfaceMap, spider: V2) {
        if anchor != nil {
            // Perched: sits, cleaning itself, then takes off — sooner if the
            // spider closes in.
            placeOnSurface(map)
            restUntil -= dt * (1 + fear * 4)
            if restUntil <= 0 {
                vel = surfaceNormal * 120 + V2(randRange(-80, 80), randRange(-20, 40))
                anchor = nil
                perchTarget = nil
                nextMove = randRange(2.5, 7)
            }
            return
        }
        // In the air: a jittery random walk, kept on its screen, with a
        // slow drift toward wherever it is thinking of landing.
        let f = (home ?? map.screenFrame(containing: pos)).insetBy(dx: 40, dy: 40)
        var acc = V2(randRange(-1, 1), randRange(-1, 1)) * 900
        if pos.x < f.minX { acc.x += 600 } else if pos.x > f.maxX { acc.x -= 600 }
        if pos.y < f.minY { acc.y += 700 } else if pos.y > f.maxY { acc.y -= 600 }
        // It likes the lower half of the room, where the food is.
        if pos.y > f.midY { acc.y -= 260 }
        // It does not like the spider much, but it is not clever about it.
        let dS = pos - spider
        if dS.length < 90 * scale { acc += dS.normalized * 500 }
        nextMove -= dt
        if nextMove <= 0, perchTarget == nil {
            // Time to land: pick somewhere near.
            if let spot = map.nearestSpot(to: pos + vel * 0.2 + V2(0, -60), within: 260 * scale),
               spot.point.distance(to: spider) > 60 * scale {
                let edge = spot.point - spot.seg.normal * (map.standoff - kind.clearance * drawScale)
                perchTarget = (edge, spot.anchor)
            } else {
                nextMove = randRange(1, 3)
            }
        }
        if let pt = perchTarget {
            let d = pt.point - pos
            acc += d.normalized * 700
            if d.length < 8 * scale + 3 {
                anchor = pt.anchor
                placeOnSurface(map)
                vel = .zero
                restUntil = randRange(1.5, 4.5)
                perchTarget = nil
                return
            }
        }
        vel += acc * dt
        vel *= exp(-2.2 * dt)
        vel = vel.clampedLength(190 * max(scale, 0.7))
        pos += vel * dt
        if abs(vel.x) > 25 { facing = vel.x >= 0 ? 1 : -1 }
        heading = approach(heading, clamp(vel.y / 400, -0.5, 0.5) * facing, 5, dt)
    }

    /// Bounding box for redraws, in world px.
    var bounds: CGRect {
        let r = 22 * drawScale
        return CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
    }
}

// MARK: - Drawing

enum PreyRenderer {
    /// Draws the creature with its position at the origin of `ctx`, y up.
    static func draw(_ p: Prey, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        let s = p.drawScale * (1 - p.eaten * 0.85)
        ctx.rotate(by: p.heading)
        ctx.scaleBy(x: s * p.facing, y: s)
        ctx.setAlpha(p.alpha)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch p.kind {
        case .cricket: drawCricket(p, in: ctx)
        case .worm: drawWorm(p, in: ctx)
        case .fruitFly: drawFly(p, in: ctx)
        }
        ctx.restoreGState()
    }

    private static let outline = CGColor(red: 0.16, green: 0.12, blue: 0.06, alpha: 1)

    private static func drawCricket(_ p: Prey, in ctx: CGContext) {
        let body = CGColor(red: 0.55, green: 0.47, blue: 0.24, alpha: 1)
        let light = CGColor(red: 0.72, green: 0.64, blue: 0.36, alpha: 1)
        let hop = p.airborne ? 1.0 : 0.0
        let twitch = sin(p.phase * 7) * 0.5
        // Hind legs: folded when sitting, kicked straight back when it hops.
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(2.2)
        for side in [CGFloat(1), -1] {
            let hip = CGPoint(x: -3, y: side > 0 ? -1 : 0)
            let knee = CGPoint(x: -9 - hop * 2, y: (side > 0 ? 6 : 5) - hop * 6)
            let foot = CGPoint(x: -6 + hop * -8, y: -4 - hop * 1)
            ctx.beginPath(); ctx.move(to: hip); ctx.addLine(to: knee); ctx.addLine(to: foot); ctx.strokePath()
        }
        // Small front legs.
        ctx.setLineWidth(1.4)
        for (i, x) in [CGFloat(2), 5].enumerated() {
            let lift = CGFloat(i) * 0.5 + twitch
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: -1)); ctx.addLine(to: CGPoint(x: x + 2, y: -4 + lift)); ctx.strokePath()
        }
        // Body and head.
        ctx.setFillColor(body)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(1.4)
        let bodyRect = CGRect(x: -8, y: -3, width: 14, height: 6)
        ctx.addEllipse(in: bodyRect); ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(light)
        ctx.addEllipse(in: CGRect(x: -6, y: -0.5, width: 8, height: 2.5)); ctx.fillPath()
        ctx.setFillColor(body)
        ctx.addEllipse(in: CGRect(x: 4, y: -2.5, width: 6, height: 6)); ctx.drawPath(using: .fillStroke)
        // Eye and antennae.
        ctx.setFillColor(outline)
        ctx.addEllipse(in: CGRect(x: 7, y: 0.2, width: 1.8, height: 1.8)); ctx.fillPath()
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.9)
        for (i, a) in [CGFloat(0.35), 0.75].enumerated() {
            let wob = sin(p.phase * 5 + CGFloat(i)) * 0.8
            ctx.beginPath(); ctx.move(to: CGPoint(x: 9, y: 2))
            ctx.addQuadCurve(to: CGPoint(x: 9 + cos(a) * 10, y: 2 + sin(a) * 10 + wob),
                             control: CGPoint(x: 12, y: 4 + wob))
            ctx.strokePath()
        }
    }

    private static func drawWorm(_ p: Prey, in ctx: CGContext) {
        let fill = CGColor(red: 0.93, green: 0.62, blue: 0.62, alpha: 1)
        let dark = CGColor(red: 0.70, green: 0.36, blue: 0.40, alpha: 1)
        // Segments along a slow wave, bunching a little as it inches.
        let n = 6
        let pulse = sin(p.phase * 2.2)
        var pts: [CGPoint] = []
        for i in 0..<n {
            let u = CGFloat(i) / CGFloat(n - 1)
            let x = -9 + u * 18 * (1 - 0.12 * pulse)
            let y = sin(u * .pi * 2 + p.phase * 3) * 1.6 - 1
            pts.append(CGPoint(x: x, y: y))
        }
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(5.6)
        ctx.beginPath(); ctx.addLines(between: pts); ctx.strokePath()
        ctx.setStrokeColor(fill)
        ctx.setLineWidth(4.2)
        ctx.beginPath(); ctx.addLines(between: pts); ctx.strokePath()
        // Segment rings.
        ctx.setStrokeColor(dark)
        ctx.setLineWidth(0.8)
        for i in 1..<(n - 1) {
            let c = pts[i]
            ctx.beginPath(); ctx.move(to: CGPoint(x: c.x, y: c.y - 2)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + 2)); ctx.strokePath()
        }
        // A face at the front: two dots.
        ctx.setFillColor(outline)
        let head = pts[n - 1]
        ctx.addEllipse(in: CGRect(x: head.x, y: head.y + 0.3, width: 1.2, height: 1.2)); ctx.fillPath()
    }

    private static func drawFly(_ p: Prey, in ctx: CGContext) {
        let body = CGColor(red: 0.28, green: 0.2, blue: 0.14, alpha: 1)
        let wing = CGColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 0.55)
        let flying = p.airborne
        // Wings: a blur when flying, folded flat when perched.
        let beat = flying ? sin(p.phase * 60) : 0
        ctx.setFillColor(wing)
        for side in [CGFloat(1), -1] {
            ctx.saveGState()
            ctx.translateBy(x: -1, y: 1)
            let ang = flying ? (0.9 + beat * 0.5) * side : 0.25 * side
            ctx.rotate(by: ang)
            ctx.addEllipse(in: CGRect(x: -7, y: -1.2, width: 7.5, height: 2.6))
            ctx.fillPath()
            ctx.restoreGState()
        }
        // Legs, dangling when flying.
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.8)
        for x in [CGFloat(-2), 0, 2] {
            ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: -1))
            ctx.addLine(to: CGPoint(x: x + (flying ? -1.5 : 0.8), y: -3.2)); ctx.strokePath()
        }
        // Body and head, red eye.
        ctx.setFillColor(body)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.9)
        ctx.addEllipse(in: CGRect(x: -4.5, y: -1.8, width: 6.5, height: 3.6)); ctx.drawPath(using: .fillStroke)
        ctx.addEllipse(in: CGRect(x: 1.2, y: -1.4, width: 3.2, height: 3.2)); ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(CGColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1))
        ctx.addEllipse(in: CGRect(x: 2.6, y: -0.2, width: 1.5, height: 1.5)); ctx.fillPath()
    }
}

// MARK: - View

/// Screen-sized, click-through; redraws only the patches the creatures are in.
final class PreyView: NSView {
    var prey: [Prey] = []
    var worldOrigin = CGPoint.zero
    /// The spider owns the creatures; picking one up goes through it.
    weak var spider: Spider?
    private var lastRects: [CGRect] = []
    private var grabbed: Prey?
    private var dragSamples: [(p: V2, t: TimeInterval)] = []
    override var isFlipped: Bool { false }

    private func world(_ event: NSEvent) -> V2 {
        let p = convert(event.locationInWindow, from: nil)
        return V2(p.x + worldOrigin.x, p.y + worldOrigin.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let spider else { return nil }
        if grabbed != nil { return self }
        let w = V2(point.x + worldOrigin.x, point.y + worldOrigin.y)
        return spider.preyHit(w) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let spider else { return }
        let w = world(event)
        guard let p = spider.preyHit(w) else { return }
        grabbed = p
        dragSamples = [(w, event.timestamp)]
        spider.beginPreyGrab(p, at: w)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let spider, let p = grabbed else { return }
        let w = world(event)
        spider.movePreyGrab(p, to: w)
        dragSamples.append((w, event.timestamp))
        if dragSamples.count > 8 { dragSamples.removeFirst(dragSamples.count - 8) }
    }

    override func mouseUp(with event: NSEvent) {
        guard let spider, let p = grabbed else { return }
        let w = world(event)
        var v = V2.zero
        if let recent = dragSamples.last(where: { event.timestamp - $0.t > 0.04 }) {
            v = (w - recent.p) / CGFloat(max(event.timestamp - recent.t, 0.008))
        }
        spider.endPreyGrab(p, throwVelocity: v)
        grabbed = nil
        dragSamples = []
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .spiderContextMenu, object: event)
    }

    /// Marks where they were and where they are now for redraw.
    func refresh() {
        var rects: [CGRect] = []
        for p in prey {
            let b = p.bounds.insetBy(dx: -6, dy: -6)
            rects.append(CGRect(x: b.minX - worldOrigin.x, y: b.minY - worldOrigin.y, width: b.width, height: b.height))
        }
        for r in lastRects + rects { setNeedsDisplay(r) }
        lastRects = rects
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for p in prey {
            let b = p.bounds
            let local = CGRect(x: b.minX - worldOrigin.x, y: b.minY - worldOrigin.y, width: b.width, height: b.height)
            guard local.intersects(dirty) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: p.pos.x - worldOrigin.x, y: p.pos.y - worldOrigin.y)
            // A soft contact shadow under anything sitting on an edge.
            if p.onSurface, p.state == .loose {
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12 * Double(p.alpha)))
                ctx.fillEllipse(in: CGRect(x: -9 * p.drawScale, y: -p.kind.clearance * p.drawScale - 2, width: 18 * p.drawScale, height: 3.5 * p.drawScale))
            }
            PreyRenderer.draw(p, in: ctx)
            ctx.restoreGState()
        }
    }
}
