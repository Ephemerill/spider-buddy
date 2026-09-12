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
    let after = settle(s, seconds: 6, cursor: V2(-4000, -4000))
    expect("and it comes down on something", after.hasPrefix("attached") || after == "dangling", after)
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

// Peek-a-boo: with a window overlapping the floor and someone about, it
// hides behind the window's edge and pops out, more than once.
do {
    let pm = SurfaceMap()
    pm.standoff = map.standoff
    let over = TrackedWindow(id: 8, frame: CGRect(x: screen.minX + 500, y: screen.minY - 80, width: 400, height: 300), depth: 0, owner: "Overlap")
    pm.rebuild(windows: [over])
    let s = Spider(map: pm)
    s.config.followCursor = true
    if let f = pm.loops.first(where: { $0.id.hasPrefix("screen") }) { s.debugAttach(loopID: f.id, segIdx: floorSeg(f), t: 300, dir: 1) }
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

// A quick swipe of the pointer near it: a small nervous hop with "!!".
do {
    let s = Spider(map: map)
    s.config.followCursor = true
    _ = settleUntilAttached(s)
    s.debugActivity("look", for: 4)
    _ = settle(s, seconds: 0.5, cursor: V2(-4000, -4000))
    let p = s.worldPos
    // A fast swipe past, 80 px off.
    var n = 0
    var hopped = false
    var exclaimed = false
    while CGFloat(n) * dt < 1.0 {
        let x = p.x - 200 + CGFloat(n) * 40          // 2400 px/s
        s.setCursor(V2(x, p.y + 80)); s.update(dt: dt); n += 1
        if s.debugState.contains(":hop") { hopped = true }
        if s.pose().emote == .exclaim { exclaimed = true }
    }
    expect("a quick swipe nearby: a nervous hop", hopped, s.debugState)
    expect("a quick swipe nearby: exclamation marks", exclaimed, "")
    // And it is small: it does not run off.
    let after = settle(s, seconds: 0.5, cursor: V2(-4000, -4000))
    expect("a nervous hop is just a hop", s.worldPos.distance(to: p) < 40 && !after.contains(":scurry"), "\(Int(s.worldPos.distance(to: p))) px away, \(after)")
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

// A window closing under its feet.
let s4 = Spider(map: map)
_ = settleUntilAttached(s4)
var tries = 0
while !s4.debugState.contains("win:") && tries < 40 { _ = settle(s4, seconds: 2); tries += 1 }
if s4.debugState.contains("win:") {
    map.rebuild(windows: [])
    let dropped = settle(s4, seconds: 0.3)
    expect("falls when its window closes", dropped == "fall" || dropped == "dangling", dropped)
    let recovered = settle(s4, seconds: 8, cursor: V2(-4000, -4000))
    expect("recovers afterwards", recovered.hasPrefix("attached") || recovered == "dangling" || recovered == "swinging", recovered)
    map.rebuild(windows: windows)
} else {
    print("  [skip] never boarded a window in time")
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
    var g = s6.gait; g.webbiness = 1; s6.apply(design: SpiderDesign(name: "S", look: SpiderLook(), personality: Personality(), gait: g))
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
    while CGFloat(n) * dt < 150, !built {
        s7.setCursor(V2(-4000, -4000)); s7.update(dt: dt); n += 1
        if s7.debugState == "building" { seenBuilding = true }
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
