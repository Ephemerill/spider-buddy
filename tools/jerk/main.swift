import AppKit

// Jerk detector: runs the spider headless for a long while and flags every
// frame where something moves further than a frame's worth of motion should
// — the body, the heading, a foot relative to the body — and says what it
// was doing on either side of the jump. The choppy transitions fall out as
// the most frequent "before > after" pairs.

let map = SurfaceMap()
map.standoff = 22 * 0.95
let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1728, height: 1117)
let windows = [
    TrackedWindow(id: 1, frame: CGRect(x: screen.minX + 180, y: screen.minY + 220, width: 760, height: 520), depth: 0, owner: "Editor"),
    TrackedWindow(id: 2, frame: CGRect(x: screen.minX + 700, y: screen.minY + 420, width: 620, height: 400), depth: 1, owner: "Browser"),
    TrackedWindow(id: 3, frame: CGRect(x: screen.maxX - 460, y: screen.minY + 120, width: 400, height: 300), depth: 2, owner: "Notes"),
]
map.rebuild(windows: windows)

let args = CommandLine.arguments
let seconds: CGFloat = args.count > 1 ? CGFloat(Double(args[1]) ?? 600) : 600
let runs = args.count > 2 ? Int(args[2]) ?? 4 : 4
let verbose = ProcessInfo.processInfo.environment["JERK_VERBOSE"] != nil
let dt: CGFloat = 1.0 / 60.0

struct Event { var t: CGFloat; var kind: String; var amount: CGFloat; var from: String; var to: String }
var events: [Event] = []
var swingTrace = 0
var ring: [String] = []
var frames = 0

func short(_ s: String) -> String {
    // "attached:walk on win:1" -> "walk", "dangling" -> "dangling"
    if s.hasPrefix("attached:") { return String(s.dropFirst(9).split(separator: " ").first ?? "") }
    return String(s.split(separator: " ").first ?? "")
}

for run in 0..<runs {
    let s = Spider(map: map)
    s.config.scale = 0.95
    var t: CGFloat = 0
    var prevFeet: [V2] = []
    var prevPos = s.worldPos
    var prevHeading: CGFloat = 0
    var prevPitch: CGFloat = 0
    var prevState = s.debugState
    var recent: [String] = []
    var mouseStill = false
    while t < seconds {
        t += dt
        frames += 1
        // A pointer that wanders, pauses, and now and then darts about.
        let phase = t.truncatingRemainder(dividingBy: 40)
        mouseStill = phase > 25
        let cx = mouseStill ? screen.midX + 300 : screen.midX + cos(Double(t) * 0.31) * 520
        let cy = mouseStill ? screen.minY + 60 : screen.midY + sin(Double(t) * 0.23) * 360
        s.setCursor(V2(CGFloat(cx), CGFloat(cy)))
        if Int(t * 60) % (60 * 97) == 0 { s.poke() }
        s.update(dt: dt)

        let p = s.pose()
        let state = s.debugState
        let mirror: CGFloat = p.facing >= 0 ? 1 : -1
        let feet = p.legs.map { V2($0.foot.x * mirror, $0.foot.y).rotated(by: p.heading) * p.scale }
        func flying(_ st: String) -> Bool { st == "fall" || st == "jump" || st == "held" || st.hasPrefix("attached:roll") }
        let moving = flying(state) || flying(prevState)
        if !prevFeet.isEmpty {
            let fromTo = (short(prevState), short(state))
            func flag(_ kind: String, _ amount: CGFloat) {
                events.append(Event(t: t + CGFloat(run) * 100_000, kind: kind, amount: amount, from: fromTo.0, to: fromTo.1))
                if verbose { print(String(format: "%3d %7.2f %-8@ %6.1f  %@ > %@   [%@]", run, t, kind as NSString, amount, fromTo.0, fromTo.1, recent.suffix(4).joined(separator: " > "))) }
            }
            if verbose, state == "swinging" || prevState == "swinging" {
                let d = p.pos.distance(to: prevPos)
                if d > 50 || swingTrace > 0 {
                    swingTrace = d > 50 ? 6 : swingTrace - 1
                    print(String(format: "   swing: pos %.0f,%.0f -> %.0f,%.0f  anchor %.0f,%.0f angle %.3f vel %.3f len %.0f->%.0f %@", prevPos.x, prevPos.y, p.pos.x, p.pos.y, p.web?.anchor.x ?? -1, p.web?.anchor.y ?? -1, s.debugSwing.angle, s.debugSwing.angVel, s.debugLine.len, s.debugLine.target, state))
                }
            }
            if !moving {
                let dp = p.pos.distance(to: prevPos)
                if dp > (state == "swinging" ? 30 : 14) { flag("body", dp) }
                let dh = abs(angleDelta(prevHeading, p.heading))
                if dh > 0.22 { flag("heading", dh) }
                let dpitch = abs(p.bodyPitch - prevPitch)
                if dpitch > 0.1 { flag("pitch", dpitch) }
                // Feet: each foot against the nearest foot last frame, so a
                // mirror flip (where feet legitimately swap slots) is fine.
                var worst: CGFloat = 0
                for f in feet {
                    let d = prevFeet.map { $0.distance(to: f) }.min() ?? 0
                    worst = max(worst, d)
                }
                if worst > 11 * p.scale { flag("foot", worst) }
                if verbose, worst > 25 {
                    for line in ring { print("      " + line) }
                    for (k, f) in feet.enumerated() {
                        let d = prevFeet.map { $0.distance(to: f) }.min() ?? 0
                        if d > 20 { print(String(format: "      leg %d: %.1f,%.1f (local %.1f,%.1f lift %.2f) moved %.1f  facing %.2f heading %.2f", k, f.x, f.y, p.legs[k].foot.x, p.legs[k].foot.y, p.legs[k].lift, d, p.facing, p.heading)) }
                    }
                }
            }
        }
        ring.append(String(format: "%.3f %@ yaw %.2f hd %.2f " + (0..<8).map { String(format: "L%d(%.0f,%.0f|%.1f)", $0, p.legs[$0].foot.x, p.legs[$0].foot.y, p.legs[$0].lift) }.joined(separator: " "), t, short(state) as NSString, p.facing, p.heading))
        if ring.count > 6 { ring.removeFirst() }
        prevFeet = feet
        prevPos = p.pos
        prevHeading = p.heading
        prevPitch = p.bodyPitch
        if state != prevState { recent.append(short(state)); if recent.count > 8 { recent.removeFirst() } }
        prevState = state
    }
}

print("frames \(frames), flagged \(events.count) (\(String(format: "%.2f", CGFloat(events.count) / (CGFloat(frames) / 3600))) per minute)")
var groups: [String: (n: Int, worst: CGFloat, kinds: Set<String>)] = [:]
for e in events {
    let key = e.from == e.to ? "within \(e.from)" : "\(e.from) > \(e.to)"
    var g = groups[key] ?? (0, 0, [])
    g.n += 1; g.worst = max(g.worst, e.amount); g.kinds.insert(e.kind)
    groups[key] = g
}
for (k, g) in groups.sorted(by: { $0.value.n > $1.value.n }).prefix(40) {
    print(String(format: "  %4d  worst %6.1f  %-30@ %@", g.n, g.worst, k as NSString, g.kinds.sorted().joined(separator: ",")))
}
