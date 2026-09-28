import AppKit

// Structures check (tools/perch.sh pieces / build): the pieces structures are
// built from, and structures built from them the way the tank's editor
// builds them — each piece dropped a little off where it would fasten, and
// pulled into place by the same snapping — then checked: does everything
// look held up, do fastened pieces' surfaces meet, does it all survive
// saving, resizing and flipping, and does the spider get about on it?

#if SHAPED
/// Every new piece, with its shape, surfaces and ports over its picture.
func piecesSheet(_ out: String) {
    let shelf = env["PC_SHELF"]
    let kinds = HabitatItemKind.allCases.filter { $0.definition.shelf != .plants && $0.definition.shelf != .furniture
        && (shelf == nil || $0.definition.shelf.rawValue == shelf) }
    let zoom = CGFloat(Double(env["PC_ZOOM"] ?? "1") ?? 1)
    let cellW: CGFloat = 330 / zoom, cellH: CGFloat = 380 / zoom, cols = 6
    let rows = Int(ceil(Double(kinds.count) / Double(cols)))
    let W = cellW * CGFloat(cols), H = cellH * CGFloat(rows)
    let img = HabitatArt.image(CGSize(width: W, height: H), scale: 1.5 * zoom) { ctx in
        ctx.setFillColor(c(0.13, 0.14, 0.16))
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (i, kind) in kinds.enumerated() {
            let cell = CGRect(x: CGFloat(i % cols) * cellW, y: H - CGFloat(i / cols + 1) * cellH, width: cellW, height: cellH)
            var h = Habitat(biome: .forest, world: CGSize(width: cellW, height: cellH - 20))
            var it = h.add(kind, at: CGPoint(x: cellW / 2, y: kind.hangs ? h.size.height : 0))
            it.seed = 4242
            it.flipped = false
            if zoom > 1 { it.w = min(it.w, cellW * 0.8); it.h = min(it.h, cellH * 0.7) }
            if kind.definition.placement == .wedged, !kind.atBack || kind.definition.mount == .wall { it.y = 40 }
            Habitat.clamp(&it, in: h.size)
            h.items[0] = it
            let m = surfaces(h, standoff: 22 * 0.78)
            ctx.saveGState()
            ctx.translateBy(x: cell.minX, y: cell.minY)
            ctx.clip(to: CGRect(x: 0, y: 0, width: cellW, height: cellH))
            ctx.setFillColor(c(0.2, 0.16, 0.12))
            ctx.fill(CGRect(x: 0, y: 0, width: cellW, height: HabitatLayout.ground))
            paintItems(h, area: h.bounds, scale: 1.5 * zoom, ctx)
            if env["PC_CLEAN"] == nil {
                overlay(h, map: m, area: h.bounds, ctx)
                portsOverlay(h, area: h.bounds, ctx)
            }
            label(ctx, "\(kind.label) [\(kind.definition.shelf.rawValue)]\(kind.climbable ? "" : " (not walked on)")", at: CGPoint(x: 6, y: cellH - 16))
            ctx.restoreGState()
            ctx.setStrokeColor(c(0.4, 0.4, 0.45))
            ctx.stroke(cell)
        }
    }
    save(img!, out)
}

/// Ports: cyan lines along, dots at ends/feet (orange), cradles and sockets
/// (green), hooks and hanging tops (magenta), bases (yellow); links white.
func portsOverlay(_ h: Habitat, area: CGRect, _ ctx: CGContext) {
    func pt(_ v: V2) -> CGPoint { CGPoint(x: v.x - area.minX, y: v.y - area.minY) }
    for it in h.items {
        for p in it.ports {
            if p.isLine {
                ctx.setStrokeColor(c(0.2, 0.9, 1, 0.5))
                ctx.setLineWidth(1)
                ctx.move(to: pt(p.pts[0]))
                for q in p.pts.dropFirst() { ctx.addLine(to: pt(q)) }
                ctx.strokePath()
                continue
            }
            let col: CGColor
            switch p.kind {
            case .end, .foot: col = c(1, 0.55, 0.1)
            case .cradle, .socket: col = c(0.3, 1, 0.3)
            case .hang, .hook: col = c(1, 0.3, 1)
            default: col = c(1, 1, 0.2)
            }
            ctx.setFillColor(col)
            let q = pt(p.pts[0])
            ctx.fillEllipse(in: CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6))
        }
    }
    for l in h.links {
        guard let j = h.joint(l) else { continue }
        ctx.setStrokeColor(c(1, 1, 1))
        ctx.setLineWidth(1.5)
        let q = pt(j.seat)
        ctx.strokeEllipse(in: CGRect(x: q.x - 6, y: q.y - 6, width: 12, height: 12))
    }
}

// MARK: - Building

/// A tank to build in, and a tally of checks.
struct Builder {
    var h = Habitat(biome: .forest, world: world)
    var fails = 0

    mutating func check(_ label: String, _ ok: Bool, _ detail: String = "") {
        print("  [\(ok ? "ok  " : "FAIL")] \(label) \(detail)")
        if !ok { fails += 1 }
    }

    /// Puts a thing in at `at` (its centre across; standing: base above
    /// the ground; hanging: its top), as the editor does, then — as if it
    /// had been dragged there, `off` short of where it fastens — snaps it
    /// into place. Returns its number.
    @discardableResult
    mutating func drop(_ kind: HabitatItemKind, x: CGFloat, y: CGFloat, scale: CGFloat = 1, tall: CGFloat? = nil, width: CGFloat? = nil,
                       flipped: Bool = false, expectSnap: Bool = true, _ label: String = "") -> Int {
        var it = h.add(kind, at: CGPoint(x: x, y: y), scale: scale)
        if let tall { it.h *= tall }
        if let width { it.w = width }
        it.flipped = flipped
        it.seed = 1000 + it.id * 37
        it.x = x
        it.y = y
        Habitat.clamp(&it, in: h.size)
        h.items[h.items.count - 1] = it
        let s = h.snap(for: it, excluding: Set([it.id] + h.dependents(of: it.id)), radius: Habitat.snapRadius)
        if expectSnap {
            check("\(kind.label)\(label.isEmpty ? "" : " " + label) snaps into place", s != nil,
                  s.map { String(format: "%@.%@ -> %@.%@, moved %.1f", kind.rawValue, $0.link.childPort,
                                 h.item(uid: $0.link.parent)!.kind.rawValue, $0.link.parentPort, $0.delta.length) } ?? "(nothing near)")
        }
        if let s {
            h.shift([it.id], by: s.delta)
            h.attach(s.link)
        }
        return it.id
    }

    /// Whether two things' surfaces meet: one loop both own, or a junction
    /// between a loop of each (near `near`, if given).
    func connected(_ a: Int, _ b: Int, _ m: SurfaceMap) -> Bool {
        let la = m.loops.filter { $0.owners.contains(a) }, lb = m.loops.filter { $0.owners.contains(b) }
        if la.contains(where: { l in lb.contains { $0.id == l.id } }) { return true }
        let ids = Set(lb.map(\.id))
        return m.junctions.contains { j in la.contains { $0.id == j.from } && ids.contains(j.to) }
    }
}

func buildCheck(_ outPrefix: String?) {
    var b = Builder()
    let G = HabitatLayout.ground
    print("== A: back wall -> brace -> branch -> hanging vine -> lower branch")
    let brace = b.drop(.brace, x: 700, y: 420, tall: 1.2, expectSnap: false)
    let cup = b.h.item(id: brace)!.port("cup")!.pts[0]
    // A branch whose middle is dragged to 9 points off the brace's cup.
    let branch = b.drop(.mediumBranch, x: cup.x + 10, y: cup.y - G - 40 + 9)
    let along = b.h.item(id: branch)!.port("along0")!
    let hangAt = along.point(at: 0.93)
    let vine = b.drop(.thinVine, x: hangAt.x + 7, y: hangAt.y - 6, tall: 1.2)
    let tip = b.h.item(id: vine)!.port("b0")!.pts[0]
    // A lower branch whose length passes 9 points under the vine's tip.
    var lower = b.drop(.shortBranch, x: tip.x + 30, y: 300, scale: 1.3, expectSnap: false)
    do {
        let lp = b.h.item(id: lower)!.port("along0")!
        b.h.shift([lower], by: tip - lp.point(at: 0.35) + V2(0, -9))
        let it = b.h.item(id: lower)!
        b.h.items.removeAll { $0.id == lower }
        lower = b.drop(.shortBranch, x: it.x, y: it.y, scale: 1.3, "under the vine")
    }
    let aIDs = [brace, branch, vine, lower]

    print("== B: two uprights -> plank -> fern and moss on it")
    let p1 = b.drop(.verticalSupport, x: 1500, y: 0, expectSnap: false)
    _ = b.drop(.verticalSupport, x: 1680, y: 0, expectSnap: false)
    let top1 = b.h.item(id: p1)!.port("top")!.pts[0]
    let plank = b.drop(.plank, x: 1590 + 6, y: top1.y - G + 7, scale: 1.1)
    // Plants put on top of it come to rest on it (the editor settles them).
    for (k, kind) in [HabitatItemKind.fern, .moss].enumerated() {
        let x: CGFloat = 1560 + CGFloat(k) * 70
        var it = b.h.add(kind, at: CGPoint(x: x, y: 0))
        let pl = b.h.item(id: plank)!
        it.y = (Habitat.restingTop(pl, from: x - it.w / 4, to: x + it.w / 4) ?? G) - G
        b.h.items[b.h.items.count - 1] = it
    }
    let second = b.h.links.filter { $0.child == b.h.item(id: plank)!.uid }.count
    b.h.linkWhatTouches(plank, within: 3)
    b.check("the plank sits on both uprights", b.h.links.filter { $0.child == b.h.item(id: plank)!.uid }.count >= 2,
            "\(second) -> \(b.h.links.filter { $0.child == b.h.item(id: plank)!.uid }.count) links")

    print("== C: built — 2×4 across two posts, a ladder up to it, a rope from it, a crate")
    let post1 = b.drop(.post, x: 2400, y: 0, tall: 1.3, expectSnap: false)
    let post2 = b.drop(.post, x: 2640, y: 0, tall: 1.3, expectSnap: false)
    let ptop = b.h.item(id: post1)!.port("top")!.pts[0]
    let beam = b.drop(.beam, x: 2520 - 5, y: ptop.y - G + 12, scale: 1.3)
    b.h.linkWhatTouches(beam, within: 3)
    let bl = b.h.item(id: beam)!.port("along0")!
    let ropeAt = bl.point(at: 0.7)
    let rope = b.drop(.rope, x: ropeAt.x + 5, y: ropeAt.y + 4, tall: 0.9)
    let ladder = b.drop(.ladder, x: 2330, y: 0, tall: (ptop.y - G + 10) / 180, expectSnap: false)
    let crate = b.drop(.crate, x: 2880, y: 0, expectSnap: false)
    _ = b.drop(.woodBlock, x: 2880, y: b.h.item(id: crate)!.h, expectSnap: false)

    print("== D: a floating branch, and a slab, given supports")
    let high = b.drop(.longBranch, x: 3300, y: 650, expectSnap: false)
    let slab = b.drop(.corkSlab, x: 3500, y: 380, expectSnap: false)
    let post = b.drop(.verticalSupport, x: 3700, y: 500, expectSnap: false)
    var sup = b.h.supports()
    b.check("before: they float", sup[high] == .floating && sup[slab] == .floating && sup[post] == .floating)
    let made = b.h.addSupport(for: high) + b.h.addSupport(for: slab) + b.h.addSupport(for: post)
    sup = b.h.supports()
    b.check("supports made for them", made.count >= 4, made.map { b.h.item(id: $0)!.kind.rawValue }.joined(separator: ", "))
    b.check("after: held up", [high, slab, post].allSatisfy { sup[$0]?.holds == true }, [high, slab, post].map { "\(sup[$0]!)" }.joined(separator: " "))
    b.check("the supports are at the back, and stand on the ground", made.allSatisfy { b.h.item(id: $0)!.kind.atBack && sup[$0] == .ground },
            made.map { "\(b.h.item(id: $0)!.kind.rawValue) \(sup[$0]!)" }.joined(separator: ", "))

    print("== everything held up")
    for it in b.h.items {
        let s = sup[it.id] ?? .floating
        if !s.holds { b.check("#\(it.id) \(it.kind.label) held up", false, "\(s)") }
    }
    b.check("nothing floating", b.h.items.allSatisfy { sup[$0.id]?.holds == true }, "\(b.h.items.count) things, \(b.h.links.count) links")

    print("== fastened surfaces meet")
    let m = surfaces(b.h, standoff: 22 * 0.78)
    for l in b.h.links {
        guard let c = b.h.item(uid: l.child), let p = b.h.item(uid: l.parent), c.kind.climbable, p.kind.climbable else { continue }
        b.check("\(c.kind.label) #\(c.id) walks onto \(p.kind.label) #\(p.id)", b.connected(c.id, p.id, m))
    }
    b.check("uprights meet the plank", b.connected(p1, plank, m))
    if env["PC_BRACE"] != nil {
        for l in m.loops where l.owners.contains(brace) || l.owners.contains(branch) {
            var to: [String: Int] = [:]
            for j in m.junctions where j.from == l.id { to[j.to, default: 0] += 1 }
            let ends = l.closed ? "closed" : String(format: "open (%.0f,%.0f)->(%.0f,%.0f)", l.segs.first!.a.x, l.segs.first!.a.y, l.segs.last!.b.x, l.segs.last!.b.y)
            print("   loop \(l.id) \(ends) segs \(l.segs.count) owners \(Set(l.owners).sorted()) junctions \(to)")
            for j in m.junctions where j.from == l.id { print(String(format: "      at v%d (%.0f,%.0f) -> %@ v%d", j.fromVertex, j.at.x, j.at.y, j.to, j.toVertex)) }
        }
    }
    if env["PC_LOOPS"] != nil {
        for l in m.loops where l.owners.contains(ladder) || l.id == "screen:0" {
            var to: [String: Int] = [:]
            for j in m.junctions where j.from == l.id { to[j.to, default: 0] += 1 }
            print("   loop \(l.id) closed \(l.closed) segs \(l.segs.count) owners \(Set(l.owners).sorted()) junctions \(to)")
        }
    }
    b.check("the ladder meets the ground", m.loops.contains { $0.id == "screen:0" && $0.owners.contains(ladder) } || b.connected(ladder, 0, m))

    for l in b.h.links {
        if let j = b.h.joint(l), j.child.distance(to: j.seat) > 0.5 {
            print(String(format: "   off by %.2f: %@.%@ on %@.%@", j.child.distance(to: j.seat), b.h.item(uid: l.child)!.kind.rawValue, l.childPort, b.h.item(uid: l.parent)!.kind.rawValue, l.parentPort))
        }
    }
    print("== carried along")
    let deps = Set(b.h.dependents(of: brace))
    b.check("moving the brace takes the branch, vine and lower branch", Set([branch, vine, lower]).isSubset(of: deps), "\(deps.sorted())")
    let pdeps = Set(b.h.dependents(of: plank))
    b.check("moving the plank takes what rests on it", pdeps.count == 2, "\(pdeps.sorted())")
    b.check("moving one upright leaves the plank on the other", !b.h.dependents(of: p1).contains(plank), "\(b.h.dependents(of: p1))")
    var cut = b.h
    cut.release([p1])
    cut.shift([p1], by: V2(-60, 0))
    cut.realign()
    b.check("…and the plank stays put, on the other", cut.item(id: plank) == b.h.item(id: plank) && cut.support(of: plank).holds, "\(cut.support(of: plank))")
    var moved = b.h
    moved.shift([brace] + moved.dependents(of: brace), by: V2(120, -40))
    moved.realign()
    let still = moved.links.allSatisfy { l in moved.joint(l).map { $0.child.distance(to: $0.seat) < 0.5 } ?? false }
    b.check("still fastened after moving the lot", still)

    print("== resized and flipped: what is fastened stays fastened")
    for (label, f) in [("branch grown 1.4×", { (h: inout Habitat) in
                            let i = h.items.firstIndex { $0.id == branch }!; h.items[i].w *= 1.4; h.items[i].h *= 1.4 }),
                       ("branch flipped", { (h: inout Habitat) in let i = h.items.firstIndex { $0.id == branch }!; h.items[i].flipped.toggle() }),
                       ("brace made taller", { (h: inout Habitat) in let i = h.items.firstIndex { $0.id == brace }!; h.items[i].h *= 1.5 }),
                       ("beam longer", { (h: inout Habitat) in let i = h.items.firstIndex { $0.id == beam }!; h.items[i].w *= 1.2 })] {
        var t = b.h
        f(&t)
        t.realign()
        let worst = t.links.compactMap { t.joint($0) }.map { $0.child.distance(to: $0.seat) }.max() ?? 0
        let held = t.supports().values.allSatisfy(\.holds)
        b.check(label, worst < 0.5 && held, String(format: "worst joint %.2f, all held %@", worst, held ? "yes" : "no"))
    }

    print("== saved and loaded")
    let data = try! JSONEncoder().encode(b.h)
    var back = try! JSONDecoder().decode(Habitat.self, from: data)
    b.check("links kept", back.links == b.h.links, "\(back.links.count)")
    back.pruneLinks()
    b.check("all still whole after loading", back.links.count == b.h.links.count)
    var again = back
    again.realign()
    b.check("nothing moves on loading", again.items == b.h.items)
    // An old save (no links at all) still loads.
    var json = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    json["links"] = nil
    let old = try? JSONDecoder().decode(Habitat.self, from: try! JSONSerialization.data(withJSONObject: json))
    b.check("a habitat saved before links loads", old != nil && old!.links.isEmpty)

    print("== the ready-made tanks: nothing left floating")
    for p in Habitat.Preset.allCases where p != .empty {
        let h = Habitat.preset(p, world: world)
        let s = h.supports()
        let floating = h.items.filter { s[$0.id] == .floating && $0.kind.climbable }
        b.check("\(p.rawValue)", floating.isEmpty, "\(h.links.count) links, \(h.items.filter { $0.kind.atBack }.count) supports"
                + (floating.isEmpty ? "" : "; floating: " + floating.map { "\($0.kind.rawValue)#\($0.id)" }.joined(separator: " ")))
    }

    print("== the spider on them")
    let scale = CGFloat(Double(env["PC_SCALE"] ?? "0.78") ?? 0.78)
    let desk = SurfaceMap()
    desk.standoff = 22 * scale
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    let secs = CGFloat(Double(env["PC_SECS"] ?? "240") ?? 240)
    for (name, start, want) in [("A (from the lower branch, the brace, the vine)", lower, aIDs), ("B (from the ground)", -1, [p1, plank]), ("C (from the ground)", -2, [ladder, post1, beam, rope])] {
        var visited: [Int: Int] = [:]
        var crossed = 0
        for run in 0..<3 {
            reseed(UInt64(77 + run))
            let tank = surfaces(b.h, standoff: 22 * scale)
            let s = Spider(map: desk)
            s.config.followCursor = false
            s.config.scale = scale
            for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
            var at: V2
            if start > 0, let it = b.h.item(id: start) { at = V2(it.x, it.rect.maxY + 10) }
            else if start == -1 { at = V2(1590, G + 30) } else { at = V2(2200, G + 30) }
            // (Structure A is up in the air: each run starts on a different piece of it.)
            if start > 0, run > 0, let it = b.h.item(id: [brace, vine][run - 1]) { at = V2(it.rect.midX + 12, it.rect.midY) }
            s.enter(map: tank, at: at, habitat: true)
            var was: Int?
            for _ in 0..<Int(secs / dt) {
                s.setCursor(V2(-4000, -4000))
                s.update(dt: dt)
                guard let a = s.standingOn, let o = tank.owner(of: a) else { continue }
                visited[o, default: 0] += 1
                if let w = was, w != o { crossed += 1 }
                was = o
            }
        }
        let got = want.filter { (visited[$0] ?? 0) > 30 }
        b.check("\(name): gets onto every piece", got.count == want.count,
                "on \(got.count)/\(want.count): " + want.map { "\(b.h.item(id: $0)!.kind.rawValue) \(visited[$0] ?? 0)f" }.joined(separator: ", ") + " · \(crossed) walks from one onto another")
    }

    houseCheck(&b, outPrefix)

    if let outPrefix {
        for (name, x, w) in [("A", CGFloat(520), CGFloat(520)), ("B", 1380, 420), ("C", 2220, 780), ("D", 3100, 800)] {
            let area = CGRect(x: x, y: 0, width: w, height: 900)
            let img = HabitatArt.image(area.size, scale: 1.5) { ctx in
                ctx.setFillColor(c(0.13, 0.14, 0.16))
                ctx.fill(CGRect(origin: .zero, size: area.size))
                ctx.setFillColor(c(0.2, 0.16, 0.12))
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: G))
                // (Hardware at the back first.)
                paintItems(b.h, area: area, scale: 1.5, ctx, only: { $0.kind.atBack })
                paintItems(b.h, area: area, scale: 1.5, ctx, only: { !$0.kind.atBack })
                if env["PC_CLEAN"] == nil {
                    overlay(b.h, map: m, area: area, ctx)
                    portsOverlay(b.h, area: area, ctx)
                }
            }
            save(img!, "\(outPrefix)_\(name).png")
        }
    }
    print(b.fails == 0 ? "all ok" : "\(b.fails) FAILED")
}

/// The loops that can be walked to from the tank's own surface.
func reachable(_ m: SurfaceMap) -> Set<String> {
    var seen: Set<String> = ["screen:0"]
    var queue = ["screen:0"]
    while let l = queue.popLast() {
        for j in m.junctions where j.from == l && !seen.contains(j.to) { seen.insert(j.to); queue.append(j.to) }
    }
    return seen
}

/// The loop whose body line passes nearest `p`.
func loopNear(_ m: SurfaceMap, _ p: V2) -> String? {
    var best: (String, CGFloat)?
    for l in m.loops { for sg in l.segs { let d = projectOnSegment(p, sg.a, sg.b).dist; if best.map({ d < $0.1 }) ?? true { best = (l.id, d) } } }
    return best.flatMap { $0.1 < 4 ? $0.0 : nil }
}

func houseCheck(_ outer: inout Builder, _ outPrefix: String?) {
    print("== E: a house — walls, a floor, a door, a window, a roof, stairs to a balcony, backing walls, furniture")
    var b = Builder()
    let G = HabitatLayout.ground
    func put(_ kind: HabitatItemKind, x: CGFloat, y: CGFloat, w: CGFloat? = nil, h: CGFloat? = nil, flipped: Bool = false) -> Int {
        var it = b.h.add(kind, at: CGPoint(x: x, y: y))
        if let w { it.w = w }
        if let h { it.h = h }
        it.x = x; it.y = y; it.flipped = flipped
        it.seed = 500 + it.id * 13
        Habitat.clamp(&it, in: b.h.size)
        b.h.items[b.h.items.count - 1] = it
        return it.id
    }
    // At the back first: the walls of the two rooms.
    _ = put(.woodBacking, x: 1150, y: 0, w: 300, h: 150)
    _ = put(.wallpaper, x: 1150, y: 164, w: 300, h: 150)
    // The way in downstairs on the left; stairs up the right side to the
    // open window upstairs.
    let door = put(.door, x: 1000, y: 0, flipped: true)
    let wallL = put(.wall, x: 1300, y: 0)
    // The floor: dropped 8 points above the tops of the walls, it snaps down onto them.
    let floor = b.drop(.floorboards, x: 1150 + 5, y: 150 + 8, width: 330)
    b.h.linkWhatTouches(floor, within: 2)
    let topY = b.h.item(id: floor)!.rect.maxY - G
    let wallL2 = b.drop(.wall, x: 1000 + 6, y: topY + 6, "upstairs")
    let window = b.drop(.windowOpen, x: 1300 - 5, y: topY + 6, "upstairs")
    let roofTop = b.h.item(id: wallL2)!.rect.maxY - G
    // (A roof a little wider than the walls are apart: it sits on both anyway.)
    let roof = b.drop(.gableRoof, x: 1150 + 4, y: roofTop + 7, scale: 318 / 240)
    b.h.linkWhatTouches(roof, within: 2)
    let stairs = put(.stairs, x: 1312 + 164 * 1.2 / 2, y: 0, w: 164 * 1.2, h: topY, flipped: true)
    let bed = put(.bed, x: 1080, y: 0)
    let table = put(.table, x: 1200, y: topY)
    _ = put(.floorLamp, x: 1260, y: topY)
    let picture = put(.picture, x: 1110, y: topY + 70)
    let clock = put(.clock, x: 1600, y: 400)
    // A twig up on the backing wall, held up by what is made for it.
    let twig = put(.twig, x: 1150, y: 110)
    let made = b.h.addSupport(for: twig)

    let sup = b.h.supports()
    b.check("the floor sits on the wall and the door", b.h.links.filter { $0.child == b.h.item(id: floor)!.uid }.count >= 2)
    b.check("the roof sits on both upstairs walls", b.h.links.filter { $0.child == b.h.item(id: roof)!.uid }.count >= 2)
    b.check("nothing in the house floats", b.h.items.allSatisfy { sup[$0.id]?.holds == true },
            b.h.items.filter { sup[$0.id]?.holds != true }.map { "\($0.kind.rawValue)" }.joined(separator: " "))
    b.check("a picture on the wallpaper is fixed to it", b.h.isBacked(b.h.item(id: picture)!))
    b.check("a clock with no wall behind it is stuck to the glass", !b.h.isBacked(b.h.item(id: clock)!))
    b.check("the twig in front of the wood wall: a bracket screwed into it", made.count == 1 && b.h.item(id: made[0])!.kind == .branchBracket
            && b.h.isBacked(b.h.item(id: made[0])!), made.map { b.h.item(id: $0)!.kind.rawValue }.joined(separator: " "))
    // A branch out in the open: propped up from the ground.
    let open = put(.mediumBranch, x: 1900, y: 380)
    let prop = b.h.addSupport(for: open)
    b.check("a branch out in the open: propped up by a stake from the ground", prop.count == 1 && b.h.item(id: prop[0])!.kind == .stake
            && b.h.item(id: prop[0])!.y < 2 && b.h.support(of: open).holds, prop.map { "\(b.h.item(id: $0)!.kind.rawValue) y \(b.h.item(id: $0)!.y)" }.joined())

    let down = V2(1150, G + 22 * 0.78), up = V2(1150, b.h.item(id: floor)!.rect.maxY + 22 * 0.78)
    var m = surfaces(b.h, standoff: 22 * 0.78)
    let inDown = loopNear(m, down), inUp = loopNear(m, up)
    var r = reachable(m)
    b.check("door open: downstairs can be walked into", inDown.map { r.contains($0) } ?? false, inDown ?? "(no floor)")
    b.check("window open: upstairs can be walked into", inUp.map { r.contains($0) } ?? false, inUp ?? "(no floor)")
    var shut = b.h
    for (i, it) in shut.items.enumerated() where it.kind.toggled != nil && (it.kind == .door || it.kind == .windowOpen) { shut.items[i].kind = it.kind.toggled! }
    m = surfaces(shut, standoff: 22 * 0.78)
    r = reachable(m)
    b.check("door shut: downstairs is closed off", loopNear(m, down).map { !r.contains($0) } ?? false)
    b.check("window shut: upstairs is closed off", loopNear(m, up).map { !r.contains($0) } ?? false)

    // The spider, let loose outside, finding its way in.
    let scale = CGFloat(Double(env["PC_SCALE"] ?? "0.78") ?? 0.78)
    let desk = SurfaceMap()
    desk.standoff = 22 * scale
    desk.debugRebuild(screen: CGRect(x: 0, y: 0, width: 1512, height: 982), menuBarHeight: 25, windows: [])
    let secs = CGFloat(Double(env["PC_SECS"] ?? "240") ?? 240)
    var inside = [0, 0], onRoof = 0, onStairs = 0, trips = 0
    var where_: [String: Int] = [:]
    let floorTop = b.h.item(id: floor)!.rect.maxY
    // Let loose outside by the door, inside downstairs, and inside upstairs.
    let starts = [V2(930, G + 30), V2(1150, G + 30), V2(1150, floorTop + 30)]
    for run in 0..<3 {
        reseed(UInt64(300 + run))
        let tank = surfaces(b.h, standoff: 22 * scale)
        let s = Spider(map: desk)
        s.config.followCursor = false
        s.config.scale = scale
        for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
        s.enter(map: tank, at: starts[run], habitat: true)
        var room: Int?
        for _ in 0..<Int(secs / dt) {
            s.setCursor(V2(-4000, -4000))
            s.update(dt: dt)
            guard s.standingOn != nil else { continue }
            let p = s.worldPos
            var now: Int?
            if p.x > 1012, p.x < 1285 {
                if p.y < G + 150 { inside[0] += 1; now = 0 } else if p.y > floorTop, p.y < floorTop + 150 { inside[1] += 1; now = 1 }
            }
            if now != room { trips += 1; room = now }
            if let a = s.standingOn, let o = tank.owner(of: a) {
                if o == roof { onRoof += 1 }; if o == stairs { onStairs += 1 }
                where_[b.h.item(id: o)?.kind.rawValue ?? "?", default: 0] += 1
            } else if let a = s.standingOn { where_[a.loopID, default: 0] += 1 }
        }
    }
    if env["PC_WHERE"] != nil { print("   where:", where_.sorted { $0.value > $1.value }.prefix(12).map { "\($0.key) \($0.value)" }.joined(separator: ", ")) }
    b.check("the spider is in downstairs", inside[0] > 60, "\(inside[0]) frames")
    b.check("…and upstairs", inside[1] > 60, "\(inside[1]) frames")
    b.check("…and goes in and out of them", trips >= 4, "\(trips) times")
    b.check("…and about on the house and its stairs", onStairs + onRoof + (where_["wall"] ?? 0) + (where_["door"] ?? 0) + (where_["windowOpen"] ?? 0) > 60,
            "stairs \(onStairs), roof \(onRoof), walls \((where_["wall"] ?? 0) + (where_["door"] ?? 0) + (where_["windowOpen"] ?? 0))")
    _ = (wallL, window, bed, table)

    // Shut: it lets itself in (and out) through the door, which shuts
    // again behind it.
    var opens = 0, shutsBehind = 0, insideShut = 0, outsideShut = 0
    for run in 0..<2 {
        reseed(UInt64(400 + run))
        var h = shut
        let tank = SurfaceMap()
        tank.standoff = 22 * scale
        tank.rebuild(habitat: h.surfaces(standoff: 22 * scale))
        let s = Spider(map: desk)
        s.config.followCursor = false
        s.config.scale = scale
        for _ in 0..<600 { s.setCursor(V2(-4000, -4000)); s.update(dt: dt); if s.debugState.hasPrefix("attached") { break } }
        s.enter(map: tank, at: run == 0 ? V2(960, G + 30) : V2(1150, G + 30), habitat: true)
        var keeper = DoorKeeper()
        for _ in 0..<Int(secs / dt) {
            s.setCursor(V2(-4000, -4000))
            s.update(dt: dt)
            let (o, c, through) = keeper.tend(h, spider: s.worldPos, attached: s.standingOn != nil, scale: scale, dt: dt)
            if !o.isEmpty || !c.isEmpty {
                for id in o { h.items[h.items.firstIndex { $0.id == id }!].kind = .door }
                for id in c { h.items[h.items.firstIndex { $0.id == id }!].kind = .doorClosed }
                opens += o.count
                shutsBehind += c.count
                tank.rebuild(habitat: h.surfaces(standoff: 22 * scale))
                s.surfacesRestructured()
            }
            if let through { s.summon(to: through) }
            guard s.standingOn != nil else { continue }
            let p = s.worldPos
            if p.x > 1012, p.x < 1285, p.y < G + 150 { insideShut += 1 } else if p.x < 990 { outsideShut += 1 }
        }
    }
    b.check("door shut: the spider pushes it open to go through", opens >= 2, "\(opens) times")
    b.check("…and it swings shut again behind it", shutsBehind >= 1, "\(shutsBehind) times")
    b.check("…so it gets in, and out", insideShut > 60 && outsideShut > 60, "inside \(insideShut), outside \(outsideShut) frames")
    _ = door

    if let outPrefix {
        let area = CGRect(x: 900, y: 0, width: 1100, height: 520)
        let m2 = surfaces(b.h, standoff: 22 * 0.78)
        let img = HabitatArt.image(area.size, scale: 1.5) { ctx in
            ctx.setFillColor(c(0.62, 0.78, 0.9))
            ctx.fill(CGRect(origin: .zero, size: area.size))
            ctx.setFillColor(c(0.4, 0.3, 0.2))
            ctx.fill(CGRect(x: 0, y: 0, width: area.width, height: G))
            paintItems(b.h, area: area, scale: 1.5, ctx, only: { $0.kind.atBack })
            paintItems(b.h, area: area, scale: 1.5, ctx, only: { !$0.kind.atBack })
            if env["PC_CLEAN"] == nil { overlay(b.h, map: m2, area: area, ctx) }
        }
        save(img!, "\(outPrefix)_E.png")
    }
    outer.fails += b.fails
}
#endif
