import AppKit

// Leg check: does every leg, every frame, look like a leg? Free life on
// awkward desktops (window corners close together, steps, cracks,
// cascades) and in every habitat, measured where the eye sees it:
//
//   stretch   a bone drawn longer or shorter than it is — past the worst
//             a flat window top ever shows for that leg (`flatStretch`)
//   reach     hip to foot past the leg's length — likewise (`flatReach`)
//   off       a planted foot not on any visible edge
//   sunk      a planted foot inside something solid
//   through   a knee or bone inside the thing it stands on
//   flip      a knee jumping from one side of its leg to the other
//   pop       a joint's screen acceleration spiking (px/frame², scale 1)
//
// Every random draw is seeded (Seeded.swift), and nothing the spider
// decides depends on its legs, so two builds live the very same lives
// frame for frame: `./tools/legs.sh ab` compares the working tree to HEAD.
//
//   flat                    flat window tops only: the envelope above, and
//                           LC_DUMP=file writes every drawn joint of every
//                           frame, to diff two builds
//   all | desk | hab | <world>[,<world>…]   (worlds: cascade, crack, ledges,
//                           diagonal, perched, tiles, wedged, hab:<preset>)
//   table base.txt new.txt  two runs' reports side by side
//   stack out.png a.png b.png…   strips one above the other
//   edges <preset>          a habitat's loops, edges and body lines
//
// LC_SCALE (1), LC_SECS (90), LC_RUNS (1), LC_SEED, LC_SEEDS (flat, 12).
// LC_V=1 lists the worst moments; LC_FILM=1 draws them into LC_OUT (with
// LC_FILMN, LC_KINDS); LC_CLIP=run:from-to:every:label draws one stretch
// of one life (LC_NAME, LC_CLEAN=1 without the joints); LC_TRACE=from-to:run
// prints every leg's bones, frame by frame. LC_NATURAL=1 walks the natural
// way (`Gait.natural`), LC_REFINED=1 the refined way (`LegMotion.refined`).

let dt: CGFloat = 1.0 / 60.0
let env = ProcessInfo.processInfo.environment
let S = CGFloat(Double(env["LC_SCALE"] ?? "1") ?? 1)
let secs = CGFloat(Double(env["LC_SECS"] ?? "90") ?? 90)
let runs = Int(env["LC_RUNS"] ?? "1") ?? 1
let outDir = env["LC_OUT"] ?? "."
let film = env["LC_FILM"] != nil
let topN = Int(env["LC_TOP"] ?? "6") ?? 6
let verbose = env["LC_V"] != nil
let naturalWalk = env["LC_NATURAL"] == "1"
let refinedWalk = env["LC_REFINED"] == "1"
func dress(_ s: Spider) {
    // (Set straight on the gait: applying a design draws random numbers,
    // and the lives would no longer match the classic walk's.)
    if naturalWalk { s.gait.natural = true }
    if refinedWalk { s.gait.motion = .refined }
}
let kinds = ["stretch", "reach", "off", "sunk", "through", "flip", "pop"]

// MARK: - Worlds

struct Solid {
    var rect: CGRect; var radius: CGFloat; var depth: Int; var id: String
    /// Shaped (the habitat's furniture): its outline, not the rect.
    var outline: [V2] = []
}

/// Signed distance to a rounded rect (or an outline): negative inside.
func sdf(_ p: V2, _ s: Solid) -> CGFloat {
    if !s.outline.isEmpty {
        var d = CGFloat.greatestFiniteMagnitude
        var inside = false
        var j = s.outline.count - 1
        for i in s.outline.indices {
            let a = s.outline[i], b = s.outline[j]
            d = min(d, projectOnSegment(p, a, b).dist)
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside ? -d : d
    }
    let r = min(s.radius, s.rect.width / 2, s.rect.height / 2)
    let hx = s.rect.width / 2 - r, hy = s.rect.height / 2 - r
    let qx = abs(p.x - s.rect.midX) - hx, qy = abs(p.y - s.rect.midY) - hy
    return V2(max(qx, 0), max(qy, 0)).length + min(max(qx, qy), 0) - r
}

final class World {
    let name: String
    let map: SurfaceMap
    /// Things with an inside: windows (rounded), furniture blocks.
    var solids: [Solid] = []
    /// Below this is the ground (habitat), if any.
    var groundY: CGFloat?
    let habitat: Bool
    let start: V2
    init(name: String, map: SurfaceMap, habitat: Bool, start: V2) {
        self.name = name; self.map = map; self.habitat = habitat; self.start = start
    }

    /// Distance from `p` to the nearest edge a foot could really be on:
    /// one that can be seen (not behind a window in front), with a window's
    /// corners rounded.
    func offEdge(_ p: V2) -> CGFloat {
        var best = CGFloat.greatestFiniteMagnitude
        for l in map.loops {
            if l.kind == .windowEdge, l.cornerRadius > 0.5, l.closed {
                let d = abs(sdf(p, Solid(rect: l.rect, radius: l.cornerRadius, depth: l.depth, id: l.id)))
                if d < best, habitat || map.isVisible(p, depth: l.depth) { best = d }
                continue
            }
            for e in l.edge {
                let d = projectOnSegment(p, e.a, e.b).dist
                if d < best, habitat || l.kind != .windowEdge || map.isVisible(p, depth: l.depth) { best = d }
            }
        }
        return best
    }

    /// How deep `p` is inside something solid it should not be in.
    /// Desktop: the window it stands on, or any window in front of that,
    /// or off the screen. Habitat: any block, or the ground.
    func depthInside(_ p: V2, standingOn loopID: String?) -> CGFloat {
        var deepest: CGFloat = 0
        if habitat {
            for s in solids { deepest = max(deepest, -sdf(p, s)) }
            if let g = groundY { deepest = max(deepest, g - p.y) }
            return deepest
        }
        if let own = loopID.flatMap({ id in solids.first { $0.id == id } }) {
            for s in solids where s.depth <= own.depth { deepest = max(deepest, -sdf(p, s)) }
        }
        let scr = map.worldBounds
        return max(deepest, scr.minX - p.x, p.x - scr.maxX, scr.minY - p.y, p.y - scr.maxY, 0)
    }
}

func desk(_ name: String, _ wins: [(CGRect, Int)], dock: CGRect? = nil) -> World {
    let m = SurfaceMap()
    m.standoff = 22 * S
    let tw = wins.enumerated().map { TrackedWindow(id: CGWindowID($0.offset + 1), frame: $0.element.0, depth: $0.element.1, owner: "Mock") }
    m.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1400, height: 900), menuBarHeight: 30, windows: tw, dock: dock)
    let w = World(name: name, map: m, habitat: false, start: V2(wins[0].0.midX, wins[0].0.maxY + 22 * S))
    w.solids = tw.map { Solid(rect: $0.frame, radius: $0.cornerRadius, depth: $0.depth, id: "win:\($0.id)") }
    return w
}

func hab(_ p: Habitat.Preset) -> World {
    // A world of its own, 1:1 with the screen, as the tank has now.
    let h = Habitat.preset(p, world: CGSize(width: 4000, height: 1250))
    let scene = h.bounds
    let m = SurfaceMap()
    m.standoff = 22 * S
    let built = h.surfaces(standoff: m.standoff)
    let w = World(name: "hab:\(p.rawValue)", map: m, habitat: true, start: V2(scene.midX, 300))
    #if SHAPED
    // (The furniture as it is shaped: see HabitatGeometry.swift.)
    m.rebuild(habitat: built)
    for it in h.items where it.kind.climbable {
        for part in it.geometry.parts {
            w.solids.append(Solid(rect: Poly.bounds(part.outline), radius: 0, depth: 0, id: "item:\(it.id)", outline: part.outline))
        }
    }
    #else
    m.rebuild(habitat: built.air, loops: built.loops)
    for it in h.items where it.kind.climbable {
        guard let r = Habitat.solidRect(it) else { continue }
        w.solids.append(Solid(rect: r, radius: 0, depth: 0, id: "item:\(it.id)"))
    }
    #endif
    w.groundY = built.air.minY
    return w
}

func desks() -> [World] {
    [
        // Cascaded windows: every top-left corner a step up and left of the last.
        desk("cascade", [(CGRect(x: 300, y: 300, width: 520, height: 320), 2),
                         (CGRect(x: 330, y: 270, width: 520, height: 320), 1),
                         (CGRect(x: 360, y: 240, width: 520, height: 320), 0)]),
        // Side by side with a narrow gap, tops a small step apart.
        desk("crack", [(CGRect(x: 250, y: 300, width: 420, height: 300), 0),
                       (CGRect(x: 684, y: 300, width: 420, height: 314), 1)]),
        // Tops almost level, one in front overlapping the other.
        desk("ledges", [(CGRect(x: 250, y: 280, width: 460, height: 320), 1),
                        (CGRect(x: 560, y: 250, width: 460, height: 356), 0)]),
        // Corner to corner: one window's bottom-right touching another's top-left.
        desk("diagonal", [(CGRect(x: 250, y: 420, width: 400, height: 280), 0),
                          (CGRect(x: 640, y: 150, width: 400, height: 280), 1)]),
        // A small window perched on top of a big one's top edge.
        desk("perched", [(CGRect(x: 250, y: 200, width: 700, height: 320), 1),
                         (CGRect(x: 500, y: 500, width: 200, height: 140), 0)]),
        // Small windows close together.
        desk("tiles", [(CGRect(x: 300, y: 300, width: 150, height: 100), 0),
                       (CGRect(x: 462, y: 318, width: 150, height: 100), 1),
                       (CGRect(x: 380, y: 410, width: 150, height: 100), 2),
                       (CGRect(x: 624, y: 290, width: 150, height: 100), 3)]),
        // Windows jammed against the screen's sides, the floor and the menu bar.
        desk("wedged", [(CGRect(x: 0, y: 12, width: 420, height: 300), 0),
                        (CGRect(x: 1400 - 380, y: 900 - 30 - 250, width: 380, height: 250), 1)],
             dock: CGRect(x: 520, y: 0, width: 420, height: 64)),
    ]
}

func habs() -> [World] { Habitat.Preset.allCases.filter { $0 != .empty }.map { hab($0) } }

// MARK: - Measuring

/// Face-on raised-leg gestures draw legs 1 and 2 with leg 0's proportions.
func borrowsBones(_ st: String, _ i: Int) -> Bool {
    (i == 1 || i == 2) && ["greet", "armsUp", "curious", "peekaboo"].contains { st.hasPrefix("attached:\($0)") }
}
/// The worst walking and standing on a flat window top ever does, per leg
/// (`legs flat`, 40 seeds, scale 1): bone stretch and reach. Only what
/// goes past these counts.
let flatStretch: [CGFloat] = [0.92, 1.05, 0.60, 0.48, 0.73, 0.73, 0.48, 0.48]
let flatReach: [CGFloat] = [0.95, 1.18, 0.90, 0.96, 0.88, 0.86, 0.74, 0.96]

struct Joints { var hip: [V2]; var knee: [V2]; var foot: [V2] }

/// Every drawn joint in screen space, as the renderer lays it out.
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

struct Event: Comparable {
    var kind: String
    var value: CGFloat
    var leg: Int
    var frame: Int
    var state: String
    var run: Int
    var world: String
    static func < (a: Event, b: Event) -> Bool { a.value < b.value }
}

final class Tally {
    var frames = 0
    var framesBy: [String: Int] = [:]          // frames with at least one of that kind
    var worst: [String: [Event]] = [:]         // the worst moments of each kind
    var byState: [String: [String: Int]] = [:] // kind -> what it was doing -> frames
    func add(_ e: Event) {
        var list = worst[e.kind, default: []]
        // One per moment: a frame within 20 of one kept replaces it if worse.
        if let k = list.firstIndex(where: { $0.world == e.world && $0.run == e.run && abs($0.frame - e.frame) < 20 }) {
            if e.value > list[k].value { list[k] = e }
        } else {
            list.append(e)
        }
        list.sort(by: >)
        if list.count > 40 { list.removeLast() }
        worst[e.kind] = list
    }
}

let thresholds: [String: CGFloat] = [
    "stretch": 0.08,   // share of a bone's length, past the flat envelope
    "reach": 0.06,     // share of the leg's length, past the flat envelope
    "off": 3.0,        // px (scale 1)
    "sunk": 3.0,       // px
    "through": 4.0,    // px
    "flip": 0.6,       // change of the bend's sine in one frame
    "pop": 6.0,        // px/frame²
]

final class Checker {
    let world: World
    let tally: Tally
    var run = 0
    var prevSide: [CGFloat] = Array(repeating: 0, count: 8)
    var prevJ: [V2] = []
    var prevV: [V2] = []
    var prevMirror: CGFloat = 1
    init(world: World, tally: Tally) { self.world = world; self.tally = tally }

    func reset() { prevSide = Array(repeating: 0, count: 8); prevJ = []; prevV = [] }

    func sample(_ s: Spider, frame: Int) {
        let p = s.pose()
        let st = s.debugState
        tally.frames += 1
        guard p.legs.count == 8 else { return }
        let j = screenJoints(p)
        let profile = SpiderRenderer.profileAmount(yaw: p.facing)
        let sc = max(p.scale, 0.05)
        let attached = st.hasPrefix("attached")
        let rolling = st.hasPrefix("attached:roll")
        // (On a line the legs are their own model, reviewed on its own.)
        let onLine = st.hasPrefix("dangling") || st.hasPrefix("swinging")
        let loopID: String? = attached ? st.components(separatedBy: " on ").last.map { String($0.split(separator: " ").first ?? "") } : nil
        let planted = s.debugPlanted
        let mirror: CGFloat = p.facing >= 0 ? 1 : -1
        var seen: Set<String> = []
        func note(_ kind: String, _ v: CGFloat, _ leg: Int) {
            guard v > thresholds[kind]! else { return }
            seen.insert(kind)
            tally.add(Event(kind: kind, value: v, leg: leg, frame: frame, state: st, run: run, world: world.name))
            tally.byState[kind, default: [:]][String(st.split(separator: " ").first ?? ""), default: 0] += 1
        }
        for i in 0..<8 {
            let r = SpiderRenderer.rig(i, profile: profile, look: s.look)
            let a = (r.knee - r.hip).length * sc, b = (r.foot - r.knee).length * sc
            let fem = j.knee[i].distance(to: j.hip[i]), tib = j.foot[i].distance(to: j.knee[i])
            if !rolling, !onLine, !borrowsBones(st, i) {
                note("stretch", max(abs(fem / a - 1), abs(tib / b - 1)) - flatStretch[i], i)
                note("reach", j.foot[i].distance(to: j.hip[i]) / (a + b) - flatReach[i], i)
            }
            // Which side of its leg the knee is on, as the sine of the bend
            // (not across the frame the sprite mirrors in, which re-pairs legs).
            let d = j.foot[i] - j.hip[i]
            let side = d.length > 1 ? d.normalized.cross(j.knee[i] - j.hip[i]) / max(fem, 1) : 0
            if !rolling, prevSide[i] != 0, mirror == prevMirror { note("flip", abs(side - prevSide[i]), i) }
            prevSide[i] = side
            guard attached, !rolling else { continue }
            // (A foot the pose holds up — a wave, a groom — is meant to be off.)
            if planted[i].planted, p.legs[i].foot.y < SpiderRenderer.ground + 2.5 {
                let off = world.offEdge(j.foot[i]) / sc
                note("off", off, i)
                // (On a visible edge — the side of a window in front, over
                // the one behind — is standing on something.)
                if off > 2.5 { note("sunk", world.depthInside(j.foot[i], standingOn: loopID) / sc, i) }
            }
            var deep: CGFloat = 0
            for q in [j.knee[i], (j.hip[i] + j.knee[i]) * 0.5, (j.knee[i] + j.foot[i]) * 0.5] {
                deep = max(deep, world.depthInside(q, standingOn: loopID))
            }
            note("through", deep / sc, i)
        }
        // Pops: joint acceleration, re-paired across a mirror flip.
        let all = j.foot + j.knee
        if mirror != prevMirror, prevJ.count == 16 {
            prevJ = (0..<8).map { prevJ[7 - $0] } + (0..<8).map { prevJ[15 - $0] }
            if prevV.count == 16 { prevV = (0..<8).map { prevV[7 - $0] } + (0..<8).map { prevV[15 - $0] } }
        }
        prevMirror = mirror
        if prevJ.count == 16 {
            let v = zip(all, prevJ).map { $0 - $1 }
            if prevV.count == 16, !st.hasPrefix("held") {
                for k in 0..<16 { note("pop", (v[k] - prevV[k]).length / sc, k % 8) }
            }
            prevV = v
        }
        prevJ = all
        for k in seen { tally.framesBy[k, default: 0] += 1 }
    }
}

// MARK: - Drawing

func drawScene(_ c: CGContext, pose: SpiderPose, world: World) {
    for s in world.solids.sorted(by: { $0.depth > $1.depth }) {
        c.setFillColor(NSColor(calibratedWhite: world.habitat ? 0.3 : 0.14, alpha: 1).cgColor)
        if let f = s.outline.first {
            c.move(to: f.point)
            for q in s.outline.dropFirst() { c.addLine(to: q.point) }
            c.closePath()
        } else {
            c.addPath(CGPath(roundedRect: s.rect, cornerWidth: s.radius, cornerHeight: s.radius, transform: nil))
        }
        c.fillPath()
    }
    c.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor)
    c.setLineWidth(1.0)
    c.beginPath()
    for l in world.map.loops { for e in l.edge { c.move(to: e.a.point); c.addLine(to: e.b.point) } }
    c.strokePath()
    if let web = pose.web, let path = SpiderRenderer.silkPath(pose) {
        c.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.62 * web.alpha))
        c.setLineWidth(1.1)
        c.addPath(path)
        c.strokePath()
    }
    let side = SpiderRenderer.spriteSide(for: pose.scale)
    SpiderRenderer.draw(pose, in: c, bounds: CGRect(x: pose.pos.x - side / 2, y: pose.pos.y - side / 2, width: side, height: side))
    guard env["LC_CLEAN"] == nil else { return }
    // Each leg's hip-knee-foot as the eye sees it, feet dotted.
    let j = screenJoints(pose)
    for i in 0..<pose.legs.count {
        c.setStrokeColor(NSColor.systemPink.withAlphaComponent(0.7).cgColor)
        c.setLineWidth(0.6)
        c.beginPath(); c.move(to: j.hip[i].point); c.addLine(to: j.knee[i].point); c.addLine(to: j.foot[i].point); c.strokePath()
        c.setFillColor(NSColor.green.cgColor)
        c.fillEllipse(in: CGRect(x: j.foot[i].x - 1, y: j.foot[i].y - 1, width: 2, height: 2))
    }
}

let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)

/// A strip of frames, each centred on the spider.
func strip(_ name: String, _ shots: [(SpiderPose, String)], world: World, cols: Int = 10, cell: CGFloat = 130, zoom: CGFloat = 3) {
    guard !shots.isEmpty else { return }
    let rows = (shots.count + cols - 1) / cols
    let W = Int(cell * CGFloat(cols) * zoom), H = Int(cell * CGFloat(rows) * zoom)
    guard let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    c.setFillColor(NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.27, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for (n, sh) in shots.enumerated() {
        let col = n % cols, row = n / cols
        let box = CGRect(x: CGFloat(col) * cell * zoom, y: CGFloat(rows - 1 - row) * cell * zoom, width: cell * zoom, height: cell * zoom)
        c.saveGState()
        c.clip(to: box)
        c.translateBy(x: box.midX, y: box.midY)
        c.scaleBy(x: zoom, y: zoom)
        c.translateBy(x: -sh.0.pos.x, y: -sh.0.pos.y)
        drawScene(c, pose: sh.0, world: world)
        c.restoreGState()
        c.setStrokeColor(gray: 0.45, alpha: 1)
        c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: sh.1, attributes: [.font: font, .foregroundColor: NSColor(white: 0.9, alpha: 1)]))
        c.textPosition = CGPoint(x: box.minX + 4, y: box.minY + 4)
        CTLineDraw(line, c)
    }
    guard let img = c.makeImage() else { return }
    let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
    try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: url)
    print("    wrote \(url.path)")
}

// MARK: - Running

func live(_ world: World) -> Tally {
    let tally = Tally()
    let checker = Checker(world: world, tally: tally)
    /// One life, from its seed; `each` sees every frame.
    func life(_ r: Int, _ each: (Spider, Int) -> Void) {
        reseed(UInt64(r * 7919 + world.name.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) } & 0xffff) + (UInt64(env["LC_SEED"] ?? "1") ?? 1))
        let s = Spider(map: world.map)
        s.config.scale = S
        s.config.followCursor = false
        s.config.approachCursor = false
        s.config.pounceOnCursor = false
        dress(s)
        s.enter(map: world.map, at: world.start, habitat: world.habitat)
        for f in 0..<Int(secs / dt) {
            s.setCursor(V2(-9e4, -9e4))
            s.update(dt: dt)
            each(s, f)
        }
    }
    func label(_ s: Spider) -> String {
        String(s.debugState.replacingOccurrences(of: "attached:", with: "").split(separator: " ").first ?? "")
    }
    if let clip = env["LC_CLIP"] {
        let p = clip.split(separator: ":").map(String.init)
        let r = Int(p[0]) ?? 0, span = p[1].split(separator: "-").compactMap { Int($0) }, every = Int(p[2]) ?? 2
        var shots: [(SpiderPose, String)] = []
        life(r) { s, f in
            if f >= span[0], f <= span[1], (f - span[0]) % every == 0 { shots.append((s.pose(), "\(p.count > 3 ? p[3] : "") \(f) \(label(s))")) }
        }
        strip(env["LC_NAME"] ?? "clip", shots, world: world, cols: shots.count, cell: 110, zoom: 2.5)
        exit(0)
    }
    if let tr = env["LC_TRACE"] {
        let parts = tr.split(separator: ":")
        let span = parts[0].split(separator: "-").compactMap { Int($0) }
        life(parts.count > 1 ? Int(parts[1]) ?? 0 : 0) { s, f in
            guard f >= span[0], f <= span[1] else { return }
            let p = s.pose()
            let j = screenJoints(p)
            let profile = SpiderRenderer.profileAmount(yaw: p.facing)
            let legs = (0..<8).map { i -> String in
                let r = SpiderRenderer.rig(i, profile: profile, look: s.look)
                let a = (r.knee - r.hip).length * p.scale, b = (r.foot - r.knee).length * p.scale
                return String(format: "%d: thigh %.2f shin %.2f reach %.2f foot %.0f,%.0f", i, j.knee[i].distance(to: j.hip[i]) / a,
                              j.foot[i].distance(to: j.knee[i]) / b, j.foot[i].distance(to: j.hip[i]) / (a + b), j.foot[i].x, j.foot[i].y)
            }
            print(f, s.debugState, String(format: "at %.0f,%.0f heading %.2f", p.pos.x, p.pos.y, p.heading))
            print("   " + legs.joined(separator: "\n   ") + "\n   " + s.debugFeetWhy)
        }
        exit(0)
    }
    for r in 0..<runs {
        checker.run = r
        checker.reset()
        life(r) { s, f in if f > 60 { checker.sample(s, frame: f) } }
    }
    report(world, tally)
    if film {
        // The worst moments of each kind, lived again and drawn: the 24
        // frames before, the 12 after.
        let per = Int(env["LC_FILMN"] ?? "2") ?? 2
        for kind in (env["LC_KINDS"] ?? kinds.joined(separator: ",")).split(separator: ",").map(String.init) {
            for (n, e) in (tally.worst[kind] ?? []).prefix(per).enumerated() {
                var shots: [(SpiderPose, String)] = []
                life(e.run) { s, f in
                    if f >= e.frame - 24, f <= e.frame + 12, (f - e.frame) % 2 == 0 {
                        shots.append((s.pose(), "\(f) \(label(s))" + (f == e.frame ? " <<" : "")))
                    }
                }
                strip("\(world.name.replacingOccurrences(of: ":", with: "-"))-\(kind)\(n)-leg\(e.leg)", shots, world: world)
            }
        }
    }
    return tally
}

func report(_ name: String, _ t: Tally) {
    var line = String(format: "%-18@ %6d fr", name as NSString, t.frames)
    for k in kinds {
        line += String(format: "  %@ %4.1f%% (%.2f)", k as NSString, Double(t.framesBy[k] ?? 0) * 100 / Double(max(t.frames, 1)), t.worst[k]?.first?.value ?? 0)
    }
    print(line)
    guard verbose else { return }
    for k in kinds {
        guard let list = t.worst[k], !list.isEmpty else { continue }
        let states = (t.byState[k] ?? [:]).sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print("    \(k): \(states)")
        for e in list.prefix(topN) {
            print(String(format: "      %.2f leg %d run %d fr %d  %@  %@", e.value, e.leg, e.run, e.frame, e.state as NSString, e.world as NSString))
        }
    }
}
func report(_ world: World, _ t: Tally) { report(world.name, t) }

let args = CommandLine.arguments
let pick = args.count > 1 ? args[1] : "all"

switch pick {
case "stack":
    let imgs = args[3...].compactMap { NSImage(contentsOfFile: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    let W = imgs.map(\.width).max() ?? 1, H = imgs.map(\.height).reduce(0, +)
    let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var y = H
    for im in imgs { y -= im.height; c.draw(im, in: CGRect(x: 0, y: y, width: im.width, height: im.height)) }
    try? NSBitmapImageRep(cgImage: c.makeImage()!).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))

case "table":
    // Two reports side by side: per world and kind, % of frames and worst,
    // before > after.
    func parse(_ path: String) -> [(String, [String: (CGFloat, CGFloat)])] {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").compactMap { line -> (String, [String: (CGFloat, CGFloat)])? in
            let f = line.split(separator: " ").map(String.init)
            guard f.count > 3, f[2] == "fr" else { return nil }
            var m: [String: (CGFloat, CGFloat)] = [:]
            var k = 3
            while k + 2 < f.count {
                m[f[k]] = (CGFloat(Double(f[k + 1].dropLast()) ?? 0), CGFloat(Double(f[k + 2].dropFirst().dropLast()) ?? 0))
                k += 3
            }
            return (f[0], m)
        }
    }
    let a = parse(args[2]), b = Dictionary(parse(args[3]), uniquingKeysWith: { x, _ in x })
    print("world".padding(toLength: 17, withPad: " ", startingAt: 0) + kinds.map { $0.padding(toLength: 20, withPad: " ", startingAt: 0) }.joined())
    for (w, m) in a {
        var row = w.padding(toLength: 17, withPad: " ", startingAt: 0)
        for k in kinds {
            let x = m[k] ?? (0, 0), y = b[w]?[k] ?? (0, 0)
            row += String(format: "%.1f>%.1f %.1f>%.1f", x.0, y.0, x.1, y.1).padding(toLength: 20, withPad: " ", startingAt: 0)
        }
        print(row)
    }

case "edges":
    let w = hab(Habitat.Preset(rawValue: args.count > 2 ? args[2] : "forestFloor") ?? .forestFloor)
    for l in w.map.loops {
        print(l.id, l.kind, "closed", l.closed, "rect", l.rect)
        for e in l.edge { print(String(format: "   edge %.1f,%.1f -> %.1f,%.1f %@", e.a.x, e.a.y, e.b.x, e.b.y, "\(e.facing)" as NSString)) }
        for e in l.segs { print(String(format: "   body %.1f,%.1f -> %.1f,%.1f %@", e.a.x, e.a.y, e.b.x, e.b.y, "\(e.facing)" as NSString)) }
    }

case "flat":
    // Flat window tops only: free life on the middle of a wide window, from
    // several seeds, until it leaves the flat stretch. The bone stretch and
    // reach seen there are the envelope the other checks measure past;
    // LC_DUMP writes every drawn joint of every frame, to diff two builds.
    let w = desk("flat", [(CGRect(x: 60, y: 200, width: 1280, height: 400), 0)])
    var dump = ""
    var frames = 0
    var legStretch = Array(repeating: CGFloat(0), count: 8), legReach = Array(repeating: CGFloat(0), count: 8)
    for seed in 0..<(Int(env["LC_SEEDS"] ?? "12") ?? 12) {
        reseed(UInt64(seed) * 104729 + 17)
        let s = Spider(map: w.map)
        s.config.scale = S
        s.config.followCursor = seed % 3 == 1
        s.config.approachCursor = seed % 3 == 1
        s.config.pounceOnCursor = false
        dress(s)
        s.debugAttach(loopID: "win:1", segIdx: 0, t: 640, dir: seed % 2 == 0 ? 1 : -1)
        for f in 0..<Int(secs / dt) {
            // For some, the pointer drifting about above the window.
            s.setCursor(seed % 3 == 1 ? V2(700 + sin(CGFloat(f) * 0.01) * 400, 700 + cos(CGFloat(f) * 0.013) * 60) : V2(-9e4, -9e4))
            s.update(dt: dt)
            let st = s.debugState
            let p = s.pose()
            guard st.hasPrefix("attached"), st.hasSuffix("on win:1"), abs(p.pos.y - (600 + 22 * S)) < 12,
                  p.pos.x > 150, p.pos.x < 1250, abs(sin(p.heading)) < 0.01 else { break }
            let j = screenJoints(p)
            dump += "\(seed) \(f) " + (j.hip + j.knee + j.foot).map { String(format: "%.3f,%.3f", $0.x, $0.y) }.joined(separator: " ") + " \(st)\n"
            frames += 1
            let profile = SpiderRenderer.profileAmount(yaw: p.facing)
            for i in 0..<8 where !borrowsBones(st, i) {
                let r = SpiderRenderer.rig(i, profile: profile, look: s.look)
                let a = (r.knee - r.hip).length * p.scale, b = (r.foot - r.knee).length * p.scale
                legStretch[i] = max(legStretch[i], abs(j.knee[i].distance(to: j.hip[i]) / a - 1), abs(j.foot[i].distance(to: j.knee[i]) / b - 1))
                legReach[i] = max(legReach[i], j.foot[i].distance(to: j.hip[i]) / (a + b))
            }
        }
    }
    print("flat: \(frames) frames")
    print("  per leg stretch max:", legStretch.map { String(format: "%.2f", $0) }.joined(separator: ","))
    print("  per leg reach max:  ", legReach.map { String(format: "%.2f", $0) }.joined(separator: ","))
    if let path = env["LC_DUMP"] { try? dump.write(toFile: path, atomically: true, encoding: .utf8) }

default:
    let worlds: [World]
    switch pick {
    case "desk": worlds = desks()
    case "hab": worlds = habs()
    case "all": worlds = desks() + habs()
    default: worlds = (desks() + habs()).filter { w in pick.split(separator: ",").contains { w.name == $0 || w.name == "hab:\($0)" } }
    }
    let total = Tally()
    for w in worlds {
        let t = live(w)
        total.frames += t.frames
        for (k, v) in t.framesBy { total.framesBy[k, default: 0] += v }
        for (_, v) in t.worst { for e in v { total.add(e) } }
    }
    report("TOTAL", total)
}
