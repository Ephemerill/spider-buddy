import AppKit

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

// Feeding: each kind of prey gets hunted down and eaten, and it cheers up.
for kind in PreyKind.allCases {
    let s = Spider(map: map)
    s.config.followCursor = false
    _ = settleUntilAttached(s)
    let p = s.release(kind)
    var caughtAt = -1.0
    var eatenAt = -1.0
    var seen: [String] = []
    var n = 0
    var off = 0
    let limit: CGFloat = kind == .fruitFly ? 150 : 90
    while CGFloat(n) * dt < limit {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        if seen.last != st { seen.append(st) }
        if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(s.worldPos.point) { off += 1 }
        if !map.worldBounds.insetBy(dx: -60, dy: -60).contains(p.pos.point) { off += 1 }
        if caughtAt < 0, p.state != .loose { caughtAt = Double(n) * Double(dt) }
        if ProcessInfo.processInfo.environment["SIM_DEBUG"] != nil, n % 120 == 0 {
            print("    \(kind.label) t=\(n / 60)s \(st) spider=\(Int(s.worldPos.x)),\(Int(s.worldPos.y)) prey=\(Int(p.pos.x)),\(Int(p.pos.y)) on=\(p.anchor?.loopID ?? "air") \(p.state)")
        }
        if p.state == .eaten { eatenAt = Double(n) * Double(dt); break }
    }
    let tail = seen.suffix(5).joined(separator: " > ")
    expect("\(kind.label): catches it", caughtAt >= 0, caughtAt < 0 ? "never  " + tail : "")
    expect("\(kind.label): eats it", eatenAt >= 0, String(format: "%.0fs  ", eatenAt) + tail)
    expect("\(kind.label): well fed afterwards", s.fed > 0.2, "fed \(s.fed)")
    expect("\(kind.label): both stay on the desktop", off == 0, "off \(off)")
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
    tank.rebuild(scene: scene, loops: hab.loops(standoff: tank.standoff))
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
// too: the only way is down, on its dragline. It catches itself well above
// the floor, and since home is under the window now it goes on down to
// the floor or leaps — it never climbs back up under the window.
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
    var catchY: CGFloat?
    var lowestOnLine = CGFloat.greatestFiniteMagnitude
    var backUnder = 0
    var done = ""
    var last = ""
    while CGFloat(n) * dt < 30 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        let kind = String(st.split(separator: ":").first ?? "")
        if seen.last != kind { seen.append(kind) }
        if kind == "dangling" || kind == "swinging" {
            if catchY == nil { catchY = s.worldPos.y }
            lowestOnLine = min(lowestOnLine, s.worldPos.y)
        }
        if last == "dangling", kind == "attached", cover.contains(s.worldPos.point) { backUnder += 1 }
        last = kind
        if st.hasPrefix("attached"), CGFloat(n) * dt > 3, !cover.contains(s.worldPos.point) { done = st; break }
    }
    expect("covered, only way is down: drops on its dragline", catchY != nil, seen.joined(separator: " > "))
    expect("covered, only way is down: catches well above the floor", (catchY ?? 0) - screen.minY > 140, "caught \(Int((catchY ?? 0) - screen.minY)) px up")
    expect("covered, only way is down: does not climb back under the window", backUnder == 0, seen.joined(separator: " > "))
    expect("covered, only way is down: ends up standing in the open", !done.isEmpty, done.isEmpty ? s.debugState + "  " + seen.joined(separator: " > ") : done)
}

// A window dropped right over it while it stands on another window's
// shelf, with the open part of the shelf close by: it scurries out along
// the shelf rather than firing lines and falling about, and once out it
// stays out.
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
    var wild = 0
    var backUnder = 0
    while CGFloat(n) * dt < 8 {
        s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
        let st = s.debugState
        if seen.last != st { seen.append(st) }
        let kind = String(st.split(separator: ":").first ?? "")
        // (Once out it is its own spider again; only the escape itself
        // must be tidy.)
        if CGFloat(n) * dt < 3, kind == "fall" || kind == "dangling" || kind == "jump" || st.contains(":shoot") { wild += 1 }
        let under = cover.contains(s.worldPos.point)
        if out < 0, !under { out = Double(n) * Double(dt) }
        if out >= 0, under { backUnder += 1 }
    }
    expect("covered with the open shelf near: scurries out along it", out >= 0 && out < 2.5 && wild == 0,
           (out < 0 ? "never left" : String(format: "out in %.1fs", out)) + ", wild frames \(wild)  " + seen.prefix(5).joined(separator: " > "))
    expect("covered with the open shelf near: stays out", backUnder == 0, "\(backUnder) frames back under it")
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
