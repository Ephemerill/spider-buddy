import AppKit

// Nav check (tools/perch.sh nav): how well the spider gets about its tank.
//
//   • hunt: a creature kept quite still on a surface somewhere in a tank; the
//     spider, hungry, goes after it. How long it takes, how often it turns
//     back on itself, the longest it goes without getting any nearer, how
//     many leaps — and whether it goes after one it cannot get to at all.
//   • go: off to a place somewhere in the tank, as when exploring: the same
//     measures, and how often it gives up.
//
// PC_PART=hunt,go  PC_SEEDS (5)  PC_PRESETS=forestFloor,…  PC_TANK=mine (the
// app's own tank, read only)  PC_TRACE=1 (a line a second)  PC_SECS (150)

#if SHAPED
private let G = HabitatLayout.ground
private let scale: CGFloat = 0.78
private let standoff = 22 * scale
private var navSeeds: Int { Int(env["PC_SEEDS"] ?? "5") ?? 5 }
private var navTrace: Bool { env["PC_TRACE"] != nil }
/// PC_TRACE=all: a line each time how it is going about it changes, too.
private var navTraceAll: Bool { env["PC_TRACE"] == "all" }
private var navSecs: CGFloat { CGFloat(Double(env["PC_SECS"] ?? "150") ?? 150) }

/// The tanks to try: the ready-made ones (or those named), or the app's own.
private func navTanks() -> [(String, Habitat)] {
    if env["PC_TANK"] == "mine" {
        guard let data = UserDefaults(suiteName: "com.gabriel.desktopspider")?.data(forKey: Habitat.key),
              var h = try? JSONDecoder().decode(Habitat.self, from: data) else { return [] }
        if h.world == nil { h = h.movedIntoWorld(HabitatLayout.defaultWorld) }
        h.clampAll()
        h.pruneLinks()
        return [("mine", h)]
    }
    let named = env["PC_PRESETS"].map { Set($0.split(separator: ",").map(String.init)) }
    return Habitat.Preset.allCases.filter { $0 != .empty && (named?.contains($0.rawValue) ?? true) }.map { ($0.rawValue, Habitat.preset($0, world: world)) }
}

/// Open floor to start from, near `x`: where it is put in the tank (never
/// inside something standing on the floor, with no floor under it).
private func openFloor(_ m: SurfaceMap, near x: CGFloat) -> CGFloat {
    let floor = G + standoff
    let spots = m.sampleSpots(spacing: 24).filter {
        $0.loop.id.hasPrefix("screen:") && $0.seg.facing == .up && abs($0.point.y - floor) < 1
    }.map(\.point.x)
    return spots.min(by: { abs($0 - x) < abs($1 - x) }) ?? x
}

/// A hungry spider in `h`, on the open floor near `x`, knowing everything
/// in it, with the tank alive; nothing else on its mind.
private func navSpider(_ h: Habitat, at wantX: CGFloat) -> (SurfaceMap, Spider, HabitatEcology) {
    let desk = SurfaceMap()
    desk.standoff = standoff
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    let m = surfaces(h, standoff: standoff)
    let x = openFloor(m, near: wantX)
    let s = Spider(map: desk)
    s.config.followCursor = false
    s.config.approachCursor = false
    s.config.scale = scale
    s.knowledge = HabitatKnowledge()
    for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
    s.enter(map: m, at: V2(x, G + 30), habitat: true)
    let e = HabitatEcology()
    e.relayout(h, map: m)
    s.ecology = e
    s.tankRebuilt(h, smooth: false, inIt: true)
    s.debugSetUrges(thirst: 0, view: 0, rest: 0, roam: 0)
    // (Settled on the floor before anything starts: standing, not still on
    // a line.)
    for i in 0..<900 {
        s.setCursor(V2(-4000, -4000))
        s.update(dt: dt)
        if i >= 180, s.debugState.hasPrefix("attached") { break }
    }
    return (m, s, e)
}

/// How a trip went.
private struct Trip {
    var done: CGFloat?          // got there (caught it, arrived) after this long
    var gaveUp = false          // stopped trying (the hunt dropped, the errand ended)
    var reversals = 0           // turned back on itself
    var stuck: CGFloat = 0      // longest without getting any nearer
    var leaps = 0
    var walked: CGFloat = 0
    var straight: CGFloat = 0
    var chased: CGFloat = 0     // time it spent going after it
}

/// Watches it go toward `goal` for up to `secs`, a frame at a time: `step`
/// says whether it is there (true), gave up (false), or neither (nil).
private func follow(_ s: Spider, _ e: HabitatEcology, toward goal: V2, secs: CGFloat, label: String,
                    step: (CGFloat) -> Bool?) -> Trip {
    var trip = Trip()
    trip.straight = s.worldPos.distance(to: goal)
    var t: CGFloat = 0
    var lastSample = s.worldPos, lastDir: V2?, sampleIn: CGFloat = 0.25
    var best = s.worldPos.distance(to: goal), bestAt: CGFloat = 0
    var wasAir = false, lastState = "", lastNote = ""
    var prev = s.worldPos
    while t < secs {
        e.update(.calm, dt: dt)
        s.setCursor(V2(-4000, -4000))
        s.update(dt: dt)
        t += dt
        let p = s.worldPos
        trip.walked += p.distance(to: prev)
        prev = p
        // Turning back: its way over the last quarter second against the one before.
        sampleIn -= dt
        if sampleIn <= 0 {
            sampleIn = 0.25
            let d = p - lastSample
            if d.length > 8 * scale {
                let dir = d.normalized
                if let l = lastDir, l.dot(dir) < -0.5 { trip.reversals += 1 }
                lastDir = dir
                lastSample = p
            }
        }
        let air = s.isAirborne
        if air, !wasAir { trip.leaps += 1 }
        wasAir = air
        let dist = p.distance(to: goal)
        if dist < best - 20 * scale { best = dist; bestAt = t }
        trip.stuck = max(trip.stuck, t - bestAt)
        if navTrace {
            let st = String(s.debugState.prefix(44))
            #if WAYS
            let note = s.debugHuntNote + " " + s.debugNavTrip
            #else
            let note = ""
            #endif
            if (Int(t * 60) % 60 == 0 && st != lastState) || (navTraceAll && note != lastNote) {
                print(String(format: "        %5.1fs (%4.0f,%4.0f) %4.0f off  %@ | %@ | %@", Double(t), Double(p.x), Double(p.y), Double(dist), st,
                             s.debugErrand, note))
                lastState = st
                lastNote = note
            }
        }
        if let r = step(t) {
            if r { trip.done = t } else { trip.gaveUp = true }
            break
        }
    }
    return trip
}

private func median(_ xs: [CGFloat]) -> CGFloat? {
    guard !xs.isEmpty else { return nil }
    let s = xs.sorted()
    return s[s.count / 2]
}

private func report(_ label: String, _ trips: [Trip], _ b: inout Builder) {
    let got = trips.filter { $0.done != nil }
    let times = got.compactMap(\.done)
    let rev = trips.map { CGFloat($0.reversals) }
    let stuck = trips.map(\.stuck)
    let ratio = got.map { $0.walked / max($0.straight, 1) }
    print(String(format: "  %-14@ got there %2d/%2d  gave up %2d  time median %5.1fs worst %5.1fs  turned back median %4.1f worst %3.0f  stuck worst %5.1fs  leaps %4.1f  walked/straight %4.1f",
                 label, got.count, trips.count, trips.filter(\.gaveUp).count, Double(median(times) ?? 0), Double(times.max() ?? 0),
                 Double(median(rev) ?? 0), Double(rev.max() ?? 0), Double(stuck.max() ?? 0),
                 Double(trips.map { CGFloat($0.leaps) }.reduce(0, +) / CGFloat(max(trips.count, 1))), Double(median(ratio) ?? 0)))
}

// MARK: Hunt

/// Spots a creature could sit on: tops of things, and the floor.
private func perches(_ m: SurfaceMap) -> [(anchor: Anchor, point: V2)] {
    m.sampleSpots(spacing: 30).filter { $0.seg.dir.perp.y > 0.6 }.map { ($0.anchor, $0.point) }
}

private func navHunt(_ b: inout Builder) -> [Trip] {
    print("== hunt: after a creature kept still somewhere in the tank")
    var all: [Trip] = []
    for (name, h) in navTanks() {
        var trips: [Trip] = []
        for sd in 0..<navSeeds {
            reseed(UInt64(9000 + sd))
            let x = CGFloat.random(in: 400...(h.size.width - 400))
            let (m, s, e) = navSpider(h, at: x)
            let spots = perches(m).filter { (250 * scale...1700 * scale).contains($0.point.distance(to: s.worldPos)) }
            guard let spot = spots.randomElement() else { continue }
            let c = s.release(.cricket, at: spot.point)
            c.debugPlace(on: spot.anchor, map: m)
            c.debugStill = true
            c.noticed = true
            c.alpha = 1
            s.debugFed = 0.05
            if navTrace { print(String(format: "    %@ seed %d: from (%.0f,%.0f) to (%.0f,%.0f) on %@", name, sd, Double(s.worldPos.x), Double(s.worldPos.y), Double(spot.point.x), Double(spot.point.y), spot.anchor.loopID)) }
            var chasing: CGFloat = 0
            let trip = follow(s, e, toward: spot.point, secs: navSecs, label: name) { t in
                if s.debugHuntTarget == c.id { chasing += dt }
                return c.state != .loose ? true : nil
            }
            var tr = trip
            tr.chased = chasing
            trips.append(tr)
            if navTrace { print(String(format: "      -> %@ in %.1fs, turned back %d, stuck %.1fs, %d leaps", tr.done != nil ? "caught" : "not caught", Double(tr.done ?? navSecs), tr.reversals, Double(tr.stuck), tr.leaps)) }
        }
        report(name, trips, &b)
        all += trips
    }
    report("all", all, &b)
    return all
}

// MARK: Go

private func navGo(_ b: inout Builder) -> [Trip] {
    print("== go: off to somewhere in the tank")
    var all: [Trip] = []
    for (name, h) in navTanks() {
        var trips: [Trip] = []
        for sd in 0..<navSeeds {
            reseed(UInt64(9500 + sd))
            let x = CGFloat.random(in: 400...(h.size.width - 400))
            let (_, s, e) = navSpider(h, at: x)
            guard let sv = s.debugPlaces else { continue }
            let options = sv.places.filter { !$0.hanging && (300 * scale...2000 * scale).contains($0.point.distance(to: s.worldPos)) }
            guard let pl = options.randomElement() else { continue }
            if navTrace { print(String(format: "    %@ seed %d: from (%.0f,%.0f) to %@ (%.0f,%.0f)", name, sd, Double(s.worldPos.x), Double(s.worldPos.y), pl.key, Double(pl.point.x), Double(pl.point.y))) }
            guard s.debugGo(to: pl) else {
                trips.append(Trip(gaveUp: true))
                if navTrace { print("      -> would not set off: \(s.debugState) | \(s.debugErrandEnd)") }
                #if WAYS
                if navTrace, let n = s.debugNav, let (l, y) = n.locate(pl.anchor) {
                    let near = n.loopNodes[l].filter { abs(n.nodes[Int($0)].along - y) < 60 }
                    print("         its surface \(pl.anchor.loopID): \(n.loopNodes[l].count) spots, round \(Int(n.perimeter[l])); "
                          + "spots by it \(near.count), parts \(Set(near.flatMap { [n.part[Int($0) * 2], n.part[Int($0) * 2 + 1]] }).sorted())")
                }
                #endif
                continue
            }
            let trip = follow(s, e, toward: pl.point, secs: navSecs, label: name) { _ in
                if s.debugErrand.contains("explore act") { return true }
                if s.debugErrandKind == nil { return false }
                return nil
            }
            trips.append(trip)
            if navTrace { print(String(format: "      -> %@ in %.1fs, turned back %d, stuck %.1fs, %d leaps  (%@)", trip.done != nil ? "there" : (trip.gaveUp ? "gave up" : "not there"), Double(trip.done ?? navSecs), trip.reversals, Double(trip.stuck), trip.leaps, s.debugErrandEnd)) }
        }
        report(name, trips, &b)
        all += trips
    }
    report("all", all, &b)
    return all
}

// MARK: Ways

#if WAYS
/// The tank's ways (HabitatNav.swift): how many, how long they take to work
/// out, and how long a question of them takes, between spots picked at random.
private func navWays(_ b: inout Builder) {
    print("== ways: the tank's ways, worked out")
    for (name, h) in navTanks() {
        let m = surfaces(h, standoff: standoff)
        let n = TankNav(map: m, habitat: h, scale: scale)
        reseed(4242)
        var times: [Double] = [], none = 0, popped: [Int] = []
        for _ in 0..<60 {
            guard n.nodes.count > 1 else { break }
            let a = n.anchor(of: Int32(Int.random(in: 0..<n.nodes.count)))
            let z = n.anchor(of: Int32(Int.random(in: 0..<n.nodes.count)))
            let began = CACurrentMediaTime()
            let p = n.plan(from: a, dir: 1, to: z, within: 10, lean: NavLean())
            times.append((CACurrentMediaTime() - began) * 1000)
            popped.append(n.lastPopped)
            if p == nil { none += 1 }
        }
        times.sort()
        let med = times.isEmpty ? 0 : times[times.count / 2]
        print(String(format: "  %-14@ %@", name, n.debugSummary))
        print(String(format: "  %-14@ plans: median %.2f ms, worst %.2f ms, most states %d, no way %d/%d", "", med, times.last ?? 0,
                     popped.max() ?? 0, none, times.count))
        b.check("\(name): ways worked out in under 2 s", n.buildTime < 2, "(\(Int(n.buildTime * 1000)) ms)")
    }
}
#endif

#if WAYS
// MARK: Reach

/// Of every place in each tank, those the ways say there is no way to from
/// the floor: there should be next to none.
private func navReach(_ b: inout Builder) {
    print("== reach: places there is no way to, from the floor")
    for (name, h) in navTanks() {
        let (_, s, _) = navSpider(h, at: h.size.width / 2)
        guard let sv = s.debugPlaces, let n = s.debugNav else { continue }
        let out = sv.places.filter { !s.debugCanGet(to: $0.anchor) }
        print(String(format: "  %-14@ %d/%d places out of reach%@", name, out.count, sv.places.count,
                     out.isEmpty ? "" : ": " + out.prefix(6).map { String(format: "%@ (%.0f,%.0f)", $0.anchor.loopID, Double($0.point.x), Double($0.point.y)) }.joined(separator: ", ")))
        _ = n
        b.check("\(name): hardly any places out of reach", out.count * 50 <= sv.places.count, "\(out.count)/\(sv.places.count)")
    }
}

// MARK: Trapped

/// A creature on a rock in mid-air, far out of reach of anything: it is
/// never hunted, and before long it slips away. And one it can get to, on
/// a rock it can reach, for comparison: that one it catches.
private func navTrapped(_ b: inout Builder) {
    print("== trapped: a creature it has no way to")
    // (PC_ROCK: another height to try, as "in reach".)
    let tryY = env["PC_ROCK"].flatMap { Double($0) }.map { CGFloat($0) }
    for (label, y, reachable) in [("out of reach", CGFloat(520), false), ("in reach", tryY ?? CGFloat(150), true)] {
        var h = Habitat(biome: .forest, world: world)
        var it = h.add(.rock, at: CGPoint(x: 2000, y: y))
        it.x = 2000
        it.y = y
        it.seed = 77
        h.items[h.items.count - 1] = it
        let (m, s, e) = navSpider(h, at: 1500)
        let own = Set(m.loops.filter { $0.owners.contains(it.id) }.map(\.id))
        guard let spot = perches(m).filter({ own.contains($0.anchor.loopID) }).min(by: { $0.point.y > $1.point.y }) else {
            b.check("\(label): somewhere on the rock to put it", false)
            continue
        }
        if navTrace, let n = s.debugNav, let floor = perches(m).min(by: { $0.point.distance(to: V2(1500, 91)) < $1.point.distance(to: V2(1500, 91)) }) {
            let plan = n.plan(from: floor.anchor, dir: 1, to: spot.anchor, within: 20, lean: NavLean())
            print("      the way there from the floor: \(plan.map { n.describe($0) } ?? "none")")
        }
        let c = s.release(.cricket, at: spot.point)
        c.debugPlace(on: spot.anchor, map: m)
        c.debugStill = true
        c.noticed = true
        c.alpha = 1
        s.debugFed = 0.05
        var hunted = false, t: CGFloat = 0
        while t < 90 {
            e.update(.calm, dt: dt)
            s.setCursor(V2(-4000, -4000))
            s.update(dt: dt)
            t += dt
            if s.debugHuntTarget == c.id { hunted = true }
            if c.gone || c.state != .loose { break }
            if navTrace, Int(t * 60) % 60 == 0 {
                print(String(format: "        %4.0fs (%4.0f,%4.0f) %@ | target %@ | %@ | %@ | %@", Double(t), Double(s.worldPos.x), Double(s.worldPos.y),
                             String(s.debugState.prefix(40)), s.debugHuntTarget.map { "\($0)" } ?? "-", s.debugErrand, s.debugHuntNote, s.debugNavTrip))
            }
        }
        print(String(format: "  %@: on the rock at (%.0f,%.0f), a way to it: %@; hunted %@, %@ after %.0f s", label, Double(spot.point.x), Double(spot.point.y),
                     c.gone ? "-" : (s.debugCanGet(to: c) ? "yes" : "no"), hunted ? "yes" : "no",
                     c.gone ? "gone" : (c.state == .loose ? "still there" : "caught"), Double(t)))
        if reachable {
            b.check("in reach: it goes after it and catches it", hunted && c.state != .loose)
        } else {
            b.check("out of reach: it never goes after it", !hunted)
            b.check("out of reach: it slips away before long", c.gone && t < 60, String(format: "(%.0f s)", Double(t)))
        }
    }
}
#endif

func navCheck() {
    var b = Builder()
    #if WAYS
    Spider.debugNavPlans = env["PC_PLANS"] != nil
    #endif
    let parts = env["PC_PART"].map { Set($0.split(separator: ",").map(String.init)) }
    #if WAYS
    if parts?.contains("ways") ?? true { navWays(&b) }
    if parts?.contains("reach") ?? true { navReach(&b) }
    if parts?.contains("trapped") ?? true { navTrapped(&b) }
    #endif
    if parts?.contains("hunt") ?? true { _ = navHunt(&b) }
    if parts?.contains("go") ?? true { _ = navGo(&b) }
    print(b.fails == 0 ? "all ok" : "\(b.fails) FAILED")
}
#endif
