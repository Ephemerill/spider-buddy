import AppKit

// Perch check: are the habitat's surfaces where its pictures are?
//
//   sheet out.png                 every kind of thing, painted, with its shape
//                                 and the surfaces worked out from it drawn over
//                                 (as it comes, flipped and bigger)
//   world <preset> out.png [x w]  a stretch of a ready-made tank, likewise
//   air [preset…]                 free life in each tank: how often a planted
//                                 foot is on nothing painted (the "crawling on
//                                 air" count), measured against the pictures
//
// PC_SECS (120), PC_RUNS (2), PC_SCALE (0.78: the size most people keep).
// Built by tools/perch.sh; `tools/perch.sh ab` runs `air` on HEAD's tree
// and this one, so the same measure is taken of the old surfaces and the new.

let env = ProcessInfo.processInfo.environment
let args = CommandLine.arguments
let dt: CGFloat = 1.0 / 60.0
let world = CGSize(width: 4000, height: 1250)

func c(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

func surfaces(_ h: Habitat, standoff: CGFloat) -> SurfaceMap {
    let m = SurfaceMap()
    m.standoff = standoff
    let built = h.surfaces(standoff: standoff)
    #if SHAPED
    m.rebuild(habitat: built)
    #else
    m.rebuild(habitat: built.air, loops: built.loops)
    #endif
    return m
}

/// Every climbable thing in `h`, painted into a picture of `area` (1 pt a pixel).
func paintItems(_ h: Habitat, area: CGRect, scale: CGFloat, _ ctx: CGContext, only: ((HabitatItem) -> Bool)? = nil) {
    for it in h.items where !it.inFront && (only?(it) ?? true) {
        let r = it.rect
        let pad = HabitatArt.itemPad(r.size)
        guard r.insetBy(dx: -pad, dy: -pad).intersects(area), let img = HabitatArt.itemImage(it, size: r.size, biome: h.biome, scale: scale, backed: h.isBacked(it)) else { continue }
        ctx.draw(img, in: CGRect(x: r.minX - pad - area.minX, y: r.minY - pad - area.minY, width: r.width + pad * 2, height: r.height + pad * 2))
    }
}

func overlay(_ h: Habitat, map: SurfaceMap, area: CGRect, _ ctx: CGContext) {
    func path(_ pts: [V2], closed: Bool = true) {
        guard let f = pts.first else { return }
        ctx.move(to: CGPoint(x: f.x - area.minX, y: f.y - area.minY))
        for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.x - area.minX, y: p.y - area.minY)) }
        if closed { ctx.closePath() }
    }
    ctx.setLineJoin(.round)
    #if SHAPED
    for it in h.items where !it.inFront {
        let g = it.geometry
        ctx.setFillColor(c(1, 0.2, 0.2, 0.18))
        for v in g.visual { path(v); ctx.fillPath() }
        for part in g.parts {
            ctx.setStrokeColor(part.role == .bulk ? c(1, 0.6, 0.2, 1) : c(0.4, 1, 0.3, 1))
            ctx.setLineWidth(1)
            path(part.outline)
            ctx.strokePath()
        }
        for hol in g.hollows {
            ctx.setStrokeColor(c(1, 0.6, 0.1, 1))
            ctx.setLineDash(phase: 0, lengths: [3, 2])
            path(hol.cavity)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        for a in g.anchors {
            let p = CGPoint(x: a.point.x - area.minX, y: a.point.y - area.minY)
            switch a.kind {
            case .perch: ctx.setFillColor(c(0.4, 1, 0.3)); ctx.fill(CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            case .tie: ctx.setStrokeColor(c(1, 1, 1)); ctx.setLineWidth(1.2); ctx.strokeEllipse(in: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6))
            case .entrance: ctx.setFillColor(c(1, 0.6, 0.1)); ctx.fillEllipse(in: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7))
            case .refuge, .drink, .bask, .lookout, .feed:
                ctx.setFillColor(c(0.3, 0.8, 1))
                ctx.move(to: CGPoint(x: p.x, y: p.y + 5)); ctx.addLine(to: CGPoint(x: p.x + 5, y: p.y))
                ctx.addLine(to: CGPoint(x: p.x, y: p.y - 5)); ctx.addLine(to: CGPoint(x: p.x - 5, y: p.y)); ctx.fillPath()
            }
        }
    }
    #endif
    for l in map.loops {
        ctx.setStrokeColor(c(1, 0.92, 0.2, 0.95))
        ctx.setLineWidth(1)
        for e in l.edge { path([e.a, e.b], closed: false) }
        ctx.strokePath()
        ctx.setStrokeColor(l.kind == .screenBorder ? c(0.4, 0.65, 1, 0.95) : c(0.3, 0.95, 1, 0.95))
        ctx.setLineWidth(1.4)
        for s in l.segs { path([s.a, s.b], closed: false) }
        ctx.strokePath()
    }
    #if SHAPED
    ctx.setFillColor(c(1, 0.2, 0.9))
    for j in map.junctions { ctx.fillEllipse(in: CGRect(x: j.at.x - area.minX - 2.5, y: j.at.y - area.minY - 2.5, width: 5, height: 5)) }
    #endif
}

func save(_ img: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

func label(_ ctx: CGContext, _ s: String, at p: CGPoint) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(white: 0.92, alpha: 1)]))
    ctx.textPosition = p
    CTLineDraw(line, ctx)
}

// MARK: - The sheet

func sheet(_ out: String) {
    let kinds = HabitatItemKind.allCases
    let cellW: CGFloat = 420, cellH: CGFloat = 470, cols = 4
    let rows = Int(ceil(Double(kinds.count) / Double(cols)))
    let W = cellW * CGFloat(cols), H = cellH * CGFloat(rows)
    let img = HabitatArt.image(CGSize(width: W, height: H), scale: 2) { ctx in
        ctx.setFillColor(c(0.13, 0.14, 0.16))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (i, kind) in kinds.enumerated() {
            let cell = CGRect(x: CGFloat(i % cols) * cellW, y: H - CGFloat(i / cols + 1) * cellH, width: cellW, height: cellH)
            // Its own little tank: a ground, and it standing on it (or
            // hanging from the lid) as it comes, flipped, and half as big again.
            var h = Habitat(biome: .forest, world: CGSize(width: cellW, height: cellH - 20))
            let big = kind.defaultSize.height > 180 ? 1.25 : 1.6
            for (x, scale, flip) in [(cellW * 0.24, CGFloat(1), false), (cellW * 0.7, CGFloat(big), true)] {
                var it = h.add(kind, at: CGPoint(x: x, y: kind.hangs ? h.size.height : 0), scale: scale)
                it.flipped = flip
                it.seed = 4242 + Int(scale * 10)
                if kind == .branch { it.y = 60 }
                Habitat.clamp(&it, in: h.size)
                h.items[h.items.count - 1] = it
            }
            let m = surfaces(h, standoff: 22 * 0.78)
            ctx.saveGState()
            ctx.translateBy(x: cell.minX, y: cell.minY)
            ctx.clip(to: CGRect(x: 0, y: 0, width: cellW, height: cellH))
            ctx.setFillColor(c(0.2, 0.16, 0.12))
            ctx.fill(CGRect(x: 0, y: 0, width: cellW, height: HabitatLayout.ground))
            paintItems(h, area: h.bounds, scale: 2, ctx)
            overlay(h, map: m, area: h.bounds, ctx)
            label(ctx, "\(kind.label)\(kind.climbable ? "" : " (scenery)")", at: CGPoint(x: 6, y: cellH - 16))
            ctx.restoreGState()
            ctx.setStrokeColor(c(0.4, 0.4, 0.45))
            ctx.stroke(cell)
        }
    }
    save(img!, out)
}

// MARK: - A stretch of a tank

func worldShot(_ p: Habitat.Preset, _ out: String, x: CGFloat?, w: CGFloat?) {
    let h = Habitat.preset(p, world: world)
    let m = surfaces(h, standoff: 22 * 0.78)
    let W = w ?? 1600
    let x0 = x ?? (world.width - W) / 2
    let area = CGRect(x: x0, y: 0, width: W, height: world.height)
    let img = HabitatArt.image(area.size, scale: 1) { ctx in
        ctx.setFillColor(c(0.13, 0.14, 0.16))
        ctx.fill(CGRect(origin: .zero, size: area.size))
        ctx.setFillColor(c(0.2, 0.16, 0.12))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: HabitatLayout.ground))
        paintItems(h, area: area, scale: 1, ctx)
        overlay(h, map: m, area: area, ctx)
    }
    save(img!, out)
}

func worldShot2(_ h: Habitat, _ m: SurfaceMap, _ out: String, x: CGFloat, w: CGFloat) {
    let area = CGRect(x: x, y: 0, width: w, height: 300)
    let img = HabitatArt.image(area.size, scale: 3) { ctx in
        ctx.setFillColor(c(0.13, 0.14, 0.16))
        ctx.fill(CGRect(origin: .zero, size: area.size))
        paintItems(h, area: area, scale: 3, ctx)
        overlay(h, map: m, area: area, ctx)
    }
    save(img!, out)
}

// MARK: - Crawling on air

/// The pictures of everything it can climb, as a mask a pixel a point.
final class Mask {
    let w: Int, h: Int
    var alpha: [UInt8]
    init(_ hab: Habitat) {
        w = Int(world.width); h = Int(world.height)
        alpha = [UInt8](repeating: 0, count: w * h)
        let ctx = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
        // The ground, and what stands on it (not its shadow: shadows are
        // painted first and soft, and a foot on one is on the ground anyway).
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: world.width, height: HabitatLayout.ground))
        paintItems(hab, area: CGRect(origin: .zero, size: world), scale: 1, ctx, only: { $0.kind.climbable })
    }
    /// Whether anything painted is within `r` of `p`.
    func solid(near p: V2, within r: Int = 2) -> Bool {
        // (The glass at the ends and the lid are solid too.)
        let R = CGFloat(r)
        if p.x < R || p.x > world.width - R || p.y > world.height - R { return true }
        let x0 = Int(p.x.rounded()), y0 = Int(p.y.rounded())
        for dy in -r...r {
            for dx in -r...r where dx * dx + dy * dy <= r * r {
                let x = x0 + dx, y = y0 + dy
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                // (Row 0 of the bitmap is the top.)
                if alpha[(h - 1 - y) * w + x] > 90 { return true }
            }
        }
        return false
    }
    /// How far from `p` the nearest painted pixel is (up to `cap`).
    func gap(_ p: V2, cap: Int = 30) -> Int {
        for r in 3...cap where solid(near: p, within: r) { return r }
        return cap
    }
}

func screenFeet(_ p: SpiderPose) -> [V2] {
    let mirror: CGFloat = p.facing >= 0 ? 1 : -1
    let g = SpiderRenderer.ground
    return p.legs.map { leg in
        var q = leg.foot
        if p.spin != 0 { let cc = SpiderRenderer.ballCentre; q = cc + (q - cc).rotated(by: p.spin) }
        q = V2(q.x * p.stretch, g + (q.y - g) * p.fatten)
        return p.pos + V2(q.x * mirror, q.y).rotated(by: p.heading) * p.scale
    }
}

func air(_ presets: [Habitat.Preset]) {
    let secs = CGFloat(Double(env["PC_SECS"] ?? "120") ?? 120)
    let runs = Int(env["PC_RUNS"] ?? "2") ?? 2
    let scale = CGFloat(Double(env["PC_SCALE"] ?? "0.78") ?? 0.78)
    let desk = SurfaceMap()
    desk.standoff = 22 * scale
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    desk.debugRebuild(screen: screen, menuBarHeight: 25, windows: [])
    var totalPlanted = 0, totalOff = 0, totalFrames = 0
    print(String(format: "%-14@ %9@ %9@ %7@ %7@ %@", "tank", "planted", "on air", "share", "gap≥6", "worst stretches"))
    for p in presets {
        let hab = Habitat.preset(p, world: world)
        let mask = Mask(hab)
        var planted = 0, off = 0, far = 0, crossings = 0
        var loopsOff: [String: Int] = [:]
        for run in 0..<runs {
            reseed(UInt64(run + 1))
            let tank = surfaces(hab, standoff: 22 * scale)
            let s = Spider(map: desk)
            s.config.followCursor = false
            s.config.scale = scale
            for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
            s.enter(map: tank, at: V2(world.width / 2, HabitatLayout.ground + 200), habitat: true)
            var n = 0
            var was: String?
            while CGFloat(n) * dt < secs {
                s.setCursor(V2(-4000, -4000))
                s.update(dt: dt)
                n += 1
                totalFrames += 1
                let st = s.debugState
                // Walked from one surface straight onto another (not a leap).
                #if SHAPED
                let now = s.standingOn?.loopID
                #else
                let now: String? = nil
                #endif
                if let a = was, let b = now, a != b { crossings += 1 }
                was = now
                guard st.hasPrefix("attached"), !st.hasPrefix("attached:roll") else { continue }
                let pose = s.pose()
                guard pose.legs.count == 8 else { continue }
                let feet = screenFeet(pose)
                let flags = s.debugPlanted
                let on = st.components(separatedBy: " on ").last.map { String($0.split(separator: " ").first ?? "") } ?? "?"
                for i in 0..<8 where flags[i].planted && pose.legs[i].foot.y < SpiderRenderer.ground + 2.5 {
                    planted += 1
                    if !mask.solid(near: feet[i]) {
                        if let d = env["PC_DUMP"], d == on, off % 150 == 0 {
                            print(String(format: "  %@ body (%.0f,%.0f) foot %d (%.0f,%.0f) gap %d  %@", on, pose.pos.x, pose.pos.y, i, feet[i].x, feet[i].y, mask.gap(feet[i]), st))
                        }
                        off += 1
                        loopsOff[on, default: 0] += 1
                        if mask.gap(feet[i]) >= 6 { far += 1 }
                    }
                }
            }
        }
        totalPlanted += planted
        totalOff += off
        let worst = loopsOff.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        print(String(format: "%-14@ %9d %9d %6.2f%% %7d %@  (walked across %d)", p.rawValue, planted, off, planted > 0 ? Double(off) * 100 / Double(planted) : 0, far, worst, crossings))
    }
    print(String(format: "%-14@ %9d %9d %6.2f%%   (%d frames)", "all", totalPlanted, totalOff,
                 totalPlanted > 0 ? Double(totalOff) * 100 / Double(totalPlanted) : 0, totalFrames))
}

#if SHAPED
/// One thing on its own: its parts and the loops worked out round it.
func chains(_ kind: HabitatItemKind) {
    var h = Habitat(biome: .forest, world: CGSize(width: 600, height: 500))
    h.add(kind, at: CGPoint(x: 300, y: kind.hangs ? 500 : 0))
    h.items[0].flipped = false
    h.items[0].seed = 4242
    let it = h.items[0]
    for part in it.geometry.parts {
        print("part \(part.name) \(part.role) n=\(part.outline.count) area=\(Int(Poly.area(part.outline)))")
        print("   " + part.outline.map { String(format: "(%.1f,%.1f)", $0.x, $0.y) }.joined(separator: " "))
    }
    let m = surfaces(h, standoff: 22 * 0.78)
    for l in m.loops {
        print("loop \(l.id) closed=\(l.closed) segs=\(l.segs.count) len=\(Int(l.perimeter))")
        if l.id != "screen:0" { print("   " + l.segs.map { String(format: "(%.1f,%.1f)", $0.a.x, $0.a.y) }.joined(separator: " ")) }
    }
    for j in m.junctions { print("junction \(j.from)@\(j.fromVertex) -> \(j.to)@\(j.toVertex) at (\(Int(j.at.x)),\(Int(j.at.y)))") }
}
#endif

switch args.count > 1 ? args[1] : "" {
#if SHAPED
case "loops":
    let h = Habitat.preset(Habitat.Preset(rawValue: args.count > 2 ? args[2] : "desertScrub") ?? .desertScrub, world: world)
    let m = surfaces(h, standoff: 22 * 0.78)
    for l in m.loops {
        let b = l.segs.reduce(CGRect.null) { $0.union(CGRect(x: min($1.a.x, $1.b.x), y: min($1.a.y, $1.b.y), width: abs($1.a.x - $1.b.x), height: abs($1.a.y - $1.b.y))) }
        let owners = Set(l.owners).sorted().map { o in o == 0 ? "tank" : "\(o):\(h.item(id: o)?.kind.rawValue ?? "?")" }
        print(String(format: "%-12@ %@ segs %3d len %5.0f  x %4.0f…%4.0f y %4.0f…%4.0f  ", l.id, l.closed ? "closed" : "open  ", l.segs.count, l.perimeter, b.minX, b.maxX, b.minY, b.maxY)
              + (l.closed ? "" : String(format: "ends (%.0f,%.0f)→(%.0f,%.0f) ", l.segs.first!.a.x, l.segs.first!.a.y, l.segs.last!.b.x, l.segs.last!.b.y)) + owners.joined(separator: " "))
    }
case "near":
    // The things of a tank round `x`, alone in a tank of their own, traced.
    let h = Habitat.preset(Habitat.Preset(rawValue: args[2]) ?? .desertScrub, world: world)
    let x = CGFloat(Double(args[3]) ?? 0), r = CGFloat(Double(args.count > 4 ? args[4] : "150") ?? 150)
    var solo = Habitat(biome: h.biome, world: world)
    solo.items = h.items.filter { abs($0.x - x) < r + $0.w / 2 && $0.kind.climbable }
    for it in solo.items { print(String(format: "item %d %@ x %.1f y %.1f w %.1f h %.1f flip %@", it.id, it.kind.rawValue, it.x, it.y, it.w, it.h, it.flipped ? "y" : "n")) }
    let m = surfaces(solo, standoff: 22 * 0.78)
    for l in m.loops where l.id.hasPrefix("screen") || true {
        print("loop \(l.id) closed=\(l.closed) segs=\(l.segs.count) " + (l.closed ? "" : String(format: "ends (%.1f,%.1f)→(%.1f,%.1f)", l.segs.first!.a.x, l.segs.first!.a.y, l.segs.last!.b.x, l.segs.last!.b.y)))
    }
    worldShot2(solo, m, args.count > 5 ? args[5] : "near.png", x: x - r, w: r * 2)
case "stress":
    // Random tanks (and random things dropped anywhere in them): every one
    // should come out with one closed loop round the tank, runs that end
    // only on something, and quickly.
    let n = Int(args.count > 2 ? args[2] : "40") ?? 40
    var worst: Double = 0, total: Double = 0, bad = 0, deadEnds = 0
    for k in 0..<n {
        reseed(UInt64(1000 + k))
        var h = Habitat.surprise(world: world)
        if k % 2 == 1 {
            // A jumble: things put anywhere, overlapping, resized, flipped.
            for _ in 0..<25 {
                let kind = HabitatItemKind.allCases.filter(\.climbable).randomElement()!
                // (Hanging things from the lid, as the editor leaves them.)
                var it = h.add(kind, at: CGPoint(x: CGFloat.random(in: 0...world.width), y: kind.hangs ? world.height : (kind.liftable ? CGFloat.random(in: 0...600) : 0)),
                               scale: CGFloat.random(in: 0.4...2.6))
                it.flipped = seededBool()
                Habitat.clamp(&it, in: h.size)
                h.items[h.items.count - 1] = it
            }
        }
        let t0 = Date()
        let m = surfaces(h, standoff: 22 * 0.78)
        let dt = Date().timeIntervalSince(t0) * 1000
        total += dt
        worst = max(worst, dt)
        let rims = m.loops.filter { $0.id.hasPrefix("screen") }
        var ends = 0
        for l in m.loops where !l.closed {
            for v in [0, l.segs.count] where m.junctions(from: l.id, at: v).isEmpty {
                ends += 1
                let p = v == 0 ? l.segs[0].a : l.segs[l.segs.count - 1].b
                var near = CGFloat.greatestFiniteMagnitude
                for o in m.loops { for sg in o.segs where !(o.id == l.id) { near = min(near, projectOnSegment(p, sg.a, sg.b).dist) } }
                let kinds = Set(l.owners).sorted().compactMap { h.item(id: $0)?.kind.rawValue }.joined(separator: "+")
                print(String(format: "   tank \(k)\(k % 2 == 1 ? " (jumble)" : "") loose end: %@ (%@) %@ at (%.1f,%.1f), nearest other surface %.1f", l.id, kinds, v == 0 ? "start" : "end", p.x, p.y, near))
            }
        }
        deadEnds += ends
        // (Besides the tank's own, a rim loop is a room closed in under
        // something bulky bridging a gap — a plank from a log to a stone.)
        if m.loop("screen:0")?.closed != true || rims.contains(where: { !$0.closed })
            || rims.contains(where: { $0.id != "screen:0" && $0.perimeter > m.loop("screen:0")!.perimeter }) {
            bad += 1
            print("tank \(k): \(rims.count) rim loops, open \(rims.filter { !$0.closed }.count), \(h.items.count) things")
            for l in rims {
                let b = l.segs.reduce(CGRect.null) { $0.union(CGRect(x: min($1.a.x, $1.b.x), y: min($1.a.y, $1.b.y), width: abs($1.a.x - $1.b.x), height: abs($1.a.y - $1.b.y))) }
                print(String(format: "   %@ len %.0f area %.0f  x %.0f…%.0f y %.0f…%.0f  %@", l.id, l.perimeter, Poly.area(l.segs.map(\.a)), b.minX, b.maxX, b.minY, b.maxY,
                             Set(l.owners).sorted().map { o in o == 0 ? "tank" : "\(o):\(h.item(id: o)?.kind.rawValue ?? "?")" }.joined(separator: " ")))
            }
        }
    }
    print(String(format: "%d tanks: %d with a broken rim, %d loose ends, build %.1f ms mean, %.1f worst", n, bad, deadEnds, total / Double(n), worst))
case "rain":
    // The sim's weather check, told as it goes.
    let desk = SurfaceMap()
    desk.standoff = 22 * 0.95
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    var hab = Habitat()
    hab.items = Habitat.legacyItems(.forestFloor)
    let tank = surfaces(hab, standoff: desk.standoff)
    let x = CGFloat(Double(args.count > 2 ? args[2] : "120") ?? 120)
    let s = Spider(map: desk)
    s.config.followCursor = false
    for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
    s.enter(map: tank, at: V2(x, HabitatLayout.ground + 30), habitat: true)
    if let rim = tank.loop("screen:0"),
       let i = rim.segs.indices.filter({ rim.segs[$0].facing == .up && min(rim.segs[$0].a.x, rim.segs[$0].b.x) < x
                                        && max(rim.segs[$0].a.x, rim.segs[$0].b.x) > x }).min(by: { rim.segs[$0].a.y < rim.segs[$1].a.y }) {
        let seg = rim.segs[i]
        print("attach seg \(i) (\(seg.a.x),\(seg.a.y))→(\(seg.b.x),\(seg.b.y))")
        s.debugAttach(loopID: "screen:0", segIdx: i, t: abs(x - seg.a.x), dir: 1)
    }
    let p0 = V2(x, 312)
    for l in tank.loops {
        for sg in (l.edge.isEmpty ? l.segs : l.edge) where sg.facing == .down {
            let lo = min(sg.a.x, sg.b.x), hi = max(sg.a.x, sg.b.x)
            guard p0.x > lo + 3, p0.x < hi - 3 else { continue }
            let y = abs(sg.b.x - sg.a.x) > 0.01 ? sg.a.y + (sg.b.y - sg.a.y) * (p0.x - sg.a.x) / (sg.b.x - sg.a.x) : max(sg.a.y, sg.b.y)
            guard y > p0.y + 4, y - p0.y < 320 * 0.95 else { continue }
            print("roof? \(l.id) \(l.kind) (\(sg.a.x),\(sg.a.y))→(\(sg.b.x),\(sg.b.y)) at y \(y)")
        }
    }
    var storm = WeatherFeel()
    storm.rain = 1; storm.wind = 0.7; storm.gust = 0.9; storm.storm = 1; storm.cold = 0.2
    for n in 0..<(60 * 12) {
        s.setCursor(V2(-4000, -4000)); s.weather = storm; s.update(dt: dt)
        if n % 60 == 0 { print(String(format: "%4.1fs (%.0f,%.0f) %@ %@ sheltered %@", Double(n) / 60, s.worldPos.x, s.worldPos.y, s.debugState, s.debugWeather, s.sheltered ? "y" : "n")) }
    }
case "persist":
    // A habitat saved before things had lasting identities loads, is given
    // them once, and keeps them from then on.
    var h = Habitat.preset(.forestFloor, world: world)
    let data = try! JSONEncoder().encode(h)
    var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    json["items"] = (json["items"] as! [[String: Any]]).map { var d = $0; d["uid"] = nil; return d }
    let old = try! JSONSerialization.data(withJSONObject: json)
    var back = try! JSONDecoder().decode(Habitat.self, from: old)
    let before = back.items.map(\.uid)
    let gave = back.giveIdentities()
    let uids = back.items.map(\.uid)
    let again = try! JSONDecoder().decode(Habitat.self, from: try! JSONEncoder().encode(back))
    print("old save decodes:", back.items.count == h.items.count, " had none:", before.allSatisfy(\.isEmpty), " given:", gave,
          " unique:", Set(uids).count == uids.count && !uids.contains(""), " kept through save/load:", again.items.map(\.uid) == uids,
          " second pass changes nothing:", !back.giveIdentities())
    // Moving, resizing and flipping keep it; a copy gets its own.
    h.items[0].x += 40; h.items[0].w *= 1.3; h.items[0].flipped.toggle()
    print("same thing by uid after edits:", h.item(uid: h.items[0].uid)?.id == h.items[0].id)
    // Its surfaces know it by its number, whose uid is its lasting identity.
    let m = surfaces(h, standoff: 17)
    let owned = Set(m.loops.flatMap(\.owners)).filter { $0 != 0 }
    print("every surface's owner is a thing in it:", owned.allSatisfy { h.item(id: $0) != nil }, "(\(owned.count) things own surfaces)")
case "one":
    // One kind alone (and the ground): its loops and junctions.
    var h = Habitat(biome: .forest, world: CGSize(width: 600, height: 500))
    let kind = HabitatItemKind(rawValue: args[2]) ?? .ladder
    let given = args.count > 3 ? CGFloat(Double(args[3]) ?? 0) : nil
    h.add(kind, at: CGPoint(x: 300, y: given ?? (kind.hangs ? 500 : 0)))
    print("item rect \(h.items[0].rect)")
    let m = surfaces(h, standoff: 22 * 0.78)
    for l in m.loops { print("loop \(l.id) closed=\(l.closed) segs=\(l.segs.count) len=\(Int(l.perimeter)) owners=\(Set(l.owners).sorted())") }
    var pairs: [String: Int] = [:]
    for j in m.junctions { pairs["\(j.from)->\(j.to)", default: 0] += 1 }
    print(pairs)
case "pieces":
    piecesSheet(args.count > 2 ? args[2] : "perch_pieces.png")
case "build":
    buildCheck(args.count > 2 ? args[2] : nil)
case "nature":
    natureCheck()
case "curious":
    curiousCheck()
case "chains":
    chains(HabitatItemKind(rawValue: args.count > 2 ? args[2] : "driftwood") ?? .driftwood)
#endif
case "sheet":
    sheet(args.count > 2 ? args[2] : "perch_sheet.png")
case "world":
    let p = Habitat.Preset(rawValue: args.count > 2 ? args[2] : "forestFloor") ?? .forestFloor
    worldShot(p, args.count > 3 ? args[3] : "perch_world.png",
              x: args.count > 4 ? CGFloat(Double(args[4]) ?? 0) : nil, w: args.count > 5 ? CGFloat(Double(args[5]) ?? 1600) : nil)
case "air":
    let names = Array(args.dropFirst(2))
    air(names.isEmpty ? Habitat.Preset.allCases.filter { $0 != .empty } : names.compactMap { Habitat.Preset(rawValue: $0) })
default:
    print("perch sheet out.png | world <preset> out.png [x w] | air [preset…]")
}
