import AppKit

// Walk harness (./tools/walk.sh): films and measures walking on a flat window top.
//   strip  — frames of one walk (SC, ACT, NAT, FROM, N, EVERY, SEED, OUT, SKEL, ZOOM)
//   trace  — foot paths in the world over a stretch, spider drawn every so often
//   stats  — per leg worst bone stretch / reach, slip of planted feet, pops,
//            over walks at every size and pace
let env = ProcessInfo.processInfo.environment
let dt: CGFloat = 1.0 / 60.0
func e(_ k: String, _ d: String) -> String { env[k] ?? d }
let natural = e("NAT", "0") == "1"
let refined = e("REF", "0") == "1"

final class Rig {
    let map: SurfaceMap
    let s: Spider
    let win = CGRect(x: 60, y: 200, width: 2400, height: 400)
    init(scale: CGFloat, act: String, seed: UInt64, pace: CGFloat = 0.5, stride: CGFloat = 0.5, stance: CGFloat = 0.5, style: GaitPreference = .march, secs: CGFloat = 12) {
        reseed(seed)
        map = SurfaceMap()
        map.standoff = 22 * scale
        let tw = [TrackedWindow(id: 1, frame: win, depth: 0, owner: "Mock")]
        map.debugRebuild(screen: CGRect(x: 0, y: 0, width: 2600, height: 900), menuBarHeight: 30, windows: tw, dock: nil)
        s = Spider(map: map)
        s.config.scale = scale
        s.config.followCursor = false
        s.config.approachCursor = false
        s.config.pounceOnCursor = false
        var g = Gait(pace: pace, stride: stride, bounce: 0.5, stance: stance, style: style, bounciness: 0.5)
        g.natural = natural
        if refined { g.motion = .refined }
        var d = s.design
        d.gait = g
        s.apply(design: d)
        s.debugAttach(loopID: "win:1", segIdx: 0, t: 100, dir: 1)
        for _ in 0..<30 { s.setCursor(V2(-9e4, -9e4)); s.update(dt: dt) }
        if act == "walk" { s.debugWalk(for: secs) } else { s.debugActivity(act, for: secs) }
    }
    func step() { s.setCursor(V2(-9e4, -9e4)); s.update(dt: dt) }
}

struct Joints { var hip: [V2]; var knee: [V2]; var foot: [V2] }
func screenJoints(_ p: SpiderPose) -> Joints {
    let mirror: CGFloat = p.facing >= 0 ? 1 : -1
    let g = SpiderRenderer.ground
    func scr(_ v: V2) -> V2 {
        var q = v
        if p.spin != 0 { let c = SpiderRenderer.ballCentre; q = c + (q - c).rotated(by: p.spin) }
        q = V2(q.x * p.stretch, g + (q.y - g) * p.fatten)
        return p.pos + V2(q.x * mirror, q.y).rotated(by: p.heading) * p.scale
    }
    return Joints(hip: p.legs.map { scr($0.hip) }, knee: p.legs.map { scr($0.knee) }, foot: p.legs.map { scr($0.foot) })
}

func drawScene(_ c: CGContext, _ p: SpiderPose, _ r: Rig, skel: Bool) {
    c.setFillColor(NSColor(calibratedWhite: 0.14, alpha: 1).cgColor)
    c.addPath(CGPath(roundedRect: r.win, cornerWidth: 10, cornerHeight: 10, transform: nil)); c.fillPath()
    let side = SpiderRenderer.spriteSide(for: p.scale)
    SpiderRenderer.draw(p, in: c, bounds: CGRect(x: p.pos.x - side / 2, y: p.pos.y - side / 2, width: side, height: side))
    guard skel else { return }
    let j = screenJoints(p)
    for i in 0..<8 {
        c.setStrokeColor((i < 4 ? NSColor.systemPink : NSColor.cyan).withAlphaComponent(0.8).cgColor)
        c.setLineWidth(0.5)
        c.beginPath(); c.move(to: j.hip[i].point); c.addLine(to: j.knee[i].point); c.addLine(to: j.foot[i].point); c.strokePath()
    }
}

let font = CTFontCreateWithName("Menlo" as CFString, 11, nil)
func label(_ c: CGContext, _ s: String, _ at: CGPoint) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(white: 0.92, alpha: 1)]))
    c.textPosition = at
    CTLineDraw(line, c)
}
func save(_ c: CGContext, _ path: String) {
    try? NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}
func canvas(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.27, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return c
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "strip"
let SC = CGFloat(Double(e("SC", "1")) ?? 1)
let ACT = e("ACT", "walk")
let SEED = UInt64(e("SEED", "3")) ?? 3
let PACE = CGFloat(Double(e("PACE", "0.5")) ?? 0.5)
let STANCE = CGFloat(Double(e("STANCE", "0.5")) ?? 0.5)

switch mode {
case "strip":
    let r = Rig(scale: SC, act: ACT, seed: SEED, pace: PACE, stance: STANCE, secs: CGFloat(Double(e("SECS", "12")) ?? 12))
    let from = Int(e("FROM", "60")) ?? 60, n = Int(e("N", "20")) ?? 20, every = Int(e("EVERY", "2")) ?? 2
    let cols = Int(e("COLS", "10")) ?? 10
    let zoom = CGFloat(Double(e("ZOOM", "3")) ?? 3)
    let cell: CGFloat = 70 * max(SC, 0.6) + 30
    let rows = (n + cols - 1) / cols
    let c = canvas(Int(cell * CGFloat(cols) * zoom), Int(cell * CGFloat(rows) * zoom))
    var f = 0
    while f < from { r.step(); f += 1 }
    for k in 0..<n {
        let p = r.s.pose()
        let col = k % cols, row = k / cols
        let box = CGRect(x: CGFloat(col) * cell * zoom, y: CGFloat(rows - 1 - row) * cell * zoom, width: cell * zoom, height: cell * zoom)
        c.saveGState(); c.clip(to: box)
        c.translateBy(x: box.midX, y: box.midY + cell * zoom * 0.1)
        c.scaleBy(x: zoom, y: zoom)
        c.translateBy(x: -p.pos.x, y: -p.pos.y)
        drawScene(c, p, r, skel: e("SKEL", "0") == "1")
        c.restoreGState()
        c.setStrokeColor(gray: 0.4, alpha: 1); c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        label(c, "\(f)", CGPoint(x: box.minX + 4, y: box.minY + 4))
        for _ in 0..<every { r.step(); f += 1 }
    }
    save(c, e("OUT", "strip.png"))

case "trace":
    // Foot paths in the world, the spider drawn now and then.
    let r = Rig(scale: SC, act: ACT, seed: SEED, pace: PACE, stance: STANCE, secs: CGFloat(Double(e("SECS", "12")) ?? 12))
    let from = Int(e("FROM", "90")) ?? 90, n = Int(e("N", "90")) ?? 90
    for _ in 0..<from { r.step() }
    var paths: [[V2]] = Array(repeating: [], count: 8)
    var knees: [[V2]] = Array(repeating: [], count: 8)
    var poses: [SpiderPose] = []
    for k in 0..<n {
        let p = r.s.pose(); let j = screenJoints(p)
        for i in 0..<8 { paths[i].append(j.foot[i]); knees[i].append(j.knee[i]) }
        if k % (Int(e("GHOST", "15")) ?? 15) == 0 { poses.append(p) }
        r.step()
    }
    let all = paths.flatMap { $0 }
    let minX = all.map(\.x).min()! - 50 * SC, maxX = all.map(\.x).max()! + 50 * SC
    let y0 = r.win.maxY
    let zoom = CGFloat(Double(e("ZOOM", "4")) ?? 4)
    let W = Int((maxX - minX) * zoom), H = Int(90 * SC * zoom)
    let c = canvas(W, H)
    c.scaleBy(x: zoom, y: zoom)
    c.translateBy(x: -minX, y: -(y0 - 10 * SC))
    for (k, p) in poses.enumerated() {
        c.setAlpha(k == poses.count - 1 ? 1 : 0.45)
        drawScene(c, p, r, skel: false)
    }
    c.setAlpha(1)
    let only = env["LEG"].flatMap { Int($0) }
    for i in 0..<8 where only == nil || only == i {
        c.setStrokeColor((i < 4 ? NSColor.systemYellow : NSColor.systemGreen).withAlphaComponent(0.9).cgColor)
        c.setLineWidth(0.4)
        c.beginPath(); c.move(to: paths[i][0].point); for q in paths[i] { c.addLine(to: q.point) }; c.strokePath()
        if only != nil {
            c.setStrokeColor(NSColor.systemPink.cgColor)
            c.beginPath(); c.move(to: knees[i][0].point); for q in knees[i] { c.addLine(to: q.point) }; c.strokePath()
        }
    }
    save(c, e("OUT", "trace.png"))

case "stats":
    // Every size, a few paces, walk / scurry / sneak.
    let scales: [CGFloat] = env["SCALES"].map { $0.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) } } ?? [0.62, 0.78, 0.95, 1.2, 1.55]
    let acts = e("ACTS", "walk,scurry,sneak").split(separator: ",").map(String.init)
    let paces: [CGFloat] = [0.15, 0.5, 1.0]
    let stances: [CGFloat] = [0.1, 0.5, 1.0]
    print("scale act    pace stance | stretch  reach  | slip px/s  maxslip | pop  | up>4 | cadence")
    var worstStretch: CGFloat = 0, worstReach: CGFloat = 0
    for sc in scales { for act in acts { for pace in paces { for st in stances {
        let r = Rig(scale: sc, act: act, seed: SEED, pace: pace, stance: st, secs: 6)
        var stretch: CGFloat = 0, reach: CGFloat = 0, slip: CGFloat = 0, maxSlip: CGFloat = 0, pop: CGFloat = 0
        var upMany = 0, frames = 0, walkFrames = 0
        var prevFoot: [V2] = [], prevPlanted: [Bool] = [], prevJ: [V2] = [], prevV: [V2] = []
        var liftoffs = 0
        var wasSwing: [Bool] = Array(repeating: false, count: 8)
        for f in 0..<330 {
            r.step()
            guard f > 20 else { continue }
            let p = r.s.pose(); let j = screenJoints(p)
            let prof = SpiderRenderer.profileAmount(yaw: p.facing)
            frames += 1
            let moving = r.s.debugGait.speed > 1
            if moving { walkFrames += 1 }
            for i in 0..<8 {
                let rg = SpiderRenderer.rig(i, profile: prof, look: r.s.look)
                let a = (rg.knee - rg.hip).length * p.scale, b = (rg.foot - rg.knee).length * p.scale
                stretch = max(stretch, abs(j.knee[i].distance(to: j.hip[i]) / a - 1), abs(j.foot[i].distance(to: j.knee[i]) / b - 1))
                reach = max(reach, j.foot[i].distance(to: j.hip[i]) / (a + b))
            }
            let planted = r.s.debugPlanted.map(\.planted)
            if prevFoot.count == 8 {
                for i in 0..<8 where planted[i] && prevPlanted[i] {
                    let d = j.foot[i].distance(to: prevFoot[i])
                    slip += d; maxSlip = max(maxSlip, d)
                }
                for i in 0..<8 { let sw = !planted[i]; if sw && !wasSwing[i] { liftoffs += 1 }; wasSwing[i] = sw }
            }
            if planted.filter({ !$0 }).count > 4 { upMany += 1 }
            prevFoot = j.foot; prevPlanted = planted
            let all = j.foot + j.knee
            if prevJ.count == 16 {
                let v = zip(all, prevJ).map { $0 - $1 }
                if prevV.count == 16 { for k in 0..<16 { pop = max(pop, (v[k] - prevV[k]).length / sc) } }
                prevV = v
            }
            prevJ = all
        }
        worstStretch = max(worstStretch, stretch); worstReach = max(worstReach, reach)
        let secs = CGFloat(walkFrames) * dt
        print(String(format: "%.2f  %-6@ %.2f %.2f   | %.3f   %.3f  | %7.2f  %6.2f | %5.1f | %4d | %.2f/s",
                     sc, act as NSString, pace, st, stretch, reach, slip / (CGFloat(frames) * dt), maxSlip, pop, upMany,
                     CGFloat(liftoffs) / 8 / max(secs, 0.1)))
    } } } }
    print(String(format: "WORST stretch %.3f reach %.3f", worstStretch, worstReach))

case "why":
    // Frames where a bone is drawn off its length, or a joint pops.
    let r = Rig(scale: SC, act: ACT, seed: SEED, pace: PACE, stance: STANCE, secs: 6)
    var prevJ: [V2] = [], prevV: [V2] = []
    for f in 0..<(Int(e("FRAMES", "330")) ?? 330) {
        r.step()
        let p = r.s.pose(); let j = screenJoints(p)
        let prof = SpiderRenderer.profileAmount(yaw: p.facing)
        var notes: [String] = []
        for i in 0..<8 {
            let rg = SpiderRenderer.rig(i, profile: prof, look: r.s.look)
            let a = (rg.knee - rg.hip).length * p.scale, b = (rg.foot - rg.knee).length * p.scale
            let fs = j.knee[i].distance(to: j.hip[i]) / a, ts = j.foot[i].distance(to: j.knee[i]) / b
            if abs(fs - 1) > 0.04 || abs(ts - 1) > 0.04 {
                notes.append(String(format: "leg%d fem %.2f tib %.2f reach %.2f", i, fs, ts, j.foot[i].distance(to: j.hip[i]) / (a + b)))
            }
        }
        let all = j.foot + j.knee
        if prevJ.count == 16 {
            let v = zip(all, prevJ).map { $0 - $1 }
            if prevV.count == 16 {
                for k in 0..<16 { let a = (v[k] - prevV[k]).length / SC; if a > Double(e("POP", "8"))! { notes.append(String(format: "pop %@%d %.1f r%.2f lift%.2f", k < 8 ? "foot" : "knee", k % 8, a, j.foot[k % 8].distance(to: j.hip[k % 8]) / ((SpiderRenderer.rig(k % 8, profile: prof, look: r.s.look).knee - SpiderRenderer.rig(k % 8, profile: prof, look: r.s.look).hip).length + (SpiderRenderer.rig(k % 8, profile: prof, look: r.s.look).foot - SpiderRenderer.rig(k % 8, profile: prof, look: r.s.look).knee).length) / p.scale, p.legs[k % 8].lift)) } }
            }
            prevV = v
        }
        prevJ = all
        if !notes.isEmpty || env["ALL"] != nil {
            print(f, r.s.debugState, r.s.debugGait.controller, String(format: "v%.0f", r.s.debugGait.speed), notes.joined(separator: " | "))
            if env["TIMING"] != nil { print("   ", r.s.debugLegTiming) }
        }
    }

default:
    print("strip | trace | stats | why")
}
