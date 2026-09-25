import AppKit

// MARK: - Prey

/// Something to hunt. Released from the menu — or, if they are let, finding
/// their own way in now and then — they live on the desktop until the
/// spider catches them, or (the ones that wandered in) they go again.
///
/// Each kind gets about its own way, and is hunted its own way:
/// - a cricket hops, and freezes when frightened; stalk it and pounce.
/// - a worm inches along; easy.
/// - a fruit fly flits about and perches; snatched out of the air.
/// - a moth circles the pointer like a lamp, and rests a long while; dozy.
/// - a beetle plods, and shuts itself up in its shell if rushed — teeth
///   just bounce off it. Creep up, or wait beside it for it to come out.
/// - an ant is quick and tireless, climbs anything, and feels footsteps
///   through what it walks on. Chasing it only sends it off: lie in wait,
///   or get ahead of it.
/// - a mosquito hangs in the air, then darts off; it is only to be caught
///   while it hangs there. It likes to pester the pointer.
/// - a ladybug climbs to the top of things and flies from there. It tastes
///   horrible: tried once, spat out, and after that left alone.
enum PreyKind: Int, CaseIterable {
    case cricket, worm, fruitFly, moth, beetle, ant, mosquito, ladybug

    var label: String {
        switch self {
        case .cricket: return "Cricket"
        case .worm: return "Worm"
        case .fruitFly: return "Fruit Fly"
        case .moth: return "Moth"
        case .beetle: return "Beetle"
        case .ant: return "Ant"
        case .mosquito: return "Mosquito"
        case .ladybug: return "Ladybug"
        }
    }
    /// Lives in the air, perching now and then: snatched rather than stalked.
    var flies: Bool { self == .fruitFly || self == .moth || self == .mosquito }
    /// Walks round corners — up walls and under ledges — not only along tops.
    var climbs: Bool { self == .ant || self == .ladybug }
    /// Walks, but has wings under its wing cases, and flies off now and then.
    var takesOff: Bool { self == .beetle || self == .ladybug }
    /// Can shut itself up in a shell that nothing bites through.
    var armoured: Bool { self == .beetle }
    /// Tastes horrible.
    var bitter: Bool { self == .ladybug }
    /// How close the spider's mouth has to come, in world px at scale 1.
    var catchRadius: CGFloat {
        switch self {
        case .cricket: return 22
        case .worm: return 24
        case .fruitFly: return 20
        case .moth: return 26
        case .beetle: return 22
        case .ant: return 17
        case .mosquito: return 17
        case .ladybug: return 19
        }
    }
    /// How long it takes to eat, in seconds (a ladybug: to taste).
    var mealTime: CGFloat {
        switch self {
        case .cricket: return 5.5
        case .worm: return 6.5
        case .fruitFly: return 3.2
        case .moth: return 5
        case .beetle: return 7.5
        case .ant: return 2.4
        case .mosquito: return 2.2
        case .ladybug: return 1.4
        }
    }
    /// How much it fills the spider up.
    var nourishment: CGFloat {
        switch self {
        case .cricket: return 0.55
        case .worm: return 0.6
        case .fruitFly: return 0.3
        case .moth: return 0.5
        case .beetle: return 0.7
        case .ant: return 0.25
        case .mosquito: return 0.25
        case .ladybug: return 0
        }
    }
    /// Height of the creature's belly above the edge it sits on, in units.
    var clearance: CGFloat {
        switch self {
        case .cricket: return 4
        case .worm: return 2.5
        case .fruitFly: return 3
        case .moth: return 2.5
        case .beetle: return 3
        case .ant: return 2.5
        case .mosquito: return 4.5
        case .ladybug: return 2.5
        }
    }
    /// How readily it takes fright, next to a cricket (beetles and ants go
    /// by their own rules).
    var wariness: CGFloat {
        switch self {
        case .moth: return 0.45
        case .ladybug: return 0.6
        case .mosquito: return 1.5
        default: return 1
        }
    }

    /// Something finding its own way in. What is about depends on the hour
    /// and the weather: moths and mosquitoes at night, ladybugs by day,
    /// worms in the rain.
    static func wanderingIn(night: Bool, raining: Bool) -> PreyKind {
        let odds: [(PreyKind, CGFloat)] = [
            (.fruitFly, 3), (.ant, 2.5), (.beetle, 1.3),
            (.moth, night ? 5 : 0.7), (.mosquito, night ? 2.5 : 1),
            (.ladybug, night ? 0.2 : 1.8), (.cricket, night ? 2 : 0.8),
            (.worm, raining ? 5 : 0.3),
        ]
        var r = randRange(0, odds.reduce(0) { $0 + $1.1 })
        for (k, w) in odds {
            r -= w
            if r <= 0 { return k }
        }
        return .fruitFly
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
    private(set) var surfaceNormal = V2(0, 1)
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

    /// Found its own way in, rather than being let loose from the menu.
    var wild = false
    /// Whether the spider has spotted it yet. What you let loose it sees at
    /// once; something that wanders in has to catch its eye first.
    var noticed = true
    /// Tried and spat out: the spider leaves it be.
    private(set) var spurned = false
    /// The age at which it means to be off. Never, for what you let loose.
    var leaveAge: CGFloat = .infinity
    /// On its way out: off the screen if it has wings, otherwise away into
    /// a crack, fading as it goes.
    private(set) var leaving = false
    /// Gone for good: to be cleared away.
    private(set) var gone = false
    /// Moved this frame.
    private(set) var astir = false
    /// Which way it is going over the world while it walks.
    private(set) var travel = V2(1, 0)
    /// Shut up in its shell (a beetle).
    private(set) var tucked = false
    /// Its age when a bite last bounced off its shell.
    private(set) var lastKnockAge: CGFloat = -99
    /// On the wing under its own power: a beetle or ladybug, flying off
    /// somewhere else.
    private(set) var flying = false
    private var tuckFor: CGFloat = 0
    private var alarmFor: CGFloat = 0
    private var knocks = 0
    private var pauseFor: CGFloat = 0
    private var fleeing = false
    private var flightFor: CGFloat = 0
    private var exitSide: CGFloat = 0
    private var dartTo: V2?
    private var hoverAt: V2
    private var hoverFor: CGFloat = 0
    private var orbit: CGFloat = 0
    private var orbitDir: CGFloat = 1
    private var lampFor: CGFloat = 0
    private var onTopFor: CGFloat = 0
    /// What is left of the jump in place from rounding a corner, eased away.
    private var cornerSlide = V2.zero
    private var lastDt: CGFloat = 1.0 / 60

    init(kind: PreyKind, id: Int, at p: V2, scale: CGFloat) {
        self.kind = kind
        self.id = id
        self.pos = p
        self.scale = scale
        hoverAt = p
        nextMove = randRange(0.5, 2)
        wanderDir = chance(0.5) ? 1 : -1
        moveDir = wanderDir
        facing = wanderDir
        orbitDir = chance(0.5) ? 1 : -1
        orbit = randRange(0, 2 * .pi)
        hoverFor = randRange(0.3, 1)
        if kind == .moth { restUntil = randRange(6, 16) }
    }

    var onSurface: Bool { anchor != nil }
    var airborne: Bool { anchor == nil && state == .loose && !held }
    /// In the air on purpose, to be snatched rather than stalked.
    var aloft: Bool { airborne && (kind.flies || flying) }
    /// A mosquito hanging still in the air — the moment to strike.
    var hovering: Bool { aloft && kind == .mosquito && dartTo == nil }
    /// Sitting on something the right way up: it casts a shadow.
    var castsShadow: Bool { onSurface && state == .loose && surfaceNormal.y > 0.5 }
    /// Drawn size: the creatures are a good deal bigger than life so they
    /// can be seen.
    var drawScale: CGFloat { scale * 1.7 }

    /// Let go of the pointer: falls (or flies off) from wherever it is.
    func drop() {
        anchor = nil
        airFor = 0
        perchTarget = nil
        flying = false
        tucked = false
        dartTo = nil
        hoverAt = pos
        cornerSlide = .zero
        if kind.flies { nextMove = randRange(1, 3) }
    }

    /// Everything it is heading for moves along with it.
    func shift(by d: V2) {
        pos += d
        hoverAt += d
        if let g = dartTo { dartTo = g + d }
        if let pt = perchTarget { perchTarget = (pt.point + d, pt.anchor) }
    }

    /// Comes out onto an edge from a crack in it, fading in.
    func emerge(on a: Anchor, dir: CGFloat, map: SurfaceMap) {
        anchor = a
        moveDir = dir
        facing = dir
        alpha = 0
        placeOnSurface(map)
    }

    /// Spat out: none the worse for it, and off it goes.
    func spatOut(map: SurfaceMap, awayFrom spider: V2) {
        state = .loose
        eaten = 0
        spurned = true
        noticed = true
        fear = 1
        drop()
        vel = V2((pos.x - spider.x >= 0 ? 1 : -1) * 90, 140)
        leaveAge = min(leaveAge, age + randRange(25, 50))
        if kind.takesOff { takeOff(map: map, awayFrom: spider) }
    }

    /// A bite bounced off its shell: it clamps up tighter, and has had
    /// about enough of this place.
    func knock() {
        knocks += 1
        lastKnockAge = age
        fear = 1
        tuck(for: randRange(3, 5))
    }

    /// Where the spider has to get its fangs to.
    var mouthPoint: V2 { pos }

    /// Puts it on the edge nearest its position, if one is close enough.
    @discardableResult
    private func settle(on map: SurfaceMap, reach: CGFloat) -> Bool {
        guard let spot = map.nearestSpot(to: pos, within: reach + map.standoff) else { return false }
        // Ground creatures only ever sit on top of things; a fly perches
        // anywhere, and a climber anywhere it can cling on the right way up.
        guard kind.flies || spot.seg.facing == .up || (kind.climbs && spot.seg.facing != .down) else { return false }
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
        pos = seg.point(at: a.t) - seg.normal * lift + cornerSlide
        surfaceNormal = seg.normal
        // A climber tips over a corner rather than snapping round it.
        heading = kind.climbs ? heading + angleDelta(heading, seg.angle) * min(1, lastDt * 12) : seg.angle
        travel = seg.dir * moveDir
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

    /// Like `slide`, but at the end of an edge it carries on round the
    /// corner onto the next — up the side of a window, underneath it.
    @discardableResult
    private func crawl(_ d: CGFloat, map: SurfaceMap) -> Bool {
        guard var a = anchor, let loop = map.loop(a.loopID), a.segIdx < loop.segs.count else { return false }
        let seg = loop.segs[a.segIdx]
        let nt = a.t + d
        func turnRound() -> Bool {
            moveDir = -moveDir
            facing = moveDir
            return false
        }
        if nt >= 0, nt <= seg.len {
            guard seg.isOpen(at: nt) else { return turnRound() }
            a.t = nt
            anchor = a
            placeOnSurface(map)
            return true
        }
        let forward = nt > seg.len
        var ni = a.segIdx + (forward ? 1 : -1)
        if loop.closed { ni = (ni + loop.segs.count) % loop.segs.count }
        guard loop.segs.indices.contains(ni), ni != a.segIdx else { return turnRound() }
        let next = loop.segs[ni]
        let joined = forward ? next.a.distance(to: seg.b) < 2 : next.b.distance(to: seg.a) < 2
        let over = forward ? nt - seg.len : -nt
        let t2 = forward ? over : next.len - over
        guard joined, next.len > 16, next.isOpen(at: t2) else { return turnRound() }
        let before = pos
        a.segIdx = ni
        a.t = t2
        anchor = a
        placeOnSurface(map)
        cornerSlide += before - pos
        pos = before
        return true
    }

    private func edgePoint(_ spot: (anchor: Anchor, point: V2, seg: Seg), map: SurfaceMap) -> V2 {
        spot.point - spot.seg.normal * (map.standoff - kind.clearance * drawScale)
    }

    func update(dt: CGFloat, t: CGFloat, map: SurfaceMap, spider: V2, spiderLoop: String? = nil, cursor: V2? = nil) {
        age += dt
        phase += dt
        lastDt = dt
        lastSpider = spider
        astir = false
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
            astir = true
            return
        }
        let before = pos

        // Fear of the spider: something big moving fast nearby is alarming;
        // something creeping up slowly is not noticed until it is very close.
        // That is what makes stalking work.
        let dSpider = spider.distance(to: pos)
        let spiderSpeed = dt > 0 ? (spider - lastSpiderPos).length / dt : 0
        lastSpiderPos = spider
        let near = dSpider < 130 * scale
        let veryNear = dSpider < 45 * scale
        switch kind {
        case .beetle:
            // It never runs. Something big coming at it for a moment makes
            // it shut up shop; only once all has been still a while does it
            // come out again. (A pounce is over before it can react.)
            if near && spiderSpeed > 35 * scale {
                alarmFor += dt
                fear = min(1, fear + dt * 2)
            } else {
                alarmFor = max(0, alarmFor - dt * 2)
                if !near || spiderSpeed < 20 * scale { fear = max(0, fear - dt * 0.3) }
            }
        case .ant:
            // It feels the spider through what it walks on, and hardly sees
            // it at all: anything big walking on its window gives it away,
            // but one keeping still it walks right up to.
            let shaking = spiderLoop != nil && spiderLoop == anchor?.loopID && spiderSpeed > 40 * scale && dSpider < 280 * scale
            if shaking || (near && spiderSpeed > 70) {
                fear = min(1, fear + dt * 2.5)
            } else {
                fear = max(0, fear - dt * 0.5)
            }
        default:
            let w = kind.wariness
            if near && (spiderSpeed > 70 || veryNear) {
                fear = min(1, fear + dt * 3 * w)
            } else if near {
                fear = min(1, fear + dt * 0.25 * w)
            } else {
                fear = max(0, fear - dt * 0.4)
            }
        }

        // Its surface may have gone (a window closed) — then it falls.
        if let a = anchor, map.loop(a.loopID) == nil { anchor = nil; vel = .zero; flying = false }
        cornerSlide = approach(cornerSlide, .zero, 10, dt)

        // Coming, and going.
        if !leaving, age > leaveAge, alpha >= 1 {
            leaving = true
            exitSide = pos.x < map.screenFrame(containing: pos).midX ? -1 : 1
        }
        if !leaving, alpha < 1 { alpha = min(1, alpha + dt / 1.2) }
        if leaving, home == nil, kind.flies || kind.takesOff {
            flyAway(dt: dt, map: map)
            astir = true
            return
        }

        switch kind {
        case .cricket: updateCricket(dt: dt, t: t, map: map, spider: spider)
        case .worm: updateWorm(dt: dt, t: t, map: map)
        case .fruitFly: updateFly(dt: dt, t: t, map: map, spider: spider)
        case .moth: updateMoth(dt: dt, map: map, spider: spider, cursor: cursor)
        case .beetle: updateBeetle(dt: dt, map: map, spider: spider)
        case .ant: updateAnt(dt: dt, map: map, spider: spider)
        case .mosquito: updateMosquito(dt: dt, map: map, spider: spider, cursor: cursor)
        case .ladybug: updateLadybug(dt: dt, map: map, spider: spider)
        }

        // Slipping away into a crack.
        if leaving {
            alpha = max(0, alpha - dt / 2.5)
            if alpha <= 0 { gone = true }
        }

        // Nothing lives off the edge of the world: back onto the floor.
        let world = map.worldBounds
        if !world.insetBy(dx: -40, dy: -40).contains(pos.point) {
            let f = map.screenFrame(containing: pos)
            pos = V2(clamp(pos.x, f.minX + 60, f.maxX - 60), f.minY + 40)
            vel = .zero
            anchor = nil
            flying = false
            dartTo = nil
            hoverAt = pos
        }
        astir = pos.distance(to: before) > 0.05 || airborne
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

    /// Which way along its edge is away from the spider.
    private func away(from spider: V2, map: SurfaceMap) -> CGFloat {
        guard let a = anchor, let seg = map.seg(a) else { return moveDir }
        return (pos - spider).dot(seg.dir) >= 0 ? 1 : -1
    }

    // MARK: Beetle

    private func tuck(for secs: CGFloat) {
        tucked = true
        tuckFor = max(tuckFor, secs)
        pauseFor = 0
    }

    private func updateBeetle(dt: CGFloat, map: SurfaceMap, spider: V2) {
        if flying { flyToPerch(dt: dt, map: map, speed: 95, bob: 260); return }
        guard anchor != nil else { tucked = false; fall(dt: dt, map: map); return }
        placeOnSurface(map)
        if tucked {
            tuckFor -= dt
            guard tuckFor <= 0, fear < 0.25 else { return }
            tucked = false
            // Knocked about enough: off somewhere quieter.
            if knocks >= 2 || (knocks == 1 && chance(0.45)) {
                knocks = 0
                takeOff(map: map, awayFrom: spider)
            } else {
                pauseFor = randRange(0.4, 1.2)
            }
            return
        }
        if alarmFor > 0.5 { tuck(for: randRange(2.5, 4.5)); return }
        // Plods along, stopping now and then to think about it.
        if pauseFor > 0 {
            pauseFor -= dt
        } else {
            slide(moveDir * 13 * scale * dt, map: map)
        }
        nextMove -= dt
        if nextMove <= 0 {
            nextMove = randRange(2.5, 7)
            if chance(0.4) { pauseFor = randRange(0.8, 2.5) }
            if chance(0.25) { moveDir = -moveDir; facing = moveDir }
        }
    }

    // MARK: Ant

    private func updateAnt(dt: CGFloat, map: SurfaceMap, spider: V2) {
        guard anchor != nil else { fall(dt: dt, map: map); return }
        placeOnSurface(map)
        // Alarmed: straight round and off the other way, double quick.
        if fear > 0.5, !fleeing {
            fleeing = true
            pauseFor = 0
            let away = away(from: spider, map: map)
            if away != moveDir { moveDir = away; facing = away }
        } else if fear < 0.2 {
            fleeing = false
        }
        if pauseFor > 0 {
            // A moment feeling about with its antennae.
            pauseFor -= dt
            return
        }
        crawl(moveDir * (fleeing ? 100 : 54) * scale * dt, map: map)
        nextMove -= dt
        if nextMove <= 0 {
            nextMove = randRange(1.5, 5)
            guard !fleeing else { return }
            if chance(0.45) { pauseFor = randRange(0.25, 0.8) }
            if chance(0.12) { moveDir = -moveDir; facing = moveDir }
        }
    }

    // MARK: Ladybug

    private func updateLadybug(dt: CGFloat, map: SurfaceMap, spider: V2) {
        if flying { flyToPerch(dt: dt, map: map, speed: 150, bob: 180); return }
        guard anchor != nil, let seg = anchor.flatMap({ map.seg($0) }) else { fall(dt: dt, map: map); return }
        placeOnSurface(map)
        // Always upwards: up any wall it comes to, and from the top of
        // things, it opens its shell and flies.
        let wall = abs(seg.dir.y) > 0.5
        onTopFor = seg.facing == .up ? onTopFor + dt : 0
        if wall {
            let up: CGFloat = seg.dir.y > 0 ? 1 : -1
            if moveDir != up { moveDir = up; facing = up }
        }
        if pauseFor > 0 {
            pauseFor -= dt * (1 + fear * 3)
            return
        }
        if !crawl(moveDir * 19 * scale * (1 + fear) * dt, map: map), wall {
            // The top of the wall, and nowhere further up: off it goes.
            takeOff(map: map, awayFrom: spider)
            return
        }
        nextMove -= dt * (1 + fear * 2)
        guard nextMove <= 0 else { return }
        nextMove = randRange(2, 5)
        if seg.facing == .up, (fear > 0.8 && chance(0.4)) || chance(onTopFor > 10 ? 0.4 : 0.06) {
            takeOff(map: map, awayFrom: spider)
        } else if chance(0.35) {
            pauseFor = randRange(0.6, 2)
        } else if seg.facing == .up, chance(0.25) {
            moveDir = -moveDir
            facing = moveDir
        }
    }

    // MARK: On the wing (beetles and ladybugs)

    /// Opens its wing cases and flies off to a ledge somewhere else, away
    /// from the spider.
    private func takeOff(map: SurfaceMap, awayFrom spider: V2) {
        let f = home ?? map.screenFrame(containing: pos)
        var best: (score: CGFloat, point: V2, anchor: Anchor)?
        for spot in map.sampleSpots(spacing: 60) where spot.seg.facing == .up && f.contains(spot.point.point) {
            let d = spot.point.distance(to: pos)
            guard d > 140, d < (kind == .beetle ? 650 : 450), spot.seg.isOpen(at: spot.anchor.t) else { continue }
            let score = spot.point.distance(to: spider) * randRange(0.6, 1.4)
            if best == nil || score > best!.score {
                best = (score, edgePoint((spot.anchor, spot.point, spot.seg), map: map), spot.anchor)
            }
        }
        guard let b = best else { return }
        perchTarget = (b.point, b.anchor)
        flying = true
        tucked = false
        flightFor = 0
        anchor = nil
        vel = surfaceNormal * 90
    }

    private func flyToPerch(dt: CGFloat, map: SurfaceMap, speed: CGFloat, bob: CGFloat) {
        flightFor += dt
        guard let pt = perchTarget, flightFor < 8 else {
            // Lost its way: it drops, and lands wherever it lands.
            flying = false
            perchTarget = nil
            airFor = 0
            return
        }
        let d = pt.point - pos
        let acc = d.normalized * 650 + V2(0, sin(phase * 9) * bob)
        vel += acc * dt
        vel *= exp(-2 * dt)
        vel = vel.clampedLength(speed * max(scale, 0.7).squareRoot())
        pos += vel * dt
        if abs(vel.x) > 20 { facing = vel.x >= 0 ? 1 : -1 }
        heading = approach(heading, clamp(vel.y / 300, -0.4, 0.4) * facing, 5, dt)
        if d.length < 8 * scale + 4 {
            flying = false
            perchTarget = nil
            vel = .zero
            anchor = pt.anchor
            moveDir = facing
            placeOnSurface(map)
            nextMove = randRange(1.5, 4)
        }
    }

    /// Off the side of the screen and away.
    private func flyAway(dt: CGFloat, map: SurfaceMap) {
        if anchor != nil {
            anchor = nil
            vel = surfaceNormal * 90
        }
        flying = !kind.flies
        tucked = false
        perchTarget = nil
        dartTo = nil
        let f = map.screenFrame(containing: pos)
        let goal = V2(exitSide < 0 ? f.minX - 150 : f.maxX + 150, min(pos.y + 160, f.maxY + 40))
        let acc = (goal - pos).normalized * 520 + V2(randRange(-1, 1), randRange(-1, 1)) * 320
        vel += acc * dt
        vel *= exp(-1.6 * dt)
        vel = vel.clampedLength(kind == .mosquito ? 280 : 170)
        pos += vel * dt
        if abs(vel.x) > 20 { facing = vel.x >= 0 ? 1 : -1 }
        heading = approach(heading, clamp(vel.y / 400, -0.5, 0.5) * facing, 5, dt)
        if !map.worldBounds.insetBy(dx: -30, dy: -30).contains(pos.point) { gone = true }
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

    // MARK: Moth

    private func updateMoth(dt: CGFloat, map: SurfaceMap, spider: V2, cursor: V2?) {
        let f = (home ?? map.screenFrame(containing: pos)).insetBy(dx: 40, dy: 40)
        // The pointer is its lamp — if it is on this screen and not far.
        let lamp = cursor.flatMap { c in f.insetBy(dx: -30, dy: -30).contains(c.point) && c.distance(to: pos) < 420 * scale ? c : nil }
        if anchor != nil {
            // Resting, wings folded back, for a good long while: the lamp
            // coming near stirs it, and so, belatedly, does the spider.
            placeOnSurface(map)
            var stir = 1 + fear * 4
            if let l = lamp, l.distance(to: pos) < 200 * scale { stir += 2 }
            restUntil -= dt * stir
            if restUntil <= 0 || fear > 0.7 {
                vel = surfaceNormal * 90 + V2(randRange(-60, 60), randRange(0, 40))
                anchor = nil
                perchTarget = nil
                nextMove = randRange(5, 12)
                lampFor = 0
            }
            return
        }
        // A floppy, looping flutter.
        var acc = V2(randRange(-1, 1), randRange(-1, 1)) * 500 + V2(cos(phase * 3.1), sin(phase * 4.7)) * 320
        if pos.x < f.minX { acc.x += 600 } else if pos.x > f.maxX { acc.x -= 600 }
        if pos.y < f.minY { acc.y += 700 } else if pos.y > f.maxY { acc.y -= 600 }
        let dS = pos - spider
        if fear > 0.3, dS.length < 80 * scale { acc += dS.normalized * 400 }
        if let l = lamp, lampFor < 30, perchTarget == nil {
            // Round and round the lamp, bumping in close, until it tires.
            lampFor += dt
            orbit += dt * 2.6 * orbitDir
            let r = (34 + 20 * sin(phase * 0.8)) * scale
            let goal = l + V2.angle(orbit) * r
            acc += (goal - pos).clampedLength(140) * 8
            nextMove = max(nextMove, 0.5)
        } else if lamp == nil {
            lampFor = max(0, lampFor - dt)
        }
        nextMove -= dt
        if nextMove <= 0, perchTarget == nil {
            // Somewhere to rest: a wall as soon as a ledge, never underneath.
            if let spot = map.nearestSpot(to: pos + vel * 0.3, within: 300 * scale),
               spot.seg.facing != .down, spot.point.distance(to: spider) > 80 * scale {
                perchTarget = (edgePoint((spot.anchor, spot.point, spot.seg), map: map), spot.anchor)
            } else {
                nextMove = randRange(1, 3)
            }
        }
        if let pt = perchTarget {
            let d = pt.point - pos
            acc += d.normalized * 650
            if d.length < 8 * scale + 3 {
                anchor = pt.anchor
                placeOnSurface(map)
                vel = .zero
                restUntil = randRange(8, 20)
                perchTarget = nil
                return
            }
        }
        vel += acc * dt
        vel *= exp(-2.6 * dt)
        vel = vel.clampedLength(135 * max(scale, 0.7))
        pos += vel * dt
        if abs(vel.x) > 30 { facing = vel.x >= 0 ? 1 : -1 }
        heading = approach(heading, clamp(vel.y / 350, -0.5, 0.5) * facing, 4, dt)
    }

    // MARK: Mosquito

    private func updateMosquito(dt: CGFloat, map: SurfaceMap, spider: V2, cursor: V2?) {
        let f = (home ?? map.screenFrame(containing: pos)).insetBy(dx: 50, dy: 50)
        if anchor != nil {
            // Resting on a wall a moment; anything coming makes it bolt.
            placeOnSurface(map)
            restUntil -= dt * (1 + fear * 6)
            if restUntil <= 0 {
                anchor = nil
                hoverAt = pos
                startDart(frame: f, map: map, spider: spider, cursor: cursor, fleeing: fear > 0.4)
            }
            return
        }
        if let goal = dartTo {
            // A dart: fast, and dead straight.
            let d = goal - pos
            let sp = 340 * max(scale, 0.7).squareRoot()
            if d.length <= sp * dt + 1 {
                pos = goal
                dartTo = nil
                hoverAt = goal
                vel = .zero
                hoverFor = randRange(0.7, 2.4)
                if let pt = perchTarget, pt.point.distance(to: goal) < 2 {
                    anchor = pt.anchor
                    perchTarget = nil
                    placeOnSurface(map)
                    restUntil = randRange(2, 5)
                }
            } else {
                vel = d.normalized * sp
                pos += vel * dt
            }
        } else {
            // Hanging in the air with a wobble. Something big coming at it
            // makes it dart off — though not always in time.
            hoverFor -= dt
            vel = .zero
            pos = hoverAt + V2(sin(phase * 11) * 1.5, sin(phase * 7.3) * 2.2)
            let bolt = fear > 0.5 && chance(dt * 2.2)
            if hoverFor <= 0 || bolt {
                startDart(frame: f, map: map, spider: spider, cursor: cursor, fleeing: bolt)
            }
        }
        if abs(vel.x) > 30 { facing = vel.x >= 0 ? 1 : -1 }
        heading = approach(heading, clamp(vel.y / 500, -0.4, 0.4) * facing, 8, dt)
    }

    private func startDart(frame f: CGRect, map: SurfaceMap, spider: V2, cursor: V2?, fleeing: Bool) {
        perchTarget = nil
        var goal: V2
        if fleeing {
            goal = pos + (pos - spider).normalized.rotated(by: randRange(-0.7, 0.7)) * randRange(150, 260) * scale
        } else if let c = cursor, f.contains(c.point), c.distance(to: pos) < 600 * scale, chance(0.7) {
            // After you: it hangs about the pointer.
            goal = c + V2.angle(randRange(0, 2 * .pi)) * randRange(35, 80) * scale
        } else if chance(0.2), let spot = map.nearestSpot(to: pos, within: 260 * scale),
                  spot.seg.facing == .left || spot.seg.facing == .right,
                  spot.point.distance(to: spider) > 120 * scale {
            let edge = edgePoint((spot.anchor, spot.point, spot.seg), map: map)
            perchTarget = (edge, spot.anchor)
            dartTo = edge
            return
        } else {
            goal = pos + V2.angle(randRange(0, 2 * .pi)) * randRange(70, 200) * scale
        }
        goal = V2(clamp(goal.x, f.minX, f.maxX), clamp(goal.y, f.minY, f.maxY))
        dartTo = goal
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
        case .moth: drawMoth(p, in: ctx)
        case .beetle: drawBeetle(p, in: ctx)
        case .ant: drawAnt(p, in: ctx)
        case .mosquito: drawMosquito(p, in: ctx)
        case .ladybug: drawLadybug(p, in: ctx)
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

    private static func line(_ ctx: CGContext, _ pts: [CGPoint]) {
        ctx.beginPath()
        ctx.addLines(between: pts)
        ctx.strokePath()
    }

    private static func polygon(_ ctx: CGContext, _ pts: [(CGFloat, CGFloat)]) {
        ctx.beginPath()
        ctx.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
        ctx.closePath()
    }

    /// Six legs seen side on (the near three), stepping while it walks and
    /// tucked up tight in `tuck`.
    private static func legs(_ p: Prey, in ctx: CGContext, hips: [CGFloat], reach: CGFloat, down: CGFloat,
                             rate: CGFloat, width: CGFloat, color: CGColor = outline, tuck: Bool = false) {
        let walking = p.astir && p.onSurface
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        for (i, x) in hips.enumerated() {
            let swing = walking ? sin(p.phase * rate + CGFloat(i) * 2.1) * reach * 0.45 : 0
            let lift = walking ? max(0, cos(p.phase * rate + CGFloat(i) * 2.1)) * 0.8 : 0
            let splay = (CGFloat(i) - CGFloat(hips.count - 1) / 2) * reach * 0.5
            if tuck {
                line(ctx, [CGPoint(x: x, y: -0.5), CGPoint(x: x + 0.6, y: -down * 0.35)])
            } else if p.airborne {
                line(ctx, [CGPoint(x: x, y: -0.5), CGPoint(x: x - reach * 0.3, y: -down * 0.7), CGPoint(x: x - reach * 0.7, y: -down)])
            } else {
                let foot = CGPoint(x: x + splay + swing, y: -down + lift)
                line(ctx, [CGPoint(x: x, y: -0.5), CGPoint(x: (x + foot.x) / 2 + 0.6, y: -down * 0.3 + 0.8), foot])
            }
        }
    }

    private static func drawMoth(_ p: Prey, in ctx: CGContext) {
        let body = CGColor(red: 0.58, green: 0.51, blue: 0.42, alpha: 1)
        let wing = CGColor(red: 0.76, green: 0.69, blue: 0.58, alpha: 1)
        let band = CGColor(red: 0.50, green: 0.43, blue: 0.34, alpha: 1)
        let flying = p.airborne
        legs(p, in: ctx, hips: [-2, 0.5, 3], reach: 3, down: 2.5, rate: 8, width: 0.8)
        func wingShape() {
            polygon(ctx, [(2, 0), (1.5, 7), (-4, 11.5), (-9, 9), (-6, 2)])
        }
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.8)
        if flying {
            // Big soft wings, beating slow and floppy: the far pair behind
            // the body, a beat behind the near.
            for (i, shade) in [(0, CGFloat(0.72)), (1, 1)] {
                let beat = sin(p.phase * 15 - CGFloat(i) * 0.5)
                ctx.saveGState()
                ctx.translateBy(x: 0, y: 1.2)
                ctx.scaleBy(x: 1, y: 0.2 + 0.8 * beat)
                ctx.setAlpha(p.alpha * shade)
                ctx.setFillColor(wing)
                wingShape(); ctx.drawPath(using: .fillStroke)
                ctx.setFillColor(band)
                polygon(ctx, [(0.5, 3), (-3, 7), (-5, 5.5), (-2, 2)]); ctx.fillPath()
                ctx.restoreGState()
                if i == 0 { drawMothBody(p, in: ctx, body: body) }
            }
        } else {
            drawMothBody(p, in: ctx, body: body)
            // At rest: wings folded back over it like a little roof.
            ctx.setFillColor(wing)
            polygon(ctx, [(3, 1.8), (-11.5, -1.2), (-10, 3.8), (-1, 4.6)]); ctx.drawPath(using: .fillStroke)
            ctx.setStrokeColor(band)
            ctx.setLineWidth(1)
            line(ctx, [CGPoint(x: -2, y: 3.6), CGPoint(x: -6, y: 1)])
            line(ctx, [CGPoint(x: -6.5, y: 3.3), CGPoint(x: -9.5, y: 0.6)])
        }
    }

    private static func drawMothBody(_ p: Prey, in ctx: CGContext, body: CGColor) {
        ctx.setFillColor(body)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.8)
        ctx.addEllipse(in: CGRect(x: -7, y: -1.8, width: 11.5, height: 4.4)); ctx.drawPath(using: .fillStroke)
        ctx.addEllipse(in: CGRect(x: 3.4, y: -1.2, width: 3.8, height: 3.8)); ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(outline)
        ctx.addEllipse(in: CGRect(x: 5.4, y: 0.2, width: 1.5, height: 1.5)); ctx.fillPath()
        // Feathery antennae.
        ctx.setLineWidth(0.7)
        let wob = sin(p.phase * 3) * 0.5
        for k in [CGFloat(0), 1] {
            let tip = CGPoint(x: 10.5 - k * 1.5, y: 6.5 + k * 0.8 + wob)
            line(ctx, [CGPoint(x: 6, y: 2.2), tip])
            for u in [CGFloat(0.4), 0.6, 0.8] {
                let b = CGPoint(x: 6 + (tip.x - 6) * u, y: 2.2 + (tip.y - 2.2) * u)
                line(ctx, [b, CGPoint(x: b.x + 1.1, y: b.y - 0.6)])
            }
        }
    }

    private static func drawBeetle(_ p: Prey, in ctx: CGContext) {
        let shell = CGColor(red: 0.13, green: 0.27, blue: 0.22, alpha: 1)
        let sheen = CGColor(red: 0.42, green: 0.66, blue: 0.55, alpha: 0.9)
        let dark = CGColor(red: 0.07, green: 0.08, blue: 0.07, alpha: 1)
        let flying = p.flying && p.airborne
        // Tucked: sunk down tight to the edge, head in.
        if p.tucked { ctx.translateBy(x: 0, y: -1.2) }
        legs(p, in: ctx, hips: [-3.5, 0, 3.5], reach: 4, down: 3, rate: 9, width: 1.2, color: dark, tuck: p.tucked)
        ctx.setFillColor(dark)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.9)
        ctx.addEllipse(in: CGRect(x: p.tucked ? 3.6 : 4.8, y: -1.4, width: 4, height: 3.6)); ctx.drawPath(using: .fillStroke)
        if !p.tucked {
            ctx.setLineWidth(0.8)
            let wob = sin(p.phase * 4) * 0.6
            line(ctx, [CGPoint(x: 8, y: 1.2), CGPoint(x: 10.5, y: 3.2 + wob), CGPoint(x: 12, y: 3 + wob)])
        }
        if flying {
            // Wing cases up and out of the way, the wings a buzz beneath.
            ctx.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 0.5))
            ctx.saveGState()
            ctx.translateBy(x: -1, y: 2)
            ctx.rotate(by: 0.6 + sin(p.phase * 50) * 0.5)
            ctx.addEllipse(in: CGRect(x: -10, y: -1.5, width: 10, height: 3)); ctx.fillPath()
            ctx.restoreGState()
            ctx.setFillColor(dark)
            ctx.addEllipse(in: CGRect(x: -7, y: -1.5, width: 12, height: 4.5)); ctx.drawPath(using: .fillStroke)
            ctx.setFillColor(shell)
            ctx.saveGState()
            ctx.translateBy(x: 2, y: 2.5)
            ctx.rotate(by: 1.0)
            ctx.addEllipse(in: CGRect(x: -9, y: -1.8, width: 10, height: 3.6)); ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
            return
        }
        // The shell: a glossy dome.
        ctx.setFillColor(shell)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -8, y: -1.2))
        ctx.addQuadCurve(to: CGPoint(x: 5.5, y: -1.2), control: CGPoint(x: -1.5, y: 11))
        ctx.closePath()
        ctx.drawPath(using: .fillStroke)
        ctx.setStrokeColor(sheen)
        ctx.setLineWidth(1.1)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -4.5, y: 2.6))
        ctx.addQuadCurve(to: CGPoint(x: 1.5, y: 3.8), control: CGPoint(x: -1.5, y: 5))
        ctx.strokePath()
    }

    private static func drawAnt(_ p: Prey, in ctx: CGContext) {
        let body = CGColor(red: 0.26, green: 0.12, blue: 0.08, alpha: 1)
        ctx.scaleBy(x: 0.9, y: 0.9)
        legs(p, in: ctx, hips: [-1.2, 0, 1.2], reach: 4.5, down: 2.8, rate: 22, width: 0.8)
        ctx.setFillColor(body)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.7)
        ctx.addEllipse(in: CGRect(x: -9.5, y: -1.2, width: 6.5, height: 4.6)); ctx.drawPath(using: .fillStroke)
        ctx.addEllipse(in: CGRect(x: -3.4, y: -0.2, width: 1.9, height: 1.9)); ctx.drawPath(using: .fillStroke)
        ctx.addEllipse(in: CGRect(x: -1.8, y: -0.6, width: 5, height: 2.8)); ctx.drawPath(using: .fillStroke)
        ctx.addEllipse(in: CGRect(x: 3, y: -0.3, width: 3.8, height: 3.4)); ctx.drawPath(using: .fillStroke)
        // Elbowed antennae, forever feeling about.
        ctx.setLineWidth(0.6)
        for k in [CGFloat(0), 1] {
            let wob = sin(p.phase * (p.astir ? 9 : 5) + k * 1.7) * 1.1
            line(ctx, [CGPoint(x: 5.8, y: 2.6), CGPoint(x: 6.4 + k * 0.6, y: 5.6), CGPoint(x: 9.2 + k * 0.5, y: 6.4 + wob)])
        }
    }

    private static func drawMosquito(_ p: Prey, in ctx: CGContext) {
        let body = CGColor(red: 0.30, green: 0.27, blue: 0.24, alpha: 1)
        let pale = CGColor(red: 0.78, green: 0.74, blue: 0.68, alpha: 1)
        let flying = p.airborne
        // Long thin legs: splayed on a wall, trailing in the air.
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.55)
        for (i, x) in [CGFloat(-1), 0, 1].enumerated() {
            let fi = CGFloat(i) - 1
            if flying {
                let sway = sin(p.phase * 3 + fi) * 0.8
                line(ctx, [CGPoint(x: x, y: -0.5), CGPoint(x: x - 3 + fi * 2, y: -3), CGPoint(x: x - 6 + fi * 3 + sway, y: -6.5)])
            } else {
                line(ctx, [CGPoint(x: x, y: -0.5), CGPoint(x: x + fi * 4, y: 2.5), CGPoint(x: x + fi * 7, y: -4.5)])
            }
        }
        // Wings: a whining blur, or laid along its back.
        ctx.setFillColor(CGColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 0.5))
        ctx.saveGState()
        ctx.translateBy(x: 0, y: 1)
        ctx.rotate(by: flying ? 0.8 + sin(p.phase * 80) * 0.6 : 0.12)
        ctx.addEllipse(in: CGRect(x: -9, y: -1, width: 9, height: 2.2)); ctx.fillPath()
        ctx.restoreGState()
        // Slender striped body, and the needle.
        ctx.setFillColor(body)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.6)
        ctx.addEllipse(in: CGRect(x: -11, y: -0.2, width: 10, height: 2.4)); ctx.drawPath(using: .fillStroke)
        ctx.setStrokeColor(pale)
        ctx.setLineWidth(0.6)
        for x in [CGFloat(-8.5), -6.5, -4.5] { line(ctx, [CGPoint(x: x, y: 0.1), CGPoint(x: x, y: 1.9)]) }
        ctx.setStrokeColor(outline)
        ctx.addEllipse(in: CGRect(x: -1.4, y: -0.6, width: 4, height: 3.4)); ctx.drawPath(using: .fillStroke)
        ctx.addEllipse(in: CGRect(x: 2.4, y: 0, width: 2.4, height: 2.4)); ctx.drawPath(using: .fillStroke)
        ctx.setLineWidth(0.55)
        line(ctx, [CGPoint(x: 4.6, y: 0.8), CGPoint(x: 9.5, y: -1.4)])
        line(ctx, [CGPoint(x: 4.4, y: 2), CGPoint(x: 7, y: 4)])
    }

    private static func drawLadybug(_ p: Prey, in ctx: CGContext) {
        let red = CGColor(red: 0.86, green: 0.16, blue: 0.12, alpha: 1)
        let black = CGColor(red: 0.08, green: 0.07, blue: 0.07, alpha: 1)
        let flying = p.flying && p.airborne
        legs(p, in: ctx, hips: [-2.2, 0, 2.2], reach: 3, down: 2.5, rate: 12, width: 0.9, color: black)
        ctx.setFillColor(black)
        ctx.setStrokeColor(outline)
        ctx.setLineWidth(0.8)
        ctx.addEllipse(in: CGRect(x: 3.2, y: -1.2, width: 3.8, height: 3.4)); ctx.drawPath(using: .fillStroke)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
        ctx.addEllipse(in: CGRect(x: 4.2, y: 1, width: 1.1, height: 1.1)); ctx.fillPath()
        ctx.addEllipse(in: CGRect(x: 5.6, y: 0.2, width: 1, height: 1)); ctx.fillPath()
        if flying {
            // Shell open, the wings beneath a buzz.
            ctx.setFillColor(CGColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 0.5))
            ctx.saveGState()
            ctx.translateBy(x: -1, y: 1.5)
            ctx.rotate(by: 0.5 + sin(p.phase * 55) * 0.5)
            ctx.addEllipse(in: CGRect(x: -9, y: -1.4, width: 9, height: 2.8)); ctx.fillPath()
            ctx.restoreGState()
            ctx.setFillColor(black)
            ctx.addEllipse(in: CGRect(x: -5, y: -1.3, width: 9, height: 3.6)); ctx.drawPath(using: .fillStroke)
            ctx.setFillColor(red)
            ctx.saveGState()
            ctx.translateBy(x: 1.5, y: 2)
            ctx.rotate(by: 0.95)
            ctx.addEllipse(in: CGRect(x: -7, y: -1.8, width: 8, height: 3.6)); ctx.drawPath(using: .fillStroke)
            ctx.restoreGState()
            return
        }
        // The dome, spotted.
        let dome = CGMutablePath()
        dome.move(to: CGPoint(x: -6.5, y: -1.2))
        dome.addQuadCurve(to: CGPoint(x: 4.2, y: -1.2), control: CGPoint(x: -1.2, y: 10))
        dome.closeSubpath()
        ctx.setFillColor(red)
        ctx.addPath(dome); ctx.drawPath(using: .fillStroke)
        ctx.saveGState()
        ctx.addPath(dome); ctx.clip()
        ctx.setFillColor(black)
        for (x, y, r) in [(CGFloat(-3.6), CGFloat(1.4), CGFloat(1.1)), (-0.4, 2.9, 1.2), (2.2, 0.6, 0.9), (-5, -0.6, 0.9)] {
            ctx.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)); ctx.fillPath()
        }
        ctx.restoreGState()
        ctx.setStrokeColor(CGColor(red: 1, green: 0.75, blue: 0.7, alpha: 0.7))
        ctx.setLineWidth(0.8)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -3.5, y: 3))
        ctx.addQuadCurve(to: CGPoint(x: 0.5, y: 3.4), control: CGPoint(x: -1.6, y: 4.2))
        ctx.strokePath()
    }
}

// MARK: - View

/// Screen-sized, click-through; redraws only the patches the creatures (and
/// the toys) are in.
final class PreyView: NSView {
    var prey: [Prey] = []
    var worldOrigin = CGPoint.zero
    /// The spider owns the creatures; picking one up goes through it.
    weak var spider: Spider?
    /// The toys out on the desktop, drawn and picked up here too.
    weak var toyBox: ToyBox?
    private var lastRects: [CGRect] = []
    private var grabbed: Prey?
    private var grabbedToy: Toy?
    private var grabbedAt = V2.zero
    /// The toy has been lifted on this drag (as against a click, a poke).
    private var toyLifted = false
    /// Something is in hand here: a drag on it goes on until it is let go.
    var busy: Bool { grabbed != nil || grabbedToy != nil }
    private var dragSamples: [(p: V2, t: TimeInterval)] = []
    override var isFlipped: Bool { false }

    private func world(_ event: NSEvent) -> V2 {
        let p = convert(event.locationInWindow, from: nil)
        return V2(p.x + worldOrigin.x, p.y + worldOrigin.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let spider else { return nil }
        if grabbed != nil || grabbedToy != nil { return self }
        let w = V2(point.x + worldOrigin.x, point.y + worldOrigin.y)
        return spider.preyHit(w) != nil || toyBox?.hit(w) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let spider else { return }
        let w = world(event)
        dragSamples = [(w, event.timestamp)]
        if let p = spider.preyHit(w) {
            grabbed = p
            spider.beginPreyGrab(p, at: w)
        } else if let toy = toyBox?.hit(w) {
            // Not picked up yet: a click is a poke, and only a drag lifts it.
            grabbedToy = toy
            grabbedAt = w
            toyLifted = false
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let spider else { return }
        let w = world(event)
        dragSamples.append((w, event.timestamp))
        if dragSamples.count > 8 { dragSamples.removeFirst(dragSamples.count - 8) }
        if let p = grabbed {
            spider.movePreyGrab(p, to: w)
        } else if let toy = grabbedToy {
            if !toy.held, !toyLifted, w.distance(to: grabbedAt) > 4 {
                toy.grab(at: grabbedAt)
                toyLifted = true
            }
            toy.drag(to: w)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let spider else { return }
        let w = world(event)
        var v = V2.zero
        if let recent = dragSamples.last(where: { event.timestamp - $0.t > 0.04 }) {
            v = (w - recent.p) / CGFloat(max(event.timestamp - recent.t, 0.008))
        }
        if let p = grabbed {
            spider.endPreyGrab(p, throwVelocity: v)
        } else if let toy = grabbedToy, let box = toyBox {
            if toy.held { toy.release(fling: v) } else if !toyLifted { toy.poke(map: box.map) }
        }
        grabbed = nil
        grabbedToy = nil
        dragSamples = []
    }

    override func rightMouseDown(with event: NSEvent) {
        NotificationCenter.default.post(name: .spiderContextMenu, object: event)
    }

    /// Marks where they were and where they are now for redraw.
    func refresh() {
        var rects: [CGRect] = []
        let boxes = prey.map { $0.bounds } + (toyBox?.toys.map { $0.bounds } ?? [])
        for b0 in boxes {
            let b = b0.insetBy(dx: -6, dy: -6)
            rects.append(CGRect(x: b.minX - worldOrigin.x, y: b.minY - worldOrigin.y, width: b.width, height: b.height))
        }
        for r in lastRects + rects { setNeedsDisplay(r) }
        lastRects = rects
    }

    override func draw(_ dirty: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        for toy in toyBox?.toys ?? [] {
            let b = toy.bounds
            guard CGRect(x: b.minX - worldOrigin.x, y: b.minY - worldOrigin.y, width: b.width, height: b.height).intersects(dirty) else { continue }
            ToyRenderer.draw(toy, in: ctx, origin: worldOrigin)
        }
        for p in prey {
            let b = p.bounds
            let local = CGRect(x: b.minX - worldOrigin.x, y: b.minY - worldOrigin.y, width: b.width, height: b.height)
            guard local.intersects(dirty) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: p.pos.x - worldOrigin.x, y: p.pos.y - worldOrigin.y)
            // A soft contact shadow under anything sitting on an edge.
            if p.castsShadow {
                ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.12 * Double(p.alpha)))
                ctx.fillEllipse(in: CGRect(x: -9 * p.drawScale, y: -p.kind.clearance * p.drawScale - 2, width: 18 * p.drawScale, height: 3.5 * p.drawScale))
            }
            PreyRenderer.draw(p, in: ctx)
            ctx.restoreGState()
        }
    }
}
