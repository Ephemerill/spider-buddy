import AppKit

// Nature check (tools/perch.sh nature): the natural world's things, each
// checked the way the spider meets it.
//
//   • reach: every surface it owns can be walked to from the tank's floor
//     (a limb or a room sealed off from the rest is a place it could only
//     leap into, and might be stuck in);
//   • shelters: a spot on the floor inside, that it can walk to, with a
//     roof over it close enough to keep the weather off, and room for the
//     spider's body under it — at the size most keep it, and a bigger one;
//   • the spider: let loose beside it, does it get onto it (and into a
//     shelter)?
//   • supports: hanging things hang from a branch, pots and platforms sit
//     on brackets, branches lie in a fork — snapped as the editor snaps;
//     nothing left floating; every kind survives saving and loading.
//
// PC_ONLY=kind,kind  PC_ALL (every kind, not only the new)  PC_SECS (200 a run)
// PC_RUNS (2)  PC_QUICK (no spider)  PC_JITTER (40 positions)  PC_ROOF (what is
// over each refuge)  PC_EVERY=from-count / old / new (the side-by-side tank)
// PC_KEEP=id,id (only those of it)  PC_PROBE[=split] (the tracer's open runs)

#if SHAPED
/// The kinds this phase added (from the twisted branch on), and the hollow log from before.
let natureKinds: [HabitatItemKind] = {
    let all = env["PC_ALL"] != nil ? HabitatItemKind.allCases : Array(HabitatItemKind.allCases.dropFirst(HabitatItemKind.allCases.firstIndex(of: .twistedBranch)!))
    guard let only = env["PC_ONLY"] else { return all }
    let names = Set(only.split(separator: ",").map(String.init))
    return all.filter { names.contains($0.rawValue) }
}()

/// A small tank with one thing in it, as it comes, flipped or not.
func soloTank(_ kind: HabitatItemKind, flipped: Bool = false, scale: CGFloat = 1) -> Habitat {
    var h = Habitat(biome: .forest, world: CGSize(width: 900, height: 560))
    var it = h.add(kind, at: CGPoint(x: 450, y: kind.hangs ? h.size.height : (kind.definition.placement == .wedged ? 140 : 0)), scale: scale)
    it.flipped = flipped
    it.seed = 4242
    // (Hung things hang low enough to reach down to.)
    if kind.hangs { it.y = h.size.height; it.h = min(it.h, h.size.height - HabitatLayout.ground - 60) }
    Habitat.clamp(&it, in: h.size)
    h.items[0] = it
    // What grows out of the side of wood, on the side of a stump; wedged
    // things up in the air held up as the editor would hold them.
    if kind.definition.traits.niche.side {
        var host = h.add(.stump, at: CGPoint(x: 360, y: 0), scale: 1.4)
        host.seed = 7
        h.items[1] = host
        h.items.swapAt(0, 1)
        var f = h.items[1]
        f.x = host.rect.maxX - host.w * 0.16 + f.w * 0.5 - 4
        f.y = host.h * 0.45
        h.items[1] = f
    } else if kind.definition.placement == .wedged, kind.definition.mount != .wall {
        h.addSupport(for: it.id)
    }
    return h
}

/// Whether anything's underside is over `p`, near enough to keep the
/// weather off (as the spider's own `roofOver` has it), and how high.
func roof(over p: V2, _ m: SurfaceMap, scale: CGFloat) -> CGFloat? {
    var best: CGFloat?
    for l in m.loops {
        let segs = l.edge.isEmpty ? l.segs : l.edge
        let lid = segs.reduce(-CGFloat.greatestFiniteMagnitude) { max($0, $1.a.y, $1.b.y) } - 2
        for s in segs where s.facing == .down {
            let lo = min(s.a.x, s.b.x), hi = max(s.a.x, s.b.x)
            guard p.x >= lo, p.x < hi else { continue }
            let y = abs(s.b.x - s.a.x) > 0.01 ? s.a.y + (s.b.y - s.a.y) * (p.x - s.a.x) / (s.b.x - s.a.x) : max(s.a.y, s.b.y)
            guard y > p.y + 4, y - p.y < 320 * scale else { continue }
            // (The lid is no roof, but right under it.)
            if l.kind == .screenBorder, min(s.a.y, s.b.y) >= lid, y - p.y > 60 * scale { continue }
            if best.map({ y < $0 }) ?? true { best = y }
        }
    }
    return best
}

/// The floor under `p`: the body line of the up-facing surface nearest above
/// the point just under it, and its loop.
func floor(at p: V2, _ m: SurfaceMap, within: CGFloat) -> (y: CGFloat, loop: String)? {
    var best: (y: CGFloat, loop: String)?
    for l in m.loops {
        for s in l.segs where s.facing == .up {
            let lo = min(s.a.x, s.b.x), hi = max(s.a.x, s.b.x)
            guard p.x >= lo, p.x <= hi, abs(s.b.x - s.a.x) > 0.01 else { continue }
            let y = s.a.y + (s.b.y - s.a.y) * (p.x - s.a.x) / (s.b.x - s.a.x)
            guard y > p.y - 2, y < p.y + within else { continue }
            if best.map({ y < $0.y }) ?? true { best = (y, l.id) }
        }
    }
    return best
}

func natureCheck() {
    var b = Builder()
    let G = HabitatLayout.ground

    print("== reach: every surface of it can be walked to from the floor")
    for kind in natureKinds where kind.climbable {
        for flip in [false, true] {
            let h = soloTank(kind, flipped: flip)
            let m = surfaces(h, standoff: 22 * 0.78)
            let r = reachable(m)
            let id = h.items.first { $0.kind == kind }!.id
            // (And the tank's own surface still whole round it.)
            let rims = m.loops.filter { $0.id.hasPrefix("screen") && !$0.closed }
            if !rims.isEmpty { b.check("\(kind.label)\(flip ? " (flipped)" : ""): the floor runs whole round it", false, rims.map(\.id).joined(separator: " ")) }
            let cut = m.loops.filter { $0.owners.contains(id) && !r.contains($0.id) && $0.perimeter > 60 }
            if !cut.isEmpty || !flip {
                b.check("\(kind.label)\(flip ? " (flipped)" : "")", cut.isEmpty,
                        cut.isEmpty ? "" : "cut off: " + cut.map { String(format: "%@ (%.0f round)", $0.id, $0.perimeter) }.joined(separator: ", "))
            }
        }
    }

    print("== robust: the floor stays whole round it wherever it is put, to a fraction of a point")
    for kind in natureKinds where kind.climbable {
        var broken: [String] = []
        for i in 0..<(Int(env["PC_JITTER"] ?? "40") ?? 40) {
            var h = soloTank(kind, flipped: i % 2 == 1)
            let dx = CGFloat(i) * 0.37 + CGFloat(i % 7) * 11.3
            h.shift(h.items.map(\.id), by: V2(dx, 0))
            let m = surfaces(h, standoff: 22 * 0.78)
            if m.loops.contains(where: { $0.id.hasPrefix("screen") && !$0.closed }) { broken.append(String(format: "+%.2f%@", dx, i % 2 == 1 ? "f" : "")) }
        }
        if !broken.isEmpty { b.check("\(kind.label)", false, "rim broken at " + broken.prefix(6).joined(separator: " ") + (broken.count > 6 ? " … (\(broken.count))" : "")) }
    }

    print("== shelters: a floor inside it can reach, roofed, with room for it")
    let shelters = natureKinds.filter { $0.functions.contains(.retreat) || $0.definition.shelf == .shelter }
    for kind in shelters {
        for (scale, label) in [(CGFloat(0.78), "usual size"), (CGFloat(1.1), "a big spider")] {
            let h = soloTank(kind, flipped: false)
            let g = 22 * scale
            let m = surfaces(h, standoff: g)
            let r = reachable(m)
            let it = h.items.first { $0.kind == kind }!
            let refuges = it.geometry.anchors.filter { $0.kind == .refuge }
            guard !refuges.isEmpty else { b.check("\(kind.label): has a refuge spot", false); continue }
            var detail: [String] = []
            var ok = true
            for a in refuges {
                guard let f = floor(at: a.point, m, within: g * 2) else { ok = false; detail.append(String(format: "no floor at %.0f", a.point.x)); continue }
                let reach = r.contains(f.loop)
                let over = roof(over: V2(a.point.x, f.y), m, scale: scale)
                if env["PC_ROOF"] != nil {
                    print(String(format: "     at (%.0f, %.0f):", a.point.x, f.y))
                    for l in m.loops {
                        for s in (l.edge.isEmpty ? l.segs : l.edge) where min(s.a.x, s.b.x) <= a.point.x && max(s.a.x, s.b.x) >= a.point.x && max(s.a.y, s.b.y) > f.y {
                            print(String(format: "       %@ %@ (%.0f,%.0f)->(%.0f,%.0f) %@", l.id, "\(l.kind)", s.a.x, s.a.y, s.b.x, s.b.y, "\(s.facing)"))
                        }
                    }
                }
                ok = ok && reach && over != nil
                detail.append(String(format: "floor %@%@, roof %@", f.loop, reach ? "" : " (CUT OFF)", over.map { String(format: "%.0f above", $0 - f.y) } ?? "NONE"))
            }
            b.check("\(kind.label), \(label)", ok, detail.joined(separator: "; "))
        }
    }

    print("== the ready-made tanks: every shelter in them can be got into, and is roofed")
    for p in Habitat.Preset.allCases where p != .empty {
        let h = Habitat.preset(p, world: world)
        let m = surfaces(h, standoff: 22 * 0.78)
        let r = reachable(m)
        var bad: [String] = [], n = 0
        for it in h.items where it.kind.climbable {
            for a in it.geometry.anchors where a.kind == .refuge {
                n += 1
                // (Something may lie on the floor under it — moss, a shell: the first surface up.)
                guard let f = floor(at: a.point, m, within: 90) else { bad.append("\(it.kind.rawValue)#\(it.id): no floor"); continue }
                if !r.contains(f.loop) { bad.append("\(it.kind.rawValue)#\(it.id): cut off") }
                else if roof(over: V2(a.point.x, f.y), m, scale: 0.78) == nil { bad.append("\(it.kind.rawValue)#\(it.id): no roof") }
            }
        }
        b.check("\(p.rawValue): \(n) refuges", bad.isEmpty, bad.joined(separator: ", "))
    }

    print("== supports: fastened as the editor fastens, and held up")
    do {
        var t = Builder()
        // A branch on the back wall to hang things from.
        let branch = t.drop(.longBranch, x: 700, y: 520, scale: 1.2, expectSnap: false)
        t.h.addSupport(for: branch)
        let along = t.h.item(id: branch)!.port("along0")!
        for (i, kind) in [HabitatItemKind.hangingBranch, .hangingRoots, .hangingFoliage, .hangingLeafShelter].enumerated() {
            let at = along.point(at: 0.2 + CGFloat(i) * 0.2)
            _ = t.drop(kind, x: at.x + 6, y: at.y - 5, tall: 0.8, "from the branch")
        }
        // A pot and a platform onto a plank on two posts.
        let p1 = t.drop(.post, x: 1500, y: 0, expectSnap: false)
        _ = t.drop(.post, x: 1720, y: 0, expectSnap: false)
        let top = t.h.item(id: p1)!.port("top")!.pts[0]
        let plank = t.drop(.plank, x: 1610 + 5, y: top.y - G + 6, scale: 1.2)
        t.h.linkWhatTouches(plank, within: 3)
        let pl = t.h.item(id: plank)!.port("along0")!
        let potAt = pl.point(at: 0.3)
        _ = t.drop(.trailingPlant, x: potAt.x - 130 * 0.22 + 4, y: potAt.y - G + 5 - 170 * 0.72 + pl.halfWidth(at: 0.3), "on the plank")
        // A branch laid in a three-pronged fork.
        let fork = t.drop(.threeFork, x: 2400, y: 0, scale: 1.3, expectSnap: false)
        let crotch = t.h.item(id: fork)!.port("crotchL")!.pts[0]
        _ = t.drop(.mediumBranch, x: crotch.x + 8, y: crotch.y - G - 40 + 10, "in the fork")
        // Floating things given supports.
        let floaters = [t.drop(.stickRaft, x: 3000, y: 380, expectSnap: false), t.drop(.mossPlatform, x: 3300, y: 300, expectSnap: false),
                        t.drop(.twistedBranch, x: 3600, y: 420, expectSnap: false), t.drop(.lianaLoop, x: 2900, y: 700, expectSnap: false)]
        for id in floaters { t.h.addSupport(for: id) }
        let sup = t.h.supports()
        let floating = t.h.items.filter { sup[$0.id]?.holds != true }
        t.check("nothing floating", floating.isEmpty, floating.map { $0.kind.rawValue }.joined(separator: " "))
        let m = surfaces(t.h, standoff: 22 * 0.78)
        for l in t.h.links {
            guard let c = t.h.item(uid: l.child), let p = t.h.item(uid: l.parent), c.kind.climbable, p.kind.climbable else { continue }
            t.check("\(c.kind.label) walks onto \(p.kind.label)", t.connected(c.id, p.id, m))
        }
        b.fails += t.fails
    }

    print("== saved and loaded: every kind")
    // (Side by side, each on its own: a jumble of them is the stress test's.)
    let split = HabitatItemKind.allCases.firstIndex(of: .twistedBranch)!
    let everyKinds = env["PC_EVERY"] == "old" ? Array(HabitatItemKind.allCases.prefix(split)) : env["PC_EVERY"] == "new" ? Array(HabitatItemKind.allCases.dropFirst(split))
        : env["PC_EVERY"].map { e in Array(HabitatItemKind.allCases.dropFirst(Int(e.split(separator: "-")[0])!).prefix(Int(e.split(separator: "-")[1])!)) } ?? HabitatItemKind.allCases
    let span = everyKinds.reduce(CGFloat(100)) { $0 + $1.defaultSize.width + 40 }
    var every = Habitat(biome: .forest, world: CGSize(width: span, height: world.height))
    var x: CGFloat = 60
    for kind in everyKinds {
        var it = every.add(kind, at: CGPoint(x: x + kind.defaultSize.width / 2, y: kind.hangs ? world.height : 0))
        it.x = x + kind.defaultSize.width / 2
        every.items[every.items.count - 1] = it
        x += kind.defaultSize.width + 40
    }
    // (PC_KEEP=id,id…: only those, where they were — to find what breaks it.)
    if let keep = env["PC_KEEP"] {
        let ids = Set(keep.split(separator: ",").compactMap { Int($0) })
        every.items = every.items.filter { ids.contains($0.id) }
    }
    if env["PC_PROBE"] != nil {
        // The body trace, its open runs laid bare.
        let off = 22 * 0.78 as CGFloat
        let groundY = HabitatLayout.ground
        let air = CGRect(x: 0, y: groundY, width: every.size.width, height: every.size.height - groundY)
        var parts: [SurfaceTrace.Part] = []
        for (i, it) in every.items.enumerated() where it.kind.climbable {
            for part in it.geometry.parts where part.outline.count >= 3 {
                parts.append(SurfaceTrace.Part(outline: part.outline, role: part.role, group: it.id, owner: it.id, depth: every.items.count - i, rect: it.rect))
            }
        }
        parts.append(SurfaceTrace.Part(outline: [V2(air.minX, air.minY), V2(air.maxX, air.minY), V2(air.maxX, air.maxY), V2(air.minX, air.maxY)],
                                       role: .bulk, group: 0, owner: 0, depth: 1_000_000, rect: air, rim: true))
        let inner = air.insetBy(dx: off + 0.013, dy: off + 0.013)
        let n = env["PC_PROBE"] == "split" ? Int(inner.width / 250) : 1
        let floorPts = (0...n).map { V2(inner.minX + inner.width * CGFloat($0) / CGFloat(n), inner.minY) }
        let paths = parts.indices.map { $0 == parts.count - 1 ? floorPts + [V2(inner.maxX, inner.maxY), V2(inner.minX, inner.maxY)]
                                                             : Poly.grown(parts[$0].outline, by: off) }
        let t = SurfaceTrace.trace(parts: parts, paths: paths, grow: off, free: air.insetBy(dx: off, dy: off))
        for ch in t.chains where !ch.closed {
            print(String(format: "   open run: (%.2f,%.2f) → (%.2f,%.2f), %d points, parts %@", ch.pts[0].x, ch.pts[0].y, ch.pts.last!.x, ch.pts.last!.y, ch.pts.count,
                         Set(ch.parts).sorted().map(String.init).joined(separator: ",")))
        }
        print("   \(t.chains.count) runs, \(t.chains.filter(\.closed).count) closed")
        for it in every.items { print(String(format: "   #%d %@ rect x %.1f…%.1f y %.1f…%.1f", it.id, it.kind.rawValue, it.rect.minX, it.rect.maxX, it.rect.minY, it.rect.maxY)) }
    }
    let back = try? JSONDecoder().decode(Habitat.self, from: JSONEncoder().encode(every))
    b.check("all \(HabitatItemKind.allCases.count) kinds come back as they went", back?.items == every.items)
    let t0 = Date()
    let mAll = surfaces(every, standoff: 22 * 0.78)
    let rims = mAll.loops.filter { $0.id.hasPrefix("screen") }
    b.check("…and a tank of every one of them lays its surfaces out", mAll.loop("screen:0")?.closed == true,
            String(format: "%.0f ms, %d loops; rims: ", Date().timeIntervalSince(t0) * 1000, mAll.loops.count)
            + rims.map { String(format: "%@ %@ %.0f", $0.id, $0.closed ? "closed" : "OPEN", $0.perimeter) }.joined(separator: ", "))
    for l in rims where !l.closed {
        for p in [l.segs.first!.a, l.segs.last!.b] {
            let near = every.items.filter { $0.rect.insetBy(dx: -60, dy: -60).contains(p.point) }.map { "\($0.kind.rawValue)#\($0.id)" }
            print(String(format: "     %@ end at (%.1f, %.1f) by %@", l.id, p.x, p.y, near.joined(separator: " ")))
        }
    }

    if env["PC_QUICK"] == nil {
        print("== the spider: let loose beside each, does it get onto it (and into shelters)?")
        let scale: CGFloat = 0.78
        let desk = SurfaceMap()
        desk.standoff = 22 * scale
        desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
        let secs = CGFloat(Double(env["PC_SECS"] ?? "200") ?? 200)
        let runs = Int(env["PC_RUNS"] ?? "2") ?? 2
        for kind in natureKinds where kind.climbable {
            let h = soloTank(kind)
            let it = h.items.first { $0.kind == kind }!
            let cavity = it.geometry.hollows.first?.cavity
            var on = 0, inside = 0
            for run in 0..<runs {
                reseed(UInt64(900 + run))
                let tank = surfaces(h, standoff: 22 * scale)
                let s = Spider(map: desk)
                s.config.followCursor = false
                s.config.scale = scale
                for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
                s.enter(map: tank, at: V2(run == 0 ? it.rect.minX - 60 : it.rect.maxX + 60, G + 30), habitat: true)
                for _ in 0..<Int(secs / dt) {
                    s.setCursor(V2(-4000, -4000))
                    s.update(dt: dt)
                    guard let a = s.standingOn else { continue }
                    if tank.owner(of: a) == it.id { on += 1 }
                    if let cavity, Poly.contains(Poly.grown(cavity, by: 4), s.worldPos) { inside += 1 }
                }
            }
            let shelter = cavity != nil
            let detail = "on it \(on) frames" + (shelter ? ", inside \(inside)" : "")
            // (What hangs from the lid is got to from above — down a line,
            // along the lid — not come across in passing: told, not checked.
            // That it can be walked onto at all is the reach check's.)
            if kind.hangs { print("  [info] \(kind.label) \(detail)"); continue }
            b.check("\(kind.label)", on > 20 && (!shelter || inside > 20), detail)
        }
    }
    print(b.fails == 0 ? "all ok" : "\(b.fails) FAILED")
}
#endif
