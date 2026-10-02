import AppKit

// Curiosity check (tools/perch.sh curious): things as things (Phase 4).
//
//   • natures: what a few kinds are to the spider, and the rules spot-checked
//     (water is drinkable, a cave shelters and encloses, a lamp glows, a
//     feather is light, a branch takes silk…);
//   • places: the named places on the examples — water dish, hollow log,
//     toadstool, leaf, branch — are there, in the world, with somewhere to
//     stand for each;
//   • the loop: a toadstool put down in a tank it knows. It notices it (not
//     at once), watches, comes closer, feels it, climbs it by its own
//     surfaces, comes to know it — and after that leaves it be. Across
//     personalities and seeds, with the times of each step;
//   • decorating: something big dropped by it, something small, something
//     moved; carried off on what it stands on (rides it, never left in the
//     air), moved in one go, taken away from under it; a rearrangement.
//
// PC_SEEDS (5)  PC_SECS (420 a run)  PC_WHO=Curious,Shy (personalities)
// PC_FILM=prefix (a film strip of each personality's first run)  PC_TRACE (every change)
// PC_PART=natures,places,loop,decor (only those)

#if SHAPED
private let G = HabitatLayout.ground
private let scale: CGFloat = 0.78

/// A tank it already knows, with a spider in it on the ground at `x`.
private func knownTank(width: CGFloat = 1800, spiderAt x: CGFloat, personality: Personality, extra: [(HabitatItemKind, CGFloat)] = [])
    -> (Habitat, SurfaceMap, Spider) {
    var h = Habitat(biome: .forest, world: CGSize(width: width, height: 640))
    _ = h.add(.rock, at: CGPoint(x: 160, y: 0))
    _ = h.add(.fern, at: CGPoint(x: width - 160, y: 0))
    for (k, at) in extra { _ = h.add(k, at: CGPoint(x: at, y: k.hangs ? h.size.height : 0)) }
    let standoff = 22 * scale
    let desk = SurfaceMap()
    desk.standoff = standoff
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    let tank = surfaces(h, standoff: standoff)
    let s = Spider(map: desk)
    s.config.followCursor = false
    s.config.approachCursor = false
    s.config.scale = scale
    var d = s.design
    d.personality = personality
    s.apply(design: d)
    s.knowledge = HabitatKnowledge()
    for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
    s.enter(map: tank, at: V2(x, G + 30), habitat: true)
    s.tankRebuilt(h, smooth: false, inIt: true)
    return (h, tank, s)
}

/// The tank changed (as the editor changes it): its surfaces laid out again, and the spider told.
private func rebuilt(_ h: Habitat, _ tank: SurfaceMap, _ s: Spider) {
    tank.rebuild(habitat: h.surfaces(standoff: tank.standoff))
    s.tankRebuilt(h, smooth: false, inIt: true)
}

private func step(_ s: Spider, _ secs: CGFloat, each: (() -> Void)? = nil) {
    for _ in 0..<Int(secs / dt) {
        s.setCursor(V2(-4000, -4000))
        s.update(dt: dt)
        each?()
    }
}

private func near(_ s: Spider, _ it: HabitatItem) -> CGFloat {
    let r = it.rect, p = s.worldPos
    return V2(max(r.minX - p.x, 0, p.x - r.maxX), max(r.minY - p.y, 0, p.y - r.maxY)).length
}

/// Whether it is holding on to something real: its body on the surfaces, not in the air.
private func footed(_ s: Spider, _ m: SurfaceMap) -> Bool {
    guard let a = s.standingOn, let p = m.worldPoint(a) else { return false }
    return p.distance(to: s.worldPos) < 16
}

// MARK: Natures and places

private func naturesCheck(_ b: inout Builder) {
    print("== natures: what a few kinds are to it")
    for k in [HabitatItemKind.waterDish, .hide, .mushroom, .branch, .broadLeaf, .barkCave, .floorLamp, .feather, .fallenLeaf,
              .floweringPlant, .lookout, .moistMoss, .bed, .vine, .stoneArch] {
        print("  \(k.label): \(k.nature)")
    }
    let n = { (k: HabitatItemKind) in k.nature }
    b.check("water dish is drinkable, wet, a moisture source", n(.waterDish).has(.drinkable) && n(.waterDish).has(.wet) && n(.waterDish).has(.moistureSource))
    b.check("water dish is made; a log is grown", n(.waterDish).has(.artificial) && n(.log).has(.organic) && !n(.log).has(.artificial))
    b.check("bark cave shelters, hides, encloses, suits sleeping", [.sheltering, .hideable, .enclosed, .sleepingSuitable].allSatisfy { n(.barkCave).has($0) })
    b.check("hollow log encloses and hides", n(.hide).has(.enclosed) && n(.hide).has(.hideable))
    b.check("toadstool: climbable, perchable, sheltering (its cap)", n(.mushroom).has(.climbable) && n(.mushroom).has(.perchable) && n(.mushroom).has(.sheltering))
    b.check("a lamp glows; a fireplace is warm", n(.floorLamp).has(.glowing) && n(.fireplace).has(.warm))
    b.check("a feather is light, movable, flexible", n(.feather).has(.lightweight) && n(.feather).has(.movable) && n(.feather).has(.flexible, 0.4))
    b.check("a hanging vine hangs, is flexible and moves", n(.vine).has(.hanging) && n(.vine).has(.flexible) && n(.vine).has(.moving, 0.4))
    b.check("a branch takes silk", n(.branch).has(.silkAnchor))
    b.check("flowers draw prey; a good ambush", n(.floweringPlant).has(.preyAttracting) && n(.floweringPlant).has(.huntingSuitable, 0.4))
    b.check("the lookout is a lookout, and elevated", n(.lookout).has(.lookoutSuitable) && n(.lookout).has(.elevated))
    b.check("damp moss: wet, cool, moist", n(.moistMoss).has(.wet) && n(.moistMoss).has(.cool) && n(.moistMoss).has(.moistureSource))
    b.check("a bed suits sleeping", n(.bed).has(.sleepingSuitable))
    b.check("a stone is no shelter, not flexible, not movable", !n(.rock).has(.sheltering) && !n(.rock).has(.flexible) && !n(.rock).has(.movable))
    b.check("scenery is not climbable", !n(.fern).has(.climbable, 0.1) && !n(.fallenLeaf).has(.climbable, 0.1))
    // Where it is.
    var h = Habitat(biome: .forest, world: CGSize(width: 1200, height: 640))
    let low = h.add(.rock, at: CGPoint(x: 400, y: 0))
    var br = h.add(.mediumBranch, at: CGPoint(x: 400, y: 200))
    br.y = 200
    h.items[h.items.count - 1] = br
    let high = h.add(.slateLedge, at: CGPoint(x: 900, y: 260))
    let ql = h.qualities(of: low), qh = h.qualities(of: h.item(id: high.id)!)
    print("  rock under a branch: \(ql)")
    b.check("a rock under a branch is covered, not exposed", ql.has(.covered) && !ql.has(.exposed))
    b.check("a ledge up high is elevated and exposed", qh.has(.elevated) && qh.has(.exposed))
}

private func placesCheck(_ b: inout Builder) {
    print("== places: on the examples, in the world, with somewhere to stand")
    let examples: [(HabitatItemKind, [InteractionPoint.Kind], String)] = [
        (.waterDish, [.drinkEdge, .waterSurface, .inspect, .touch], "drinking edge, water surface, inspection spot"),
        (.hide, [.entrance, .interior, .top, .inspect], "entrance, interior, roof"),
        (.mushroom, [.side, .top, .underside, .beneath, .edge, .touch], "stem, cap, underside"),
        (.broadLeaf, [.top, .underside, .edge], "leaf top, underside, edge"),
        (.fallenLeaf, [.touch, .inspect], "a leaf on the ground: touched, looked at"),
        (.mediumBranch, [.perch, .launch, .silkAnchor, .underside], "perch points, launch points, silk anchors"),
        (.barkCave, [.entrance, .top, .touch], "a cave's way in"),
        (.rockPool, [.drinkEdge, .waterSurface], "a pool's rim and water"),
    ]
    for (kind, want, what) in examples {
        var h = Habitat(biome: .forest, world: CGSize(width: 1200, height: 640))
        var it = h.add(kind, at: CGPoint(x: 600, y: kind.definition.placement == .wedged ? 150 : 0))
        it.seed = 11
        h.items[0] = it
        if kind.definition.placement == .wedged { h.addSupport(for: it.id) }
        let m = surfaces(h, standoff: 22 * scale)
        let pts = h.item(id: it.id)!.interactionPoints(on: m)
        let r = it.rect.insetBy(dx: -200, dy: -200)
        let inWorld = pts.allSatisfy { r.contains($0.point.point) }
        let missing = want.filter { k in !pts.contains { $0.kind == k } }
        let standable = pts.filter { $0.stand != nil }.count
        // Named after the parts they are on.
        let named = Set(pts.map(\.part)).sorted().joined(separator: ",")
        let summary = Dictionary(grouping: pts, by: \.kind).map { "\($0.key.rawValue)×\($0.value.count)" }.sorted().joined(separator: " ")
        if env["PC_TRACE"] != nil {
            for p in pts where [.touch, .inspect].contains(p.kind) {
                print(String(format: "    %@ at %.0f,%.0f from %.0f,%.0f (thing %.0f…%.0f)", p.label, Double(p.point.x), Double(p.point.y),
                             Double(p.standPoint?.x ?? -1), Double(p.standPoint?.y ?? -1), Double(it.rect.minX), Double(it.rect.maxX)))
            }
        }
        b.check("\(kind.label): \(what)", missing.isEmpty && inWorld && standable >= 2,
                missing.isEmpty ? "[\(summary)] parts {\(named)}" : "missing \(missing.map(\.rawValue)) — have [\(summary)]")
        if kind == .mushroom {
            let parts = Set(pts.filter { [.side, .underside, .top].contains($0.kind) }.map { "\($0.kind.rawValue):\($0.part)" })
            b.check("toadstool: stem side, cap top, cap underside", parts.contains("side:stem") && parts.contains("top:cap") && parts.contains("underside:cap"),
                    parts.sorted().joined(separator: " "))
        }
    }
}

// MARK: The loop

private struct Run {
    var noticed: CGFloat?, watched: CGFloat?, approached: CGFloat?, touched: CGFloat?, climbed: CGFloat?, onTop: CGFloat?, familiar: CGFloat?
    var climbedBy = ""
    var probes: Set<String> = []
    var afterLooks = 0
    var afterInquiries = 0
    var floating = 0
    var closest = CGFloat.greatestFiniteMagnitude
}

private func film(_ path: String, _ frames: [(SpiderPose, String, V2?, V2?)], h: Habitat, area: CGRect) {
    guard !frames.isEmpty else { return }
    let cols = Int(env["PC_COLS"] ?? "6") ?? 6, zoom = CGFloat(Double(env["PC_ZOOM"] ?? "2") ?? 2)
    let rows = (frames.count + cols - 1) / cols
    let cw = Int(area.width * zoom), chH = Int(area.height * zoom)
    guard let c = CGContext(data: nil, width: cw * cols, height: chH * rows, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    for (n, f) in frames.enumerated() {
        let ox = CGFloat(n % cols * cw), oy = CGFloat((rows - 1 - n / cols) * chH)
        c.saveGState()
        c.translateBy(x: ox, y: oy)
        c.clip(to: CGRect(x: 0, y: 0, width: cw, height: chH))
        c.scaleBy(x: zoom, y: zoom)
        c.setFillColor(NSColor(calibratedRed: 0.55, green: 0.7, blue: 0.62, alpha: 1).cgColor)
        c.fill(CGRect(origin: .zero, size: area.size))
        c.setFillColor(NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.18, alpha: 1).cgColor)
        c.fill(CGRect(x: 0, y: 0, width: area.width, height: G - area.minY))
        paintItems(h, area: area, scale: scale, c)
        c.translateBy(x: -area.minX, y: -area.minY)
        let pose = f.0
        let side = SpiderRenderer.spriteSide(for: pose.scale)
        SpiderRenderer.draw(pose, in: c, bounds: CGRect(x: pose.pos.x - side / 2, y: pose.pos.y - side / 2, width: side, height: side))
        if let p = f.2 { c.setFillColor(CGColor(red: 1, green: 0.15, blue: 0.2, alpha: 1)); c.fillEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4)) }
        if let p = f.3 { c.setStrokeColor(CGColor(red: 0.3, green: 0.9, blue: 1, alpha: 0.8)); c.setLineWidth(0.8); c.strokeEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)) }
        c.restoreGState()
        c.saveGState()
        c.translateBy(x: ox, y: oy)
        label(c, f.1, at: CGPoint(x: 6, y: CGFloat(chH) - 16))
        c.restoreGState()
    }
    if let img = c.makeImage() { save(img, path) }
}

private func loopRun(_ who: String, _ p: Personality, seed: UInt64, secs: CGFloat, filmPath: String?) -> Run {
    reseed(seed)
    var (h, tank, s) = knownTank(spiderAt: 520, personality: p)
    step(s, 8)
    // A toadstool put down some way off.
    let before = s.worldPos.x
    let mx = before < 900 ? before + 300 : before - 300
    var it = h.add(.mushroom, at: CGPoint(x: mx, y: 0))
    it.seed = 5
    h.items[h.items.count - 1] = it
    rebuilt(h, tank, s)
    let uid = it.uid
    let know = s.knowledge!
    var r = Run()
    var t: CGFloat = 0
    var last = ""
    var wasOnIt = false, wasAttached = true, settled = false
    var offFor = 0
    var startDist: CGFloat = 0
    var frames: [(SpiderPose, String, V2?, V2?)] = []
    var nextShot: CGFloat = 0
    let trace = env["PC_TRACE"] != nil
    for _ in 0..<Int(secs / dt) {
        s.setCursor(V2(-4000, -4000))
        s.update(dt: dt)
        t += dt
        let stage = know.stage(of: uid)
        let inq = s.debugInquiryUID == uid ? s.debugInquiry : "-"
        let state = s.debugState
        let d = near(s, it)
        r.closest = min(r.closest, d)
        if r.noticed == nil, stage != .unknown {
            r.noticed = t
            if trace { print("    noticed: \(s.debugLastNotice)") }
        }
        if r.watched == nil, inq.hasPrefix("watch") { r.watched = t; startDist = d }
        if r.watched != nil, r.approached == nil, inq.hasPrefix("approach") || inq.hasPrefix("probe"), d < startDist - 20 || d < 30 { r.approached = t }
        if let f = s.debugFeelAt, it.rect.insetBy(dx: -8, dy: -8).contains(f.point) {
            if r.touched == nil { r.touched = t }
        }
        let onIt = s.debugUnderfoot == it.id && s.isStanding
        if onIt, !wasOnIt {
            if r.climbed == nil { r.climbed = t; r.climbedBy = wasAttached ? "walking" : "a leap" }
        }
        if onIt, r.onTop == nil, s.worldPos.y > it.rect.minY + it.h * 0.75, s.debugFooting > 0.6 { r.onTop = t }
        wasOnIt = onIt
        wasAttached = s.isStanding
        // (A frame or two up off it — a hop, a shake — is its own doing;
        // left standing on nothing, it would stay off.)
        offFor = s.isStanding && !footed(s, tank) ? offFor + 1 : 0
        if offFor == 6 {
            r.floating += 1
            if r.floating <= 3, let a = s.standingOn, let p = tank.worldPoint(a) {
                print(String(format: "    (off its surface at %.2fs: %.1f pt, %@ seg %d t %.1f, %@)", Double(t), Double(p.distance(to: s.worldPos)),
                             a.loopID, a.segIdx, Double(a.t), state))
            }
        }
        for pr in ["feel", "peer", "water", "beneath", "inside", "otherSide", "partway", "top", "leapOn"] where inq.contains("done [") {
            if let dn = inq.range(of: "done ["), inq[dn.upperBound...].prefix(while: { $0 != "]" }).contains(pr) { r.probes.insert(pr) }
        }
        if r.familiar == nil, stage == .familiar { r.familiar = t }
        // Once it knows it, and has finished up with it: never looked into again.
        if r.familiar != nil, s.debugInquiryUID != uid { settled = true }
        if settled {
            if s.debugInquiryUID == uid { r.afterInquiries += 1 }
            if let e = s.debugEyeOn, it.rect.insetBy(dx: -20, dy: -20).contains(e.point), s.debugInquiryUID == nil { r.afterLooks += 1 }
        }
        let line = "\(stage) | \(inq) | \(state)"
        if trace, line != last { print(String(format: "    %6.2f  d %4.0f  %@", Double(t), Double(d), line)) }
        last = line
        // Film: from just before it notices until a little after it knows it.
        if filmPath != nil, frames.count < 48, t >= nextShot, r.noticed.map({ t > $0 - 1 }) ?? false, r.familiar.map({ t < $0 + 8 }) ?? true, d < 260 {
            let tag = String(format: "%.1fs %@ %@", Double(t), "\(stage)", String(inq.prefix(while: { $0 != " " })))
                + " " + String(state.split(separator: ":").dropFirst().first?.split(separator: " ").first ?? "")
            frames.append((s.pose(), tag, s.debugFeelAt, s.debugEyeOn))
            nextShot = t + (inq.contains("probe") || inq.hasPrefix("approach") ? 0.7 : 1.4)
        }
        if let f = r.familiar, t > f + 150 { break }
    }
    let fw = CGFloat(Double(env["PC_FILMW"] ?? "360") ?? 360)
    if let path = filmPath { film(path, frames, h: h, area: CGRect(x: it.rect.midX - fw / 2, y: G - 20, width: fw, height: max(fw * 0.55, it.h + 70))) }
    _ = h
    return r
}

private func loopCheck(_ b: inout Builder) {
    print("== the loop: a toadstool put down in a tank it knows")
    let seeds = Int(env["PC_SEEDS"] ?? "5") ?? 5
    let secs = CGFloat(Double(env["PC_SECS"] ?? "420") ?? 420)
    let who: [(String, Personality)] = [("Default", Personality())]
        + Personality.presets.filter { ["Curious", "Shy", "Show-off", "Lazy"].contains($0.name) }.map { ($0.name, $0.p) }
    let wanted = env["PC_WHO"].map { Set($0.split(separator: ",").map(String.init)) }
    func f(_ x: CGFloat?) -> String { x.map { String(format: "%5.1f", Double($0)) } ?? "  -  " }
    for (name, p) in who where wanted?.contains(name) ?? true {
        print("  \(name)  (curiosity \(p.curiosity), bravery \(p.bravery))")
        print("     seed  noticed watched approached touched climbed  on-top  familiar  climbed-by  probes")
        var full = 0, instant = 0, after = 0, floating = 0
        let first = Int(env["PC_SEED0"] ?? "0") ?? 0
        for sd in first..<(first + seeds) {
            let path = sd == first ? env["PC_FILM"].map { "\($0)_\(name).png" } : nil
            let r = loopRun(name, p, seed: UInt64(100 + sd), secs: secs, filmPath: path)
            print("     \(sd)    \(f(r.noticed))  \(f(r.watched))  \(f(r.approached))  \(f(r.touched))  \(f(r.climbed))  \(f(r.onTop))  \(f(r.familiar))  \(r.climbedBy.padding(toLength: 10, withPad: " ", startingAt: 0))  \(r.probes.sorted().joined(separator: ","))"
                  + (r.afterInquiries > 0 || r.afterLooks > 0 ? "  after: inquiries \(r.afterInquiries) looks \(r.afterLooks)" : ""))
            if r.noticed != nil, r.watched != nil, r.approached != nil, r.touched != nil, r.climbed != nil, r.familiar != nil { full += 1 }
            if let n = r.noticed, n < 0.3 { instant += 1 }
            if r.afterInquiries > 0 { after += 1 }
            floating += r.floating
        }
        b.check("\(name): the whole loop (notice, watch, approach, touch, climb, familiar)", full >= (name == "Shy" || name == "Lazy" ? seeds / 2 : seeds - 1), "\(full)/\(seeds)")
        b.check("\(name): not noticed the instant it is put down", instant <= max(1, seeds * 2 / 5), "\(instant)/\(seeds) within 0.3 s")
        b.check("\(name): left be once familiar", after == 0, "\(after) runs looked into it again")
        b.check("\(name): never standing on nothing", floating == 0, "\(floating) times")
    }
}

// MARK: Decorating

private func decorCheck(_ b: inout Builder) {
    print("== decorating round it")
    let shy = Personality.presets.first { $0.name == "Shy" }!.p
    let curious = Personality.presets.first { $0.name == "Curious" }!.p
    let bold = Personality.presets.first { $0.name == "Show-off" }!.p

    // Something big put down right by it.
    for (name, p) in [("Shy", shy), ("Show-off", bold)] {
        var backed = 0, startled = 0
        for sd in 0..<6 {
            reseed(UInt64(300 + sd))
            var (h, tank, s) = knownTank(spiderAt: 700, personality: p)
            step(s, 3)
            guard s.isStanding else { continue }
            let x = s.worldPos.x + 95
            let big = h.add(.boulder, at: CGPoint(x: x, y: 0))
            rebuilt(h, tank, s)
            let d0 = near(s, big)
            var d1: CGFloat = d0, jumped = false
            var lastLine = ""
            var tt: CGFloat = 0
            step(s, 5) {
                tt += dt
                d1 = max(d1, near(s, big))
                if s.debugState.contains("startle") || s.isAirborne { jumped = true }
                let line = "\(s.debugState) | \(s.debugInquiry) | \(s.debugWalk)"
                if env["PC_TRACE"] == "2", line != lastLine { print(String(format: "      %.2f d %.0f x %.0f %@", Double(tt), Double(near(s, big)), Double(s.worldPos.x), line)) }
                lastLine = line
            }
            if d1 > d0 + 25 { backed += 1 }
            if jumped { startled += 1 }
            if env["PC_TRACE"] != nil { print(String(format: "    d %.0f → %.0f  %@  %@", Double(d0), Double(d1), s.debugState, s.debugInquiry)) }
        }
        print("  a boulder dropped by a \(name) one: backed off \(backed)/6, started \(startled)/6")
        if name == "Shy" { b.check("big thing by a timid one: it starts, and backs off to watch", backed >= 4 && startled >= 4, "\(backed)/6 backed off, \(startled)/6 started") }
        else { b.check("big thing by a bold one: less of a fright", startled <= 5, "\(startled)/6 started") }
    }

    // Something small put down near a curious one: it goes to see.
    var saw = 0
    for sd in 0..<6 {
        reseed(UInt64(400 + sd))
        var (h, tank, s) = knownTank(spiderAt: 700, personality: curious)
        step(s, 3)
        let small = h.add(.pineCone, at: CGPoint(x: s.worldPos.x + 110, y: 0))
        rebuilt(h, tank, s)
        var went = false
        var errands: [String] = [s.debugErrandKind ?? "-"]
        step(s, 40) {
            if s.debugInquiryUID == small.uid, near(s, small) < 40 { went = true }
            let k = s.debugErrandKind ?? "-"
            if k != errands.last { errands.append(k) }
        }
        if went { saw += 1 }
        if env["PC_TRACE"] != nil {
            print("    small \(sd): went \(went), noticed \(s.knowledge!.stage(of: small.uid)), errands \(errands.joined(separator: " > ")), now \(s.debugState) | \(s.debugInquiry)")
        }
    }
    b.check("small thing put down: a curious one goes to see it", saw >= 5, "\(saw)/6")

    // Something it knows, moved: it sees it go.
    var looked = 0
    for sd in 0..<6 {
        reseed(UInt64(500 + sd))
        var (h, tank, s) = knownTank(spiderAt: 700, personality: Personality(), extra: [(.log, 900)])
        step(s, 3)
        guard let i = h.items.firstIndex(where: { $0.kind == .log }) else { continue }
        if near(s, h.items[i]) > 380 { h.items[i].x = s.worldPos.x + 220; rebuilt(h, tank, s); step(s, 4) }
        h.items[i].x += 70
        let moved = h.items[i]
        rebuilt(h, tank, s)
        var saw = false
        step(s, 2.5) { if let e = s.debugEyeOn, moved.rect.insetBy(dx: -30, dy: -30).contains(e.point) { saw = true } }
        if saw { looked += 1 }
    }
    b.check("something it knows moved: it looks at it", looked >= 4, "\(looked)/6")

    // Carried off on what it stands on.
    for (label, how) in [("dragged about", 0), ("moved in one go", 1), ("taken away", 2)] {
        var ok = 0, detail: [String] = []
        for sd in 0..<5 {
            reseed(UInt64(600 + sd))
            var (h, tank, s) = knownTank(spiderAt: 700, personality: Personality(), extra: [(.stump, 700)])
            guard let si = h.items.firstIndex(where: { $0.kind == .stump }) else { continue }
            let stump = h.items[si]
            // On its top.
            guard let top = stump.interactionPoints(on: tank).first(where: { $0.kind == .top }), let a = top.stand else { continue }
            s.debugAttach(loopID: a.loopID, segIdx: a.segIdx, t: a.t, dir: 1)
            step(s, 0.4)
            guard s.debugUnderfoot == stump.id else { detail.append("not on it"); continue }
            let p0 = s.worldPos
            var worst: CGFloat = 0
            switch how {
            case 0:
                // Picked up and carried 240 across and 60 up, over two seconds.
                let d = V2(240, 60)
                for k in 1...120 {
                    let off = d * (CGFloat(k) / 120)
                    s.thingsCarried([stump.id: off])
                    s.setCursor(V2(-4000, -4000)); s.update(dt: dt)
                    worst = max(worst, abs((s.worldPos - p0 - off).x))
                }
                h.items[si].x += d.x
                h.items[si].y += d.y
                rebuilt(h, tank, s)
                step(s, 3)
                let rode = worst < 30 && s.debugUnderfoot == stump.id && footed(s, tank)
                if rode { ok += 1 } else { detail.append(String(format: "lag %.0f on %@ footed %@", Double(worst), "\(s.debugUnderfoot ?? -1)", "\(footed(s, tank))")) }
            case 1:
                h.items[si].x += 400
                rebuilt(h, tank, s)
                step(s, 2)
                if s.debugUnderfoot == stump.id, footed(s, tank), abs(s.worldPos.x - p0.x - 400) < 60 { ok += 1 } else { detail.append("at \(Int(s.worldPos.x - p0.x)) on \(s.debugUnderfoot ?? -1)") }
            default:
                h.items.remove(at: si)
                rebuilt(h, tank, s)
                var landed = false
                step(s, 4) { if s.isStanding, footed(s, tank) { landed = true } }
                if landed, s.worldPos.y < p0.y { ok += 1 } else { detail.append(s.debugState) }
            }
        }
        b.check("standing on something \(label): \(how == 2 ? "it drops, and lands" : "it goes with it")", ok >= 4, "\(ok)/5 " + detail.prefix(3).joined(separator: "; "))
    }

    // A rearrangement: out exploring after.
    var explored = 0
    for sd in 0..<4 {
        reseed(UInt64(700 + sd))
        var (h, tank, s) = knownTank(width: 4000, spiderAt: 2000, personality: Personality())
        step(s, 3)
        let fresh = Habitat.preset(.forestFloor, world: h.size)
        h = fresh
        rebuilt(h, tank, s)
        var exploring = false
        var noticed = 0
        step(s, 60) { if s.debugInquiry.hasPrefix("exploring") || s.debugInquiryUID != nil { exploring = true } }
        noticed = h.items.filter { s.knowledge!.stage(of: $0.uid) != .unknown }.count
        if exploring, noticed >= 3 { explored += 1 }
        print("  rearranged: exploring \(exploring), noticed \(noticed) of \(h.items.count) in a minute")
    }
    b.check("a rearrangement has it out exploring", explored >= 3, "\(explored)/4")
}

func curiousCheck() {
    var b = Builder()
    let parts = env["PC_PART"].map { Set($0.split(separator: ",").map(String.init)) }
    if parts?.contains("natures") ?? true { naturesCheck(&b) }
    if parts?.contains("places") ?? true { placesCheck(&b) }
    if parts?.contains("loop") ?? true { loopCheck(&b) }
    if parts?.contains("decor") ?? true { decorCheck(&b) }
    print(b.fails == 0 ? "all ok" : "\(b.fails) FAILED")
}
#endif
