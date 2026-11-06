import AppKit

// Pose trace exporter: runs the real Spider headless through a scripted
// scenario and writes one JSON line per frame, for the Windows port to be
// compared against frame by frame (see MAC_HANDOFF.md and
// WINDOWS_PARITY_PLAN.md).
//
//   build/Trace <scenario.json> <out.jsonl>
//
// A scenario names a desktop (tests/golden/desktops/<name>.json, found
// beside the scenario's own folder), a length, a pointer script and a list
// of timed commands. The Windows tools read the very same two files, so both
// platforms live the same scripted life.
//
// Environment:
//   LC_SEED       seed for every random draw (tools/legs/Seeded.swift); default 1
//   TR_SCALE      overrides the scenario's spider scale
//   TR_SECONDS    overrides its length
//   TR_HOUR       hour of day the spider believes it is (default 14)
//   TR_EVERY      write every Nth frame only (default 1)
//   TR_DETAIL     "full" (the whole pose) or "state" (just state and position);
//                 overrides the scenario's own "detail"
//   TR_<NAME>     substituted for "$NAME" anywhere in a scenario's strings
//                 (TR_PREY=cricket, TR_ACT=walk, ...)
//
// Scenario file:
//   { "id": "flat-walk", "desktop": "desk-a", "seconds": 12, "dt": 0.016666666666666666,
//     "scale": 0.95, "detail": "full",
//     "config": { "followCursor": false, "approachCursor": false, "pounceOnCursor": false,
//                 "liveliness": 1.0, "webs": true, "hammocks": true },
//     "design": { ...a SpiderDesign as JSON... },       (optional; default design if absent)
//     "cursor": { "mode": "none" }
//             | { "mode": "orbit", "cx": 960, "cy": 540, "rx": 500, "ry": 320, "wx": 0.23, "wy": 0.17 }
//             | { "mode": "wiggle", "cx": 480, "cy": 800, "ax": 30, "ay": 0, "hz": 3 }
//             | { "mode": "points", "points": [[t, x, y], ...] },   (linear between points)
//     "windowPaths": [ { "id": 1, "points": [[t, x, y], ...] } ],   (window origin moves)
//     "events": [ { "t": 1.0, "cmd": "attach", ... } ] }
//
// Commands (all times in seconds; the event runs just before that frame's update):
//   attach {loop, seg, at, dir}      walk {seconds}             noPauses
//   gait {name}                      activity {name, seconds}   beat {name}
//   hang {x, y, length, swing, kick} lineTo {length}
//   jump {x, y}                      fall
//   grab {x?, y?}                    (default: where the spider is)
//   dragTo {x, y, seconds}           (moves the held spider there over that long)
//   endGrab {vx, vy}                 scroll {dy, precise, starts}
//   poke                             buildHammock
//   release {kind, x?, y?}           (kind: cricket worm fruitfly moth beetle ant mosquito ladybug)
//   emote {name}                     weather {wet, snow, dust}
//   cinema {on}                      (the screen becomes a cinema: floor and ceiling only)

setvbuf(stdout, nil, _IONBF, 0)
let argv = Array(CommandLine.arguments.dropFirst())
guard argv.count >= 2 else {
    print("usage: Trace <scenario.json> <out.jsonl>")
    exit(2)
}
let env = ProcessInfo.processInfo.environment

func fail(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(2) }
func loadJSON(_ path: String) -> [String: Any] {
    guard let d = FileManager.default.contents(atPath: path),
          let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { fail("cannot read \(path)") }
    return o
}
func num(_ v: Any?, _ d: Double = 0) -> Double { (v as? NSNumber)?.doubleValue ?? d }
func flag(_ v: Any?, _ d: Bool = false) -> Bool { (v as? NSNumber)?.boolValue ?? d }
/// A string, with "$NAME" taken from TR_NAME.
func txt(_ v: Any?, _ d: String = "") -> String {
    guard let s = v as? String else { return d }
    if s.hasPrefix("$") { return env["TR_" + String(s.dropFirst())] ?? d }
    return s
}
func points3(_ v: Any?) -> [(t: Double, x: Double, y: Double)] {
    (v as? [[Any]] ?? []).compactMap { p in
        guard p.count >= 3 else { return nil }
        return (num(p[0]), num(p[1]), num(p[2]))
    }
}
func along(_ pts: [(t: Double, x: Double, y: Double)], _ t: Double) -> (Double, Double)? {
    guard let first = pts.first, let last = pts.last else { return nil }
    if t <= first.t { return (first.x, first.y) }
    if t >= last.t { return (last.x, last.y) }
    for i in 1..<pts.count where t <= pts[i].t {
        let a = pts[i - 1], b = pts[i]
        let u = (t - a.t) / max(b.t - a.t, 1e-9)
        return (a.x + (b.x - a.x) * u, a.y + (b.y - a.y) * u)
    }
    return (last.x, last.y)
}

// MARK: Scenario and desktop

let scPath = argv[0], outPath = argv[1]
let sc = loadJSON(scPath)
let scenarioID = txt(sc["id"], URL(fileURLWithPath: scPath).deletingPathExtension().lastPathComponent)
let deskName = txt(sc["desktop"], "desk-a")
let deskPath = URL(fileURLWithPath: scPath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("desktops").appendingPathComponent(deskName + ".json").path
let desk = loadJSON(deskPath)
let scr = desk["screen"] as? [String: Any] ?? [:]
let screen = CGRect(x: num(scr["x"]), y: num(scr["y"]), width: num(scr["w"], 1920), height: num(scr["h"], 1080))
let menuBar = CGFloat(num(desk["menuBarHeight"]))

let scale = CGFloat(Double(env["TR_SCALE"] ?? "") ?? num(sc["scale"], 0.95))
let dt = CGFloat(num(sc["dt"], 1.0 / 60.0))
let seconds = CGFloat(Double(env["TR_SECONDS"] ?? "") ?? num(sc["seconds"], 10))
let every = max(1, Int(env["TR_EVERY"] ?? "1") ?? 1)
let detail = env["TR_DETAIL"] ?? txt(sc["detail"], "full")

struct WinSpec { var id: UInt32; var frame: CGRect; var depth: Int; var owner: String; var corner: CGFloat }
var specs: [WinSpec] = (desk["windows"] as? [[String: Any]] ?? []).map {
    WinSpec(id: UInt32(num($0["id"])),
            frame: CGRect(x: num($0["x"]), y: num($0["y"]), width: num($0["w"]), height: num($0["h"])),
            depth: Int(num($0["depth"])), owner: txt($0["owner"], "App"), corner: CGFloat(num($0["corner"], 26)))
}
let baseOrigins = specs.map { ($0.frame.minX, $0.frame.minY) }

let map = SurfaceMap()
map.standoff = 22 * scale
var cinemaOn = false
func rebuild() {
    let wins = specs.map { s -> TrackedWindow in
        var w = TrackedWindow(id: s.id, frame: s.frame, depth: s.depth, owner: s.owner)
        w.cornerRadius = s.corner
        return w
    }
    map.debugRebuild(screen: screen, menuBarHeight: menuBar, windows: wins, cinema: cinemaOn)
}
rebuild()

// MARK: Spider

let spider = Spider(map: map)
spider.config.scale = scale
for (k, v) in sc["config"] as? [String: Any] ?? [:] {
    switch k {
    case "liveliness": spider.config.liveliness = CGFloat(num(v))
    case "followCursor": spider.config.followCursor = flag(v)
    case "approachCursor": spider.config.approachCursor = flag(v)
    case "pounceOnCursor": spider.config.pounceOnCursor = flag(v)
    case "webs": spider.config.webs = flag(v)
    case "hammocks": spider.config.hammocks = flag(v)
    case "scale": break
    default: FileHandle.standardError.write("config key not supported by Trace: \(k)\n".data(using: .utf8)!)
    }
}
if let dj = sc["design"] as? [String: Any] {
    guard let data = try? JSONSerialization.data(withJSONObject: dj),
          let d = try? JSONDecoder().decode(SpiderDesign.self, from: data) else { fail("design in \(scPath) does not decode") }
    spider.apply(design: d)
}

// MARK: Pointer script

func cursorAt(_ t: Double) -> V2 {
    let c = sc["cursor"] as? [String: Any] ?? [:]
    switch txt(c["mode"], "none") {
    case "orbit":
        let cx = num(c["cx"], Double(screen.midX)), cy = num(c["cy"], Double(screen.midY))
        return V2(CGFloat(cx + cos(t * num(c["wx"], 0.23)) * num(c["rx"], 500)),
                  CGFloat(cy + sin(t * num(c["wy"], 0.17)) * num(c["ry"], 320)))
    case "wiggle":
        let s = sin(2 * Double.pi * num(c["hz"], 3) * t)
        return V2(CGFloat(num(c["cx"]) + num(c["ax"], 30) * s), CGFloat(num(c["cy"]) + num(c["ay"]) * s))
    case "points":
        if let p = along(points3(c["points"]), t) { return V2(CGFloat(p.0), CGFloat(p.1)) }
        return V2(-9e4, -9e4)
    default:
        return V2(-9e4, -9e4)   // far away, as the film tools park it
    }
}

// MARK: Commands

var drag: (from: V2, to: V2, startFrame: Int, frames: Int)?
func preyKind(_ name: String) -> PreyKind {
    let key = name.lowercased().replacingOccurrences(of: " ", with: "")
    return PreyKind.allCases.first { $0.label.lowercased().replacingOccurrences(of: " ", with: "") == key } ?? .cricket
}
func xy(_ e: [String: Any]) -> V2 { V2(CGFloat(num(e["x"])), CGFloat(num(e["y"]))) }

func run(_ e: [String: Any], frame: Int) {
    switch txt(e["cmd"]) {
    case "attach": spider.debugAttach(loopID: txt(e["loop"]), segIdx: Int(num(e["seg"])), t: CGFloat(num(e["at"])), dir: CGFloat(num(e["dir"], 1)))
    case "walk": spider.debugWalk(for: CGFloat(num(e["seconds"], 10)))
    case "noPauses": spider.debugNoPauses()
    case "gait": spider.debugGaitStyle(txt(e["name"]))
    case "activity": spider.debugActivity(txt(e["name"]), for: CGFloat(num(e["seconds"], 3)))
    case "beat": spider.debugBeat(txt(e["name"]))
    case "hang": spider.debugHang(at: xy(e), length: CGFloat(num(e["length"], 200)), swing: flag(e["swing"]), kick: CGFloat(num(e["kick"])))
    case "lineTo": spider.debugLineTo(CGFloat(num(e["length"])))
    case "jump": spider.debugJump(to: xy(e))
    case "fall": spider.debugFall()
    case "grab": spider.beginGrab(at: e["x"] == nil ? spider.worldPos : xy(e))
    case "dragTo":
        let n = max(1, Int((num(e["seconds"], 1) / Double(dt)).rounded()))
        drag = (spider.worldPos, xy(e), frame, n)
    case "endGrab": drag = nil; spider.endGrab(throwVelocity: V2(CGFloat(num(e["vx"])), CGFloat(num(e["vy"]))))
    case "scroll":
        spider.scroll(CGFloat(num(e["dy"])), precise: flag(e["precise"], true), startsGesture: e["starts"] == nil ? nil : flag(e["starts"]))
    case "poke": spider.poke()
    case "buildHammock": spider.buildHammock()
    case "release":
        _ = spider.release(preyKind(txt(e["kind"], "cricket")), at: e["x"] == nil ? nil : xy(e), in: nil)
    case "emote": spider.debugEmote(txt(e["name"]))
    case "weather": spider.debugWeatherOn(wet: e["wet"] == nil ? nil : CGFloat(num(e["wet"])),
                                          snow: e["snow"] == nil ? nil : CGFloat(num(e["snow"])),
                                          dust: e["dust"] == nil ? nil : CGFloat(num(e["dust"])))
    case "cinema": cinemaOn = flag(e["on"], true); rebuild()
    default: FileHandle.standardError.write("unknown command: \(txt(e["cmd"]))\n".data(using: .utf8)!)
    }
}

var events: [(frame: Int, order: Int, e: [String: Any])] = []
for (i, e) in (sc["events"] as? [[String: Any]] ?? []).enumerated() {
    events.append((Int((num(e["t"]) / Double(dt)).rounded()), i, e))
}
events.sort { ($0.frame, $0.order) < ($1.frame, $1.order) }
let windowPaths = (sc["windowPaths"] as? [[String: Any]] ?? []).map { (id: UInt32(num($0["id"])), pts: points3($0["points"])) }

// MARK: Run

#if arch(arm64)
let arch = "arm64"
#else
let arch = "x86_64"
#endif
let total = Int((seconds / dt).rounded())
var out = ""
out += "{\"type\":\"header\",\"scenario\":\(encodeJSON(scenarioID)),\"desktop\":\(encodeJSON(deskName)),"
out += "\"seed\":\(env["LC_SEED"] ?? "1"),\"scale\":\(Double(scale)),\"dt\":\(Double(dt)),\"frames\":\(total),"
out += "\"every\":\(every),\"detail\":\(encodeJSON(detail)),\"hour\":\(traceHour),\"arch\":\"\(arch)\","
out += "\"build\":\(encodeJSON(env["TR_BUILD"] ?? "")),\"commit\":\(encodeJSON(env["TR_COMMIT"] ?? ""))}\n"

var next = 0
for f in 0..<total {
    let t = Double(f) * Double(dt)
    // A window being dragged: rebuilt every frame it moves (the app's tracker
    // does it at 30 Hz while a window moves).
    var moved = false
    for wp in windowPaths {
        guard let i = specs.firstIndex(where: { $0.id == wp.id }), let p = along(wp.pts, t) else { continue }
        let o = CGPoint(x: p.0, y: p.1)
        if specs[i].frame.origin != o { specs[i].frame.origin = o; moved = true }
    }
    if moved { rebuild() }
    while next < events.count, events[next].frame <= f { run(events[next].e, frame: f); next += 1 }
    if let d = drag {
        let u = min(1, CGFloat(f - d.startFrame + 1) / CGFloat(d.frames))
        spider.moveGrab(to: d.from + (d.to - d.from) * u)
        if f - d.startFrame + 1 >= d.frames { drag = nil }
    }
    spider.setCursor(cursorAt(t))
    spider.update(dt: dt)
    guard f % every == 0 else { continue }
    let state = spider.debugState
    if detail == "state" {
        out += "{\"f\":\(f),\"state\":\(encodeJSON(state)),\"x\":\(Double(spider.worldPos.x)),\"y\":\(Double(spider.worldPos.y))}\n"
    } else {
        let pose = spider.pose()
        out += "{\"f\":\(f),\"state\":\(encodeJSON(state)),\"held\":\(spider.isHeld),\"pose\":\(encodeJSON(pose))}\n"
    }
}
guard (try? out.write(toFile: outPath, atomically: true, encoding: .utf8)) != nil else { fail("cannot write \(outPath)") }
print("wrote \(outPath): \(scenarioID), \(total) frames, scale \(scale), seed \(env["LC_SEED"] ?? "1")")
