import AppKit
Spider.debugGlideTally = true

// Headless behaviour check: run the spider against a synthetic desktop and
// report what it does. Catches "never lands", "falls forever", "jitters in
// place", "jumps every frame" without putting anything on screen.

let map = SurfaceMap()
map.standoff = 22 * 0.95
let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1728, height: 1117)
let windows = [
    TrackedWindow(id: 1, frame: CGRect(x: screen.minX + 180, y: screen.minY + 220,
                                       width: 760, height: 520), depth: 0, owner: "Editor"),
    TrackedWindow(id: 2, frame: CGRect(x: screen.minX + 700, y: screen.minY + 420,
                                       width: 620, height: 400), depth: 1, owner: "Browser"),
    TrackedWindow(id: 3, frame: CGRect(x: screen.maxX - 460, y: screen.minY + 120,
                                       width: 400, height: 300), depth: 2, owner: "Notes"),
]
map.rebuild(windows: windows)

print("world \(map.worldBounds)  loops: \(map.loops.count)")
/// Index of the floor segment of a screen loop (the border is a U under a
/// menu bar, a closed box without one).
func floorSeg(_ loop: SurfaceLoop) -> Int {
    loop.segs.firstIndex { $0.facing == .up } ?? 0
}
for l in map.loops {
    let blocked = l.segs.enumerated().flatMap { i, s in s.blocked.map { "seg\(i)[\(Int($0.lo))..\(Int($0.hi))]" } }
    print("  \(l.id.padding(toLength: 12, withPad: " ", startingAt: 0)) \(l.kind) segs=\(l.segs.count) perim=\(Int(l.perimeter)) depth=\(l.depth)"
          + (blocked.isEmpty ? "" : "  blocked: " + blocked.joined(separator: " ")))
}
let spots = map.sampleSpots(spacing: 40)
print("reachable spots: \(spots.count)")

let spider = Spider(map: map)
spider.config.liveliness = 3.0   // compress a long session into a short run
spider.config.scale = 0.95

var last = ""
var counts: [String: Int] = [:]
var transitions = 0
let dt: CGFloat = 1.0 / 60.0
var t: CGFloat = 0
var minY = CGFloat.greatestFiniteMagnitude
var offscreenFrames = 0
var stuckFrames = 0
var lastPos = spider.worldPos

// Park the cursor somewhere plausible and move it about a bit.
for step in 0..<(60 * 240) {   // 240 simulated seconds
    t += dt
    let cx = screen.midX + cos(Double(t) * 0.23) * 500
    let cy = screen.midY + sin(Double(t) * 0.17) * 320
    spider.setCursor(V2(CGFloat(cx), CGFloat(cy)))
    spider.update(dt: dt)

    let st = spider.debugState
    counts[String(st.split(separator: ":").first ?? "?"), default: 0] += 1
    if st != last {
        transitions += 1
        if transitions < 60 || step % 900 == 0 {
            print(String(format: "%7.2fs  %@", Double(t), st))
        }
        last = st
    }
    let p = spider.worldPos
    minY = min(minY, p.y)
    if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(p.point) { offscreenFrames += 1 }
    if p.distance(to: lastPos) < 0.02 { stuckFrames += 1 } else { stuckFrames = 0 }
    lastPos = p
    if stuckFrames > 60 * 20 {
        print("!! stuck at \(p.point) after \(Int(t))s in \(st)")
        break
    }
}

print("\n--- 240s summary ---")
print("state transitions: \(transitions)  (\(String(format: "%.1f", Double(transitions) / 240.0))/s)")
for (k, v) in counts.sorted(by: { $0.value > $1.value }) {
    print(String(format: "  %-10@ %5.1f%%", k as NSString, Double(v) / Double(60 * 240) * 100))
}
print("lowest y reached: \(Int(minY))  (world minY \(Int(map.worldBounds.minY)))")
print("frames off-world: \(offscreenFrames)")

// ---------------------------------------------------------------------------
// Scripted interaction tests
// ---------------------------------------------------------------------------

func settle(_ spider: Spider, seconds: CGFloat, cursor: V2? = nil) -> String {
    var n = 0
    while CGFloat(n) * dt < seconds {
        if let c = cursor { spider.setCursor(c) }
        spider.update(dt: dt)
        n += 1
    }
    return spider.debugState
}

func expect(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("  [\(ok ? "ok  " : "FAIL")] \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
}

print("\n--- interaction tests ---")
/// Runs until the spider is attached again, so tests never sample it mid-hop.
/// Runs on until it is holding something — a surface or a line — so a
/// check never lands on the instant it happens to be mid-jump.
func settleUntilHoldingSomething(_ spider: Spider, seconds: CGFloat, cursor: V2 = V2(-4000, -4000)) -> String {
    var elapsed: CGFloat = 0
    var last = spider.debugState
    while elapsed < seconds + 6 {
        spider.setCursor(cursor)
        spider.update(dt: dt)
        elapsed += dt
        last = spider.debugState
        if elapsed >= seconds, last.hasPrefix("attached") || last == "dangling" || last == "swinging" { return last }
    }
    return last
}

func settleUntilAttached(_ spider: Spider, limit: CGFloat = 20) -> String {
    var elapsed: CGFloat = 0
    while elapsed < limit {
        spider.setCursor(V2(-4000, -4000))
        spider.update(dt: dt)
        elapsed += dt
        if elapsed > 1, spider.debugState.hasPrefix("attached") { return spider.debugState }
    }
    return spider.debugState
}

let s2 = Spider(map: map)
expect("settles onto a surface", settleUntilAttached(s2).hasPrefix("attached"), s2.debugState)

// Pick up and flick it sideways.
var p = s2.worldPos
s2.beginGrab(at: p)
expect("grab takes hold", s2.debugState == "held", s2.debugState)
for i in 0..<18 {
    p += V2(26, 6)
    s2.setCursor(p)
    s2.moveGrab(to: p)
    s2.update(dt: dt)
    _ = i
}
expect("follows the pointer", s2.worldPos.distance(to: p) < 60,
       "gap \(Int(s2.worldPos.distance(to: p)))px")
s2.endGrab(throwVelocity: V2(1500, 260))
expect("release throws it", s2.debugState == "thrown", s2.debugState)
let after = settle(s2, seconds: 6, cursor: V2(-4000, -4000))
/// Runs on until it is holding on to something (a ledge or a line), so a
/// sample never lands mid-leap.
func settleUntilHolding(_ spider: Spider, seconds: CGFloat) -> String {
    var n = 0
    var st = spider.debugState
    while CGFloat(n) * dt < seconds {
        spider.setCursor(V2(-4000, -4000)); spider.update(dt: dt); n += 1
        st = spider.debugState
        if CGFloat(n) * dt > 2, st.hasPrefix("attached") || st == "dangling" || st == "swinging" { break }
    }
    return st
}
_ = after
let after1 = settleUntilHolding(s2, seconds: 8)
expect("a thrown spider ends up somewhere", after1.hasPrefix("attached") || after1 == "dangling" || after1 == "swinging", after1)

// Fling it hard upward: should bounce or catch itself on a line, not vanish.
s2.beginGrab(at: s2.worldPos)
s2.endGrab(throwVelocity: V2(-2400, 2200))
let after2 = settleUntilHolding(s2, seconds: 12)
expect("a hard throw recovers", after2.hasPrefix("attached") || after2 == "dangling" || after2 == "swinging", after2)
expect("stays inside the desktop", map.worldBounds.insetBy(dx: -40, dy: -40).contains(s2.worldPos.point),
       "\(s2.worldPos.point)")

// Rappel, then reel back in with the scroll wheel.
let s3 = Spider(map: map)
s3.config.webs = true
_ = settleUntilAttached(s3)
// Under the browser window, on the stretch with nothing but floor below it
// (its left part is over the editor window, which is in front).
if let l2 = map.loop("win:2"), let under = l2.segs.firstIndex(where: { $0.facing == .down }) {
    let seg = l2.segs[under]
    let want = V2(screen.minX + 1150, seg.a.y)
    // It may decide to leap or swing off in the moment it is given to
    // settle: put it back until it stays.
    for _ in 0..<5 {
        s3.debugAttach(loopID: "win:2", segIdx: under, t: (want - seg.a).dot(seg.dir), dir: 1)
        _ = settle(s3, seconds: 0.3, cursor: V2(-4000, -4000))
        if s3.debugState.hasPrefix("attached") { break }
    }
}
let yStart = s3.worldPos.y
s3.scroll(-4)
for _ in 0..<8 { s3.update(dt: dt) }
let dangled = s3.debugState
expect("scroll-down starts a rappel", dangled == "dangling", dangled)
if dangled == "dangling" {
    _ = settle(s3, seconds: 1.2)
    // It may have come down onto a window just below in the meantime.
    expect("it descends", s3.worldPos.y < yStart - (s3.debugState == "dangling" ? 25 : 10),
           "y \(Int(yStart)) -> \(Int(s3.worldPos.y))  [\(s3.debugState)]")
    if s3.debugState == "dangling" {
        let yLow = s3.worldPos.y
        for _ in 0..<60 { s3.scroll(6); s3.update(dt: dt) }
        if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil {
            var n = 0
            while CGFloat(n) * dt < 2 {
                s3.update(dt: dt); n += 1
                if n % 12 == 0 { let l = s3.debugLine; print("    t=\(String(format: "%.1f", CGFloat(n) * dt)) \(s3.debugState) y=\(Int(s3.worldPos.y)) len=\(Int(l.len)) target=\(Int(l.target)) \(l.style) pump=\(l.pumping) cursor=\(s3.debugCursorNear)") }
            }
        } else {
            _ = settle(s3, seconds: 2)
        }
        expect("scroll-up reels it in", s3.worldPos.y > yLow + 15,
               "y \(Int(yLow)) -> \(Int(s3.worldPos.y))  [\(s3.debugState)]")
    }
}

// On a line it means something: down, a while hanging, then home, the
// floor, a swing or a jump — never turning right round to the other side,
// and never hanging about forever.
do {
    var flips = 0
    var longest: CGFloat = 0
    var endings: Set<String> = []
    for trial in 0..<4 {
        let s = Spider(map: map)
        s.config.webs = true
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        if let l2 = map.loop("win:2"), let under = l2.segs.firstIndex(where: { $0.facing == .down }) {
            let seg = l2.segs[under]
            let want = V2(screen.minX + 1100 + CGFloat(trial) * 60, seg.a.y)
            s.debugAttach(loopID: "win:2", segIdx: under, t: (want - seg.a).dot(seg.dir), dir: 1)
            _ = settle(s, seconds: 0.5, cursor: V2(-4000, -4000))
        }
        s.scroll(-4)
        var n = 0
        var onLine: CGFloat = 0
        var lastFacing = s.pose().facing
        while CGFloat(n) * dt < 40 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if st == "dangling" {
                onLine += dt
                let f = s.pose().facing
                if (f >= 0) != (lastFacing >= 0) { flips += 1 }
                lastFacing = f
            } else if onLine > 0.5 {
                endings.insert(st.hasPrefix("attached") ? "landed" : String(st.split(separator: " ").first ?? ""))
                longest = max(longest, onLine)
                break
            }
        }
        if s.debugState == "dangling" { longest = max(longest, onLine) }
    }
    expect("on a line: never turns right round", flips == 0, "\(flips) side changes")
    expect("on a line: gets on with it", longest < 40, String(format: "longest hang %.0fs, ended by %@", longest, endings.sorted().joined(separator: ",")))
}

// A window opening over it: it must get out from under at once — up a
// line to the ceiling or by dropping — and never sit frozen beneath it.
do {
    for trial in 0..<2 {
        let s = Spider(map: map)
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        // On the floor (a drop is no use there, so it goes up) and then on a
        // window's shelf (where either will do).
        if trial == 0 {
            if let sl = map.loops.first(where: { $0.id.hasPrefix("screen") }) {
                s.debugAttach(loopID: sl.id, segIdx: floorSeg(sl), t: 500, dir: 1)
            }
        } else if let w = windows.first {
            s.debugAttach(loopID: "win:\(w.id)", segIdx: 0, t: 120, dir: 1)
        }
        for _ in 0..<20 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
        let p = s.worldPos
        let cover = CGRect(x: p.x - 160, y: p.y - 120, width: 320, height: 240)
        map.rebuild(windows: windows + [TrackedWindow(id: 777, frame: cover, depth: -1, owner: "Mock")])
        // An escape is immediate; note what it is doing a moment later.
        for _ in 0..<12 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
        let moment = s.debugState
        var seen: [String] = []
        var n = 0
        var out = -1.0
        while CGFloat(n) * dt < 10 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if seen.last != st { seen.append(st) }
            if out < 0, !cover.insetBy(dx: -10, dy: -10).contains(s.worldPos.point) { out = Double(n) * Double(dt) }
        }
        if trial == 0 {
            // The screen's rim is always its to walk: it draws above the
            // window, so it just carries on there, unbothered.
            let end = s.debugState
            // (It may still wander off in its own time — a swing is its own
            // idea, not an escape — so only the first few seconds count.)
            // (It may already have been mid-swing or mid-leap of its own accord.)
            let flee = moment.contains(":shoot") || moment == "fall"
            expect("covered on the floor: carries on along the rim", !flee, moment + "  then " + seen.prefix(4).joined(separator: " > "))
        } else {
            expect("covered on the shelf: gets clear quickly", out >= 0 && out < 2.5,
                   out < 0 ? "never left  " + seen.joined(separator: " > ") : String(format: "%.1fs  ", out) + seen.prefix(6).joined(separator: " > "))
            let end = s.debugState
            expect("covered on the shelf: ends up clear of it", !cover.contains(s.worldPos.point), end)
        }
        map.rebuild(windows: windows)
    }
}

// Feeding: each kind of prey gets hunted down and eaten, and it cheers up —
// except a ladybug, which is tasted, spat out, and then left alone.
for kind in PreyKind.allCases {
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    let p = s.release(kind)
    var caughtAt = -1.0
    var eatenAt = -1.0
    var spatAt = -1.0
    var recaught = 0
    var seen: [String] = []
    var n = 0
    var off = 0
    let limit: CGFloat = kind.flies || kind.bitter ? 150 : 90
    while CGFloat(n) * dt < limit {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        if seen.last != st { seen.append(st) }
        if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(s.worldPos.point) { off += 1 }
        if !p.leaving, !map.worldBounds.insetBy(dx: -60, dy: -60).contains(p.pos.point) { off += 1 }
        if caughtAt < 0, p.state != .loose { caughtAt = Double(n) * Double(dt) }
        if caughtAt >= 0, spatAt < 0, p.state == .loose { spatAt = Double(n) * Double(dt) }
        if spatAt >= 0, p.state == .caught { recaught += 1 }
        if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil, n % (kind == .ant ? 30 : 120) == 0 {
            print("    \(kind.label) t=\(n / 60)s \(st) spider=\(Int(s.worldPos.x)),\(Int(s.worldPos.y)) prey=\(Int(p.pos.x)),\(Int(p.pos.y)) on=\(p.anchor?.loopID ?? "air") \(p.state)\(p.tucked ? " tucked" : "")\(p.flying ? " flying" : "") fear \(String(format: "%.2f", p.fear)) travel \(Int(p.travel.x)),\(Int(p.travel.y))")
        }
        if p.state == .eaten { eatenAt = Double(n) * Double(dt); break }
        if spatAt >= 0, Double(n) * Double(dt) > spatAt + 20 { break }
    }
    let tail = seen.suffix(5).joined(separator: " > ")
    expect("\(kind.label): catches it", caughtAt >= 0, caughtAt < 0 ? "never  " + tail : String(format: "%.0fs", caughtAt))
    if kind.bitter {
        expect("\(kind.label): spits it out", spatAt >= 0 && p.spurned, "state \(p.state)")
        expect("\(kind.label): and leaves it be", recaught == 0, "caught again \(recaught) frames")
    } else {
        expect("\(kind.label): eats it", eatenAt >= 0, String(format: "%.0fs  ", eatenAt) + tail)
        expect("\(kind.label): well fed afterwards", s.fed > 0.2, "fed \(s.fed)")
    }
    expect("\(kind.label): both stay on the desktop", off == 0, "off \(off)")
}

// The creatures themselves, each on its own, with a make-believe spider.
do {
    let far = V2(-3000, -3000)
    func run(_ p: Prey, _ secs: CGFloat, spider: (CGFloat) -> V2 = { _ in V2(-3000, -3000) }, cursor: V2? = nil,
             each: (CGFloat) -> Void = { _ in }) {
        var tt: CGFloat = 0
        while tt < secs {
            tt += dt
            p.update(dt: dt, t: tt, map: map, spider: spider(tt), cursor: cursor)
            each(tt)
        }
    }
    func top(_ id: String) -> (Int, Seg)? {
        guard let l = map.loop(id), let i = l.segs.firstIndex(where: { $0.facing == .up }) else { return nil }
        return (i, l.segs[i])
    }
    // An ant goes round the corner and down the side of a window.
    if let (i, seg) = top("win:3") {
        let ant = Prey(kind: .ant, id: 900, at: .zero, scale: 0.95)
        ant.emerge(on: Anchor(loopID: "win:3", segIdx: i, t: seg.len - 40), dir: 1, map: map)
        var sides = Set<Int>()
        var lowest = ant.pos.y
        run(ant, 12, each: { _ in
            if let a = ant.anchor { sides.insert(a.segIdx) }
            lowest = min(lowest, ant.pos.y)
        })
        expect("ant: walks round corners onto the sides", sides.count >= 2, "segs \(sides.sorted())")
        expect("ant: and down them", lowest < seg.a.y - 60, "lowest \(Int(lowest)) top \(Int(seg.a.y))")
        expect("ant: still on the window", ant.anchor?.loopID == "win:3", "\(ant.anchor?.loopID ?? "air")")
    }
    // A ladybug put low on a wall climbs it, and before long flies.
    if let l = map.loop("win:3"), let si = l.segs.firstIndex(where: { $0.facing == .right }) {
        let bug = Prey(kind: .ladybug, id: 901, at: .zero, scale: 0.95)
        let seg = l.segs[si]
        let lowT = seg.dir.y > 0 ? CGFloat(30) : seg.len - 30
        bug.emerge(on: Anchor(loopID: "win:3", segIdx: si, t: lowT), dir: seg.dir.y > 0 ? -1 : 1, map: map)
        let startY = bug.pos.y
        var highest = startY
        var flew = -1.0
        run(bug, 120, each: { tt in
            highest = max(highest, bug.pos.y)
            if flew < 0, bug.flying { flew = Double(tt) }
            if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil, Int(tt * 60) % 60 == 0 {
                print("    ladybug t=\(Int(tt)) \(Int(bug.pos.x)),\(Int(bug.pos.y)) on \(bug.anchor.map { "\($0.loopID)#\($0.segIdx)" } ?? "air") flying \(bug.flying)")
            }
        })
        expect("ladybug: climbs up the wall", highest > startY + 120, "from \(Int(startY)) to \(Int(highest))")
        expect("ladybug: flies off from the top", flew >= 0, flew < 0 ? "never" : String(format: "%.0fs", flew))
    }
    // A beetle rushed at shuts itself up; left in peace, it comes out.
    if let (i, seg) = top("screen:0") {
        let beetle = Prey(kind: .beetle, id: 902, at: .zero, scale: 0.95)
        beetle.emerge(on: Anchor(loopID: "screen:0", segIdx: i, t: seg.len / 2), dir: 1, map: map)
        run(beetle, 2)
        let home = beetle.pos
        var tuckedAt = -1.0
        run(beetle, 6, spider: { tt in home + V2(300 - tt * 70, 20) }, each: { tt in
            if tuckedAt < 0, beetle.tucked { tuckedAt = Double(tt) }
        })
        expect("beetle: walked right past, it tucks in", tuckedAt >= 0, "fear \(beetle.fear)")
        let still = home + V2(60, 20)
        var outAt = -1.0
        run(beetle, 15, spider: { _ in still }, each: { tt in
            if outAt < 0, !beetle.tucked { outAt = Double(tt) }
        })
        expect("beetle: with the spider keeping still, it comes out", outAt >= 0, "fear \(beetle.fear)")
        let sneaky = Prey(kind: .beetle, id: 903, at: .zero, scale: 0.95)
        sneaky.emerge(on: Anchor(loopID: "screen:0", segIdx: i, t: seg.len / 2), dir: 1, map: map)
        run(sneaky, 2)
        let spot = sneaky.pos
        var sneakTucked = false
        run(sneaky, 9, spider: { tt in spot + V2(max(40, 300 - tt * 25), 20) }, each: { _ in if sneaky.tucked { sneakTucked = true } })
        expect("beetle: a sneak up on it goes unnoticed", !sneakTucked)
    }
    // A mosquito hangs about the pointer, now hovering, now darting.
    do {
        let c = V2(screen.midX, screen.midY)
        let m = Prey(kind: .mosquito, id: 904, at: c + V2(300, 100), scale: 0.95)
        var hover = 0, frames = 0
        var dsum: CGFloat = 0
        var jumps = 0
        var last = m.pos
        run(m, 30, cursor: c, each: { tt in
            if m.pos.distance(to: last) > 12 { jumps += 1 }
            last = m.pos
            guard tt > 5 else { return }
            frames += 1
            if m.hovering { hover += 1 }
            dsum += m.pos.distance(to: c)
        })
        let h = Double(hover) / Double(frames) * 100
        expect("mosquito: spends a good part of its time hovering", h > 25 && h < 95, String(format: "%.0f%%", h))
        expect("mosquito: keeps near the pointer", dsum / CGFloat(frames) < 160, "mean \(Int(dsum / CGFloat(frames)))")
        expect("mosquito: never teleports", jumps == 0, "\(jumps) jumps")
    }
    // A moth circles the pointer like a lamp.
    do {
        let c = V2(screen.midX, screen.midY + 100)
        let moth = Prey(kind: .moth, id: 905, at: c + V2(-220, -40), scale: 0.95)
        var dsum: CGFloat = 0, frames = 0
        run(moth, 14, cursor: c, each: { tt in
            guard tt > 6 else { return }
            frames += 1
            dsum += moth.pos.distance(to: c)
        })
        expect("moth: drawn to the pointer", dsum / CGFloat(frames) < 110, "mean \(Int(dsum / CGFloat(frames)))")
        let alone = Prey(kind: .moth, id: 906, at: c, scale: 0.95)
        var perched = -1.0
        run(alone, 30, each: { tt in if perched < 0, alone.onSurface { perched = Double(tt) } })
        expect("moth: with no lamp about, settles somewhere", perched >= 0)
    }
    // Things that wandered in go again in their own time.
    for kind in [PreyKind.moth, .ant, .beetle, .cricket] {
        let s = Spider(map: map)
        let p = Prey(kind: kind, id: 907, at: V2(screen.midX, screen.midY), scale: 0.95)
        if !kind.flies, let (i, seg) = top("screen:0") {
            p.emerge(on: Anchor(loopID: "screen:0", segIdx: i, t: seg.len / 3), dir: 1, map: map)
        }
        p.leaveAge = 3
        var goneAt = -1.0
        run(p, 30, each: { tt in if goneAt < 0, p.gone { goneAt = Double(tt) } })
        _ = s
        expect("\(kind.label): wandered in, leaves again", goneAt >= 0, "alpha \(p.alpha) at \(Int(p.pos.x)),\(Int(p.pos.y))")
    }
    _ = far
}

// Wandering in: every kind turns up somewhere sensible, unnoticed, and none
// of them outstays its welcome.
do {
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    var kinds: [PreyKind: Int] = [:]
    var badSpawn = 0
    let probe = Spider(map: map)
    _ = settleUntilAttached(probe)
    for _ in 0..<200 {
        for p in probe.releaseWild(night: chance(0.5), raining: chance(0.2)) {
            kinds[p.kind, default: 0] += 1
            if p.noticed || !p.wild { badSpawn += 1 }
            if !map.worldBounds.insetBy(dx: -40, dy: -40).contains(p.pos.point) { badSpawn += 1 }
            if !p.kind.flies, p.anchor == nil { badSpawn += 1 }
        }
    }
    print("  wandering in, 200 tries: " + PreyKind.allCases.map { "\($0.label) \(kinds[$0] ?? 0)" }.joined(separator: ", "))
    expect("wandering in: every kind turns up", kinds.count == PreyKind.allCases.count)
    expect("wandering in: unnoticed, and somewhere sensible", badSpawn == 0, "\(badSpawn)")
    var released = 0
    var eaten = 0
    var off = 0
    for _ in 0..<3 { released += s.releaseWild(night: false, raining: false).count }
    let mine = s.prey.map { $0 }
    var n = 0
    while CGFloat(n) * dt < 280 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        for p in mine where !p.leaving && !map.worldBounds.insetBy(dx: -60, dy: -60).contains(p.pos.point) { off += 1 }
    }
    eaten = mine.filter { $0.state == .eaten }.count
    let left = s.prey.filter { $0.state == .loose }.count
    print("  \(released) wandered in: \(eaten) eaten, \(mine.filter { $0.gone }.count) went off, \(left) still about")
    expect("wandering in: none of them stay for good", left == 0, "\(left) left")
    expect("wandering in: all stay on the desktop", off == 0, "\(off)")
}

// Picking prey up and dropping it elsewhere: it lands, and gets hunted anew.
do {
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    let p = s.release(.cricket)
    for _ in 0..<6 { s.update(dt: dt) }
    let from = p.pos
    s.beginPreyGrab(p, at: from)
    for i in 0..<30 { s.movePreyGrab(p, to: from + V2(CGFloat(i) * 8, CGFloat(i) * 3)); s.update(dt: dt) }
    expect("held prey follows the pointer", p.pos.distance(to: from + V2(232, 87)) < 2, "\(p.pos)")
    s.endPreyGrab(p, throwVelocity: V2(300, 200))
    var n = 0
    while CGFloat(n) * dt < 6, !p.onSurface { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1 }
    expect("dropped prey lands on something", p.onSurface, "\(p.pos) state \(p.state)")
    expect("dropped prey stays on the desktop", map.worldBounds.contains(p.pos.point), "\(p.pos)")
}

// A window sitting just above the floor: from under it, it must be able to
// get down to the floor (a short drop) rather than dither.
do {
    let low = SurfaceMap()
    low.standoff = map.standoff
    let lowWin = TrackedWindow(id: 5, frame: CGRect(x: screen.minX + 400, y: screen.minY + 58, width: 500, height: 300), depth: 0, owner: "Low")
    low.debugRebuild(screen: screen, menuBarHeight: 25, windows: [lowWin])
    var reached = -1.0
    var stuck = 0.0
    var seen: [String] = []
    for trial in 0..<3 {
        let s = Spider(map: low)
        s.config.followCursor = false
        s.debugAttach(loopID: "win:5", segIdx: 2, t: 120 + CGFloat(trial) * 100, dir: 1)   // the underside
        var n = 0
        var lastPos = s.worldPos
        var still = 0.0
        while CGFloat(n) * dt < 40 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if seen.last != st { seen.append(st) }
            if s.worldPos.distance(to: lastPos) < 0.3 { still += Double(dt) } else { still = 0; lastPos = s.worldPos }
            stuck = max(stuck, still)
            if st.contains("screen:0") { reached = Double(n) * Double(dt); break }
        }
        if reached >= 0 { break }
    }
    expect("gets down from a window just above the floor", reached >= 0, reached < 0 ? "never  " + seen.suffix(8).joined(separator: " > ") : String(format: "%.0fs", reached))
    expect("never freezes under it", stuck < 12, String(format: "still for %.0fs", stuck))
}

// Teleport: from any state, it is put in the middle and comes down on
// something, holding nothing.
do {
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    // Get it onto a line and hunting, then rescue it from all of that.
    let p = s.release(.worm)
    s.scroll(-4); for _ in 0..<40 { s.update(dt: dt) }
    let before = s.debugState
    s.teleport(to: V2(screen.midX, screen.midY))
    expect("teleport puts it in the air at the middle", s.debugState == "fall" && s.worldPos.distance(to: V2(screen.midX, screen.midY)) < 1, "\(s.debugState) from \(before)")
    let after = settleUntilHoldingSomething(s, seconds: 6)
    expect("and it comes down on something", after.hasPrefix("attached") || after == "dangling" || after == "swinging", after)
    expect("prey is still loose afterwards", p.state == .loose, "\(p.state)")
}

// An unfinished hammock is never left hanging about: abandon the build and
// the threads go; a wipe clears a half-made one at once.
do {
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    s.debugActivity("build", for: 0)
    expect("starting a build stakes out the corner", s.hasAnyHammock, "")
    // Thrown across the room on the way, it keeps the plan; called off
    // (a video goes full screen), the threads go.
    s.beginGrab(at: s.worldPos)
    s.endGrab(throwVelocity: V2(-900, 500))
    _ = settle(s, seconds: 3, cursor: V2(-4000, -4000))
    expect("a thrown builder keeps its plan", s.hasAnyHammock, "\(s.debugState)")
    s.fullScreenApp = true
    _ = settle(s, seconds: 1, cursor: V2(-4000, -4000))
    s.fullScreenApp = false
    expect("an abandoned build leaves nothing behind", !s.hasAnyHammock, "\(s.debugState)")

    // A half-made one under the pointer goes with a wipe.
    let s2 = Spider(map: map)
    s2.config.followCursor = false
    _ = settleUntilAttached(s2)
    s2.debugActivity("build", for: 0)
    var n = 0
    while CGFloat(n) * dt < 60, s2.debugState != "building" { s2.setCursor(V2(-4000, -4000)); s2.update(dt: dt); n += 1 }
    if s2.debugState == "building", let h = s2.hammock {
        _ = settle(s2, seconds: 2)
        let c = V2(h.rect.midX, h.rect.midY)
        for i in 0..<20 { s2.wipeHammock(at: c + V2(CGFloat(i) * 3, 0), movement: 8); s2.update(dt: dt) }
        expect("a wipe clears a half-made hammock", !s2.hasAnyHammock, "\(s2.debugState) progress \(s2.hammock?.progress ?? -1)")
    } else {
        print("  [skip] never started building in time")
    }
}

// The box: its patch. Around a window it climbs about inside and takes
// things easy; thrown out, it comes back; freed, it goes back to normal.
// Around nothing, it hangs from the top on a line and sways.
do {
    let w = windows[2]   // Notes, bottom right
    let box = w.frame.insetBy(dx: -140, dy: -120)
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    s.confine = box
    var n = 0
    var out = 0
    var counts: [String: Int] = [:]
    var wild = 0
    var outRun = 0, longestOut = 0
    while CGFloat(n) * dt < 150 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if CGFloat(n) * dt > 20, !box.insetBy(dx: -30, dy: -30).contains(s.worldPos.point) { out += 1; outRun += 1 } else { outRun = 0 }
        longestOut = max(longestOut, outRun)
        let st = s.debugState
        if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil, n % 60 == 0 { print("    box t=\(n / 60) \(st) at \(Int(s.worldPos.x)),\(Int(s.worldPos.y)) box=\(box)") }
        counts[String(st.split(separator: " ").first ?? ""), default: 0] += 1
        if st == "swinging" { wild += 1 }
    }
    let top = counts.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value * 100 / n)%" }.joined(separator: ", ")
    expect("boxed: keeps to its patch", out < n * 25 / 100 && longestOut < 60 * 30,
           "out \(out * 100 / n)% of the time, longest \(longestOut / 60)s  " + top)
    expect("boxed: no swinging", wild == 0, "\(wild) frames")
    let restful = (counts["attached:rest"] ?? 0) + (counts["attached:idle"] ?? 0) + (counts["attached:sleep"] ?? 0) + (counts["attached:look"] ?? 0)
    expect("boxed: takes it easy", restful > n / 4, "\(restful * 100 / n)% restful  " + top)

    // Thrown right out of it: makes its own way back.
    s.beginGrab(at: s.worldPos)
    s.endGrab(throwVelocity: V2(-1400, 600))
    var back = -1.0
    n = 0
    while CGFloat(n) * dt < 60, back < 0 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if CGFloat(n) * dt > 3, box.contains(s.worldPos.point), s.debugState.hasPrefix("attached") { back = Double(n) * Double(dt) }
    }
    expect("thrown out of its box, it comes back", back >= 0, back < 0 ? "still out: \(s.debugState) at \(s.worldPos)" : String(format: "back in %.0fs", back))

    // Freed: it wanders off again and behaves as usual.
    s.confine = nil
    var left = -1.0
    n = 0
    while CGFloat(n) * dt < 300, left < 0 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if !box.contains(s.worldPos.point) { left = Double(n) * Double(dt) }
    }
    expect("freed, it goes back to its usual ways", left >= 0, left < 0 ? "never left the old box: \(s.debugState)" : String(format: "left after %.0fs", left))

    // Nothing inside.
    let empty = CGRect(x: screen.minX + 250, y: screen.minY + 772, width: 350, height: 120)
    expect("an empty box has nothing to stand on", !map.sampleSpots(spacing: 30).contains { empty.contains($0.point.point) }, "")
    let s2 = Spider(map: map)
    s2.config.followCursor = false
    _ = settleUntilAttached(s2)
    s2.confine = empty
    n = 0
    var hanging = 0
    var xs: [CGFloat] = []
    var out2 = 0
    while CGFloat(n) * dt < 90 {
        s2.setCursor(V2(-4000, -4000)); s2.update(dt: dt); n += 1
        if CGFloat(n) * dt > 10 {
            if s2.debugState == "dangling" { hanging += 1 }
            if !empty.insetBy(dx: -30, dy: -30).contains(s2.worldPos.point) { out2 += 1 }
            xs.append(s2.worldPos.x)
        }
    }
    let spread = (xs.max() ?? 0) - (xs.min() ?? 0)
    expect("empty box: hangs on a line", hanging > n * 80 / 100, "\(hanging * 100 / n)% hanging, now \(s2.debugState)")
    expect("empty box: a light sway, not a swing", spread > 4 && spread < 90, "sways over \(Int(spread)) px")
    expect("empty box: stays inside", out2 == 0, "out \(out2) frames")
    s2.confine = nil
}

// A window overlapping the edge of the screen: the rim is still its to walk.
do {
    let rim = SurfaceMap()
    rim.standoff = map.standoff
    let over = TrackedWindow(id: 8, frame: CGRect(x: screen.minX + 500, y: screen.minY - 80, width: 400, height: 300), depth: 0, owner: "Overlap")
    rim.rebuild(windows: [over])
    let floor = rim.loops.first { $0.id.hasPrefix("screen") }
    let blocked = floor?.segs.flatMap { $0.blocked }.count ?? -1
    expect("a window over the screen edge does not block it", blocked == 0, "\(blocked) blocked stretches")
    let s = Spider(map: rim)
    s.config.followCursor = false
    if let f = floor { s.debugAttach(loopID: f.id, segIdx: floorSeg(f), t: 300, dir: 1) }
    s.debugWalk(for: 30)
    var n = 0
    var crossed = false
    var fell = false
    while CGFloat(n) * dt < 30 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if s.worldPos.x > over.frame.midX, s.debugState.contains("screen:0") { crossed = true }
        if s.debugState == "fall" { fell = true }
    }
    expect("it walks the rim right across the overlapping window", crossed && !fell, "crossed \(crossed), fell \(fell), now \(s.debugState) at \(Int(s.worldPos.x))")
}

// Peek-a-boo: standing on a window with another window over part of its
// top edge and someone about, it hides behind that window's edge and pops
// out, more than once. (On the screen's own rim it is never behind
// anything — the desktop edge is in front of every window — so the game
// is a window-on-window one.)
do {
    let pm = SurfaceMap()
    pm.standoff = map.standoff
    let back = TrackedWindow(id: 7, frame: CGRect(x: screen.minX + 200, y: screen.minY + 200, width: 900, height: 300), depth: 1, owner: "Back")
    let over = TrackedWindow(id: 8, frame: CGRect(x: screen.minX + 700, y: screen.minY + 150, width: 400, height: 500), depth: 0, owner: "Overlap")
    pm.rebuild(windows: [back, over])
    let s = Spider(map: pm)
    s.config.followCursor = true
    s.debugAttach(loopID: "win:7", segIdx: 0, t: 300, dir: 1)   // the back window's top shelf
    for _ in 0..<20 { s.setCursor(V2(screen.minX + 350, screen.minY + 100)); s.update(dt: dt) }
    s.playPeekaboo()
    var n = 0
    var hiddenFrames = 0, shownFrames = 0, pops = 0
    var wasHidden = false
    var played = false
    while CGFloat(n) * dt < 40 {
        s.setCursor(V2(screen.minX + 350, screen.minY + 100)); s.update(dt: dt); n += 1
        let st = s.debugState
        if st.contains(":peekaboo") { played = true }
        let hidden = s.pose().hiddenBy.contains { $0.contains(s.worldPos.point) }
        if hidden { hiddenFrames += 1 } else { shownFrames += 1 }
        if wasHidden && !hidden { pops += 1 }
        wasHidden = hidden
        if played, !st.contains(":peekaboo"), CGFloat(n) * dt > 5 { break }
    }
    expect("peek-a-boo: plays when asked", played, s.debugState)
    expect("peek-a-boo: hides behind the window and pops out again", hiddenFrames > 30 && pops >= 2, "hidden \(hiddenFrames) frames, popped out \(pops) times")
    expect("peek-a-boo: ends up out in the open", !(s.pose().hiddenBy.contains { $0.contains(s.worldPos.point) }), s.debugState)
}

// The laser dot: it races to it wherever it is put, and pounces on it.
do {
    let s = Spider(map: map)
    s.config.followCursor = true
    _ = settleUntilAttached(s)
    // On top of the Editor window, well away from wherever it is.
    let w = windows[0]
    var dot = V2(w.frame.midX, w.frame.maxY + map.standoff)
    if s.worldPos.distance(to: dot) < 200 { dot = V2(windows[1].frame.midX, windows[1].frame.maxY + map.standoff) }
    s.laser = dot
    var n = 0
    var reachedAt = -1.0
    var pounced = false
    while CGFloat(n) * dt < 30 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if reachedAt < 0, s.worldPos.distance(to: dot) < 40 { reachedAt = Double(n) * Double(dt) }
        if reachedAt >= 0, s.debugState.contains(":hop") || s.debugState.contains(":peer") { pounced = true }
        if pounced, CGFloat(n) * dt > reachedAt + 3 { break }
    }
    expect("laser: races to the dot", reachedAt >= 0, reachedAt < 0 ? "never, now \(s.debugState) at \(s.worldPos) dot \(dot)" : String(format: "%.0fs", reachedAt))
    expect("laser: pounces on it", pounced, s.debugState)
    // Moved along the same window: follows.
    let dot2 = dot + V2(200, 0)
    s.laser = dot2
    n = 0
    var followed = false
    while CGFloat(n) * dt < 12, !followed {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if s.worldPos.distance(to: dot2) < 40 { followed = true }
    }
    expect("laser: follows when it moves", followed, "\(Int(CGFloat(n) * dt))s, \(s.debugState)")
    s.laser = nil
    let after = settle(s, seconds: 0.5)
    expect("laser: puzzled when it vanishes", after.contains(":look"), after)
}

// A quick swipe of the pointer near it gets no start out of it: no hop,
// no "!", no startle, and it does not run off.
do {
    let s = Spider(map: map)
    s.config.followCursor = true
    _ = settleUntilAttached(s)
    s.debugActivity("look", for: 4)
    _ = settle(s, seconds: 0.5, cursor: V2(-4000, -4000))
    let p = s.worldPos
    // A fast swipe past, 80 px off.
    var n = 0
    var jumped = false
    var exclaimed = false
    while CGFloat(n) * dt < 1.0 {
        let x = p.x - 200 + CGFloat(n) * 40          // 2400 px/s
        s.setCursor(V2(x, p.y + 80)); s.update(dt: dt); n += 1
        if s.debugState.contains(":hop") || s.debugState.contains(":startle") { jumped = true }
        if [.exclaim, .surprise].contains(s.pose().emote) { exclaimed = true }
    }
    expect("a quick swipe nearby: no hop or startle", !jumped, s.debugState)
    expect("a quick swipe nearby: no exclamation marks", !exclaimed, "")
    let after = settle(s, seconds: 0.5, cursor: V2(-4000, -4000))
    expect("a quick swipe nearby: it stays put", s.worldPos.distance(to: p) < 40 && !after.contains(":scurry"), "\(Int(s.worldPos.distance(to: p))) px away, \(after)")
}

// Sleepy and on the floor, it goes up onto a window to sleep, Z's rising.
do {
    let s = Spider(map: map)
    s.config.followCursor = false
    var lazy = s.personality; lazy.laziness = 1; lazy.energy = 0.2
    s.apply(design: SpiderDesign(name: "S", look: SpiderLook(), personality: lazy, gait: s.gait))
    // On the right wall of the Browser window: its top is round the corner.
    s.debugAttach(loopID: "win:2", segIdx: 1, t: 150, dir: 1)
    for _ in 0..<20 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
    s.debugActivity("bed", for: 0)
    var n = 0
    var sleptOnWindow = -1.0
    var zs = false
    while CGFloat(n) * dt < 90, sleptOnWindow < 0 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil, n % 60 == 0 { print("    bed t=\(n / 60) \(st) at \(Int(s.worldPos.x)),\(Int(s.worldPos.y))") }
        if st.contains(":sleep on win:") {
            sleptOnWindow = Double(n) * Double(dt)
            for _ in 0..<120 { s.update(dt: dt); if s.pose().emote == .zzz { zs = true } }
        }
    }
    expect("sleepy: beds down on top of a window", sleptOnWindow >= 0, sleptOnWindow < 0 ? "never, now \(s.debugState)" : String(format: "after %.0fs", sleptOnWindow))
    expect("sleepy: Z's rise from it", zs || sleptOnWindow < 0, "")
}

// The habitat: it lives on the furniture of a tank, never leaving it.
do {
    let tank = SurfaceMap()
    tank.standoff = map.standoff
    let scene = CGRect(x: 0, y: 0, width: 900, height: 540)
    let hab = Habitat.preset(.forestFloor)
    let built = hab.surfaces(in: scene, standoff: tank.standoff)
    tank.rebuild(habitat: built.air, loops: built.loops)
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    s.enter(map: tank, at: V2(scene.midX, scene.midY), habitat: true)
    var n = 0
    var out = 0
    var loops: Set<String> = []
    var counts: [String: Int] = [:]
    while CGFloat(n) * dt < 180 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        if !scene.insetBy(dx: -30, dy: -30).contains(s.worldPos.point) { out += 1 }
        let st = s.debugState
        if let on = st.split(separator: " ").last, st.contains(" on ") { loops.insert(String(on)) }
        counts[String(st.split(separator: " ").first ?? ""), default: 0] += 1
    }
    let top = counts.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value * 100 / n)%" }.joined(separator: ", ")
    expect("habitat: stays in the tank", out == 0, "out \(out) frames  " + top)
    expect("habitat: climbs about on the furniture", loops.filter { $0.hasPrefix("item:") }.count >= 2, loops.sorted().joined(separator: ","))
    // Home again: the same spider, back on the desktop.
    let fedBefore = s.fed
    s.enter(map: map, at: V2(screen.midX, screen.maxY - 80), habitat: false)
    let back = settleUntilAttached(s)
    expect("habitat: comes back to the desktop", back.hasPrefix("attached") && s.fed == fedBefore, back)
}

// A line hung at the very edge of the screen must not jitter at the bottom
// of the swing: the pendulum reverses a few times a second, not every frame.
do {
    // A gentle swing: fast enough to be a swing, too slow to grab the wall
    // as it passes.
    for (name, anchorX) in [("at the edge", screen.minX + 20), ("well inside", screen.midX)] {
        let s = Spider(map: map)
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        s.debugHang(at: V2(anchorX, screen.maxY - 60), length: 260, swing: true, kick: 0.4)
        var n = 0
        var flips = 0
        var lastSign: CGFloat = 0
        var lastX = s.worldPos.x
        var onLine = 0
        while CGFloat(n) * dt < 6 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let dx = s.worldPos.x - lastX
            lastX = s.worldPos.x
            // Only the time spent hanging counts; once it lets go and walks
            // off, direction changes are just it wandering.
            if ProcessInfo.processInfo.environment["SIM_TRACE"] != nil, n % 3 == 0 {
                print(String(format: "%5.2f x=%7.1f ang=%6.3f vel=%6.3f %@", CGFloat(n) * dt, s.worldPos.x, s.debugSwing.angle, s.debugSwing.angVel, s.debugState))
            }
            guard s.isOnLine else { lastSign = 0; continue }
            onLine += 1
            let sign: CGFloat = dx > 0.05 ? 1 : (dx < -0.05 ? -1 : 0)
            if sign != 0, lastSign != 0, sign != lastSign { flips += 1 }
            if sign != 0 { lastSign = sign }
        }
        let perSec = CGFloat(flips) / max(0.5, CGFloat(onLine) * dt)
        expect("swinging \(name): reverses only at the ends of the arc", perSec < 2.5, "\(flips) direction changes in \(Int(CGFloat(onLine) * dt))s on the line, now \(s.debugState)")
    }
}

// A window closing under its feet.
let s4 = Spider(map: map)
_ = settleUntilAttached(s4)
var tries = 0
while !s4.debugState.contains("win:") && tries < 40 { _ = settle(s4, seconds: 2); tries += 1 }
if s4.debugState.contains("win:") {
    map.rebuild(windows: [])
    let dropped = settle(s4, seconds: 0.3)
    expect("falls when its window closes", dropped == "fall" || dropped == "dangling", dropped)
    let recovered = settleUntilHoldingSomething(s4, seconds: 8)
    expect("recovers afterwards", recovered.hasPrefix("attached") || recovered == "dangling" || recovered == "swinging", recovered)
    map.rebuild(windows: windows)
} else {
    print("  [skip] never boarded a window in time")
}

/// Puts it on a spot and gives it a moment; it may leap or swing off in
/// that moment of its own accord, so it is put back until it stays.
func park(_ s: Spider, loopID: String, segIdx: Int, t: CGFloat) -> Bool {
    for _ in 0..<6 {
        s.debugAttach(loopID: loopID, segIdx: segIdx, t: t, dir: 1)
        for _ in 0..<20 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
        if s.debugState.hasPrefix("attached"), !s.debugState.contains(":shoot"), !s.debugState.contains(":crouch") { return true }
    }
    return false
}

// A long fall — its footing gone from high up — is taken on a dragline:
// it lets go, drops, and takes hold of the line a good way above the floor
// (never inches from it), hangs a moment, then does one thing: back up, or
// on down, or off. It must end up standing somewhere, with no bouncing
// between climbing and dropping, and never land where it cannot be seen.
do {
    let fm = SurfaceMap()
    fm.standoff = map.standoff
    let high = TrackedWindow(id: 21, frame: CGRect(x: screen.minX + 500, y: screen.maxY - 520, width: 600, height: 300), depth: 0, owner: "High")
    fm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [high], cinema: false)
    var caughtHeights: [CGFloat] = []
    var worst = ""
    var trials = 0, lineTrials = 0, settled = 0, flipFlops = 0, coveredLandings = 0
    for trial in 0..<8 {
        let s = Spider(map: fm)
        s.config.webs = true
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        // Hanging under the window, then its footing goes: nothing under
        // it but the floor, a long way down.
        guard let under = fm.loop("win:21")?.segs.firstIndex(where: { $0.facing == .down }),
              park(s, loopID: "win:21", segIdx: under, t: 80 + CGFloat(trial) * 50) else { continue }
        let top = s.worldPos.y
        s.debugFall()
        trials += 1
        var n = 0
        var falls = 0, hangs = 0
        var lowestOnLine = CGFloat.greatestFiniteMagnitude
        var firstCatch: CGFloat?
        var last = ""
        var done = ""
        while CGFloat(n) * dt < 30 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            let kind = String(st.split(separator: ":").first ?? "")
            if kind != last {
                if kind == "fall" { falls += 1 }
                if kind == "dangling" || kind == "swinging" {
                    hangs += 1
                    if firstCatch == nil { firstCatch = s.worldPos.y }
                }
                last = kind
            }
            if kind == "dangling" || kind == "swinging" { lowestOnLine = min(lowestOnLine, s.worldPos.y) }
            if st.hasPrefix("attached"), CGFloat(n) * dt > 2 {
                if !fm.isVisible(s.worldPos, depth: Int.max) && !st.contains("screen") && !st.contains("menu") { coveredLandings += 1 }
                done = st
                break
            }
        }
        if let c = firstCatch {
            lineTrials += 1
            caughtHeights.append(c - screen.minY)
        }
        if !done.isEmpty { settled += 1 }
        // Fell, caught, climbed, dropped, caught again: that is the jank.
        if falls > 1 || hangs > 1 { flipFlops += 1; worst = "trial \(trial): \(falls) falls, \(hangs) hangs, ended \(done.isEmpty ? s.debugState : done)" }
        _ = top
    }
    expect("long fall: takes to its dragline", lineTrials == trials, "\(lineTrials) of \(trials)")
    let lowestCatch = caughtHeights.min() ?? 0
    expect("long fall: takes hold well clear of the floor", lowestCatch > 140,
           "lowest catch \(Int(lowestCatch)) px up  (\(caughtHeights.map { String(Int($0)) }.joined(separator: ", ")))")
    expect("long fall: settles somewhere afterwards", settled == trials, "\(settled) of \(trials)")
    expect("long fall: no climbing and dropping again", flipFlops == 0, worst)
    expect("long fall: never lands where it cannot be seen", coveredLandings == 0, "\(coveredLandings)")
}

// Dropped from the top of the screen by hand: it shoots a line up and
// catches itself on the way down, well above the floor — a fling, though,
// it rides out.
do {
    let dm = SurfaceMap()
    dm.standoff = map.standoff
    dm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: false)
    var caught: [CGFloat] = []
    var flungCaught = 0
    for trial in 0..<8 {
        let s = Spider(map: dm)
        s.config.webs = true
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        let hand = V2(screen.midX + CGFloat(trial - 3) * 120, screen.maxY - 120)
        s.beginGrab(at: s.worldPos)
        s.setCursor(hand)
        for _ in 0..<30 { s.setCursor(hand); s.update(dt: dt) }
        // Two plain drops, two light tosses, two brisk ones, two hard flings.
        let fling = trial >= 6
        let toss: [V2] = [V2(20, -30), V2(-30, 10), V2(500, 120), V2(-700, 60), V2(1200, 250), V2(-1400, -100), V2(2300, 300), V2(-2200, 600)]
        s.endGrab(throwVelocity: toss[trial])
        var n = 0
        var firstCatch: CGFloat?
        while CGFloat(n) * dt < 8 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if (st == "dangling" || st == "swinging"), firstCatch == nil { firstCatch = s.worldPos.y - screen.minY }
            if st.hasPrefix("attached") { break }
        }
        if fling { if firstCatch != nil { flungCaught += 1 } }
        else if let c = firstCatch { caught.append(c) }
    }
    expect("dropped or tossed from the top: catches itself on a line", caught.count == 6, "\(caught.count) of 6")
    expect("dropped from the top: well above the floor", (caught.min() ?? 0) > 140, "catches at \(caught.map { String(Int($0)) }.joined(separator: ", ")) px up")
    expect("flung hard: no line, it flies", flungCaught == 0, "\(flungCaught) of 2 took a line")
}

// The window under it simply closing: there is nothing left to fasten a
// line to, so it falls — and lands on the floor, first time, no snatching
// at a line on the way down and no line from nowhere at the bottom.
do {
    let fm = SurfaceMap()
    fm.standoff = map.standoff
    let high = TrackedWindow(id: 22, frame: CGRect(x: screen.minX + 500, y: screen.maxY - 520, width: 600, height: 300), depth: 0, owner: "High")
    var landedFirst = 0, lined = 0
    for trial in 0..<4 {
        fm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [high], cinema: false)
        let s = Spider(map: fm)
        s.config.webs = true
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        guard park(s, loopID: "win:22", segIdx: 0, t: 100 + CGFloat(trial) * 80) else { continue }
        fm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: false)
        var n = 0
        var sawLine = false
        while CGFloat(n) * dt < 6 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if st == "dangling" || st == "swinging" { sawLine = true }
            if st.hasPrefix("attached") { if !sawLine { landedFirst += 1 }; break }
        }
        if sawLine { lined += 1 }
    }
    expect("window closes under it: falls and lands, no line", landedFirst == 4 && lined == 0, "landed first \(landedFirst) of 4, took a line \(lined)")
}

// Covered on a shelf with no open stretch near, and the ceiling covered
// too: the only way is down. The shelf is behind the window now, so no
// line is fastened to it — it drops — and it never climbs back up under
// the window.
do {
    let cm = SurfaceMap()
    cm.standoff = map.standoff
    let shelf = TrackedWindow(id: 41, frame: CGRect(x: screen.minX + 300, y: screen.midY - 100, width: 1100, height: 300), depth: 1, owner: "Shelf")
    cm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [shelf], cinema: false)
    let s = Spider(map: cm)
    s.config.webs = true
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    _ = park(s, loopID: "win:41", segIdx: 0, t: 550)
    let p = s.worldPos
    let cover = CGRect(x: p.x - 320, y: p.y - 120, width: 640, height: screen.maxY - p.y + 200)
    cm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [shelf, TrackedWindow(id: 42, frame: cover, depth: 0, owner: "Cover")], cinema: false)
    var n = 0
    var seen: [String] = []
    var hiddenLine = 0
    var backUnder = 0
    var done = ""
    var last = ""
    while CGFloat(n) * dt < 30 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        let kind = String(st.split(separator: ":").first ?? "")
        if seen.last != kind { seen.append(kind) }
        // Hanging from it, that is: a line still racing out to its mark
        // may pass over the window. (And the menu bar is over every
        // window, whatever the cover's rect says.)
        if kind == "dangling" || kind == "swinging", let w = s.pose().web, w.anchor.y < screen.maxY - 40,
           cover.insetBy(dx: 4, dy: 4).contains(w.anchor.point) { hiddenLine += 1 }
        if last == "dangling", kind == "attached", cover.contains(s.worldPos.point) { backUnder += 1 }
        last = kind
        if st.hasPrefix("attached"), CGFloat(n) * dt > 3, !cover.contains(s.worldPos.point) { done = st; break }
    }
    expect("covered, only way is down: drops", seen.contains("fall"), seen.joined(separator: " > "))
    expect("covered, only way is down: no line fastened under the window", hiddenLine == 0, "\(hiddenLine) frames")
    expect("covered, only way is down: does not climb back under the window", backUnder == 0, seen.joined(separator: " > "))
    expect("covered, only way is down: ends up standing in the open", !done.isEmpty, done.isEmpty ? s.debugState + "  " + seen.joined(separator: " > ") : done)
}

// Standing on a window that is resized from the far end — or the Dock
// growing — it keeps its place on the ground rather than being slid along
// the edge on still legs. A window dragged as a whole carries it along.
do {
    let rm = SurfaceMap()
    rm.standoff = map.standoff
    var frame = CGRect(x: screen.minX + 300, y: screen.midY - 150, width: 900, height: 300)
    rm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [TrackedWindow(id: 51, frame: frame, depth: 0, owner: "Resized")], cinema: false)
    let s = Spider(map: rm)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    _ = park(s, loopID: "win:51", segIdx: 0, t: 450)
    func still(_ secs: CGFloat) {
        s.debugActivity("rest", for: 20)
        for _ in 0..<Int(secs / dt) { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
    }
    still(0.5)
    let before = s.worldPos
    // Dragged in from the left by 160, a little at a time, as a window is.
    for _ in 0..<16 {
        frame.origin.x += 10; frame.size.width -= 10
        rm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [TrackedWindow(id: 51, frame: frame, depth: 0, owner: "Resized")], cinema: false)
        still(0.05)
    }
    still(0.5)
    let slid = abs(s.worldPos.x - before.x)
    expect("window resized under it: keeps its place", slid < 2 && s.debugState.hasPrefix("attached:rest"), String(format: "moved %.1f px, %@", slid, s.debugState))
    let mid = s.worldPos
    for _ in 0..<16 {
        frame.origin.x += 6; frame.origin.y += 3
        rm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [TrackedWindow(id: 51, frame: frame, depth: 0, owner: "Resized")], cinema: false)
        still(0.05)
    }
    still(0.5)
    let carried = s.worldPos - mid
    expect("window dragged with it on: goes along", abs(carried.x - 96) < 3 && abs(carried.y - 48) < 3, String(format: "carried %.1f,%.1f", carried.x, carried.y))
}

// A window dropped right over it while it stands on another window's
// shelf, with the open part of the shelf close by: the shelf is behind the
// window now, so it leaves it — drops, or a line out — and never walks
// along it under the window to the open part. Once out it stays out.
do {
    let em = SurfaceMap()
    em.standoff = map.standoff
    let shelf = TrackedWindow(id: 31, frame: CGRect(x: screen.minX + 300, y: screen.minY + 300, width: 900, height: 400), depth: 1, owner: "Shelf")
    em.debugRebuild(screen: screen, menuBarHeight: 25, windows: [shelf], cinema: false)
    let s = Spider(map: em)
    s.config.webs = true
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    _ = park(s, loopID: "win:31", segIdx: 0, t: 450)
    let p = s.worldPos
    let cover = CGRect(x: p.x - 120, y: p.y - 300, width: 240, height: 400)
    em.debugRebuild(screen: screen, menuBarHeight: 25, windows: [shelf, TrackedWindow(id: 32, frame: cover, depth: 0, owner: "Cover")], cinema: false)
    var n = 0
    var out = -1.0
    var seen: [String] = []
    var walkedUnder = 0
    var backUnder = 0
    while CGFloat(n) * dt < 8 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        if seen.last != st { seen.append(st) }
        let under = cover.contains(s.worldPos.point)
        if n > 6, under, s.currentLoopID == "win:31", st.contains(":walk") || st.contains(":scurry") { walkedUnder += 1 }
        if out < 0, !under { out = Double(n) * Double(dt) }
        if out >= 0, under { backUnder += 1 }
    }
    expect("covered with the open shelf near: gets off the shelf", out >= 0 && out < 2.5,
           (out < 0 ? "never left" : String(format: "out in %.1fs", out)) + "  " + seen.prefix(5).joined(separator: " > "))
    expect("covered with the open shelf near: never walks along it under the window", walkedUnder == 0, "\(walkedUnder) frames")
    expect("covered with the open shelf near: stays out", backUnder == 0, "\(backUnder) frames back under it")
}

// On the side of a window when another opens over it: it drops or lines
// out — never walks down the covered side to the open part below — and
// never takes hold of the covered window anywhere the new one hides it.
do {
    var walked = 0, touched = 0, runs = 0
    for trial in 0..<20 {
        let em = SurfaceMap()
        em.standoff = map.standoff
        let wall = TrackedWindow(id: 41, frame: CGRect(x: screen.minX + 300, y: screen.minY + 200, width: 700, height: 600), depth: 1, owner: "Wall")
        em.debugRebuild(screen: screen, menuBarHeight: 25, windows: [wall], cinema: false)
        let s = Spider(map: em)
        s.config.webs = true
        s.config.followCursor = false
        _ = settleUntilAttached(s)
        let side = trial % 2 == 0 ? 1 : 3
        _ = park(s, loopID: "win:41", segIdx: side, t: 300)
        guard s.currentLoopID == "win:41" else { continue }
        runs += 1
        let p = s.worldPos
        let cover = CGRect(x: p.x - 250, y: p.y - 150, width: 500, height: 300)
        em.debugRebuild(screen: screen, menuBarHeight: 25, windows: [wall, TrackedWindow(id: 42, frame: cover, depth: 0, owner: "Cover")], cinema: false)
        // (A beat to notice, and the line fired from where it stands, are
        // the escape itself; taking hold there again once gone is not.)
        var left = false
        for n in 0..<(60 * 8) {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt)
            if s.currentLoopID != "win:41" { left = true }
            guard n > 6, s.currentLoopID == "win:41", cover.insetBy(dx: -4, dy: -4).contains(s.worldPos.point) else { continue }
            let st = s.debugState
            if st.contains(":walk") || st.contains(":scurry") { walked += 1; break }
            if left { touched += 1; break }
        }
    }
    expect("covered on a window's side: never walks down it under the window", runs > 0 && walked == 0, "\(walked) of \(runs)")
    expect("covered on a window's side: never holds the hidden part", touched == 0, "\(touched) of \(runs)")
}

// Petting.
let s5 = Spider(map: map)
_ = settleUntilAttached(s5)
var c = s5.worldPos
for i in 0..<180 {
    c = s5.worldPos + V2(CGFloat(sin(Double(i) * 0.6)) * 14, 2)
    s5.setCursor(c)
    s5.update(dt: dt)
}
expect("petting makes it happy", s5.pose().happy > 0.4,
       "happy \(String(format: "%.2f", Double(s5.pose().happy)))")

// Swinging: shoot a line at something above and swing off the ledge.
do {
    let s6 = Spider(map: map)
    s6.config.followCursor = false
    var h = Habits(); h.swing = 0.9; s6.apply(design: SpiderDesign(name: "S", habits: h))
    _ = settleUntilAttached(s6)
    // Stand on the bottom of the screen, under the windows, facing right.
    if let sl = map.loops.first(where: { $0.id.hasPrefix("screen") }) {
        s6.debugAttach(loopID: sl.id, segIdx: floorSeg(sl), t: 300, dir: 1)
    }
    s6.debugActivity("swing", for: 0)
    let aimed = s6.debugState
    expect("takes aim", aimed.hasPrefix("attached:shoot"), aimed)
    var seen: Set<String> = []
    var off = 0
    var n = 0
    while CGFloat(n) * dt < 12 {
        s6.setCursor(V2(-4000, -4000)); s6.update(dt: dt); n += 1
        seen.insert(String(s6.debugState.split(separator: ":").first ?? ""))
        if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(s6.worldPos.point) { off += 1 }
    }
    expect("swings on the line", seen.contains("swinging"), seen.sorted().joined(separator: ","))
    expect("lets go or grabs on", seen.contains("jump") || seen.contains("attached"), seen.sorted().joined(separator: ","))
    expect("stays on the desktop while swinging", off == 0, "off \(off)")
}

// Hammock: build it in a corner, sleep in it, get wiped out of it.
do {
    let s7 = Spider(map: map)
    s7.config.followCursor = false
    _ = settleUntilAttached(s7)
    s7.buildHammock()
    var built = false, seenBuilding = false
    var n = 0
    var lastB = ""
    while CGFloat(n) * dt < 150, !built {
        s7.setCursor(V2(-4000, -4000)); s7.update(dt: dt); n += 1
        if ProcessInfo.processInfo.environment["SIM_TRACE"] != nil, lastB != s7.debugState + " \(s7.hammock?.progress ?? -1)" {
            lastB = s7.debugState + " \(s7.hammock?.progress ?? -1)"
            print(String(format: "  %6.2f %@  pos %.0f,%.0f", CGFloat(n) * dt, lastB, s7.worldPos.x, s7.worldPos.y))
        }
        if s7.debugState.contains("building") || s7.debugState.contains("spinning") { seenBuilding = true }
        if let h = s7.hammock, h.progress >= 1 { built = true }
    }
    expect("goes to a corner and spins a hammock", seenBuilding && built,
           "\(Int(CGFloat(n) * dt))s, \(s7.debugState), corner \(s7.hammock.map { $0.left ? "left" : "right" } ?? "-")")
    if let h = s7.hammock {
        let top = map.menuBarBottom(for: screen) ?? screen.maxY
        expect("hammock is in a top corner under the menu bar",
               abs(h.rect.maxY - top) < 1 && (abs(h.rect.minX - screen.minX) < 1 || abs(h.rect.maxX - screen.maxX) < 1),
               "\(h.rect)")
    }
    // Send it to bed.
    _ = settleUntilAttached(s7, limit: 10)
    s7.napInHammock()
    var napped = false
    n = 0
    while CGFloat(n) * dt < 120, !napped {
        s7.setCursor(V2(-4000, -4000)); s7.update(dt: dt); n += 1
        if s7.debugState == "nesting" { napped = true }
    }
    expect("naps in the hammock", napped, "\(Int(CGFloat(n) * dt))s, \(s7.debugState)")
    expect("asleep in it", s7.pose().sleep > 0.5 || settle(s7, seconds: 3).isEmpty || s7.pose().sleep > 0.5,
           "sleep \(String(format: "%.2f", Double(s7.pose().sleep)))")
    // Wipe it away with the pointer.
    if let h = s7.hammock {
        var x = h.rect.minX + 5
        var wipes = 0
        while s7.hammock != nil, wipes < 400 {
            x += 12; if x > h.rect.maxX - 5 { x = h.rect.minX + 5 }
            s7.wipeHammock(at: V2(x, h.rect.midY), movement: 12)
            s7.update(dt: dt)
            wipes += 1
        }
        expect("wiping the pointer across it clears it", s7.hammock == nil, "\(wipes) wipes, now \(s7.debugState)")
        let after = settleUntilAttached(s7, limit: 15)
        expect("tumbles out and recovers", after.hasPrefix("attached") || after == "dangling", after)
    }
}

// Full-screen video: cinema manners. Only the floor and ceiling exist; it
// settles and watches, wanders a little, never leaps or swings, does not
// nod off for a long while, and ignores the pointer.
do {
    let cinema = SurfaceMap()
    cinema.standoff = map.standoff
    cinema.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: true)
    let s8 = Spider(map: cinema)
    s8.config.followCursor = true
    var fast = s8.gait; fast.pace = 1; fast.style = .scurry
    s8.apply(design: SpiderDesign(name: "S", look: SpiderLook(), personality: Personality(), gait: fast))
    _ = settleUntilAttached(s8)
    s8.fullScreenApp = true
    var n = 0
    var counts: [String: Int] = [:]
    var wild = 0
    var onFloor = 0
    var asleep = 0
    while CGFloat(n) * dt < 120 {
        s8.setCursor(V2(screen.midX + cos(CGFloat(n) * 0.02) * 300, screen.minY + 30 + abs(sin(CGFloat(n) * 0.01)) * 200)); s8.update(dt: dt); n += 1
        let st = s8.debugState
        let head = String(st.split(separator: " ").first ?? "")
        counts[head, default: 0] += 1
        if CGFloat(n) * dt > 10 {
            if st == "jump" || st == "swinging" || st == "dangling" || st.contains(":crouch") || st.contains(":shoot") { wild += 1 }
            if st.contains("screen:0") { onFloor += 1 }
            if st.contains(":sleep") { asleep += 1 }
        }
    }
    let top = counts.sorted { $0.value > $1.value }.prefix(5).map { "\($0.key) \($0.value * 100 / n)%" }.joined(separator: ", ")
    // Once it has its seat it should stay put: another 60 s, counting how
    // much of it is spent on the move and how far it strays.
    var moving = 0
    var away = 0
    let seat = s8.worldPos
    var m = 0
    while CGFloat(m) * dt < 60 {
        s8.setCursor(V2(-4000, -4000)); s8.update(dt: dt); m += 1
        let st = s8.debugState
        if st.contains(":walk") || st.contains(":sneak") || st.contains(":turn") || st.contains(":scurry") { moving += 1 }
        if s8.worldPos.distance(to: seat) > 80 { away += 1 }
    }
    expect("cinema: gets cosy and stays put", moving < m * 12 / 100 && away < m * 15 / 100, "moving \(moving * 100 / m)%, away from its seat \(away * 100 / m)%")
    expect("cinema: no leaping, swinging or silk", wild == 0, "wild frames \(wild)  " + top)
    expect("cinema: stays on the floor or ceiling", onFloor > n * 85 / 100, "\(onFloor * 100 / n)%  " + top)
    expect("cinema: mostly sits and watches", (counts["attached:watch"] ?? 0) > n * 35 / 100, top)
    expect("cinema: does not nod off", asleep == 0, top)
    expect("cinema: unbothered by the pointer", !s8.debugState.contains(":startle"), s8.debugState)
    let p = s8.worldPos
    expect("cinema: well inside the screen", screen.insetBy(dx: 10, dy: 10).contains(p.point), "\(p)")
    let cornerDist = min(p.x - screen.minX, screen.maxX - p.x)
    expect("cinema: watches from a corner", cornerDist < 120, "\(Int(cornerDist)) px from the side")
    let pose = s8.pose()
    expect("cinema: head tipped up at the picture", pose.headTilt > 0.4 || !s8.debugState.contains(":watch"), "tilt \(pose.headTilt) in \(s8.debugState)")

    // The show ends: back to normal within a little while.
    cinema.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: false)
    s8.fullScreenApp = false
    var resumed = false
    n = 0
    while CGFloat(n) * dt < 40, !resumed {
        s8.setCursor(V2(-4000, -4000)); s8.update(dt: dt); n += 1
        let st = s8.debugState
        if st.contains(":walk") || st == "jump" || st.contains(":look") || st == "dangling" || st.contains(":turn") { resumed = true }
    }
    expect("resumes when the video ends", resumed, "\(Int(CGFloat(n) * dt))s, \(s8.debugState)")
}

// A film starting while it is high up on the side of the screen: it must
// not jump — it stays exactly where it is and crawls to a corner, every
// frame a small step from the last, and the same when the film ends.
do {
    let m = SurfaceMap()
    m.standoff = map.standoff
    m.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: false)
    let s9 = Spider(map: m)
    _ = settleUntilAttached(s9)
    // The left wall, a third of the way down from the top.
    guard let rim = m.loop("screen:0"), let wall = rim.segs.firstIndex(where: { $0.facing == .right }) else {
        expect("cinema: a wall to start on", false); fatalError()
    }
    s9.debugAttach(loopID: "screen:0", segIdx: wall, t: rim.segs[wall].len * 0.33, dir: 1)
    for _ in 0..<30 { s9.setCursor(V2(-4000, -4000)); s9.update(dt: dt) }
    let before = s9.worldPos
    m.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: true)
    s9.surfacesRestructured()
    s9.fullScreenApp = true
    s9.update(dt: dt)
    expect("cinema: does not teleport when the film starts", s9.worldPos.distance(to: before) < 3,
           "moved \(Int(s9.worldPos.distance(to: before))) px, \(s9.debugState)")
    var biggestStep: CGFloat = 0
    var prev = s9.worldPos
    var n = 0
    var watched = 0
    while CGFloat(n) * dt < 90 {
        s9.setCursor(V2(-4000, -4000)); s9.update(dt: dt); n += 1
        biggestStep = max(biggestStep, s9.worldPos.distance(to: prev))
        prev = s9.worldPos
        if CGFloat(n) * dt > 60, s9.debugState.contains(":watch") { watched += 1 }
    }
    let p = s9.worldPos
    expect("cinema: every step is a small one", biggestStep < 12, "biggest step \(String(format: "%.1f", biggestStep)) px")
    expect("cinema: crawls to a corner from the wall", watched > 60 * 10 && p.x - screen.minX < 120
           && min(p.y - screen.minY, screen.maxY - p.y) < 120, "\(s9.debugState) at \(p), watched \(watched / 60)s of the last 30")
    // The show ends: the menu bar is back, and again it stays put.
    let seat = s9.worldPos
    m.debugRebuild(screen: screen, menuBarHeight: 25, windows: [], cinema: false)
    s9.surfacesRestructured()
    s9.fullScreenApp = false
    s9.update(dt: dt)
    expect("cinema: does not teleport when the film ends", s9.worldPos.distance(to: seat) < 3,
           "moved \(Int(s9.worldPos.distance(to: seat))) px, \(s9.debugState)")
}

// ---------------------------------------------------------------------------
// Personalities: every preset and a few random designs each live 150s. They
// must all stay on the desktop, and the mix of what they do should differ.
// ---------------------------------------------------------------------------

print("\n--- personalities (150s each) ---")
var designs: [(String, SpiderDesign)] = Personality.presets.map { p in
    var d = SpiderDesign(); d.name = p.name; d.personality = p.p; return (p.name, d)
}
for i in 0..<4 { let d = SpiderDesign.random(); designs.append(("random\(i) \(d.look.legs.rawValue)/\(d.gait.style.rawValue)", d)) }
var allFine = true
for (name, d) in designs {
    let sp = Spider(map: map)
    sp.apply(design: d)
    var mix: [String: Int] = [:]
    var off = 0, stuck = 0, worstStuck = 0
    var lastP = sp.worldPos
    var tt: CGFloat = 0
    for _ in 0..<(60 * 150) {
        tt += dt
        sp.setCursor(V2(screen.midX + cos(tt * 0.3) * 400, screen.midY + sin(tt * 0.2) * 300))
        sp.update(dt: dt)
        let st = sp.debugState
        let act = st.split(separator: ":").count > 1 ? String(st.split(separator: ":")[1]).split(separator: " ").first.map(String.init) ?? "?" : String(st)
        mix[act, default: 0] += 1
        let p = sp.worldPos
        if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(p.point) { off += 1 }
        if p.distance(to: lastP) < 0.02 && st != "nesting" { stuck += 1; worstStuck = max(worstStuck, stuck) } else { stuck = 0 }
        lastP = p
    }
    let top = mix.sorted { $0.value > $1.value }.prefix(5)
        .map { "\($0.key) \(Int(Double($0.value) / 90))%" }.joined(separator: ", ")
    let ok = off == 0 && worstStuck < 60 * 40
    if !ok { allFine = false }
    print("  [\(ok ? "ok  " : "FAIL")] \(name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(top)  off=\(off) stuck=\(worstStuck / 60)s")
}
expect("every personality stays on the desktop", allFine)

// A window opens over the top of the line while it is on it: nothing up
// there to climb out onto any more. It must not jitter at the top — it
// swings off (or steps down to the floor), and ends up holding something.
do {
    let s = Spider(map: map)
    s.config.webs = true
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    var started = false
    if let l2 = map.loop("win:2"), let under = l2.segs.firstIndex(where: { $0.facing == .down }) {
        let seg = l2.segs[under]
        let want = V2(screen.minX + 1150, seg.a.y)
        for _ in 0..<5 {
            s.debugAttach(loopID: "win:2", segIdx: under, t: (want - seg.a).dot(seg.dir), dir: 1)
            _ = settle(s, seconds: 0.3, cursor: V2(-4000, -4000))
            if s.debugState.hasPrefix("attached") { break }
        }
        s.scroll(-4)
        for _ in 0..<40 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
        started = s.debugState == "dangling"
    }
    expect("lost-top: it is on a line to begin with", started, s.debugState)
    if started {
        let anchorY = map.loop("win:2")!.segs.first(where: { $0.facing == .down })!.a.y
        // A new window, in front of everything, right over the anchor.
        let cover = TrackedWindow(id: 9, frame: CGRect(x: screen.minX + 1000, y: anchorY - 200,
                                                       width: 400, height: 400), depth: 0, owner: "Popup")
        map.rebuild(windows: [cover] + windows.map {
            TrackedWindow(id: $0.id, frame: $0.frame, depth: $0.depth + 1, owner: $0.owner) })
        s.surfacesRestructured()
        var seen: Set<String> = []
        var topFrames = 0
        var n = 0
        var last = s.debugState
        while CGFloat(n) * dt < 30 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            seen.insert(String(st.split(separator: ":").first ?? "?"))
            if st == "dangling", s.worldPos.y > anchorY - 60 { topFrames += 1 }
            if st != last, ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil {
                print("    t=\(String(format: "%.1f", CGFloat(n) * dt)) \(st) y=\(Int(s.worldPos.y)) len=\(Int(s.debugLine.len))")
            }
            last = st
        }
        expect("lost-top: it swings off rather than hanging at the top",
               seen.contains("swinging") || seen.contains("jump") || seen.contains("attached"), "\(seen.sorted())")
        expect("lost-top: not stuck under the new window", topFrames < 60 * 6, "\(topFrames / 60)s at the top")
        expect("lost-top: it ends up holding something", s.debugState.hasPrefix("attached") || s.debugState == "nesting", s.debugState)
        map.rebuild(windows: windows)
    }
}

// The habit dials: at "never" a thing is not in the hat; at "all the time"
// it wins the draw whenever it is possible.
do {
    var never = Habits()
    never.drum = 0; never.dance = 0; never.roll = 0; never.spin = 0; never.pushup = 0
    var always = Habits()
    always.drum = 1
    var seen: [String: Set<String>] = ["never": [], "always": []]
    for (label, h) in [("never", never), ("always", always)] {
        let s = Spider(map: map)
        s.config.followCursor = false
        s.apply(design: SpiderDesign(name: "H", habits: h))
        _ = settleUntilAttached(s)
        var n = 0
        while CGFloat(n) * dt < 120 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if st.hasPrefix("attached:") {
                let act = String(st.dropFirst("attached:".count).split(separator: " ").first ?? "")
                seen[label]!.insert(act)
            }
        }
    }
    let banned: Set<String> = ["drum", "dance", "roll", "spin", "pushup"]
    expect("habits: dialled to never, it never does those", seen["never"]!.isDisjoint(with: banned),
           "\(seen["never"]!.intersection(banned).sorted())")
    expect("habits: dialled all the way up, it drums", seen["always"]!.contains("drum"), "\(seen["always"]!.sorted())")
}

// Rolling is a ball going along the ground: only ever on top of something,
// never under a window or up the side of one — and never carried round a
// corner onto either. Asked to show it off from underneath, it gets down
// onto a floor first.
do {
    let rm = SurfaceMap()
    rm.standoff = map.standoff
    let w = TrackedWindow(id: 41, frame: CGRect(x: screen.minX + 400, y: screen.minY + 260, width: 520, height: 300), depth: 0, owner: "W")
    rm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [w], cinema: false)
    if let loop = rm.loop("win:41"),
       let top = loop.segs.firstIndex(where: { $0.facing == .up }),
       let side = loop.segs.firstIndex(where: { $0.facing == .left || $0.facing == .right }),
       let under = loop.segs.firstIndex(where: { $0.facing == .down }) {
        var rolly = Habits()
        rolly.roll = 1
        var offFloor: [String] = []
        var onFloor = 0
        for (label, seg, t) in [("top", top, CGFloat(60)), ("top", top, loop.segs[top].len - 60), ("side", side, CGFloat(120)), ("under", under, CGFloat(200))] {
            for _ in 0..<3 {
                let s = Spider(map: rm)
                s.config.followCursor = false
                s.config.webs = false
                s.apply(design: SpiderDesign(name: "R", habits: rolly))
                _ = settleUntilAttached(s)
                guard park(s, loopID: "win:41", segIdx: seg, t: t) else { continue }
                var n = 0
                while CGFloat(n) * dt < 25 {
                    s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
                    guard s.debugState.hasPrefix("attached:roll") else { continue }
                    if s.debugFooting > 0.7 { onFloor += 1 } else { offFloor.append("\(label) \(String(format: "%.1f", s.debugFooting)) \(s.debugState)") }
                }
            }
        }
        expect("roll: never under a window or up its side", offFloor.isEmpty, "\(offFloor.count) frames, e.g. \(offFloor.prefix(2))")
        expect("roll: it still rolls on top of things", onFloor > 0, "\(onFloor) frames")

        var demoRolled = 0, demoTrials = 0, demoOff = 0
        for _ in 0..<4 {
            let s = Spider(map: rm)
            s.config.followCursor = false
            s.config.webs = false
            _ = settleUntilAttached(s)
            guard park(s, loopID: "win:41", segIdx: under, t: 200) else { continue }
            demoTrials += 1
            s.demo(\.roll)
            var n = 0
            while CGFloat(n) * dt < 8 {
                s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
                guard s.debugState.hasPrefix("attached:roll") else { continue }
                if s.debugFooting > 0.7 { demoRolled += 1; break } else { demoOff += 1 }
            }
        }
        expect("roll: shown off from underneath, it rolls on a floor", demoTrials > 0 && demoRolled == demoTrials && demoOff == 0,
               "\(demoRolled)/\(demoTrials), \(demoOff) frames off the floor")
    }
}

// Under a window with its catch just below — on the floor under a low
// window, or on the top of the window beneath — it gets it quickly: down
// onto it, not pacing back and forth along the underside.
do {
    let um = SurfaceMap()
    um.standoff = map.standoff
    let low = TrackedWindow(id: 51, frame: CGRect(x: screen.minX + 300, y: screen.minY + 120, width: 600, height: 260), depth: 0, owner: "Low")
    let over = TrackedWindow(id: 52, frame: CGRect(x: screen.minX + 250, y: screen.minY + 520, width: 700, height: 300), depth: 0, owner: "Over")
    um.debugRebuild(screen: screen, menuBarHeight: 25, windows: [low, over], cinema: false)
    var times: [String] = []
    var missed: [String] = []
    var skipped = 0
    let dbg = ProcessInfo.processInfo.environment["SIM_UNDER"] != nil
    // (window id, prey on: y of the surface under it)
    for (winID, floorY) in [(51, screen.minY), (52, low.frame.maxY)] {
        guard let loop = um.loop("win:\(winID)"), let under = loop.segs.firstIndex(where: { $0.facing == .down }) else { continue }
        let seg = loop.segs[under]
        for kind in [PreyKind.worm, .cricket, .beetle] {
            for dx in [CGFloat(0), 45, -70, 110] {
                let s = Spider(map: um)
                s.config.followCursor = false
                s.config.webs = false
                _ = settleUntilAttached(s)
                let t0 = seg.len / 2
                // Still hanging under it when its catch turns up.
                guard park(s, loopID: "win:\(winID)", segIdx: under, t: t0), s.debugFooting < -0.5,
                      s.debugState.contains("win:\(winID)") else { skipped += 1; continue }
                let at = V2(s.worldPos.x + dx, floorY + 6)
                let p = s.release(kind, at: at)
                var n = 0, caught = -1.0
                var seen: [String] = []
                while CGFloat(n) * dt < 15 {
                    s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
                    let st = s.debugState
                    if seen.last != st { seen.append(st) }
                    if dbg, (n % 30 == 0 || st == "jump" || st.contains("crouch")) { print("    \(kind.label) dx \(Int(dx)) \(s.debugActivity) t=\(String(format: "%.1f", Double(n) * Double(dt))) \(st) spider=\(Int(s.worldPos.x)),\(Int(s.worldPos.y)) prey=\(Int(p.pos.x)),\(Int(p.pos.y)) \(p.state)\(p.tucked ? " tucked" : "")") }
                    if p.state != .loose { caught = Double(n) * Double(dt); break }
                }
                let label = "\(kind.label) \(Int(dx)) below win:\(winID)"
                // (A cricket hops off when it lands by it, and a chase can run
                // on: counted in how quick the catches are, not in this.)
                if caught < 0 { if kind != .cricket { missed.append(label + ": " + seen.prefix(8).joined(separator: " > ")) } } else { times.append(String(format: "%.1f", caught)) }
                if dbg { print(String(format: "  SEQ %@ %.1fs: ", label, caught) + seen.prefix(9).joined(separator: " > ").replacingOccurrences(of: "attached:", with: "")) }
            }
        }
    }
    print("    under a window, catch below: caught in \(times.joined(separator: " ")) s (\(skipped) not under it to start)")
    let quick = times.compactMap { Double($0) }.filter { $0 < 2.5 }.count
    expect("under a window, prey right below: mostly caught at once (under 2.5 s)", quick * 4 >= times.count * 3, "\(quick)/\(times.count)")
    expect("under a window, a worm or beetle right below: it gets it within 15 s", missed.isEmpty, "\(missed.count) missed: \(missed.prefix(3).joined(separator: " | "))")
}

// The Studio's ▶ next to every habit, in a copy of the Studio's little box,
// from every kind of edge in it: each has to actually do its thing within
// a few seconds — getting itself somewhere it can first, if need be (to a
// floor to roll, somewhere with a line to swing on, high enough to drop).
do {
    let pm = SurfaceMap()
    let scale: CGFloat = 1.55
    pm.standoff = -SpiderRenderer.ground * scale
    let b = CGRect(x: 0, y: 0, width: 330, height: 320).insetBy(dx: 4, dy: 4)
    let ledge = CGRect(x: b.midX - 80, y: b.minY + 70, width: 160, height: 70)
    pm.debugRebuild(screen: b, menuBarHeight: 0, windows: [TrackedWindow(id: 1, frame: ledge, depth: 0, owner: "Studio")])
    // (The hammock ones the desktop spider shows; a thought is only a bubble.)
    let expected: [PartialKeyPath<Habits>: String] = [
        \Habits.wander: "attached:walk", \Habits.leap: "jump", \Habits.rappel: "dangling", \Habits.swing: "swinging",
        \Habits.sleep: "attached:sleep", \Habits.drum: "attached:drum", \Habits.dance: "attached:dance", \Habits.roll: "attached:roll",
        \Habits.spin: "attached:spin", \Habits.pushup: "attached:pushup", \Habits.stretch: "attached:legStretch",
        \Habits.wiggle: "attached:wiggle", \Habits.armsUp: "attached:armsUp", \Habits.look: "attached:look",
        \Habits.rest: "attached:rest", \Habits.groom: "attached:groom", \Habits.fidget: "attached:fidget",
        \Habits.scratch: "attached:scratch", \Habits.peer: "attached:peer", \Habits.approach: "attached:walk",
        \Habits.curious: "attached:curious", \Habits.stare: "attached:stare", \Habits.glance: "attached:glance",
        \Habits.greet: "attached:greet", \Habits.wave: "attached:wave", \Habits.peekaboo: "attached:armsUp",
    ]
    let starts: [(String, Int, CGFloat)] = [("screen:0", 0, 126), ("screen:0", 1, 120), ("screen:0", 2, 120), ("screen:0", 3, 120),
                                            ("win:1", 0, 114), ("win:1", 1, 60), ("win:1", 2, 110), ("win:1", 3, 60)]
    var missed: [String] = []
    var tried = 0
    for (title, key) in Habits.groups.flatMap({ $0.1 }) {
        guard let want = expected[key] else { continue }
        for (loopID, seg, t) in starts {
            let sp = Spider(map: pm)
            sp.config.scale = scale
            sp.config.webs = true
            sp.config.followCursor = true
            sp.debugAttach(loopID: loopID, segIdx: seg, t: t, dir: 1)
            for _ in 0..<30 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
            tried += 1
            sp.demo(key)
            var did = false
            for _ in 0..<Int(10 / dt) {
                sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt)
                if sp.debugState.hasPrefix(want) { did = true; break }
            }
            if !did { missed.append("\(title) from \(loopID)/\(seg)") }
        }
    }
    expect("studio: every habit's ▶ does it, from anywhere in the box", missed.isEmpty,
           "\(missed.count)/\(tried) missed: \(missed.prefix(6).joined(separator: "; "))")
}

// Commotions: a notification makes it jump — straight up off the top of a
// window and back down onto it — and stare at where it came up; on a side
// or underneath it only starts. The volume or brightness only turns its
// head: no start, no jump.
do {
    let cm = SurfaceMap()
    cm.standoff = map.standoff
    let w = TrackedWindow(id: 31, frame: CGRect(x: screen.minX + 400, y: screen.minY + 200, width: 700, height: 400), depth: 0, owner: "W")
    cm.debugRebuild(screen: screen, menuBarHeight: 25, windows: [w], cinema: false)
    let banner = V2(screen.maxX - 180, screen.maxY - 75)
    guard let loop = cm.loop("win:31"),
          let top = loop.segs.firstIndex(where: { $0.facing == .up }),
          let side = loop.segs.firstIndex(where: { $0.facing == .left || $0.facing == .right }),
          let under = loop.segs.firstIndex(where: { $0.facing == .down }) else {
        print("  [skip] commotion: no window loop"); exit(0)
    }
    func fresh() -> Spider {
        let s = Spider(map: cm)
        s.config.followCursor = false
        s.config.webs = false
        _ = settleUntilAttached(s)
        return s
    }
    // On top: up, and back down on the same window, staring.
    var hops = 0, landedBack = 0, stared = 0, rises: [CGFloat] = [], trials = 0
    for trial in 0..<6 {
        let s = fresh()
        // Mid-turn or gathering for a leap it only flinches: not a trial.
        guard park(s, loopID: "win:31", segIdx: top, t: 150 + CGFloat(trial) * 60),
              !["turn", "crouch", "shoot", "eat"].contains(where: { s.debugState.contains(":\($0)") }) else { continue }
        trials += 1
        let y0 = s.worldPos.y
        s.noticeCommotion(at: banner, fright: true)
        var peak = y0, sawJump = false, n = 0
        while CGFloat(n) * dt < 1.5 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            peak = max(peak, s.worldPos.y)
            if s.debugState.hasPrefix("jump") { sawJump = true }
            if sawJump, s.debugState.hasPrefix("attached") { break }
        }
        if sawJump { hops += 1; rises.append(peak - y0) }
        if s.debugState.hasPrefix("attached"), s.debugState.contains("win:31") { landedBack += 1 }
        _ = settle(s, seconds: 0.5, cursor: V2(-4000, -4000))
        if s.debugState.contains(":look") { stared += 1 }
    }
    expect("notification on top of a window: it jumps up", trials > 0 && hops == trials, "\(hops)/\(trials), rises \(rises.map { Int($0) })")
    expect("notification on top of a window: it lands back on it", landedBack == trials, "\(landedBack)/\(trials)")
    expect("notification on top of a window: then it stares", stared == trials, "\(stared)/\(trials)")

    // A side, and underneath: a start in place, then the stare.
    for (label, seg) in [("side", side), ("underneath", under)] {
        let s = fresh()
        guard park(s, loopID: "win:31", segIdx: seg, t: 60) else { print("  [skip] commotion \(label): would not park"); continue }
        s.noticeCommotion(at: banner, fright: true)
        var jumped = false, startled = false, n = 0
        while CGFloat(n) * dt < 0.5 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            if !s.debugState.hasPrefix("attached") { jumped = true }
            if s.debugState.contains(":startle") { startled = true }
        }
        _ = settle(s, seconds: 0.3, cursor: V2(-4000, -4000))
        expect("notification on a window's \(label): it starts, no jump", startled && !jumped, s.debugState)
        expect("notification on a window's \(label): then it stares", s.debugState.contains(":look"), s.debugState)
    }

    // The volume: a look, nothing more.
    let s = fresh()
    if park(s, loopID: "win:31", segIdx: top, t: 200) {
        s.noticeCommotion(at: banner, fright: false)
        var jumped = false, startled = false, n = 0
        while CGFloat(n) * dt < 1.0 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            if !s.debugState.hasPrefix("attached") { jumped = true }
            if s.debugState.contains(":startle") { startled = true }
        }
        expect("volume change: only a look", !jumped && !startled && s.debugState.contains(":look"), s.debugState)
    }

    // The charger: on top, a real leap — up off the window under gravity
    // and back down on it; on a side or underneath, it bobs where it is and
    // every foot stays on the window the whole while.
    print("--- charger ---")
    var leaps = 0, back = 0, chargeRises: [CGFloat] = [], chargeTrials = 0
    for trial in 0..<6 {
        let s = fresh()
        guard park(s, loopID: "win:31", segIdx: top, t: 150 + CGFloat(trial) * 60),
              !["turn", "crouch", "shoot", "eat"].contains(where: { s.debugState.contains(":\($0)") }) else { continue }
        chargeTrials += 1
        let y0 = s.worldPos.y
        let was = s.debugState + " " + s.debugActivity
        s.perkUp()
        var peak = y0, sawJump = false, n = 0
        while CGFloat(n) * dt < 2.0 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            peak = max(peak, s.worldPos.y)
            if s.debugState.hasPrefix("jump") { sawJump = true }
            if sawJump, s.debugState.hasPrefix("attached") { break }
        }
        if sawJump { leaps += 1; chargeRises.append(peak - y0) } else if ProcessInfo.processInfo.environment["SIM_CHARGE"] != nil { print("CHT no leap from", was) }
        if sawJump, s.debugState.hasPrefix("attached"), s.debugState.contains("win:31") { back += 1 }
    }
    expect("charger on top of a window: it leaps up for real", chargeTrials > 0 && leaps == chargeTrials && chargeRises.allSatisfy { $0 > 25 },
           "\(leaps)/\(chargeTrials), rises \(chargeRises.map { Int($0) })")
    expect("charger on top of a window: it lands back on it", back == chargeTrials, "\(back)/\(chargeTrials)")
    for (label, seg) in [("side", side), ("underneath", under)] {
        // Gathered for a leap it only crackles, and keeps its footing
        // anyway: not a trial. A few goes to find it standing about.
        var found: Spider?
        for _ in 0..<5 where found == nil {
            let s = fresh()
            guard park(s, loopID: "win:31", segIdx: seg, t: 60) else { continue }
            for _ in 0..<30 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
            if !["turn", "crouch", "shoot"].contains(where: { s.debugState.contains(":\($0)") }) { found = s }
        }
        guard let s = found else { print("  [skip] charger \(label): never standing about"); continue }
        let was = s.debugState
        s.perkUp()
        // Out of a walk the stride is finished, and a leg that was up (a
        // scratch) comes down, in the first moments; after that, none that
        // is down comes up again.
        var lifts = 0, frames = 0, left = false, n = 0
        var wasDown = s.debugPlanted.map { $0.planted }
        while CGFloat(n) * dt < 2.0 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            if !s.debugState.hasPrefix("attached") { left = true }
            let down = s.debugPlanted.map { $0.planted }
            if CGFloat(n) * dt > 0.45, s.debugState.contains(":bounce") || s.debugState.contains(":wiggle") {
                frames += 1
                for i in down.indices where wasDown[i] && !down[i] {
                    lifts += 1
                    if ProcessInfo.processInfo.environment["SIM_CHARGE"] != nil { print("CHW", label, n, i, s.debugFeetWhy, "was", was) }
                }
            }
            wasDown = down
        }
        expect("charger on a window's \(label): feet stay on it", frames > 30 && lifts == 0 && !left,
               "\(lifts) feet lifted over \(frames) frames, left \(left ? "yes" : "no")")
    }
}

// ---------------------------------------------------------------------------
// Memory: what it goes through nudges its personality — a little, within
// bounds, fading again — and never touches the Studio's design.
// ---------------------------------------------------------------------------

print("\n--- memory ---")
do {
    let day: TimeInterval = 86_400
    let shy = Personality.presets.first { $0.name == "Shy" }!.p
    let showOff = Personality.presets.first { $0.name == "Show-off" }!.p
    var shyDesign = SpiderDesign(); shyDesign.personality = shy
    func fmt(_ s: TraitShift) -> String {
        String(format: "energy %+.3f curiosity %+.3f bravery %+.3f play %+.3f affection %+.3f lazy %+.3f prowess %+.3f roaming %+.3f",
               s.energy, s.curiosity, s.bravery, s.playfulness, s.affection, s.laziness, s.prowess, s.roaming)
    }
    func bounded(_ s: TraitShift) -> Bool { TraitShift.traits.allSatisfy { abs(s[keyPath: $0]) <= TraitShift.most + 1e-6 } }

    let plain = Spider(map: map)
    plain.apply(design: shyDesign)
    expect("no memory: its personality is the Studio's", plain.personality == shy)

    // A fortnight of gentle attention: stroked and said hello to a few
    // times a day, and an hour of company.
    let loved = SpiderMemory()
    for _ in 0..<14 {
        for _ in 0..<6 { loved.record(.petted); loved.record(.greeted) }
        loved.record(.company, 6)
        loved.live(for: day, Moment(), base: shy)
    }
    let l = loved.shift
    print("  loved shy spider after a fortnight: \(fmt(l))")
    expect("gentle attention: warmer and bolder", l.affection > 0.04 && l.bravery > 0.03, fmt(l))
    expect("gentle attention: bounded", bounded(l))
    expect("gentle attention: still a shy spider", shy.shifted(by: l).bravery < 0.4,
           String(format: "bravery %.2f -> %.2f", shy.bravery, shy.shifted(by: l).bravery))
    let sp = Spider(map: map)
    sp.apply(design: shyDesign)
    sp.memory = loved
    expect("with memory: the design it hands the Studio is untouched", sp.design.personality == shy && sp.basePersonality == shy)
    expect("with memory: the personality it acts on is shifted", sp.personality.affection > shy.affection)

    // Reinforced over and over it saturates rather than running away.
    let doted = SpiderMemory()
    for _ in 0..<2000 { doted.record(.petted); doted.record(.played); doted.record(.huntWon) }
    doted.settle(base: shy)
    expect("endless reinforcement stays bounded", bounded(doted.shift), fmt(doted.shift))

    // A burst of frights: warier at once, much less so an hour or two on.
    let fright = SpiderMemory()
    for _ in 0..<5 { fright.record(.startled) }
    fright.settle(base: shy)
    let dip = fright.shift.bravery
    fright.live(for: 2 * 3600, Moment(), base: shy)
    let later = fright.shift.bravery
    print(String(format: "  frights: bravery %+.3f at once, %+.3f two hours on", dip, later))
    expect("frights: warier for a while", dip < -0.05 && later > dip * 0.45 && later < 0)

    // Left be: every lesson fades back to who it was.
    loved.live(for: 90 * day, Moment(), base: shy)
    expect("unkept memories fade back to the Studio's personality", TraitShift.traits.allSatisfy { abs(loved.shift[keyPath: $0]) < 0.01 }, fmt(loved.shift))

    // The same fling is fun to a show-off and a fright to a shy one.
    let flungShy = SpiderMemory(), flungBold = SpiderMemory()
    for _ in 0..<6 { flungShy.record(.thrown); flungBold.record(.thrown) }
    flungShy.settle(base: shy); flungBold.settle(base: showOff)
    expect("thrown: a show-off takes it as play, a shy spider as a fright",
           flungBold.shift.playfulness > 0.02 && flungShy.shift.bravery < flungBold.shift.bravery - 0.03,
           "bold \(fmt(flungBold.shift)) | shy \(fmt(flungShy.shift))")

    // Left alone: more independent — never sulky.
    let lonely = SpiderMemory()
    lonely.live(for: 6 * 3600, Moment(company: false, alone: true, calm: false, place: nil), base: shy)
    expect("left alone: more independent, no less affectionate", lonely.shift.roaming > 0.03 && lonely.shift.affection >= 0, fmt(lonely.shift))

    // Good hunts: surer of itself, and a taste for what it ate.
    let hunter = SpiderMemory()
    for _ in 0..<10 { hunter.record(.huntWon); hunter.record(.fed); hunter.warm(to: PreyKind.cricket.memoryName, by: 0.15) }
    hunter.record(.huntMissed)
    hunter.settle(base: shy)
    expect("good hunts: more sure of itself", hunter.shift.prowess > 0.03, fmt(hunter.shift))
    expect("a favourite snack", hunter.favourite(prefix: "prey.") == "cricket")

    // Places: a fright somewhere puts it off; settling somewhere endears it.
    let homely = SpiderMemory()
    let top = Place(at: V2(screen.midX, screen.maxY - 30), in: screen, on: .menuBar, habitat: false)
    let floor = Place(at: V2(screen.midX, screen.minY + 20), in: screen, on: .screenBorder, habitat: false)
    homely.live(for: 1800, Moment(company: false, alone: false, calm: true, place: top), base: shy)
    for _ in 0..<3 { homely.record(.startled, at: floor) }
    expect("places: likes where it settles, less where it was frightened",
           homely.appeal(of: top) > 1.03 && homely.appeal(of: floor) < 0.97,
           String(format: "top %.2f floor %.2f", homely.appeal(of: top), homely.appeal(of: floor)))

    // Kept across launches (in a throwaway defaults domain, not the app's).
    let suite = "com.gabriel.desktopspider.memorytest"
    if let defaults = UserDefaults(suiteName: suite) {
        hunter.save(to: defaults)
        let back = SpiderMemory.load(from: defaults)
        back.settle(base: shy)
        let same = TraitShift.traits.allSatisfy { abs(back.shift[keyPath: $0] - hunter.shift[keyPath: $0]) < 0.002 }
        expect("remembered across launches", same && back.favourite(prefix: "prey.") == "cricket", fmt(back.shift))
        defaults.removePersistentDomain(forName: suite)
    }

    // What it does: the same shy spider, with and without a well-loved
    // memory, you about with the pointer resting on the desktop. The loved
    // one spends more of its time over by the pointer and doing things
    // with you; both stay on the desktop and never get stuck.
    struct Run { var near = 0; var frames = 0; var social = 0; var starts = 0; var off = 0; var stuck = 0 }
    func live(_ memory: SpiderMemory?, seconds: Int) -> Run {
        let s = Spider(map: map)
        s.apply(design: shyDesign)
        s.memory = memory
        var r = Run(), lastAct = "", stuck = 0
        var lastP = s.worldPos
        var tt: CGFloat = 0
        let rest = V2(screen.midX - 120, screen.midY + 80)
        for _ in 0..<(60 * seconds) {
            tt += dt
            // Resting, but not idle: a hand on the mouse, barely moving it.
            s.setCursor(rest + V2(sin(tt * 0.7) * 3, cos(tt * 0.5) * 3))
            s.update(dt: dt)
            let st = s.debugState
            let parts = st.split(separator: ":")
            let act = parts.count > 1 ? String(parts[1].split(separator: " ").first ?? "") : ""
            if act != lastAct, !act.isEmpty {
                r.starts += 1
                if ["greet", "wave", "stare", "curious", "glance", "armsUp"].contains(act) { r.social += 1 }
            }
            lastAct = act
            r.frames += 1
            if s.worldPos.distance(to: rest) < 260 { r.near += 1 }
            if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(s.worldPos.point) { r.off += 1 }
            if s.worldPos.distance(to: lastP) < 0.02, st != "nesting" { stuck += 1; r.stuck = max(r.stuck, stuck) } else { stuck = 0 }
            lastP = s.worldPos
        }
        return r
    }
    let fond = SpiderMemory()
    for _ in 0..<40 { fond.record(.petted); fond.record(.greeted); fond.record(.company, 3) }
    fond.live(for: day, Moment(), base: shy)
    var a = Run(), b = Run()
    var fine = true
    for _ in 0..<4 {
        let x = live(nil, seconds: 300), y = live(fond, seconds: 300)
        a.near += x.near; a.frames += x.frames; a.social += x.social; a.starts += x.starts
        b.near += y.near; b.frames += y.frames; b.social += y.social; b.starts += y.starts
        if x.off > 0 || y.off > 0 || x.stuck > 60 * 40 || y.stuck > 60 * 40 { fine = false }
    }
    let nearA = Double(a.near) / Double(a.frames) * 100, nearB = Double(b.near) / Double(b.frames) * 100
    print(String(format: "  shy, pointer resting, 4×300s: plain %.0f%% of the time near it, %d social of %d starts; loved %.0f%%, %d of %d",
                 nearA, a.social, a.starts, nearB, b.social, b.starts))
    print("  (loved shift \(fmt(fond.shift)))")
    // (Too little in it, against how much one run differs from the next,
    // to hold a run to: a report only.)
    _ = (nearA, nearB)

    // The clearest place to see it: how it takes a click. The same weighted
    // draw as ever, read off hundreds of times: a loved shy spider answers
    // with a wave or a hello more often, and starts less; one given a run
    // of frights starts more.
    // (Each click gets the same memory, fresh: a click is itself something
    // to remember, and would otherwise change what is being measured.)
    func clicks(_ p: Personality, _ memory: SpiderMemory?, _ n: Int) -> (warm: Double, start: Double) {
        let s = Spider(map: map)
        s.config.followCursor = false
        var d = SpiderDesign(); d.personality = p
        s.apply(design: d)
        _ = settleUntilAttached(s)
        var warm = 0, start = 0
        for _ in 0..<n {
            if let m = memory { s.memory = SpiderMemory(state: m.state) }
            s.poke()
            let st = s.debugState
            if st.contains(":wave") || st.contains(":greet") || st.contains(":armsUp") { warm += 1 }
            if st.contains(":startle") { start += 1 }
            s.update(dt: dt)
        }
        return (Double(warm) / Double(n) * 100, Double(start) / Double(n) * 100)
    }
    let frightened = SpiderMemory()
    for _ in 0..<6 { frightened.record(.startled) }
    let mid = Personality()
    let c0 = clicks(shy, nil, 3000), c1 = clicks(shy, fond, 3000)
    let c2 = clicks(mid, nil, 3000), c3 = clicks(mid, frightened, 3000)
    print(String(format: "  3000 clicks each: shy %.1f%% warm / %.1f%% startled, loved shy %.1f%% / %.1f%%; middling %.1f%% / %.1f%%, just frightened %.1f%% / %.1f%%",
                 c0.warm, c0.start, c1.warm, c1.start, c2.warm, c2.start, c3.warm, c3.start))
    expect("loved: takes a click more warmly, and starts less", c1.warm > c0.warm + 2 && c1.start < c0.start)
    expect("just frightened: starts at a click more, for now", c3.start > c2.start)
    expect("with memories it stays on the desktop and never gets stuck", fine)
}

// Toys: each kind lands, settles and stays put on the desktop however it is
// batted about; the wind-up bug walks and runs down; the feather drifts,
// and dangles on its string. Then a spider finds each, plays with it and
// in the end tires of it — a lively one sooner and harder than a lazy one.
do {
    print("\n--- toys ---")
    for kind in ToyKind.allCases {
        let box = ToyBox(map: map); box.scale = 0.95
        let toy = box.add(kind, near: V2(screen.midX, screen.midY))!
        var rest = -1.0, off = 0, n = 0
        while CGFloat(n) * dt < 20 {
            box.update(dt: dt); n += 1
            if !map.worldBounds.insetBy(dx: -5, dy: -5).contains(toy.pos.point) { off += 1 }
            if rest < 0, toy.onSurface, toy.speed < 1 { rest = Double(n) * Double(dt) }
        }
        expect("toy \(kind.label): lands and settles", rest >= 0 && toy.onSurface, String(format: "%.1fs on %@", rest, toy.anchor?.loopID ?? "air"))
        var still = 0
        for i in 0..<6 {
            toy.bat(V2(i % 2 == 0 ? 700 : -700, 250), map: map)
            for _ in 0..<(60 * (kind == .feather ? 30 : 12)) {
                box.update(dt: dt)
                if !map.worldBounds.insetBy(dx: -5, dy: -5).contains(toy.pos.point) { off += 1 }
            }
            if toy.speed < 1 { still += 1 }
        }
        expect("toy \(kind.label): batted about, stays on the desktop and comes to rest", off == 0 && still == 6, "off \(off), at rest \(still)/6")
    }
    do {
        let box = ToyBox(map: map); box.scale = 0.95
        let w = windows[0].frame
        let ball = Toy(kind: .ball, id: 90, at: V2(w.midX - 200, w.maxY + 40), scale: 0.95)
        box.debugInsert(ball)
        for _ in 0..<120 { box.update(dt: dt) }
        let onTop = ball.anchor?.loopID
        ball.bat(V2(-420, 0), map: map)
        var fellAtX: CGFloat?
        for _ in 0..<(60 * 8) { box.update(dt: dt); if fellAtX == nil, ball.airborne { fellAtX = ball.pos.x } }
        expect("ball: rolls along a window top and tips off the end", onTop == "win:1" && fellAtX.map { abs($0 - w.minX) < 12 } == true,
               "on \(onTop ?? "-"), fell at x \(fellAtX.map { "\(Int($0))" } ?? "never") (edge \(Int(w.minX)))")
        expect("ball: lands on something below", ball.onSurface && ball.pos.y < w.maxY, "\(ball.anchor?.loopID ?? "air")")
    }
    do {
        let box = ToyBox(map: map); box.scale = 0.95
        let bug = box.add(.windUpBug, near: V2(screen.midX, screen.midY))!
        for _ in 0..<(60 * 3) { box.update(dt: dt) }
        bug.poke(map: map)
        var travelled: CGFloat = 0, last = bug.pos, ranDown = -1.0
        for n in 0..<(60 * 40) {
            box.update(dt: dt)
            travelled += bug.pos.distance(to: last); last = bug.pos
            if ranDown < 0, bug.wound <= 0 { ranDown = Double(n) * Double(dt) }
        }
        expect("wind-up bug: walks off when wound, and runs down", travelled > 200 && ranDown > 8 && ranDown < 30 && bug.speed < 1,
               String(format: "%.0f px, ran down at %.0fs", Double(travelled), ranDown))
    }
    do {
        let box = ToyBox(map: map); box.scale = 0.95
        let f = Toy(kind: .feather, id: 91, at: V2(screen.midX, screen.minY + 400), scale: 0.95)
        box.debugInsert(f)
        var n = 0
        while !f.onSurface, n < 60 * 30 { box.update(dt: dt); n += 1 }
        expect("feather: drifts down slowly", CGFloat(n) * dt > 3, String(format: "%.1fs", Double(CGFloat(n) * dt)))
        f.grab(at: f.pos)
        var g = f.pos
        for i in 0..<(60 * 3) { g = V2(screen.midX + sin(CGFloat(i) * 0.05) * 200, screen.minY + 500); f.drag(to: g); box.update(dt: dt) }
        let hang = f.pos.distance(to: g)
        expect("feather: dangles on its string below the pointer", hang > 60 && hang < 110 && f.pos.y < g.y, "\(Int(hang)) px")
    }

    func play(_ kind: ToyKind, _ p: Personality, secs: CGFloat = 150) -> (firstBat: Double, bored: Double, off: Int, retreats: Int) {
        let s = Spider(map: map)
        s.config.followCursor = false
        var d = SpiderDesign(); d.personality = p
        s.apply(design: d)
        _ = settleUntilAttached(s)
        let box = ToyBox(map: map); box.scale = 0.95
        s.toys = box
        let toy = box.add(kind, near: s.worldPos)!
        s.seeToy(toy)
        var firstBat = -1.0, bored = -1.0, played = false, off = 0, retreats = 0, lastStage = ""
        var n = 0
        while CGFloat(n) * dt < secs {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); box.update(dt: dt); n += 1
            let st = s.debugToy
            let stage = String(st.split(separator: " ").first ?? "-")
            if stage != lastStage { if stage == "retreat" { retreats += 1 }; lastStage = stage }
            if stage == "play" { played = true }
            if firstBat < 0, st.contains("bats "), !st.contains("bats 0") { firstBat = Double(n) * Double(dt) }
            if played, bored < 0, stage == "-" { bored = Double(n) * Double(dt) }
            if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(s.worldPos.point) { off += 1 }
        }
        return (firstBat, bored, off, retreats)
    }
    func preset(_ name: String) -> Personality { Personality.presets.first { $0.name == name }!.p }
    for kind in ToyKind.allCases {
        // (Two goes: whether it gets round to a toy in time is a matter of chance.)
        var r = play(kind, preset("Friendly"))
        if r.firstBat < 0 || r.bored < 0 { r = play(kind, preset("Friendly")) }
        expect("toy \(kind.label): a spider finds it, plays, and tires of it", r.firstBat >= 0 && r.bored > r.firstBat && r.off == 0,
               String(format: "first bat %.0fs, bored at %.0fs, off %d", r.firstBat, r.bored, r.off))
    }
    var shyRetreats = 0, boldRetreats = 0
    for _ in 0..<5 {
        boldRetreats += play(.ball, preset("Hyper"), secs: 90).retreats
        shyRetreats += play(.ball, preset("Shy"), secs: 90).retreats
    }
    // A ball put down near it, twenty times over: how long before it is
    // after it — the lively at once, the lazy when they get round to it.
    func reaction(_ p: Personality) -> Double {
        let s = Spider(map: map)
        s.config.followCursor = false
        var d = SpiderDesign(); d.personality = p
        s.apply(design: d)
        _ = settleUntilAttached(s)
        s.debugActivity("rest", for: 20)
        let box = ToyBox(map: map); box.scale = 0.95
        s.toys = box
        let toy = box.place(.ball, at: s.worldPos + V2(200, 120))
        toy.grab(at: toy.pos)
        box.update(dt: dt)
        toy.release(fling: .zero)
        var n = 0
        while CGFloat(n) * dt < 4 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); box.update(dt: dt); n += 1
            if s.debugToy.hasPrefix("play") || s.debugToy.hasPrefix("investigate") { break }
        }
        return Double(n) * Double(dt)
    }
    let hyperReact = (0..<20).map { _ in reaction(preset("Hyper")) }.reduce(0, +) / 20
    let lazyReact = (0..<20).map { _ in reaction(preset("Lazy")) }.reduce(0, +) / 20
    expect("toys: a lively spider is after a toy sooner than a lazy one", hyperReact * 2 < lazyReact,
           String(format: "hyper %.2fs, lazy %.2fs on average", hyperReact, lazyReact))
    expect("toys: only a timid one backs away", boldRetreats == 0, "shy \(shyRetreats), hyper \(boldRetreats)")
}

// Toys played with the pointer: thrown for it, it goes straight for it,
// like the dot; a feather dangled for it keeps it at it, leaping, with no
// tiring of it while you play.
do {
    func friendly() -> Spider {
        let s = Spider(map: map)
        s.config.followCursor = false
        var d = SpiderDesign(); d.personality = Personality.presets.first { $0.name == "Friendly" }!.p
        s.apply(design: d)
        _ = settleUntilAttached(s)
        s.debugActivity("rest", for: 20)
        return s
    }
    for kind in ToyKind.allCases where kind != .feather {
        let s = friendly()
        let box = ToyBox(map: map); box.scale = 0.95
        s.toys = box
        let toy = box.place(kind, at: s.worldPos + V2(260, 220))
        toy.grab(at: toy.pos)
        // Held up for it a few seconds first: it waits on it, eyes on it.
        for _ in 0..<(60 * 3) { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); box.update(dt: dt) }
        expect("held \(kind.label): waits on it in your hand", s.debugToy.hasPrefix("play"), s.debugToy + " — " + s.debugState)
        toy.release(fling: V2(-150, 50))
        toy.wind()
        var reacted = -1.0, reached = -1.0, n = 0
        while CGFloat(n) * dt < 15, reached < 0 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); box.update(dt: dt); n += 1
            if reacted < 0, s.debugToy.hasPrefix("play") { reacted = Double(n) * Double(dt) }
            if s.worldPos.distance(to: toy.pos) < 45 { reached = Double(n) * Double(dt) }
        }
        expect("thrown \(kind.label): goes straight for it", reacted >= 0 && reacted < 2.5 && reached >= 0,
               String(format: "after %.1fs, there at %.1fs — %@", reacted, reached, s.debugState))
    }
    do {
        let s = friendly()
        let box = ToyBox(map: map); box.scale = 0.95
        s.toys = box
        let f = box.place(.feather, at: s.worldPos + V2(0, 150))
        f.grab(at: f.pos)
        let home = f.pos
        var n = 0, leaps = 0, lastMode = "", ended = false, dropped = false, hand = f.pos
        while CGFloat(n) * dt < 40 {
            // Waved slowly back and forth over it, re-caught if it pulls it off.
            let tt = CGFloat(n) * dt
            if !f.held { dropped = true; f.grab(at: hand) }
            hand = home + V2(sin(tt * 0.8) * 140, 0)
            f.drag(to: hand)
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); box.update(dt: dt); n += 1
            let m = String(s.debugState.prefix(4))
            if m == "jump", lastMode != "jump" { leaps += 1 }
            lastMode = m
            if n > 60 * 3, !s.debugToy.hasPrefix("play") && !s.debugToy.hasPrefix("investigate") { ended = true }
        }
        expect("dangled feather: leaps at it, again and again", leaps >= 3, "\(leaps) leaps")
        expect("dangled feather: stays on its string", !dropped)
        expect("dangled feather: never tires of it while you play", !ended, s.debugToy)
    }
}

// Traces: what it leaves about. Silk fastened to real edges rides along
// with them, stretches, and snaps when pulled apart; a window brought
// between its ends cuts it, and one closed lets go of it; the pointer
// pushes it aside slowly and snaps it quickly. Husks land on ledges, ride
// along, fall when the ledge goes and can be flicked off. Flies stick in
// the silk. And the spider itself leaves lines behind its leaps and
// drops, spins webs, carries its catch off to eat and hauls toys about —
// none of it with traces turned off.
do {
    print("\n--- traces ---")
    let away = V2(-4000, -4000)
    func tick(_ k: TraceKeeper, spider s: Spider? = nil, box: ToyBox? = nil, cursor: V2 = V2(-4000, -4000),
              prey: [Prey] = [], frames: Int, each: (() -> Void)? = nil) {
        for _ in 0..<frames {
            box?.update(dt: dt)
            if let s { s.setCursor(cursor); s.update(dt: dt) }
            for p in prey { p.update(dt: dt, t: 0, map: map, spider: away) }
            k.update(dt: dt, cursor: cursor, prey: s?.prey ?? prey, spider: s?.worldPos, spiderGrounded: s?.isStanding ?? false)
            each?()
        }
    }
    let pair = [
        TrackedWindow(id: 11, frame: CGRect(x: screen.minX + 200, y: screen.minY + 300, width: 300, height: 300), depth: 1, owner: "A"),
        TrackedWindow(id: 12, frame: CGRect(x: screen.minX + 700, y: screen.minY + 300, width: 300, height: 300), depth: 2, owner: "B"),
    ]
    func moved(_ w: TrackedWindow, _ dx: CGFloat, depth: Int? = nil) -> TrackedWindow {
        TrackedWindow(id: w.id, frame: w.frame.offsetBy(dx: dx, dy: 0), depth: depth ?? w.depth, owner: w.owner)
    }
    let aR = V2(screen.minX + 500, screen.minY + 450), bL = V2(screen.minX + 700, screen.minY + 450)
    func strandBetween(_ k: TraceKeeper, _ a: V2, _ b: V2) -> Strand? {
        guard let pa = SilkPin.at(a, map: map), let pb = SilkPin.at(b, map: map),
              let id = k.leaveLine([a, V2.lerp(a, b, 0.5) - V2(0, 6), b], from: pa, to: pb) else { return nil }
        return k.strand(id)
    }

    // Between two windows: rides along, stretches, snaps.
    do {
        map.rebuild(windows: pair)
        let k = TraceKeeper(map: map); k.scale = 0.95
        guard let s = strandBetween(k, aR, bL) else { expect("traces: a strand between two windows", false, "no pins"); throw CancellationError() }
        tick(k, frames: 180)
        let sag = (s.rope.head + s.rope.tail) * 0.5 - s.rope.points[s.rope.points.count / 2]
        expect("strand: hangs between them, sagging a little, and comes to rest", s.asleep && sag.y > 0 && sag.y < 40,
               String(format: "sag %.1f, asleep %@", Double(sag.y), s.asleep ? "yes" : "no"))
        map.rebuild(windows: [moved(pair[0], -30), pair[1]])
        tick(k, frames: 30)
        expect("strand: rides along with a window dragged, stretching", k.strand(s.id) != nil && abs(s.rope.head.x - (aR.x - 30)) < 1,
               "head at \(Int(s.rope.head.x)), window edge at \(Int(aR.x - 30))")
        map.rebuild(windows: [moved(pair[0], -200), pair[1]])
        tick(k, frames: 30)
        let loose = k.strands.filter { $0.kind == .loose }
        expect("strand: pulled too far apart, it snaps, each end left hanging", k.strand(s.id) == nil && loose.count == 2, k.debugSummary)
        let hanging = loose.map { $0.rope.tail.y < $0.rope.head.y - 10 }
        tick(k, frames: 120)
        expect("strand: the loose ends hang down", loose.allSatisfy { $0.rope.tail.y < $0.rope.head.y - 10 }, "\(hanging)")
        map.rebuild(windows: [pair[1]])
        tick(k, frames: 150)
        expect("strand: the end on a window that closed goes with it", k.strands.filter { $0.kind == .loose }.count == 1, k.debugSummary)
    }

    // A window brought in front, between the ends, cuts it; one over an
    // end unsticks that end.
    do {
        map.rebuild(windows: pair)
        let k = TraceKeeper(map: map); k.scale = 0.95
        let s = strandBetween(k, aR, bL)!
        tick(k, frames: 60)
        let front = TrackedWindow(id: 13, frame: CGRect(x: screen.minX + 560, y: screen.minY + 250, width: 80, height: 400), depth: 0, owner: "C")
        map.rebuild(windows: [front, moved(pair[0], 0, depth: 1), moved(pair[1], 0, depth: 2)])
        tick(k, frames: 30)
        expect("strand: a window brought in front between its ends cuts it", k.strand(s.id) == nil && k.strands.filter { $0.kind == .loose }.count == 2, k.debugSummary)
        map.rebuild(windows: pair)
        let k2 = TraceKeeper(map: map); k2.scale = 0.95
        let s2 = strandBetween(k2, aR, bL)!
        tick(k2, frames: 60)
        let overEnd = TrackedWindow(id: 14, frame: CGRect(x: screen.minX + 420, y: screen.minY + 380, width: 150, height: 150), depth: 0, owner: "D")
        map.rebuild(windows: [overEnd, moved(pair[0], 0, depth: 1), moved(pair[1], 0, depth: 2)])
        tick(k2, frames: 30)
        expect("strand: a window over one end unsticks it there; it hangs from the other", s2.kind == .loose && s2.head?.loopID == "win:12", "\(s2.kind) from \(s2.head?.loopID ?? "-")")
        // Across two rim edges — the menu bar and the floor — nothing comes in front of it.
        map.rebuild(windows: windows)
        let k3 = TraceKeeper(map: map); k3.scale = 0.95
        let top = V2(screen.minX + 300, (map.menuBarBottom(for: screen) ?? screen.maxY))
        if let st = strandBetween(k3, top, V2(screen.minX + 300, screen.minY)) {
            tick(k3, frames: 60)
            expect("strand: from the menu bar to the floor, down over windows, stays", k3.strand(st.id) != nil, k3.debugSummary)
        } else {
            print("  [skip] no menu bar here")
        }
    }

    // The pointer: a slow push bends it and it springs back; a swipe snaps it.
    do {
        map.rebuild(windows: pair)
        let k = TraceKeeper(map: map); k.scale = 0.95
        let s = strandBetween(k, aR, bL)!
        tick(k, frames: 120)
        let restY = s.rope.points[7].y
        var lowest = restY
        var c = V2(screen.minX + 600, screen.minY + 520)
        for _ in 0..<60 {
            c.y -= 2.2
            tick(k, cursor: c, frames: 1)
            lowest = min(lowest, s.rope.points[7].y)
        }
        tick(k, frames: 180)
        expect("strand: pushed slowly with the pointer, it bends and does not break", k.strand(s.id) != nil && lowest < restY - 8,
               String(format: "bent %.0f px, now %@", Double(restY - lowest), k.debugSummary))
        expect("strand: and springs back", abs(s.rope.points[7].y - restY) < 3, String(format: "%.1f px off", Double(s.rope.points[7].y - restY)))
        tick(k, cursor: V2(screen.minX + 600, screen.minY + 580), frames: 1)
        tick(k, cursor: V2(screen.minX + 600, screen.minY + 560), frames: 1)
        tick(k, cursor: V2(screen.minX + 600, screen.minY + 340), frames: 1)
        expect("strand: swiped through quickly, it snaps", k.strand(s.id) == nil, k.debugSummary)
    }

    // Leftovers: onto a window's top, along with it, off when it goes.
    do {
        map.rebuild(windows: windows)
        let k = TraceKeeper(map: map); k.scale = 0.95
        let w = windows[0].frame
        k.leaveLeftover(of: .moth, at: V2(w.midX - 100, w.maxY + 30), facing: 1)
        k.leaveLeftover(of: .ant, at: V2(w.midX, w.maxY + 30), facing: 1)
        expect("leftovers: nothing much is left of an ant", k.leftovers.count == 1)
        guard let l = k.leftovers.first else { throw CancellationError() }
        tick(k, frames: 120)
        expect("leftovers: lands on the window's top", l.rest?.loopID == "win:1" && abs(l.pos.y - w.maxY) < 12, "\(l.rest?.loopID ?? "air") at \(Int(l.pos.y))")
        let x0 = l.pos.x
        map.rebuild(windows: [moved(windows[0], 60), windows[1], windows[2]])
        tick(k, frames: 10)
        expect("leftovers: rides along when the window is dragged", abs(l.pos.x - x0 - 60) < 1.5, "moved \(Int(l.pos.x - x0))")
        map.rebuild(windows: [windows[1], windows[2]])
        tick(k, frames: 240)
        expect("leftovers: falls when the window closes, onto whatever is below", l.rest != nil && l.pos.y < w.maxY - 100,
               "\(l.rest?.loopID ?? "air") at \(Int(l.pos.y))")
        let before = l.pos
        tick(k, cursor: before + V2(-40, 3), frames: 1)
        tick(k, cursor: before + V2(40, 3), frames: 1)
        tick(k, frames: 180)
        expect("leftovers: flicked away by a quick pointer", l.pos.distance(to: before) > 20, "moved \(Int(l.pos.distance(to: before))) px")
        map.rebuild(windows: windows)
    }

    // The most at once: past it, the oldest fade; with no limit, none do.
    do {
        for limit in [3, nil] as [Int?] {
            let k = TraceKeeper(map: map); k.scale = 0.95; k.limit = limit
            for i in 0..<6 {
                k.leaveLeftover(of: .moth, at: V2(screen.minX + 200 + CGFloat(i) * 60, screen.minY + 60), facing: 1)
                tick(k, frames: 20)
            }
            let newest = k.leftovers.map(\.id).sorted().suffix(3)
            tick(k, frames: 60 * 6)
            if let n = limit {
                expect("limit \(n): only that many are left, the newest", k.leftovers.count == n && Set(k.leftovers.map(\.id)) == Set(newest),
                       k.debugSummary)
            } else {
                expect("no limit: they all stay", k.leftovers.count == 6, k.debugSummary)
            }
        }
        let k = TraceKeeper(map: map); k.scale = 0.95; k.limit = nil
        for i in 0..<5 { k.leaveLeftover(of: .beetle, at: V2(screen.minX + 200 + CGFloat(i) * 60, screen.minY + 60), facing: 1) }
        tick(k, frames: 30)
        k.limit = 2
        tick(k, frames: 60 * 6)
        expect("limit lowered: the extra fade away at once", k.leftovers.count == 2, k.debugSummary)
    }

    // A fly stuck in the silk, struggling, for a while.
    do {
        map.rebuild(windows: pair)
        let k = TraceKeeper(map: map); k.scale = 0.95
        _ = strandBetween(k, aR, bL)!
        tick(k, frames: 60)
        let fly = Prey(kind: .fruitFly, id: 500, at: V2(screen.minX + 600, screen.minY + 470), scale: 0.95)
        var stuckAt = -1, freedAt = -1, n = 0, far: CGFloat = 0
        while n < 60 * 20 {
            if stuckAt < 0 { fly.pos.y -= 2; fly.vel = V2(0, -120) }
            tick(k, prey: [fly], frames: 1)
            n += 1
            if stuckAt < 0, k.isSnagged(fly.id) { stuckAt = n }
            if stuckAt >= 0, freedAt < 0 { far = max(far, abs(fly.pos.y - (screen.minY + 450))) }
            if stuckAt >= 0, freedAt < 0, !k.isSnagged(fly.id) { freedAt = n }
        }
        expect("snag: a fly flying into the silk is caught in it", stuckAt >= 0, "never")
        expect("snag: and held there, struggling", far < 16, String(format: "strayed %.0f px", Double(far)))
        expect("snag: until it struggles free", freedAt > stuckAt && CGFloat(freedAt - stuckAt) * dt > 4,
               String(format: "stuck %.1fs", Double(CGFloat(max(freedAt - stuckAt, 0)) * dt)))
        map.rebuild(windows: windows)
    }

    Spider.debugTraceOdds = 1
    let floorLoop = map.loop("screen:0")!
    let fi = floorSeg(floorLoop)

    // Webs: in the corner of the floor and the wall, and under a ledge.
    do {
        let k = TraceKeeper(map: map); k.scale = 0.95
        let s = Spider(map: map); s.config.followCursor = false; s.traces = k
        _ = park(s, loopID: floorLoop.id, segIdx: fi, t: 140)
        let asked = s.debugSpinWeb()
        var n = 0
        while n < 60 * 25, k.webs.first.map({ $0.progress < 1 }) ?? true { tick(k, spider: s, frames: 1); n += 1 }
        let web = k.webs.first
        expect("web: spins one in the corner of the floor", asked && web?.shape == .corner && web?.progress == 1,
               "\(asked ? "went" : "nowhere"), \(k.debugSummary) after \(n / 60)s, \(s.debugState)")
        if let f = web?.frame {
            expect("web: right in the corner", f.o.distance(to: V2(screen.minX, floorLoop.edge[fi].a.y)) < 2 && f.x.dot(f.y) > -0.1,
                   "at \(Int(f.o.x)),\(Int(f.o.y))")
        }
        // Under the editor's bottom edge.
        let k2 = TraceKeeper(map: map); k2.scale = 0.95
        let s2 = Spider(map: map); s2.config.followCursor = false; s2.traces = k2
        _ = park(s2, loopID: "win:1", segIdx: 2, t: 300)
        let under = s2.debugSpinWeb()
        n = 0
        while n < 60 * 20, k2.webs.first.map({ $0.progress < 1 }) ?? true { tick(k2, spider: s2, frames: 1); n += 1 }
        expect("web: spins a tangle under a window it hangs from", under && k2.webs.first?.shape == .underside && k2.webs.first?.progress == 1,
               "\(k2.debugSummary), \(s2.debugState)")
    }

    // A fly in its web: it feels it, and comes for it.
    do {
        let k = TraceKeeper(map: map); k.scale = 0.95
        let s = Spider(map: map); s.config.followCursor = false; s.traces = k
        k.onTremble = { p, strength in s.feelTremble(at: p, strength: strength) }
        _ = park(s, loopID: floorLoop.id, segIdx: fi, t: 140)
        _ = s.debugSpinWeb()
        var n = 0
        while n < 60 * 25, k.webs.first.map({ $0.progress < 1 }) ?? true { tick(k, spider: s, frames: 1); n += 1 }
        _ = settle(s, seconds: 3)
        if let web = k.webs.first, let inWeb = web.world(V2(0.3, 0.25)) {
            let fly = s.release(.fruitFly)
            fly.pos = inWeb + V2(0, 8)
            fly.vel = V2(0, -60)
            fly.noticed = false
            var stuck = false, caught = -1.0
            n = 0
            while n < 60 * 40, caught < 0 {
                tick(k, spider: s, frames: 1)
                n += 1
                if k.isSnagged(fly.id) { stuck = true }
                if fly.state != .loose { caught = Double(n) * Double(dt) }
            }
            expect("web: a fly blundering in is stuck", stuck)
            expect("web: and it comes for it", caught >= 0, caught < 0 ? s.debugState : String(format: "%.0fs", caught))
        }
    }

    // Its catch carried off to the end of its ledge, eaten there, and
    // what is left of it left there.
    do {
        let k = TraceKeeper(map: map); k.scale = 0.95
        let s = Spider(map: map); s.config.followCursor = false; s.traces = k
        _ = park(s, loopID: floorLoop.id, segIdx: fi, t: 200)
        let cricket = s.release(.cricket)
        s.debugCatch(cricket)
        let from = s.worldPos
        var carried: CGFloat = 0, eaten = false, n = 0, carryFrames = 0
        while n < 60 * 25, !eaten {
            tick(k, spider: s, frames: 1)
            n += 1
            if s.debugCarrying { carryFrames += 1; carried = max(carried, s.worldPos.distance(to: from)) }
            eaten = cricket.state == .eaten
        }
        expect("meal: carried off along its ledge before it is eaten", carried > 60, String(format: "carried %.0f px over %.1fs", Double(carried), Double(CGFloat(carryFrames) * dt)))
        expect("meal: then eaten", eaten, s.debugState)
        tick(k, spider: s, frames: 120)
        expect("meal: and the leftovers left lying on the floor", k.leftovers.count == 1 && k.leftovers.first?.rest != nil, k.debugSummary)
    }

    // Lines left behind: a leap trails one, fastened where it lands; the
    // line it came down on, left where it stepped off.
    do {
        let k = TraceKeeper(map: map); k.scale = 0.95
        let s = Spider(map: map); s.config.followCursor = false; s.traces = k
        let w0 = windows[0].frame, w1 = windows[1].frame
        _ = park(s, loopID: "win:1", segIdx: 0, t: w0.width - 340)
        s.debugJump(to: V2(w1.minX + 260, w1.maxY + map.standoff))
        var leapt = false, n = 0
        while n < 60 * 6 { tick(k, spider: s, frames: 1); n += 1; if s.debugState.hasPrefix("jump") { leapt = true }; if leapt, s.isStanding { break } }
        tick(k, spider: s, frames: 90)
        let leap = k.strands.first { $0.kind == .leap }
        expect("leap: trails a line, fastened from where it went to where it came down",
               leapt && leap?.head?.loopID == "win:1" && leap?.tail != nil && leap?.spinnerets == nil,
               "\(k.debugSummary) \(leap?.head?.loopID ?? "-") -> \(leap?.tail?.loopID ?? "-"), \(s.debugState)")

        var hang: Strand?
        for _ in 0..<6 where hang == nil {
            let k2 = TraceKeeper(map: map); k2.scale = 0.95
            let s2 = Spider(map: map); s2.config.followCursor = false; s2.traces = k2
            _ = park(s2, loopID: "win:1", segIdx: 2, t: 300)
            s2.debugRappel()
            var m = 0
            while m < 60 * 50, hang == nil {
                tick(k2, spider: s2, frames: 1)
                m += 1
                hang = k2.strands.first { $0.kind == .hang }
                if m > 120, s2.isStanding, hang == nil { break }
            }
        }
        expect("drop: the line it came down on is left, from the window above to where it stepped off",
               hang?.head?.loopID == "win:1" && hang?.tail != nil, hang.map { "\($0.head?.loopID ?? "-") -> \($0.tail?.loopID ?? "-")" } ?? "never came down it")
    }

    // A toy hauled off on a line.
    do {
        let k = TraceKeeper(map: map); k.scale = 0.95
        let box = ToyBox(map: map); box.scale = 0.95
        k.toyBox = box
        let s = Spider(map: map); s.config.followCursor = false; s.traces = k; s.toys = box
        let seg = floorLoop.segs[fi]
        _ = park(s, loopID: floorLoop.id, segIdx: fi, t: 300)
        let ball = Toy(kind: .bell, id: 70, at: seg.point(at: 330) + V2(0, 10), scale: 0.95)
        box.debugInsert(ball)
        tick(k, box: box, frames: 90)
        let start = ball.pos
        let hitched = s.debugTow()
        var towed: CGFloat = 0, n = 0, wasTowing = false
        while n < 60 * 9 {
            tick(k, spider: s, box: box, frames: 1)
            n += 1
            if s.debugTowing { wasTowing = true; towed = max(towed, (start - ball.pos).dot(seg.dir)) }
            if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil, n % 15 == 0 {
                print(String(format: "    tow t=%.2f spider x %.0f ball x %.0f roll-ish %.0f  %@ %@", Double(CGFloat(n) * dt), Double(s.worldPos.x), Double(ball.pos.x), Double(ball.vel.x), s.debugState, k.debugSummary))
            }
            if wasTowing, !s.debugTowing { break }
        }
        tick(k, spider: s, box: box, frames: 60)
        expect("tow: hitches a line to the toy and hauls it off along the ledge", hitched && towed > 30,
               String(format: "hauled %.0f px, %@", Double(towed), k.debugSummary))
        expect("tow: lets go of it after a while, the line left on the toy", !s.debugTowing && ball.onSurface && k.strands.contains { $0.toyID == ball.id },
               "\(s.debugState) \(k.debugSummary)")
    }

    // Left to itself for a while, it leaves this and that about; with
    // traces off, nothing at all.
    Spider.debugTraceOdds = nil
    for on in [true, false] {
        let k = TraceKeeper(map: map); k.scale = 0.95; k.enabled = on
        let s = Spider(map: map); s.traces = k; s.config.liveliness = 3
        k.onTremble = { p, strength in s.feelTremble(at: p, strength: strength) }
        _ = settleUntilAttached(s)
        var made = Set<Int>(), webs = Set<Int>(), bits = Set<Int>(), strayed = 0, n = 0
        var feedAt = 40
        while n < 60 * 240 {
            let tt = CGFloat(n) * dt
            let c = V2(screen.midX + cos(tt * 0.23) * 500, screen.midY + sin(tt * 0.17) * 320)
            if n / 60 == feedAt { _ = s.release(PreyKind.allCases.randomElement()!); feedAt += 50 }
            tick(k, spider: s, cursor: c, frames: 1)
            n += 1
            for st in k.strands where st.kind != .free { made.insert(st.id) }
            for w in k.webs { webs.insert(w.id) }
            for l in k.leftovers { bits.insert(l.id) }
            for st in k.strands where st.rope.live {
                if st.rope.points.contains(where: { !map.worldBounds.insetBy(dx: -300, dy: -300).contains($0.point) }) { strayed += 1 }
            }
        }
        if on {
            print("    240s of life: \(made.count) strands, \(webs.count) webs, \(bits.count) leftovers; now \(k.debugSummary)")
            expect("traces on: it leaves something about in four minutes", made.count + webs.count + bits.count > 0)
            expect("traces on: the silk stays on the desktop", strayed == 0, "\(strayed) frames off it")
        } else {
            expect("traces off: it leaves nothing at all", made.isEmpty && webs.isEmpty && bits.isEmpty && k.isEmpty, k.debugSummary)
        }
    }
    map.rebuild(windows: windows)
} catch {}

// Every stretch where the body went along the ground with all its feet
// down and sliding with it. Landings touch down with a few px of it; a
// long one is sliding on ice.
print("\n--- gliding (feet sliding over the ground, none lifted) ---")
let runs = Spider.debugGlideRuns
print(String(format: "%d glides; over 10 px: %d; over 25 px: %d", runs.count, runs.filter { $0.px > 10 }.count, runs.filter { $0.px > 25 }.count))
var byWhat: [String: (n: Int, px: CGFloat)] = [:]
for r in runs where r.px > 5 {
    let k = r.what.components(separatedBy: " ").prefix(2).joined(separator: " ")
    byWhat[k, default: (0, 0)].n += 1; byWhat[k, default: (0, 0)].px += r.px
}
for (k, v) in byWhat.sorted(by: { $0.value.px > $1.value.px }) { print(String(format: "  %-20@ %4d over 5 px, %6.0f px in all", k as NSString, v.n, v.px)) }
print("longest:")
for r in runs.sorted(by: { $0.px > $1.px }).prefix(8) { print(String(format: "  %5.1f px over %3d frames  %@", r.px, r.frames, r.what as NSString)) }
