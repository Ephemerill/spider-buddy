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
expect("a thrown spider ends up somewhere", after.hasPrefix("attached") || after == "dangling", after)

// Fling it hard upward: should bounce or catch itself on a line, not vanish.
s2.beginGrab(at: s2.worldPos)
s2.endGrab(throwVelocity: V2(-2400, 2200))
let after2 = settle(s2, seconds: 8, cursor: V2(-4000, -4000))
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
    expect("it descends", s3.worldPos.y < yStart - 25,
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
                s.debugAttach(loopID: sl.id, segIdx: 0, t: 500, dir: 1)
            }
        } else if let w = windows.first {
            s.debugAttach(loopID: "win:\(w.id)", segIdx: 0, t: 120, dir: 1)
        }
        for _ in 0..<20 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt) }
        let p = s.worldPos
        let cover = CGRect(x: p.x - 160, y: p.y - 120, width: 320, height: 240)
        map.rebuild(windows: windows + [TrackedWindow(id: 777, frame: cover, depth: -1, owner: "Mock")])
        var seen: [String] = []
        var n = 0
        var out = -1.0
        while CGFloat(n) * dt < 10 {
            s.setCursor(V2(-4000, -4000)); s.update(dt: dt); n += 1
            let st = s.debugState
            if seen.last != st { seen.append(st) }
            if out < 0, !cover.insetBy(dx: -10, dy: -10).contains(s.worldPos.point) { out = Double(n) * Double(dt) }
        }
        let where_ = trial == 0 ? "floor" : "shelf"
        expect("covered on the \(where_): gets clear quickly", out >= 0 && out < 2.5,
               out < 0 ? "never left  " + seen.joined(separator: " > ") : String(format: "%.1fs  ", out) + seen.prefix(6).joined(separator: " > "))
        let end = s.debugState
        expect("covered on the \(where_): settles somewhere clear", (end.hasPrefix("attached") || end == "dangling" || end == "nesting") && !cover.contains(s.worldPos.point), end)
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
    expect("\(kind.label): stays on the desktop", off == 0, "off \(off)")
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
        s6.debugAttach(loopID: sl.id, segIdx: 0, t: 300, dir: 1)
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

// Full-screen app: keep out of the way, asleep in a bottom corner (or the hammock).
do {
    let s8 = Spider(map: map)
    s8.config.followCursor = true
    _ = settleUntilAttached(s8)
    s8.fullScreenApp = true
    var n = 0
    var asleepAt: CGFloat = -1
    while CGFloat(n) * dt < 120 {
        s8.setCursor(V2(screen.midX + cos(CGFloat(n) * 0.02) * 300, screen.midY)); s8.update(dt: dt); n += 1
        if asleepAt < 0, s8.debugState.hasPrefix("attached:sleep") { asleepAt = CGFloat(n) * dt }
    }
    let p = s8.worldPos
    let nearBottom = p.y - screen.minY < 60
    let nearSide = min(p.x - screen.minX, screen.maxX - p.x) < 120
    expect("full screen: goes to sleep in a bottom corner", asleepAt > 0 && nearBottom && nearSide,
           "\(asleepAt > 0 ? "asleep after \(Int(asleepAt))s" : "never slept"), at \(Int(p.x - screen.minX)),\(Int(p.y - screen.minY)) from bottom-left, now \(s8.debugState)")
    expect("stays asleep with the pointer about", s8.debugState.hasPrefix("attached:sleep"), s8.debugState)
    s8.fullScreenApp = false
    var woke = false
    n = 0
    while CGFloat(n) * dt < 30, !woke {
        s8.setCursor(V2(-4000, -4000)); s8.update(dt: dt); n += 1
        if !s8.debugState.hasPrefix("attached:sleep") { woke = true }
    }
    expect("wakes when the app leaves full screen", woke, "\(Int(CGFloat(n) * dt))s, \(s8.debugState)")

    // With a hammock, that is where it goes.
    let s9 = Spider(map: map)
    s9.config.followCursor = false
    _ = settleUntilAttached(s9)
    s9.restoreHammock(left: true)
    s9.fullScreenApp = true
    var nested = false
    n = 0
    while CGFloat(n) * dt < 120, !nested {
        s9.setCursor(V2(-4000, -4000)); s9.update(dt: dt); n += 1
        if s9.debugState == "nesting" { nested = true }
    }
    expect("full screen with a hammock: sleeps in it", nested, "\(Int(CGFloat(n) * dt))s, \(s9.debugState)")
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
