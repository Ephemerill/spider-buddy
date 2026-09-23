import AppKit

// Smoothness check: what the eye catches in the legs, measured where the
// eye sees it — every foot and knee in screen space, frame by frame.
//
//   snap      a joint's acceleration spikes (a hand-off that jerks)
//   reversal  a joint reverses direction while still moving fast (a leg
//             flicking back and forth, rather than easing through a stop)
//
// Scenarios:
//   pairs     every ordered pair of on-ledge activities, the second cutting
//             into the first early and late: the worst hand-offs
//   sweep     the pointer swept back and forth right over it
//   hover     the pointer resting close by
//   gaze      how far the drawn gaze is off the pointer, on each surface
//
// `./tools/smooth.sh [pairs|sweep|hover|gaze|all]`

let dt: CGFloat = 1.0 / 60.0
let snapA: CGFloat = 2.5        // px/frame², at scale 1
let revV: CGFloat = 0.55        // px/frame both sides of a reversal

let sm = SurfaceMap()
sm.standoff = 22
let screenRect = CGRect(x: 0, y: 0, width: 1200, height: 800)
let win = CGRect(x: 300, y: 200, width: 500, height: 300)
// AIR_NOROUND=1: the feet placed as if the window's corners were square.
sm.debugRebuild(screen: screenRect, menuBarHeight: 0,
                windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock",
                                        cornerRadius: ProcessInfo.processInfo.environment["AIR_NOROUND"] != nil ? 0 : SurfaceMap.windowCornerRadius)])

/// Every joint that is drawn, in screen space: 8 feet then 8 knees, plus
/// the body origin. Slots are re-paired across a mirror flip (leg i is
/// drawn where leg 7-i was), so a flip is not counted as a jump.
func joints(_ p: SpiderPose) -> [V2] {
    let mirror: CGFloat = p.facing >= 0 ? 1 : -1
    let g = SpiderRenderer.ground
    func scr(_ v: V2) -> V2 {
        var q = v
        if p.spin != 0 {
            let c = SpiderRenderer.ballCentre
            q = c + (q - c).rotated(by: p.spin)
        }
        q = V2(q.x * p.stretch, g + (q.y - g) * p.fatten)
        return p.pos + V2(q.x * mirror, q.y).rotated(by: p.heading) * p.scale
    }
    return p.legs.map { scr($0.foot) } + p.legs.map { scr($0.knee) } + [p.pos]
}

struct Tally {
    var snaps = 0, reversals = 0, frames = 0
    var worstA: CGFloat = 0
    var worstJoint = ""
    mutating func add(_ o: Tally) {
        snaps += o.snaps; reversals += o.reversals; frames += o.frames
        if o.worstA > worstA { worstA = o.worstA; worstJoint = o.worstJoint }
    }
    var score: Int { snaps + reversals }
}

final class Meter {
    var prev: [V2] = []
    var vel: [V2] = []
    var prevMirror: CGFloat = 1
    var tally = Tally()
    func reset() { prev = []; vel = []; tally = Tally() }
    func sample(_ p: SpiderPose, measuring: Bool = true) {
        let j = joints(p)
        let mirror: CGFloat = p.facing >= 0 ? 1 : -1
        if mirror != prevMirror {
            // The model swapped leg i with leg 7-i at the flip.
            prev = remap(prev); vel = remap(vel)
        }
        prevMirror = mirror
        defer { prev = j }
        guard prev.count == j.count else { vel = Array(repeating: .zero, count: j.count); return }
        let v = zip(j, prev).map { $0 - $1 }
        defer { vel = v }
        guard measuring, vel.count == v.count else { return }
        tally.frames += 1
        let s = max(p.scale, 0.05)
        for i in 0..<v.count - 1 {
            let a = (v[i] - vel[i]).length / s
            if a > tally.worstA { tally.worstA = a; tally.worstJoint = (i < 8 ? "foot\(i)" : "knee\(i - 8)") }
            if a > snapA { tally.snaps += 1 }
            let v0 = vel[i] / s, v1 = v[i] / s
            if v0.dot(v1) < 0, v0.length > revV, v1.length > revV { tally.reversals += 1 }
        }
    }
    private func remap(_ a: [V2]) -> [V2] {
        guard a.count == 17 else { return a }
        var k = a
        for i in 0..<8 { k[i] = a[7 - i]; k[8 + i] = a[15 - i] }
        return k
    }
}

func freshSpider(followCursor: Bool, loop: String = "win:9", seg: Int = 0, at t: CGFloat = 250) -> Spider {
    let s = Spider(map: sm)
    s.config.scale = 1.0
    s.config.followCursor = followCursor
    s.config.pounceOnCursor = false
    s.debugAttach(loopID: loop, segIdx: seg, t: t, dir: 1)
    return s
}

func activityName(_ s: Spider) -> String { String(s.debugActivity.split(separator: " ").first ?? "") }

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "all"
let far = V2(-9e4, -9e4)
let bigLog = ProcessInfo.processInfo.environment["BIG"] != nil
if ProcessInfo.processInfo.environment["RAW"] != nil { Spider.debugRawLegs = true }

// MARK: - pairs

let ledge = ["look", "rest", "groom", "wave", "curious", "fidget", "scratch", "armsUp", "dance", "glance",
             "peer", "pushup", "legStretch", "stare", "greet", "drum", "wiggle", "bounce", "stretch",
             "shake", "hop", "walk", "sneak", "scurry", "turn", "startle"]

func runPairs() {
    // Each activity alone, from standing: its own motion, to tell a bad
    // hand-off from a busy gesture.
    var solo: [String: Tally] = [:]
    for a in ledge {
        let s = freshSpider(followCursor: false)
        let m = Meter()
        for _ in 0..<30 { s.setCursor(far); s.update(dt: dt); m.sample(s.pose(), measuring: false) }
        s.debugActivity(a, for: 1.4)
        for _ in 0..<Int(2.0 / dt) { s.setCursor(far); s.update(dt: dt); m.sample(s.pose()) }
        solo[a] = m.tally
    }
    print("solo (from standing, 2 s):")
    for a in ledge.sorted(by: { solo[$0]!.score > solo[$1]!.score }) {
        let t = solo[a]!
        print(String(format: "  %-11@ snaps %4d  rev %4d  worst %5.2f %@", a as NSString, t.snaps, t.reversals, t.worstA, t.worstJoint as NSString))
    }

    struct Row { var key: String; var tally: Tally; var excess: Int }
    var rows: [Row] = []
    var total = Tally()
    for a in ledge {
        for b in ledge {
            for cut: CGFloat in [0.3, 1.0] {
                let s = freshSpider(followCursor: false)
                let m = Meter()
                for _ in 0..<30 { s.setCursor(far); s.update(dt: dt); m.sample(s.pose(), measuring: false) }
                s.debugActivity(a, for: 1.4)
                for _ in 0..<Int(1.4 * cut / dt) { s.setCursor(far); s.update(dt: dt); m.sample(s.pose(), measuring: false) }
                s.debugActivity(b, for: 1.4)
                // The hand-off, and on through the second one and out of it.
                for _ in 0..<Int(2.0 / dt) { s.setCursor(far); s.update(dt: dt); m.sample(s.pose()) }
                total.add(m.tally)
                let excess = m.tally.score - solo[b]!.score
                rows.append(Row(key: "\(a) > \(b) @\(Int(cut * 100))%", tally: m.tally, excess: excess))
            }
        }
    }
    print(String(format: "\npairs: %d runs  snaps %d  reversals %d  (%.2f per second)", rows.count, total.snaps, total.reversals,
                 CGFloat(total.score) / (CGFloat(total.frames) * dt)))
    print("worst hand-offs (score above the second activity's own):")
    for r in rows.sorted(by: { $0.excess > $1.excess }).prefix(30) {
        print(String(format: "  %+4d  snaps %3d rev %3d worst %5.2f %-7@ %@", r.excess, r.tally.snaps, r.tally.reversals, r.tally.worstA,
                     r.tally.worstJoint as NSString, r.key as NSString))
    }
}

// MARK: - pointer scenarios

let gestures: Set<String> = ["greet", "armsUp", "wave", "curious", "wiggle", "dance", "bounce", "startle", "hop"]

func runPointer(_ name: String, seconds: CGFloat, cursorAt: (CGFloat, V2) -> V2) {
    var tally = Tally()
    var counts: [String: Int] = [:]
    var gestureCount = 0
    var flips = 0
    var gaps: [CGFloat] = []
    let runs = 6
    for run in 0..<runs {
        let s = freshSpider(followCursor: true, at: 120 + CGFloat(run) * 50)
        let m = Meter()
        var t: CGFloat = 0
        var prevAct = activityName(s)
        var prevMirror: CGFloat = 1
        var lastGesture: CGFloat = -99
        var history: [SpiderPose] = []
        while t < seconds {
            t += dt
            s.setCursor(cursorAt(t, s.worldPos))
            s.update(dt: dt)
            let p = s.pose()
            let before = m.tally.worstA
            m.sample(p)
            let act = activityName(s)
            history.append(p)
            if history.count > 5 { history.removeFirst() }
            if bigLog, m.tally.worstA > max(before, 8) {
                print(String(format: "    big %5.1f %@ at %.2fs  %@ (was %@)  yaw %.2f", m.tally.worstA, m.tally.worstJoint as NSString, t,
                             s.debugState as NSString, prevAct as NSString, p.facing))
                let n = Int(m.tally.worstJoint.filter(\.isNumber)) ?? 0
                for h in history {
                    print(String(format: "        pos %6.1f,%6.1f hd %5.2f yaw %5.2f  foot%d %6.1f,%6.1f lift %.2f  pitch %.2f", h.pos.x, h.pos.y, h.heading,
                                 h.facing, n, h.legs[n].foot.x, h.legs[n].foot.y, h.legs[n].lift, h.bodyPitch))
                }
            }
            if act != prevAct {
                counts[act, default: 0] += 1
                if gestures.contains(act) {
                    gestureCount += 1
                    if lastGesture > 0 { gaps.append(t - lastGesture) }
                    lastGesture = t
                }
                prevAct = act
            }
            let mirror: CGFloat = p.facing >= 0 ? 1 : -1
            if mirror != prevMirror { flips += 1; prevMirror = mirror }
        }
        tally.add(m.tally)
    }
    let minutes = seconds * CGFloat(runs) / 60
    gaps.sort()
    let medianGap = gaps.isEmpty ? 0 : gaps[gaps.count / 2]
    let minGap = gaps.first ?? 0
    print(String(format: "\n%@: gestures %.1f/min (gap min %.1fs, median %.1fs)  side flips %.1f/min  snaps %.1f/s  reversals %.1f/s  worst %.2f %@",
                 name as NSString, CGFloat(gestureCount) / minutes, minGap, medianGap, CGFloat(flips) / minutes,
                 CGFloat(tally.snaps) / (CGFloat(tally.frames) * dt), CGFloat(tally.reversals) / (CGFloat(tally.frames) * dt),
                 tally.worstA, tally.worstJoint as NSString))
    print("  starts/min: " + counts.sorted { $0.value > $1.value }.map { String(format: "%@ %.1f", $0.key, CGFloat($0.value) / minutes) }.joined(separator: ", "))
}

func runSweep() {
    // Back and forth right across it, a hand's width either side, about
    // once a second — the "moving the pointer over it" case.
    runPointer("sweep (fast, over it)", seconds: 90) { t, p in
        V2(p.x + 90 * sin(t * 2 * .pi / 1.1), p.y + 35)
    }
    runPointer("sweep (slow, near)", seconds: 90) { t, p in
        V2(p.x + 140 * sin(t * 2 * .pi / 3.5), p.y + 70)
    }
}

func runHover() {
    runPointer("hover (resting near)", seconds: 90) { _, p in V2(p.x + 70, p.y + 60) }
}

// MARK: - gaze

func runGaze() {
    // On each side of the window, pointer in eight directions round it:
    // how far off is the direction the glints are drawn toward?
    guard let loop = sm.loop("win:9") else { return }
    print("\ngaze error, degrees (mean / worst), by surface:")
    for (i, seg) in loop.segs.enumerated() {
        var errs: [CGFloat] = []
        for k in 0..<8 {
            let s = freshSpider(followCursor: true, seg: i, at: seg.len * 0.5)
            let ang = CGFloat(k) / 8 * 2 * .pi
            for _ in 0..<90 {
                s.setCursor(s.worldPos + V2.angle(ang) * 160)
                s.update(dt: dt)
            }
            let p = s.pose()
            let want = V2.angle(ang)
            let drawn = SpiderRenderer.drawnGaze(p)
            guard drawn.length > 0.2 else { continue }
            errs.append(abs(angleDelta(drawn.angle, want.angle)) * 180 / .pi)
        }
        let mean = errs.reduce(0, +) / CGFloat(max(errs.count, 1))
        print(String(format: "  seg %d (%@, heading %4.0f°): %5.1f / %5.1f  (%d samples)", i, "\(seg.facing)" as NSString,
                     seg.angle * 180 / .pi, mean, errs.max() ?? 0, errs.count))
    }
}

/// `trace greet,walk:0.5` — runs the sequence and prints every frame where
/// a joint snaps or reverses, with the pose around it.
func runTrace(_ spec: String) {
    let s = freshSpider(followCursor: false)
    for _ in 0..<30 { s.setCursor(far); s.update(dt: dt) }
    var prev: [V2] = []
    var vel: [V2] = []
    var prevMirror: CGFloat = 1
    var f = 0
    for item in spec.split(separator: ",") {
        let parts = item.split(separator: ":")
        let dur = parts.count > 1 ? CGFloat(Double(parts[1]) ?? 1.4) : 1.4
        s.debugActivity(String(parts[0]), for: dur)
        for _ in 0..<Int(dur / dt) {
            s.setCursor(far); s.update(dt: dt); f += 1
            let p = s.pose()
            let j = joints(p)
            let mirror: CGFloat = p.facing >= 0 ? 1 : -1
            if mirror != prevMirror, prev.count == 17 {
                var k = prev, w = vel
                for i in 0..<8 { k[i] = prev[7 - i]; k[8 + i] = prev[15 - i]; w[i] = vel[7 - i]; w[8 + i] = vel[15 - i] }
                prev = k; vel = w
                print(String(format: "%4d  -- mirror flip, yaw %.2f", f, p.facing))
            }
            prevMirror = mirror
            if let n = ProcessInfo.processInfo.environment["TRACE_LEG"].flatMap({ Int($0) }), prev.count == 17 {
                let v = j[n] - prev[n]
                print(String(format: "%4d %@ leg%d screen %6.1f,%6.1f  v %5.2f  local %5.1f,%5.1f lift %.2f", f,
                             s.debugActivity.split(separator: " ").prefix(2).joined(separator: " "), n, j[n].x, j[n].y, v.length,
                             p.legs[n].foot.x, p.legs[n].foot.y, p.legs[n].lift))
            }
            if prev.count == 17 {
                let v = zip(j, prev).map { $0 - $1 }
                if vel.count == 17 {
                    for i in 0..<16 {
                        let a = (v[i] - vel[i]).length
                        let rev = vel[i].dot(v[i]) < 0 && vel[i].length > revV && v[i].length > revV
                        if a > snapA || rev {
                            let l = p.legs[i % 8]
                            print(String(format: "%4d %-18@ %@%d a %5.2f v %5.2f%@  yaw %5.2f  foot %5.1f,%5.1f knee %5.1f,%5.1f lift %.2f",
                                         f, s.debugActivity.split(separator: " ").prefix(2).joined(separator: " ") as NSString,
                                         i < 8 ? "foot" : "knee", i % 8, a, v[i].length, rev ? " REV" : "", p.facing,
                                         l.foot.x, l.foot.y, l.knee.x, l.knee.y, l.lift))
                        }
                    }
                }
                vel = v
            }
            prev = j
        }
    }
}

// MARK: - landings

/// Throws, leaps and falls onto the window: for each landing, how long
/// after the body has come to rest the last foot is down on the ledge
/// (it should be down by then), and how rough the feet were on the way.
func runLand() {
    struct Landing { var kind: String; var bodyRest: CGFloat; var feetDown: CGFloat; var worst: CGFloat }
    var out: [Landing] = []
    func watch(_ s: Spider, _ kind: String, seconds: CGFloat = 4) {
        let m = Meter()
        var t: CGFloat = 0
        var landedAt: CGFloat = -1
        var restAt: CGFloat = -1
        var downAt: CGFloat = -1
        var still = 0
        var prevPos = s.pose().pos
        var wasAttached = s.debugState.hasPrefix("attached")
        var worst: CGFloat = 0
        while t < seconds {
            t += dt
            s.setCursor(far)
            s.update(dt: dt)
            let p = s.pose()
            let attached = s.debugState.hasPrefix("attached")
            m.sample(p, measuring: landedAt >= 0)
            if attached && !wasAttached && landedAt < 0 { landedAt = t }
            wasAttached = attached
            if landedAt >= 0 {
                worst = max(worst, m.tally.worstA)
                let v = p.pos.distance(to: prevPos) / dt
                still = v < 20 ? still + 1 : 0
                if restAt < 0, still >= 4 { restAt = t - 3 * dt - landedAt }
                if downAt < 0, s.debugFeetDown { downAt = t - landedAt }
                if ProcessInfo.processInfo.environment["LANDTRACE"] == kind, downAt < 0 {
                    print(String(format: "  %.3f v %4.0f  %@", t - landedAt, p.pos.distance(to: prevPos) / dt, s.debugFeetWhy as NSString))
                }
                if restAt >= 0, downAt >= 0 { break }
            }
            prevPos = p.pos
        }
        if landedAt >= 0 { out.append(Landing(kind: kind, bodyRest: restAt, feetDown: downAt, worst: worst)) }
    }
    guard let loop = sm.loop("win:9") else { return }
    let top = loop.segs[0]
    // Thrown: picked up off the ledge, dragged, flung at the window top.
    for (k, v) in [V2(0, 300), V2(250, 150), V2(-300, 0), V2(500, 400), V2(-150, 700), V2(0, -200), V2(800, 100), V2(120, 1100)].enumerated() {
        let s = freshSpider(followCursor: false, at: 120 + CGFloat(k) * 30)
        for _ in 0..<20 { s.setCursor(far); s.update(dt: dt) }
        var grab = s.worldPos
        s.beginGrab(at: grab)
        for _ in 0..<12 { grab = grab + V2(0, 6); s.moveGrab(to: grab); s.update(dt: dt) }
        for _ in 0..<6 { grab = grab + v * dt; s.moveGrab(to: grab); s.update(dt: dt) }
        s.endGrab(throwVelocity: v)
        watch(s, "throw \(Int(v.x)),\(Int(v.y))")
    }
    // Leaps: from the floor up onto the window top, and along it.
    let floor = sm.loops.first { $0.id.hasPrefix("screen") }!
    for k in 0..<6 {
        let s = freshSpider(followCursor: false, loop: floor.id, seg: 0, at: 360 + CGFloat(k) * 40)
        for _ in 0..<20 { s.setCursor(far); s.update(dt: dt) }
        s.debugJump(to: top.point(at: 60 + CGFloat(k) * 70))
        watch(s, "leap up \(k)")
    }
    for k in 0..<4 {
        let s = freshSpider(followCursor: false, at: 80)
        for _ in 0..<20 { s.setCursor(far); s.update(dt: dt) }
        s.debugJump(to: top.point(at: 200 + CGFloat(k) * 60))
        watch(s, "leap along \(k)")
    }
    // Falls: the ledge goes from under it.
    for k in 0..<4 {
        let s = freshSpider(followCursor: false, at: 100 + CGFloat(k) * 90)
        for _ in 0..<20 { s.setCursor(far); s.update(dt: dt) }
        s.debugFall()
        watch(s, "fall \(k)", seconds: 6)
    }
    print("\nlandings: feet down vs body at rest (seconds after touchdown; lag > 0 = legs still coming down after the body stopped)")
    var lags: [CGFloat] = []
    for l in out {
        let lag = l.feetDown - l.bodyRest
        if l.feetDown >= 0, l.bodyRest >= 0 { lags.append(lag) }
        print(String(format: "  %-16@ body rest %5.2f  feet down %5.2f  lag %+5.2f  worst jolt %5.1f", l.kind as NSString, l.bodyRest, l.feetDown, lag, l.worst))
    }
    lags.sort()
    if !lags.isEmpty {
        print(String(format: "  lag median %+.2f  worst %+.2f  (%d landings, %d never got all feet down)", lags[lags.count / 2], lags.last!, out.count, out.filter { $0.feetDown < 0 }.count))
    }
}

/// `filmland vx,vy [out.png]` — a throw, from the grab to settled, drawn
/// every other frame round the moment it lands.
func filmLand(_ spec: String, out: String) {
    let parts = spec.split(separator: ",").compactMap { Double($0) }
    let v = V2(CGFloat(parts.first ?? 300), CGFloat(parts.count > 1 ? parts[1] : 300))
    let s = freshSpider(followCursor: false, at: 200)
    for _ in 0..<20 { s.setCursor(far); s.update(dt: dt) }
    var grab = s.worldPos
    s.beginGrab(at: grab)
    var frames: [(SpiderPose, String)] = []
    for _ in 0..<12 { grab = grab + V2(0, 6); s.moveGrab(to: grab); s.update(dt: dt); frames.append((s.pose(), "held")) }
    for _ in 0..<6 { grab = grab + v * dt; s.moveGrab(to: grab); s.update(dt: dt); frames.append((s.pose(), "held")) }
    s.endGrab(throwVelocity: v)
    var landedIdx = -1
    for f in 0..<240 {
        s.setCursor(far); s.update(dt: dt)
        let st = s.debugState
        frames.append((s.pose(), String(st.split(separator: " ").first ?? "")))
        if landedIdx < 0, st.hasPrefix("attached") { landedIdx = frames.count - 1 }
        if landedIdx >= 0, frames.count - landedIdx > 30 { break }
        _ = f
    }
    // Round the landing: 20 frames before, 30 after, every other frame.
    let from = max(0, (landedIdx < 0 ? frames.count - 50 : landedIdx - 20))
    let picks = stride(from: from, to: frames.count, by: 2).map { $0 }
    let cols = 9, cell: CGFloat = 170
    let rows = (picks.count + cols - 1) / cols
    let W = Int(cell) * cols, H = Int(cell) * rows
    guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(gray: 0.22, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let font = CTFontCreateWithName("Menlo" as CFString, 9, nil)
    for (n, idx) in picks.enumerated() {
        let (pose, st) = frames[idx]
        let box = CGRect(x: CGFloat(n % cols) * cell, y: CGFloat(rows - 1 - n / cols) * cell, width: cell, height: cell)
        c.saveGState(); c.addRect(box); c.clip()
        // The window's top edge, where it is relative to the spider.
        c.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor); c.setLineWidth(2)
        let ly = box.midY + (win.maxY - pose.pos.y)
        c.beginPath(); c.move(to: CGPoint(x: box.minX, y: ly)); c.addLine(to: CGPoint(x: box.maxX, y: ly)); c.strokePath()
        SpiderRenderer.draw(pose, in: c, bounds: box)
        c.restoreGState()
        let tag = idx == landedIdx ? "LAND" : "\(idx - max(landedIdx, 0))"
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(tag) \(st)", attributes: [.font: font, .foregroundColor: NSColor.white]))
        c.textPosition = CGPoint(x: box.minX + 4, y: box.minY + 4); CTLineDraw(line, c)
        c.setStrokeColor(gray: 0.4, alpha: 1); c.setLineWidth(1); c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
    }
    guard let img = c.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

/// `filmjump [out.png]` — a leap along the window top: the crouch, the
/// push-off and the first of the flight, close up, every other frame.
func filmJump(out: String) {
    guard let loop = sm.loop("win:9") else { return }
    let s = freshSpider(followCursor: false, at: 120)
    for _ in 0..<20 { s.setCursor(far); s.update(dt: dt) }
    s.debugJump(to: loop.segs[0].point(at: 380))
    var frames: [(SpiderPose, String)] = []
    for _ in 0..<70 {
        s.setCursor(far); s.update(dt: dt)
        frames.append((s.pose(), String(s.debugState.split(separator: " ").first ?? "")))
    }
    let picks = stride(from: 0, to: frames.count, by: 2).map { $0 }
    let cols = 9, cell: CGFloat = 170
    let rows = (picks.count + cols - 1) / cols
    let W = Int(cell) * cols, H = Int(cell) * rows
    guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(gray: 0.22, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let font = CTFontCreateWithName("Menlo" as CFString, 9, nil)
    for (n, idx) in picks.enumerated() {
        let (pose, st) = frames[idx]
        let box = CGRect(x: CGFloat(n % cols) * cell, y: CGFloat(rows - 1 - n / cols) * cell, width: cell, height: cell)
        c.saveGState(); c.addRect(box); c.clip()
        c.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor); c.setLineWidth(2)
        let ly = box.midY + (win.maxY - pose.pos.y)
        c.beginPath(); c.move(to: CGPoint(x: box.minX, y: ly)); c.addLine(to: CGPoint(x: box.maxX, y: ly)); c.strokePath()
        SpiderRenderer.draw(pose, in: c, bounds: box)
        c.restoreGState()
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(idx) \(st)", attributes: [.font: font, .foregroundColor: NSColor.white]))
        c.textPosition = CGPoint(x: box.minX + 4, y: box.minY + 4); CTLineDraw(line, c)
        c.setStrokeColor(gray: 0.4, alpha: 1); c.setLineWidth(1); c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
    }
    guard let img = c.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

/// Every habit's ▶ in a copy of the Studio's preview box: what it goes
/// on to do in the next few seconds.
func runDemos() {
    let pm = SurfaceMap()
    let scale: CGFloat = 1.55
    pm.standoff = -SpiderRenderer.ground * scale
    let b = CGRect(x: 0, y: 0, width: 330, height: 320).insetBy(dx: 4, dy: 4)
    let ledge = CGRect(x: b.midX - 80, y: b.minY + 70, width: 160, height: 70)
    pm.debugRebuild(screen: b, menuBarHeight: 0, windows: [TrackedWindow(id: 1, frame: ledge, depth: 0, owner: "Studio")])
    for (group, dials) in Habits.groups {
        print("\n\(group)")
        for (title, key) in dials {
            let sp = Spider(map: pm)
            sp.config.scale = scale
            sp.config.webs = true
            sp.config.followCursor = true
            sp.debugAttach(loopID: "win:1", segIdx: 0, t: 40, dir: 1)
            for _ in 0..<30 { sp.setCursor(far); sp.update(dt: dt) }
            sp.demo(key)
            var seen: [String] = []
            let secs: CGFloat = ProcessInfo.processInfo.environment["DEMO_SECS"].flatMap { Double($0) }.map { CGFloat($0) } ?? 8
            let only = ProcessInfo.processInfo.environment["DEMO_ONLY"]
            if let only, !title.contains(only) { continue }
            for _ in 0..<Int(secs / dt) {
                sp.setCursor(far); sp.update(dt: dt)
                let st = sp.debugState.replacingOccurrences(of: " on win:1", with: "").replacingOccurrences(of: " on screen:0", with: "")
                if seen.last != st { seen.append(st) }
            }
            print(String(format: "  %-28@ %@", title as NSString, seen.prefix(only == nil ? 7 : 40).joined(separator: " > ") as NSString))
        }
    }
}

/// Two windows, one in front of the other and overlapping its top edge —
/// the dark one behind, the white one in front — and the spider walking
/// into where they meet, drawn in screen space so every foot can be seen
/// against the real edges.
let twoA = CGRect(x: 100, y: 100, width: 520, height: 300)     // behind (dark)
let twoB = CGRect(x: 380, y: 360, width: 480, height: 220)     // in front (white)
let twoMap: SurfaceMap = {
    let m = SurfaceMap()
    m.standoff = 22
    m.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1000, height: 700), menuBarHeight: 0,
                   windows: [TrackedWindow(id: 2, frame: twoB, depth: 0, owner: "White"),
                             TrackedWindow(id: 1, frame: twoA, depth: 1, owner: "Dark")])
    return m
}()

func filmTwo(_ out: String) {
    for l in twoMap.loops {
        print(l.id, l.segs.enumerated().map { i, s in "\(i):\(s.facing) \(Int(s.a.x)),\(Int(s.a.y))->\(Int(s.b.x)),\(Int(s.b.y)) blocked \(s.blocked.map { "\(Int($0.lo))..\(Int($0.hi))" })" }.joined(separator: " | "))
    }
    // Shots: (loop, seg, t, dir, walk seconds before the picture, title)
    let shots: [(String, Int, CGFloat, CGFloat, Int, String)] = ProcessInfo.processInfo.environment["TWO_SHOTS"].map { spec in
        spec.split(separator: ";").map { part in
            let f = part.split(separator: ",").map(String.init)
            return (f[0], Int(f[1])!, CGFloat(Double(f[2])!), CGFloat(Double(f[3])!), Int(f[4])!, f.count > 5 ? f[5] : "")
        }
    } ?? []
    let cols = 3, cell: CGFloat = 300
    let rows = max(1, (shots.count + cols - 1) / cols)
    let W = Int(cell) * cols, H = Int(cell) * rows
    guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    c.scaleBy(x: 2, y: 2)
    let font = CTFontCreateWithName("Menlo" as CFString, 9, nil)
    for (n, shot) in shots.enumerated() {
        let s = Spider(map: twoMap)
        s.config.scale = 1.4
        s.config.followCursor = false
        s.debugAttach(loopID: shot.0, segIdx: shot.1, t: shot.2, dir: shot.3)
        if shot.4 > 0 { s.debugWalk(for: 30) }
        for f in 0..<max(shot.4, 40) {
            s.setCursor(far); s.update(dt: dt)
            if f == shot.4 && shot.4 > 0 { s.debugActivity("look", for: 30) }
        }
        let p = s.pose()
        if ProcessInfo.processInfo.environment["TWO_FEET"] == "\(n)" {
            print("shot \(n) body \(Int(p.pos.x)),\(Int(p.pos.y)) heading \(String(format: "%.2f", p.heading)) facing \(String(format: "%.2f", p.facing))")
            for (i, f) in s.debugFeet.enumerated() {
                print(String(format: "  leg %d foot %5.0f,%5.0f -> %5.0f,%5.0f   rest %5.0f,%5.0f -> %5.0f,%5.0f", i, f.foot.x, f.foot.y, f.placed.x, f.placed.y, f.rest.x, f.rest.y, f.restPlaced.x, f.restPlaced.y))
            }
        }
        let box = CGRect(x: CGFloat(n % cols) * cell, y: CGFloat(rows - 1 - n / cols) * cell, width: cell, height: cell)
        c.saveGState(); c.addRect(box); c.clip()
        // World -> this cell, centred on the spider.
        c.translateBy(x: box.midX - p.pos.x, y: box.midY - p.pos.y)
        c.setFillColor(gray: 0.35, alpha: 1); c.fill(CGRect(x: p.pos.x - 400, y: p.pos.y - 400, width: 800, height: 800))
        c.setFillColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1); c.fill(twoA)
        c.setFillColor(gray: 0.97, alpha: 1); c.fill(twoB)
        c.setStrokeColor(gray: 0.6, alpha: 1); c.setLineWidth(1); c.stroke(twoB)
        let pb = CGRect(x: p.pos.x - 150, y: p.pos.y - 150, width: 300, height: 300)
        SpiderRenderer.draw(p, in: c, bounds: pb)
        // Feet, as dots.
        let mirror: CGFloat = p.facing >= 0 ? 1 : -1
        for leg in p.legs {
            let g = SpiderRenderer.ground
            let q = V2(leg.foot.x * p.stretch, g + (leg.foot.y - g) * p.fatten)
            let w = p.pos + V2(q.x * mirror, q.y).rotated(by: p.heading) * p.scale
            c.setFillColor(red: 1, green: 0.2, blue: 0.3, alpha: 1)
            c.fillEllipse(in: CGRect(x: w.x - 2.5, y: w.y - 2.5, width: 5, height: 5))
        }
        c.restoreGState()
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(n) \(shot.5) \(s.debugState)", attributes: [.font: font, .foregroundColor: NSColor.white]))
        c.textPosition = CGPoint(x: box.minX + 4, y: box.minY + 4); CTLineDraw(line, c)
        c.setStrokeColor(gray: 0.5, alpha: 1); c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
    }
    guard let img = c.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

/// `filmhat topHat out.png` — walking side on in a hat, close up.
func filmHat(_ name: String, out: String) {
    let s = freshSpider(followCursor: false, at: 60)
    var d = SpiderDesign()
    d.look.hat = Hat(rawValue: name) ?? .topHat
    s.apply(design: d)
    s.debugWalk(for: 30)
    var frames: [SpiderPose] = []
    for f in 0..<96 { s.setCursor(far); s.update(dt: dt); if f >= 30, f % 3 == 0 { frames.append(s.pose()) } }
    let cols = 11, cell: CGFloat = 150
    let W = Int(cell) * cols, H = Int(cell) * ((frames.count + cols - 1) / cols)
    guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(gray: 0.85, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let rows = H / Int(cell)
    for (n, p) in frames.enumerated() {
        let box = CGRect(x: CGFloat(n % cols) * cell, y: CGFloat(rows - 1 - n / cols) * cell, width: cell, height: cell)
        c.saveGState(); c.addRect(box); c.clip()
        SpiderRenderer.draw(p, in: c, bounds: box.offsetBy(dx: 0, dy: -20))
        c.restoreGState()
    }
    guard let img = c.makeImage() else { return }
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
}

/// Round every corner of a window, both ways, at several paces: every
/// frame, how far each foot that is meant to be standing is from any edge
/// it could be standing on. Anything over a couple of points is a foot on
/// thin air.
func runCornerAir() {
    guard let loop = sm.loop("win:9") else { return }
    // Against the real outline: a window's corners are rounded
    // (AIR_SQUARE=1 measures against the square corners instead).
    let square = ProcessInfo.processInfo.environment["AIR_SQUARE"] != nil
    func offEdge(_ p: V2) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for l in sm.loops {
            let R = square ? 0 : (l.kind == .windowEdge ? SurfaceMap.windowCornerRadius : 0)
            for e in l.edge {
                let (t, _) = projectOnSegment(p, e.a, e.b)
                var q = e.point(at: t)
                if R > 0 {
                    let r = l.rect
                    let cx: CGFloat? = q.x < r.minX + R ? r.minX + R : (q.x > r.maxX - R ? r.maxX - R : nil)
                    let cy: CGFloat? = q.y < r.minY + R ? r.minY + R : (q.y > r.maxY - R ? r.maxY - R : nil)
                    if let cx, let cy {
                        let c = V2(cx, cy)
                        best = min(best, abs(p.distance(to: c) - R))
                        continue
                    }
                }
                best = min(best, p.distance(to: q))
                _ = q; q = .zero
            }
        }
        return best
    }
    var worstAll: CGFloat = 0
    var badFrames = 0, frames = 0
    var cases: [(String, Int, CGFloat)] = []
    let verbose = ProcessInfo.processInfo.environment["AIR_VERBOSE"] != nil
    for (si, seg) in loop.segs.enumerated() {
        for dir: CGFloat in [1, -1] {
            for (gi, pace) in [CGFloat(0.6), 1.0, 1.5].enumerated() {
                let s = Spider(map: sm)
                s.config.scale = 1.0
                s.config.followCursor = false
                s.config.walkSpeed = 62 * pace
                // Start well back from the corner it is heading for.
                let start = dir > 0 ? max(seg.len - 110, 10) : min(110, seg.len - 10)
                s.debugAttach(loopID: "win:9", segIdx: si, t: start, dir: dir)
                s.debugWalk(for: 30)
                var bad = 0
                var worst: CGFloat = 0
                for f in 0..<Int(3.2 / dt) {
                    s.setCursor(far); s.update(dt: dt)
                    guard f > 20, s.debugState.hasPrefix("attached") else { continue }
                    frames += 1
                    var frameWorst: CGFloat = 0
                    var which = -1
                    for (i, leg) in s.debugPlanted.enumerated() where leg.planted {
                        let d = offEdge(leg.world)
                        if d > frameWorst { frameWorst = d; which = i }
                    }
                    if frameWorst > 2 {
                        bad += 1
                        if verbose { print(String(format: "  seg %d dir %+.0f pace %.1f f %3d  foot %d off by %.1f  at %.0f,%.0f  body %.0f,%.0f", si, dir, pace, f, which, frameWorst, s.debugPlanted[which].world.x, s.debugPlanted[which].world.y, s.worldPos.x, s.worldPos.y)) }
                    }
                    worst = max(worst, frameWorst)
                }
                badFrames += bad
                worstAll = max(worstAll, worst)
                cases.append(("seg \(si) (\(seg.facing)) dir \(Int(dir)) pace \(pace)", bad, worst))
                _ = gi
            }
        }
    }
    print(String(format: "corners: %d of %d frames with a standing foot off the edge by > 2pt (worst %.1f)", badFrames, frames, worstAll))
    for c in cases where c.1 > 0 { print(String(format: "  %-36@ %3d frames, worst %5.1f", c.0 as NSString, c.1, c.2)) }
}

switch mode {
case "cornerair": runCornerAir()
case "filmhat": filmHat(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "topHat",
                        out: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "build/hat.png")
case "two": filmTwo(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/two.png")
case "demos": runDemos()
case "filmjump": filmJump(out: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "build/jumpclose.png")
case "filmland": filmLand(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "300,300",
                          out: CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "build/land.png")
case "land": runLand()
case "trace": runTrace(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "greet,walk")
case "pairs": runPairs()
case "sweep": runSweep()
case "hover": runHover()
case "gaze": runGaze()
default:
    runPairs(); runSweep(); runHover(); runGaze()
}
