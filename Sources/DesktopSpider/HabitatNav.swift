import CoreGraphics
import QuartzCore
import Foundation

// MARK: - Finding its way about the tank
//
// The tank's surfaces as the ways it can go (the desktop has none of this:
// there it goes along its windows' edges, a leap at a time). Every surface
// is marked off into spots a stride or so apart, and from each it can walk
// on to the next along it, either way; turn round; go over onto another
// surface where the two meet (a junction: see HabitatGeometry.swift); leap,
// where a leap from there comes down cleanly on something — each one flown
// beforehand exactly as it would be flown (the arc, the air, what it would
// catch hold of on the way: see `Spider.updateAirborne`), so a leap it
// plans is a leap it can make; or go through a shut door, which opens for
// it. The cheapest way from where it is to where it is going is the way it
// takes (A*, with the straight distance there for the estimate) — found
// afresh each time it decides, so it goes on the way it set off unless
// something changes: it comes down somewhere else, a leap turns out not to
// be on, what it is after moves. A way that let it down costs more, or is
// out, for the rest of that trip.
//
// Worked out off the main thread whenever the surfaces are laid out again,
// and asked on the main thread, where each question is quick. Whether it
// can get somewhere at all is known straight off (the ways fall into parts
// it can get about all of; see `reach`), so it never sets its heart on
// prey, or a place, it cannot get to.

/// What getting somewhere costs it just now — how readily it leaps, the
/// ways over it knows, a gale — and what has gone wrong on the way already.
struct NavLean {
    /// On its leaps, all told: a bold spider's cost it less.
    var leap: Float = 1
    /// Per `TankNav.hops`: a way over it knows costs it less (empty: none).
    var hops: [Float] = []
    /// Surfaces (by loop) it keeps off if it can — what sways, in a gale —
    /// and how many times more it costs to go onto one.
    var keepOff: Set<Int32> = []
    var keepOffCost: Float = 1
    /// By edge: what it has found out about it on this trip (infinity: out).
    var penalty: [Int32: Float] = [:]
}

final class TankNav {
    /// A spot on a surface.
    struct Node {
        var loop: Int32
        var seg: Int32
        var t: CGFloat
        /// How far round its loop from the loop's start.
        var along: CGFloat
        /// Where the body is, standing there (corners rounded, as it walks them).
        var p: V2
        /// Out from the surface there.
        var normal: V2
    }
    enum Kind: UInt8 { case walk, turn, hop, leap, door }
    /// A way from one state (a spot, and which way along its loop it is
    /// going: `node * 2`, or `node * 2 + 1` going against the loop) to the next.
    struct Edge {
        var to: Int32
        var kind: Kind
        /// Hop: into `hops`; leap: into `leaps`; door: into `doors`.
        var ref: Int32
        var cost: Float
    }
    /// A way over: had from the spot before the place two surfaces meet
    /// (`at`), walking into it.
    struct Hop { var junction: SurfaceJunction; var key: String; var onto: Int32; var at: Int32 }
    struct Leap { var from: Int32; var to: Int32; var aim: V2; var land: V2; var onto: Int32 }
    struct Door { var id: Int; var from: Int32; var to: Int32; var at: V2 }

    /// The spider's size it was worked out for (its reach in the air).
    let scale: CGFloat
    let loopIDs: [String]
    let loopIndex: [String: Int32]
    let closed: [Bool]
    let perimeter: [CGFloat]
    /// Per loop, how far round it each segment starts.
    let starts: [[CGFloat]]
    /// Per loop: the thing it is the surface of (0: the tank).
    let owner: [Int]
    let nodes: [Node]
    /// Per loop, its nodes in order round it.
    let loopNodes: [[Int32]]
    /// Out of each state, `edges[first[s]..<first[s + 1]]`.
    let first: [Int32]
    let edges: [Edge]
    let hops: [Hop]
    let leaps: [Leap]
    let doors: [Door]
    /// The spots, filed by square.
    private let file: NodeFile
    /// States it cannot stop in: walking into the end of a run with only
    /// another surface to go on onto, it is over onto that before it could.
    let noStop: [Bool]
    /// The part of the ways each state is in (see `reach`).
    let part: [Int32]
    private let partEdges: [[Int32]]

    /// How far apart the spots are, and the longest leap it plans.
    static let spacing: CGFloat = 30
    static let leapRange: CGFloat = 460
    /// A turn round on the spot, as far as walking goes.
    static let turnCost: Float = 55
    /// How near a spot counts as at it (stopping there, it runs on a few
    /// points before it comes to a stop: most, at a scurry).
    static let near: CGFloat = 16
    /// Tools: how long the working out took.
    private(set) var buildTime: CFTimeInterval = 0

    var states: Int { nodes.count * 2 }
    @inline(__always) static func dir(of s: Int32) -> CGFloat { s & 1 == 0 ? 1 : -1 }
    @inline(__always) static func state(_ node: Int32, _ dir: CGFloat) -> Int32 { node * 2 + (dir < 0 ? 1 : 0) }

    // MARK: Which surfaces it was worked out for

    private var mapID: ObjectIdentifier?
    private var mapGeneration = -1

    /// These are the ways about `map` as it is now.
    func adopt(_ map: SurfaceMap) {
        mapID = ObjectIdentifier(map)
        mapGeneration = map.generation
    }

    func fits(_ map: SurfaceMap, scale sc: CGFloat) -> Bool {
        mapID == ObjectIdentifier(map) && mapGeneration == map.generation && abs(sc - scale) < 0.005
    }

    // MARK: Working it out

    /// Worked out for `map` (a copy of the tank's, off the main thread, or
    /// the tank's own), with the doors in `habitat`, for a spider of `scale`.
    init(map: SurfaceMap, habitat: Habitat?, scale sc: CGFloat) {
        let began = CACurrentMediaTime()
        scale = sc
        let loops = map.loops
        loopIDs = loops.map(\.id)
        var index: [String: Int32] = [:]
        for (i, l) in loops.enumerated() { index[l.id] = Int32(i) }
        loopIndex = index
        closed = loops.map(\.closed)
        var cum: [[CGFloat]] = []
        for l in loops {
            var c: [CGFloat] = [0]
            c.reserveCapacity(l.segs.count + 1)
            for s in l.segs { c.append(c.last! + s.len) }
            cum.append(c)
        }
        starts = cum
        // (Its own copy, here: what is worked out below uses it before
        // everything is in place.)
        let perimeter = cum.map { $0.last ?? 0 }
        self.perimeter = perimeter
        owner = loops.map { l in l.owners.first(where: { $0 != 0 }) ?? 0 }
        // (In a fixed order, whatever order the map keeps them in.)
        let junctions = map.junctions.sorted {
            ($0.from, $0.fromVertex, $0.to, $0.toVertex) < ($1.from, $1.fromVertex, $1.to, $1.toVertex)
        }
        func vertexAlong(_ l: Int, _ v: Int) -> CGFloat {
            let n = loops[l].segs.count
            return loops[l].closed ? cum[l][v % max(n, 1)] : cum[l][min(max(v, 0), n)]
        }

        // Doors: a spot on the floor either side, as the places have them.
        var doorSides: [(id: Int, at: V2, sides: [(loop: Int, along: CGFloat)])] = []
        if let h = habitat {
            let off = map.standoff
            for it in h.items where it.kind == .doorClosed {
                let r = it.rect
                var sides: [(loop: Int, along: CGFloat)] = []
                for side in [CGFloat(-1), 1] {
                    let x = side < 0 ? r.minX - 30 * sc : r.maxX + 30 * sc
                    if let s = HabitatItem.floor(below: V2(x, r.minY + 30 * sc), on: map, notOwnedBy: it.id),
                       abs(s.point.y - (r.minY + off)) < 30 * sc, let li = index[s.anchor.loopID] {
                        sides.append((Int(li), cum[Int(li)][s.anchor.segIdx] + s.anchor.t))
                    }
                }
                if sides.count == 2 { doorSides.append((it.id, V2(r.midX, r.minY + off), sides)) }
            }
        }

        // The spots: where others meet each loop, its ends, the doors — and
        // no further apart than a stride or so in between.
        var must: [[CGFloat]] = Array(repeating: [], count: loops.count)
        for j in junctions {
            if let a = index[j.from] { must[Int(a)].append(vertexAlong(Int(a), j.fromVertex)) }
            if let b = index[j.to] { must[Int(b)].append(vertexAlong(Int(b), j.toVertex)) }
        }
        for d in doorSides { for s in d.sides { must[s.loop].append(s.along) } }
        var nodes: [Node] = []
        var loopNodes: [[Int32]] = []
        let radius = Spider.cornerRadius * sc
        for (li, l) in loops.enumerated() {
            let P = perimeter[li]
            var mine: [Int32] = []
            guard P > 1, !l.segs.isEmpty else { loopNodes.append(mine); continue }
            var stops = must[li]
            if !l.closed { stops += [0, P] }
            if stops.isEmpty { stops = [0] }
            stops.sort()
            var uniq: [CGFloat] = []
            for s in stops where uniq.last.map({ s - $0 > 0.5 }) ?? true { uniq.append(s) }
            if l.closed, uniq.count > 1, let f = uniq.first, let last = uniq.last, f + P - last <= 0.5 { uniq.removeLast() }
            var at: [CGFloat] = []
            let count = l.closed ? uniq.count : uniq.count - 1
            for k in 0..<count {
                let a = uniq[k], b = k + 1 < uniq.count ? uniq[k + 1] : uniq[0] + P
                let parts = max(1, Int(((b - a) / TankNav.spacing).rounded(.up)))
                for q in 0..<parts {
                    var x = a + (b - a) * CGFloat(q) / CGFloat(parts)
                    if x >= P { x -= P }
                    at.append(x)
                }
            }
            if !l.closed { at.append(P) }
            at.sort()
            for x in at {
                var k = TankNav.segment(cum[li], x)
                var t = x - cum[li][k]
                if k >= l.segs.count { k = l.segs.count - 1; t = l.segs[k].len }
                let a = Anchor(loopID: l.id, segIdx: k, t: t)
                let r = map.resolve(a, cornerRadius: radius)
                mine.append(Int32(nodes.count))
                nodes.append(Node(loop: Int32(li), seg: Int32(k), t: t, along: x, p: r?.pos ?? l.segs[k].point(at: t),
                                  normal: r?.normal ?? l.segs[k].normal))
            }
            loopNodes.append(mine)
        }
        self.nodes = nodes
        self.loopNodes = loopNodes
        // (The spot at `x` round loop `l`: stops closer together than a
        // hair were made one.)
        func nodeAt(_ l: Int, _ x: CGFloat) -> Int32? {
            let ns = loopNodes[l]
            guard !ns.isEmpty else { return nil }
            var lo = 0, hi = ns.count
            while lo < hi {
                let m = (lo + hi) / 2
                if nodes[Int(ns[m])].along < x { lo = m + 1 } else { hi = m }
            }
            var best: (d: CGFloat, n: Int32)?
            for k in [lo - 1, lo, 0, ns.count - 1] where k >= 0 && k < ns.count {
                var d = abs(nodes[Int(ns[k])].along - x)
                if loops[l].closed { d = min(d, perimeter[l] - d) }
                if d < best?.d ?? .greatestFiniteMagnitude { best = (d, ns[k]) }
            }
            return best.flatMap { $0.d < 0.6 ? $0.n : nil }
        }

        let S = nodes.count * 2
        var out: [[Edge]] = Array(repeating: [], count: S)
        var noStop = [Bool](repeating: false, count: S)

        // Where each spot comes in its loop's order.
        var place = [Int](repeating: 0, count: nodes.count)
        for ns in loopNodes { for (k, n) in ns.enumerated() { place[Int(n)] = k } }
        /// The spot before `n` on its loop, going `dir` (round the loop, if
        /// it is closed), and how far that is.
        func before(_ n: Int32, _ dir: CGFloat) -> (n: Int32, d: CGFloat)? {
            let l = Int(nodes[Int(n)].loop), ns = loopNodes[l], k = place[Int(n)]
            var m = dir > 0 ? k - 1 : k + 1
            if m < 0 || m >= ns.count {
                guard loops[l].closed, ns.count > 1 else { return nil }
                m = (m + ns.count) % ns.count
            }
            let p = ns[m]
            var d = dir > 0 ? nodes[Int(n)].along - nodes[Int(p)].along : nodes[Int(p)].along - nodes[Int(n)].along
            if d <= 0 { d += perimeter[l] }
            return (p, d)
        }

        // Over onto another surface where they meet, keeping the way it
        // goes (as `Spider.crossJunction` does) — which it does walking into
        // the place they meet, never turning round on it: so the way over
        // is had from the spot before, and takes in the walk there.
        var hops: [Hop] = []
        var forcedEnd = Set<Int>()   // loop * 2 + (its far end ? 1 : 0)
        for j in junctions {
            guard let a = index[j.from], let b = index[j.to] else { continue }
            let la = loops[Int(a)], lb = loops[Int(b)]
            let na = la.segs.count, nb = lb.segs.count
            guard na > 0, nb > 0, let at = nodeAt(Int(a), vertexAlong(Int(a), j.fromVertex)),
                  let to = nodeAt(Int(b), vertexAlong(Int(b), j.toVertex)) else { continue }
            let h = Int32(hops.count)
            var used = false
            for dir in [CGFloat(1), -1] {
                let fromOK = dir > 0 ? (la.closed || j.fromVertex > 0) : (la.closed || j.fromVertex < na)
                let toOK = dir > 0 ? (lb.closed || j.toVertex < nb) : (lb.closed || j.toVertex > 0)
                guard fromOK, toOK, let from = before(at, dir) else { continue }
                let inDir = dir > 0 ? la.segs[(j.fromVertex - 1 + na) % na].dir : la.segs[j.fromVertex % na].dir * -1
                let outDir = dir > 0 ? lb.segs[j.toVertex % nb].dir : lb.segs[(j.toVertex - 1 + nb) % nb].dir * -1
                let bend = Float((1 - inDir.dot(outDir)) / 2)
                out[Int(TankNav.state(from.n, dir))].append(Edge(to: TankNav.state(to, dir), kind: .hop, ref: h,
                                                                 cost: Float(from.d) + 3 + 25 * bend))
                used = true
                if !la.closed, dir > 0, j.fromVertex >= na { forcedEnd.insert(Int(a) * 2 + 1) }
                if !la.closed, dir < 0, j.fromVertex <= 0 { forcedEnd.insert(Int(a) * 2) }
            }
            if used { hops.append(Hop(junction: j, key: routeKey(j), onto: b, at: at)) }
        }
        // Walking into the end of a run with another surface to go on onto,
        // it goes on onto it: it cannot stop there, nor (overrunning a stop
        // a little, as it does) just short of it.
        for li in loops.indices where !loops[li].closed {
            let P = perimeter[li]
            for n in loopNodes[li] {
                let x = nodes[Int(n)].along
                if forcedEnd.contains(li * 2 + 1), x >= P - TankNav.near { noStop[Int(TankNav.state(n, 1))] = true }
                if forcedEnd.contains(li * 2), x <= TankNav.near { noStop[Int(TankNav.state(n, -1))] = true }
            }
        }

        // Along each loop, either way; and round on the spot.
        for (li, ns) in loopNodes.enumerated() where !ns.isEmpty {
            let P = perimeter[li]
            for k in ns.indices {
                let a = ns[k]
                let nextK = k + 1 < ns.count ? k + 1 : (loops[li].closed && ns.count > 1 ? 0 : -1)
                if nextK >= 0 {
                    let b = ns[nextK]
                    var d = nodes[Int(b)].along - nodes[Int(a)].along
                    if d <= 0 { d += P }
                    out[Int(TankNav.state(a, 1))].append(Edge(to: TankNav.state(b, 1), kind: .walk, ref: -1, cost: Float(d)))
                    out[Int(TankNav.state(b, -1))].append(Edge(to: TankNav.state(a, -1), kind: .walk, ref: -1, cost: Float(d)))
                }
                for dir in [CGFloat(1), -1] where !noStop[Int(TankNav.state(a, dir))] {
                    out[Int(TankNav.state(a, dir))].append(Edge(to: TankNav.state(a, -dir), kind: .turn, ref: -1, cost: TankNav.turnCost))
                }
            }
        }

        // Through the doors.
        var doors: [Door] = []
        for d in doorSides {
            guard let a = nodeAt(d.sides[0].loop, d.sides[0].along), let b = nodeAt(d.sides[1].loop, d.sides[1].along) else { continue }
            let pa = nodes[Int(a)], pb = nodes[Int(b)]
            let w = Float(pa.p.distance(to: pb.p))
            for (x, y) in [(a, b), (b, a)] {
                let px = nodes[Int(x)], py = nodes[Int(y)]
                let sx = loops[Int(px.loop)].segs[Int(px.seg)], sy = loops[Int(py.loop)].segs[Int(py.seg)]
                let toward: CGFloat = (d.at - px.p).dot(sx.dir) >= 0 ? 1 : -1
                let away: CGFloat = (py.p - d.at).dot(sy.dir) >= 0 ? 1 : -1
                let ref = Int32(doors.count)
                doors.append(Door(id: d.id, from: x, to: y, at: d.at))
                for dir in [CGFloat(1), -1] where !noStop[Int(TankNav.state(x, dir))] {
                    out[Int(TankNav.state(x, dir))].append(Edge(to: TankNav.state(y, away), kind: .door, ref: ref,
                                                                cost: 220 + w + (dir == toward ? 0 : TankNav.turnCost)))
                }
            }
        }

        // Leaps: from every spot to anywhere a leap comes down cleanly.
        let flight = Flight(map: map, loops: loops, scale: sc)
        var leaps: [Leap] = []
        let file = NodeFile(nodes: nodes, cell: 64)
        self.file = file
        var buckets: [Int64: (d: CGFloat, j: Int32)] = [:]
        var landed: Set<Int64> = []
        for i in nodes.indices {
            let a = nodes[i]
            let li = Int(a.loop)
            let canStay = !noStop[i * 2] || !noStop[i * 2 + 1]
            guard canStay else { continue }
            buckets.removeAll(keepingCapacity: true)
            file.each(near: a.p, within: TankNav.leapRange) { j in
                guard j != i else { return }
                let b = nodes[j]
                let d = a.p.distance(to: b.p)
                guard d >= 24, d <= TankNav.leapRange else { return }
                if b.loop == a.loop {
                    // (Not along what it could as well walk.)
                    let P = perimeter[li]
                    var w = abs(b.along - a.along)
                    if loops[li].closed { w = min(w, P - w) }
                    if w <= d * 1.5 + 50 { return }
                }
                // (One aim at each stretch of each surface: the nearest.)
                let key = Int64(b.loop) << 32 | Int64(Int((b.along / 75).rounded(.down)))
                if let have = buckets[key], have.d <= d { return }
                buckets[key] = (d, Int32(j))
            }
            landed.removeAll(keepingCapacity: true)
            for key in buckets.keys.sorted() {
                let j = Int(buckets[key]!.j)
                let b = nodes[j]
                guard let v = Spider.arc(from: a.p, to: b.p) else { continue }
                // (Into what it stands on: only a drop, from under something.)
                let into = v.normalized.dot(a.normal) < -0.05
                if into, !(a.normal.y < -0.9 && b.p.y < a.p.y - 4) { continue }
                let launch = Spider.pushOff(v, from: a.p, to: b.p, normal: a.normal)
                guard let l = flight.fly(from: a.p, launch: launch, launchLoop: a.loop, target: b.p) else { continue }
                if flight.blocked(from: a.p, launch: v, to: b.p) { continue }
                if into, flight.blocked(from: a.p, launch: launch, to: b.p) { continue }
                // Where it comes down: the spot there.
                guard let k = TankNav.nearest(loopNodes[Int(l.loop)], nodes, perimeter[Int(l.loop)], loops[Int(l.loop)].closed, l.along) else { continue }
                let landKey = Int64(k)
                if landed.contains(landKey) { continue }
                landed.insert(landKey)
                let s = loops[Int(l.loop)].segs[Int(l.seg)]
                let landDir: CGFloat = l.vel.dot(s.dir) >= 0 ? 1 : -1
                let dist = a.p.distance(to: l.point)
                let effort = min(launch.length / Spider.maxJumpSpeed, 1.2)
                let under: Float = s.facing == .down ? 40 : 0
                let cost = 110 + 0.8 * Float(dist) + 160 * Float(effort * effort) + under
                let ref = Int32(leaps.count)
                leaps.append(Leap(from: Int32(i), to: k, aim: b.p, land: l.point, onto: l.loop))
                // (Facing the other way, it turns to face its mark first.)
                let seg = loops[li].segs[Int(a.seg)]
                let facing: CGFloat = (b.p - a.p).dot(seg.dir) >= 0 ? 1 : -1
                for dir in [CGFloat(1), -1] where !noStop[Int(TankNav.state(Int32(i), dir))] {
                    out[Int(TankNav.state(Int32(i), dir))].append(Edge(to: TankNav.state(k, landDir), kind: .leap, ref: ref,
                                                                       cost: cost + (dir == facing ? 0 : TankNav.turnCost * 0.8)))
                }
            }
        }

        var firstIdx: [Int32] = [0]
        firstIdx.reserveCapacity(S + 1)
        var flat: [Edge] = []
        flat.reserveCapacity(out.reduce(0) { $0 + $1.count })
        for list in out {
            flat += list
            firstIdx.append(Int32(flat.count))
        }
        first = firstIdx
        edges = flat
        self.hops = hops
        self.leaps = leaps
        self.doors = doors
        self.noStop = noStop
        (part, partEdges) = TankNav.parts(states: S, first: firstIdx, edges: flat)
        buildTime = CACurrentMediaTime() - began
    }

    /// The segment of a loop (by its starts) `x` round it is on.
    static func segment(_ cum: [CGFloat], _ x: CGFloat) -> Int {
        var lo = 0, hi = cum.count - 1
        while lo < hi {
            let m = (lo + hi + 1) / 2
            if cum[m] <= x { lo = m } else { hi = m - 1 }
        }
        return lo
    }

    /// The spot on a loop nearest `x` round it (its spots `ns`, in order).
    static func nearest(_ ns: [Int32], _ nodes: [Node], _ P: CGFloat, _ closed: Bool, _ x: CGFloat) -> Int32? {
        guard !ns.isEmpty else { return nil }
        var lo = 0, hi = ns.count
        while lo < hi {
            let m = (lo + hi) / 2
            if nodes[Int(ns[m])].along < x { lo = m + 1 } else { hi = m }
        }
        var best: (d: CGFloat, n: Int32)?
        // (Either side of it — and, round a closed loop, the far ends.)
        for k in [lo - 1, lo, 0, ns.count - 1] where k >= 0 && k < ns.count {
            var d = abs(nodes[Int(ns[k])].along - x)
            if closed { d = min(d, P - d) }
            if d < best?.d ?? .greatestFiniteMagnitude { best = (d, ns[k]) }
        }
        return best?.n
    }

    // MARK: The parts it can get about all of

    /// Strongly connected parts of the ways (Tarjan's, without recursion),
    /// and which part leads straight into which.
    private static func parts(states S: Int, first: [Int32], edges: [Edge]) -> ([Int32], [[Int32]]) {
        var index = [Int32](repeating: -1, count: S), low = [Int32](repeating: 0, count: S)
        var onStack = [Bool](repeating: false, count: S)
        var stack: [Int32] = [], comp = [Int32](repeating: -1, count: S)
        var next: Int32 = 0, count: Int32 = 0
        var call: [(v: Int32, e: Int32)] = []
        for s0 in 0..<S where index[s0] < 0 {
            index[s0] = next; low[s0] = next; next += 1
            stack.append(Int32(s0)); onStack[s0] = true
            call.append((Int32(s0), first[s0]))
            while let top = call.last {
                let v = Int(top.v)
                if top.e < first[v + 1] {
                    call[call.count - 1].e = top.e + 1
                    let w = Int(edges[Int(top.e)].to)
                    if index[w] < 0 {
                        index[w] = next; low[w] = next; next += 1
                        stack.append(Int32(w)); onStack[w] = true
                        call.append((Int32(w), first[w]))
                    } else if onStack[w] {
                        low[v] = min(low[v], index[w])
                    }
                } else {
                    call.removeLast()
                    if let up = call.last { low[Int(up.v)] = min(low[Int(up.v)], low[v]) }
                    if low[v] == index[v] {
                        while let w = stack.popLast() {
                            onStack[Int(w)] = false
                            comp[Int(w)] = count
                            if Int(w) == v { break }
                        }
                        count += 1
                    }
                }
            }
        }
        var into: [Set<Int32>] = Array(repeating: [], count: Int(count))
        for s in 0..<S {
            let c = comp[s]
            for e in Int(first[s])..<Int(first[s + 1]) {
                let d = comp[Int(edges[e].to)]
                if d != c { into[Int(c)].insert(d) }
            }
        }
        return (comp, into.map { $0.sorted() })
    }

    /// Every part it can get to from part `c` (itself included), worked out
    /// the first time it is asked.
    private var reachCache: [Int32: [UInt64]] = [:]
    private func reach(_ c: Int32) -> [UInt64] {
        if let r = reachCache[c] { return r }
        let n = partEdges.count
        var bits = [UInt64](repeating: 0, count: (n + 63) / 64)
        var todo = [c]
        bits[Int(c) / 64] |= 1 << UInt64(Int(c) % 64)
        while let x = todo.popLast() {
            for y in partEdges[Int(x)] where bits[Int(y) / 64] & (1 << UInt64(Int(y) % 64)) == 0 {
                bits[Int(y) / 64] |= 1 << UInt64(Int(y) % 64)
                todo.append(y)
            }
        }
        reachCache[c] = bits
        return bits
    }

    // MARK: Where things are on it

    /// Which loop an anchor is on, and how far round it.
    func locate(_ a: Anchor) -> (loop: Int, along: CGFloat)? {
        guard let l = loopIndex[a.loopID] else { return nil }
        let c = starts[Int(l)]
        guard a.segIdx >= 0, a.segIdx < c.count - 1 else { return nil }
        return (Int(l), c[a.segIdx] + a.t)
    }

    func anchor(of n: Int32) -> Anchor {
        let nd = nodes[Int(n)]
        return Anchor(loopID: loopIDs[Int(nd.loop)], segIdx: Int(nd.seg), t: nd.t)
    }

    /// How far it is round loop `l` from `x` to `y` going `dir` (nil: not
    /// that way, off the end of a run).
    func walk(_ l: Int, from x: CGFloat, to y: CGFloat, dir: CGFloat) -> CGFloat? {
        let d = dir > 0 ? y - x : x - y
        if d >= 0 { return d }
        return closed[l] ? d + perimeter[l] : nil
    }

    /// The spots either side of `x` on loop `l`: the last at or before it,
    /// and the first after it (round the loop, if it is closed).
    private func around(_ l: Int, _ x: CGFloat) -> (before: Int32?, after: Int32?) {
        let ns = loopNodes[l]
        guard !ns.isEmpty else { return (nil, nil) }
        var lo = 0, hi = ns.count
        while lo < hi {
            let m = (lo + hi) / 2
            if nodes[Int(ns[m])].along <= x { lo = m + 1 } else { hi = m }
        }
        let before: Int32? = lo > 0 ? ns[lo - 1] : (closed[l] ? ns.last : nil)
        let after: Int32? = lo < ns.count ? ns[lo] : (closed[l] ? ns.first : nil)
        return (before, after)
    }

    /// The states it could set off in from `a`, going `dir`: along to the
    /// spot ahead, or back to the one behind (turning round first, if it
    /// has to); on over onto another surface where it meets this one just
    /// ahead or behind — what getting into each costs, and the way over
    /// that got it there (-1: none).
    private func entries(_ a: Anchor, dir: CGFloat) -> [(s: Int32, cost: Float, via: Int32)] {
        guard let (l, x) = locate(a) else { return [] }
        let (b, f) = around(l, x)
        var out: [(s: Int32, cost: Float, via: Int32)] = []
        func add(_ s: Int32, _ c: CGFloat, _ via: Int32 = -1) {
            if let i = out.firstIndex(where: { $0.s == s }) {
                if Float(c) < out[i].cost { out[i] = (s, Float(c), via) }
            } else {
                out.append((s, Float(c), via))
            }
        }
        /// On over where another surface meets this one at `v` (the spot it
        /// comes to next going `d`), by the ways over had from `u` (the spot
        /// before that): their cost, less the walk from `u` it has done.
        func over(from u: Int32?, at v: Int32, d: CGFloat, dist: CGFloat, extra: CGFloat) {
            guard let u, u != v, let walked = walk(l, from: nodes[Int(u)].along, to: nodes[Int(v)].along, dir: d) else { return }
            let s = TankNav.state(u, d)
            for e in Int(first[Int(s)])..<Int(first[Int(s) + 1]) where edges[e].kind == .hop && hops[Int(edges[e].ref)].at == v {
                add(edges[e].to, dist + CGFloat(edges[e].cost) - walked + extra, Int32(e))
            }
        }
        if let f, let d = walk(l, from: x, to: nodes[Int(f)].along, dir: 1) {
            let turn = dir < 0 ? CGFloat(TankNav.turnCost) : 0
            add(TankNav.state(f, 1), d + turn)
            over(from: b, at: f, d: 1, dist: d, extra: turn)
            if d <= TankNav.near { add(TankNav.state(f, dir), d) }
        }
        if let b, let d = walk(l, from: x, to: nodes[Int(b)].along, dir: -1) {
            let turn = dir > 0 ? CGFloat(TankNav.turnCost) : 0
            add(TankNav.state(b, -1), d + turn)
            over(from: f, at: b, d: -1, dist: d, extra: turn)
            if d <= TankNav.near { add(TankNav.state(b, dir), d) }
        }
        return out
    }

    /// Whether it can get from `a` to anywhere by `b` at all.
    func canReach(from a: Anchor, dir: CGFloat, to b: Anchor) -> Bool {
        reachable(from: a, dir: dir)(b)
    }

    /// Everywhere it can get to from `a` (going `dir`), to ask of one place
    /// after another: whether it can get to anywhere by each.
    func reachable(from a: Anchor, dir: CGFloat) -> (Anchor) -> Bool {
        let from = Set(entries(a, dir: dir).map { part[Int($0.s)] })
        // (Nowhere to start from — a scrap too small to have spots: as far
        // as it knows, it can.)
        guard !from.isEmpty else { return { _ in true } }
        var bits = [UInt64](repeating: 0, count: (partEdges.count + 63) / 64)
        for c in from { for (i, w) in reach(c).enumerated() { bits[i] |= w } }
        return { [self] b in
            guard let (l, y) = self.locate(b) else { return true }
            let (u, v) = self.around(l, y)
            for n in [u, v] {
                guard let n else { continue }
                for s in [TankNav.state(n, 1), TankNav.state(n, -1)] {
                    let c = Int(self.part[Int(s)])
                    if bits[c / 64] & (1 << UInt64(c % 64)) != 0 { return true }
                }
            }
            return false
        }
    }

    // MARK: The way there

    /// A way from where it is to a goal: the states it goes through, from
    /// the one it gets onto the ways in, and the edge into each after that.
    struct Plan {
        var states: [Int32] = []
        var vias: [Int32] = []
        var cost: Float = 0
        var start: Anchor
        var goal: Anchor
        var within: CGFloat
        /// Straight there along what it is on, no ways needed: which way.
        var direct: CGFloat?
    }

    // (Kept between questions: asked on the main thread only.)
    private var g: [Float] = []
    private var via: [Int32] = []
    private var prev: [Int32] = []
    private var touched: [Int32] = []
    private var heapF: [Float] = []
    private var heapS: [Int32] = []

    /// The cheapest way from `start` (going `dir`) to within `within` of
    /// `goal`, given how it leans (`NavLean`); nil if there is none.
    func plan(from start: Anchor, dir: CGFloat, to goal: Anchor, within: CGFloat, lean: NavLean) -> Plan? {
        guard let (gl, gy) = locate(goal) else { return nil }
        let S = states
        if g.count != S {
            g = [Float](repeating: .infinity, count: S)
            via = [Int32](repeating: -1, count: S)
            prev = [Int32](repeating: -1, count: S)
        }
        for s in touched { g[Int(s)] = .infinity; via[Int(s)] = -1; prev[Int(s)] = -1 }
        touched.removeAll(keepingCapacity: true)
        heapF.removeAll(keepingCapacity: true)
        heapS.removeAll(keepingCapacity: true)

        var result = Plan(start: start, goal: goal, within: within)
        var best = Float.infinity
        var bestState: Int32 = -1
        // Along what it is on, straight there.
        if let (sl, sx) = locate(start), sl == gl {
            for d in [dir, -dir] {
                guard let w = walk(sl, from: sx, to: gy, dir: d) else { continue }
                let c = Float(max(0, w - within)) + (d == dir || w <= within ? 0 : TankNav.turnCost)
                if c < best { best = c; result.direct = d }
            }
        }
        // Where it could get off the ways, and what is left from each.
        var goalExtra: [Int32: Float] = [:]
        let reachOut = max(within, 0) + TankNav.spacing * 1.5
        for n in loopNodes[gl] {
            let x = nodes[Int(n)].along
            var sep = abs(x - gy)
            if closed[gl] { sep = min(sep, perimeter[gl] - sep) }
            guard sep <= reachOut else { continue }
            for d in [CGFloat(1), -1] {
                let s = TankNav.state(n, d)
                guard !noStop[Int(s)] else { continue }
                var extra = Float.infinity
                if let w = walk(gl, from: x, to: gy, dir: d) { extra = Float(max(0, w - within)) }
                if let w = walk(gl, from: x, to: gy, dir: -d) {
                    extra = min(extra, w <= within ? 0 : Float(w - within) + TankNav.turnCost)
                }
                if extra < .infinity { goalExtra[s] = extra }
            }
        }
        // Where that is (between the spots either side of it).
        var gp = V2.zero
        let (gu, gv) = around(gl, gy)
        if let gu, let gv, let span = walk(gl, from: nodes[Int(gu)].along, to: nodes[Int(gv)].along, dir: 1), span > 0.01,
           let part = walk(gl, from: nodes[Int(gu)].along, to: gy, dir: 1) {
            gp = V2.lerp(nodes[Int(gu)].p, nodes[Int(gv)].p, min(part / span, 1))
        } else if let n = gu ?? gv {
            gp = nodes[Int(n)].p
        }
        // (Where its own surface has nowhere there it could stop — a scrap
        // between two others, say — anywhere right by it on something else.
        // Only right by it: never the other side of a plank.)
        let close = min(within, 16) + 4
        if goalExtra.isEmpty {
            file.each(near: gp, within: close) { k in
                let n = nodes[k]
                guard Int(n.loop) != gl else { return }
                let d = n.p.distance(to: gp)
                guard d <= close else { return }
                for dir in [CGFloat(1), -1] {
                    let s = TankNav.state(Int32(k), dir)
                    guard !noStop[Int(s)] else { continue }
                    let ex = Float(max(0, d - within))
                    if ex < goalExtra[s] ?? .infinity { goalExtra[s] = ex }
                }
            }
        }
        let hScale = Float(min(1, 0.8 * CGFloat(lean.leap)))
        func h(_ s: Int32) -> Float {
            let p = nodes[Int(s) / 2].p
            return hScale * Float(max(0, p.distance(to: gp) - within - TankNav.spacing))
        }
        func push(_ s: Int32, _ f: Float) {
            heapF.append(f); heapS.append(s)
            var i = heapF.count - 1
            while i > 0 {
                let p = (i - 1) / 2
                if heapF[p] <= heapF[i] { break }
                heapF.swapAt(p, i); heapS.swapAt(p, i)
                i = p
            }
        }
        func pop() -> (Float, Int32)? {
            guard let top = heapF.first else { return nil }
            let s = heapS[0]
            let lastF = heapF.removeLast(), lastS = heapS.removeLast()
            if !heapF.isEmpty {
                heapF[0] = lastF; heapS[0] = lastS
                var i = 0
                let n = heapF.count
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < n, heapF[l] < heapF[m] { m = l }
                    if r < n, heapF[r] < heapF[m] { m = r }
                    if m == i { break }
                    heapF.swapAt(m, i); heapS.swapAt(m, i)
                    i = m
                }
            }
            return (top, s)
        }
        for (s, c, v) in entries(start, dir: dir) where c < g[Int(s)] {
            if g[Int(s)] == .infinity { touched.append(s) }
            g[Int(s)] = c
            via[Int(s)] = v
            prev[Int(s)] = -1
            push(s, c + h(s))
        }
        var popped = 0
        while let (f, s) = pop() {
            if f >= best { break }
            let gs = g[Int(s)]
            if f > gs + h(s) + 0.01 { continue }   // (a stale entry)
            popped += 1
            if let ex = goalExtra[s], gs + ex < best {
                best = gs + ex
                bestState = s
                result.direct = nil
            }
            for e in Int(first[Int(s)])..<Int(first[Int(s) + 1]) {
                let ed = edges[e]
                var c = ed.cost
                switch ed.kind {
                case .hop:
                    if !lean.hops.isEmpty { c *= lean.hops[Int(ed.ref)] }
                    if lean.keepOff.contains(hops[Int(ed.ref)].onto) { c = c * lean.keepOffCost + 150 }
                case .leap:
                    c *= lean.leap
                    if lean.keepOff.contains(leaps[Int(ed.ref)].onto) { c = c * lean.keepOffCost + 150 }
                default:
                    break
                }
                if let p = lean.penalty[Int32(e)] { c += p }
                guard c < .infinity else { continue }
                let ng = gs + c
                let t = Int(ed.to)
                if ng < g[t] {
                    if g[t] == .infinity { touched.append(ed.to) }
                    g[t] = ng
                    via[t] = Int32(e)
                    prev[t] = s
                    push(ed.to, ng + h(ed.to))
                }
            }
        }
        lastPopped = popped
        if bestState < 0 {
            guard result.direct != nil else { return nil }
            result.cost = best
            return result
        }
        var path: [Int32] = [], vias: [Int32] = []
        var s = bestState
        while s >= 0 {
            path.append(s)
            vias.append(via[Int(s)])
            s = prev[Int(s)]
        }
        result.states = path.reversed()
        result.vias = vias.reversed()
        result.cost = best
        return result
    }
    /// Tools: how many states the last question went through.
    private(set) var lastPopped = 0

    /// The next thing to do on a way: a walk (over onto the next surface,
    /// and on, at each of `hops`) to stop at `to`; a leap; a door.
    enum Leg {
        case walk(dir: CGFloat, to: Anchor, within: CGFloat, hops: [SurfaceJunction], hopEdges: [Int32], length: CGFloat)
        case leap(edge: Int32, aim: V2)
        case door(edge: Int32, at: V2)
    }

    /// The first leg of `plan`, from `here`.
    func leg(of plan: Plan, from here: Anchor) -> Leg? {
        if let d = plan.direct {
            guard let (l, x) = locate(here), let (gl, y) = locate(plan.goal), l == gl else { return nil }
            return .walk(dir: d, to: plan.goal, within: plan.within, hops: [], hopEdges: [], length: walk(l, from: x, to: y, dir: d) ?? 0)
        }
        guard let s0 = plan.states.first, let (l, x) = locate(here) else { return nil }
        let n0 = nodes[Int(s0) / 2]
        var i = 0
        var length: CGFloat = 0
        var hops: [SurfaceJunction] = [], hopEdges: [Int32] = []
        var sep = abs(n0.along - x)
        if closed[l] { sep = min(sep, perimeter[l] - sep) }
        let firstVia = plan.vias.first ?? -1
        let atFirst = firstVia < 0 && Int(n0.loop) == l && sep <= TankNav.near
        if firstVia >= 0 {
            // Straight on over onto another surface, where it meets this one
            // just ahead (or behind).
            let hp = self.hops[Int(edges[Int(firstVia)].ref)]
            hops.append(hp.junction)
            hopEdges.append(firstVia)
            length = walk(l, from: x, to: nodes[Int(hp.at)].along, dir: TankNav.dir(of: s0)) ?? 0
        } else if atFirst {
            if plan.states.count > 1 {
                let e = plan.vias[1]
                let ed = edges[Int(e)]
                switch ed.kind {
                case .leap: return .leap(edge: e, aim: leaps[Int(ed.ref)].aim)
                case .door: return .door(edge: e, at: doors[Int(ed.ref)].at)
                case .turn:
                    i = 1
                    if plan.states.count > 2 {
                        let e2 = plan.vias[2], ed2 = edges[Int(e2)]
                        if ed2.kind == .leap { return .leap(edge: e2, aim: leaps[Int(ed2.ref)].aim) }
                        if ed2.kind == .door { return .door(edge: e2, at: doors[Int(ed2.ref)].at) }
                    }
                default: break
                }
            }
        } else {
            guard Int(n0.loop) == l, let w = walk(l, from: x, to: n0.along, dir: TankNav.dir(of: s0)) else { return nil }
            length = w
        }
        let dir = TankNav.dir(of: plan.states[i])
        var j = i
        while j + 1 < plan.states.count {
            let e = plan.vias[j + 1]
            let ed = edges[Int(e)]
            guard ed.kind == .walk || ed.kind == .hop, TankNav.dir(of: plan.states[j + 1]) == dir else { break }
            if ed.kind == .hop {
                hops.append(self.hops[Int(ed.ref)].junction)
                hopEdges.append(e)
            }
            length += CGFloat(ed.cost)
            j += 1
        }
        let last = plan.states[j]
        let nl = nodes[Int(last) / 2]
        // At the end of the way, on to the goal itself — on ahead, or, if it
        // is there at the end of the way already, back round to it.
        if j == plan.states.count - 1, let (gl, y) = locate(plan.goal), gl == Int(nl.loop) {
            let on = walk(gl, from: nl.along, to: y, dir: dir), back = walk(gl, from: nl.along, to: y, dir: -dir)
            let onCost = on.map { max(0, $0 - plan.within) } ?? .greatestFiniteMagnitude
            let backCost = back.map { $0 <= plan.within ? 0 : $0 - plan.within + CGFloat(TankNav.turnCost) } ?? .greatestFiniteMagnitude
            if onCost <= backCost, let on {
                return .walk(dir: dir, to: plan.goal, within: plan.within, hops: hops, hopEdges: hopEdges, length: length + on)
            }
            if length < 1, hops.isEmpty, let back {
                return .walk(dir: -dir, to: plan.goal, within: plan.within, hops: [], hopEdges: [], length: back)
            }
        }
        return .walk(dir: dir, to: anchor(of: Int32(Int(last) / 2)), within: 3, hops: hops, hopEdges: hopEdges, length: length)
    }

    /// Tools: a plan, step by step — each state as loop@how far round it,
    /// and which way it is going; each way by its kind and cost.
    func describe(_ plan: Plan) -> String {
        if let d = plan.direct { return String(format: "straight %+.0f", Double(d)) }
        var out: [String] = []
        for (k, s) in plan.states.enumerated() {
            let n = nodes[Int(s) / 2]
            if plan.vias[k] >= 0 {
                let e = edges[Int(plan.vias[k])]
                out.append(String(format: "-%@ %.0f->", "\(e.kind)", Double(e.cost)))
            }
            out.append(String(format: "%@@%.0f%@", loopIDs[Int(n.loop)], Double(n.along), TankNav.dir(of: s) > 0 ? "+" : "-"))
        }
        return out.joined(separator: " ")
    }

    /// Tools: what it came to.
    var debugSummary: String {
        var kinds: [Kind: Int] = [:]
        for e in edges { kinds[e.kind, default: 0] += 1 }
        let parts = Set(part).count
        return String(format: "%d loops, %d spots, %d ways (walk %d, turn %d, hop %d, leap %d, door %d), %d parts, %.0f ms",
                      loopIDs.count, nodes.count, edges.count, kinds[.walk] ?? 0, kinds[.turn] ?? 0, kinds[.hop] ?? 0,
                      kinds[.leap] ?? 0, kinds[.door] ?? 0, parts, buildTime * 1000)
    }
}

// MARK: - Spots, filed by square

/// The spots, filed by the squares they are in, to find those near a point.
private final class NodeFile {
    let cell: CGFloat
    private var cells: [Int64: [Int32]] = [:]
    private let p: [V2]
    init(nodes: [TankNav.Node], cell: CGFloat) {
        self.cell = cell
        p = nodes.map(\.p)
        for (i, n) in nodes.enumerated() { cells[key(n.p), default: []].append(Int32(i)) }
    }
    private func key(_ q: V2) -> Int64 { key(Int((q.x / cell).rounded(.down)), Int((q.y / cell).rounded(.down))) }
    private func key(_ cx: Int, _ cy: Int) -> Int64 { Int64(cx) << 32 | Int64(UInt32(bitPattern: Int32(cy))) }
    func each(near q: V2, within r: CGFloat, _ body: (Int) -> Void) {
        let x0 = Int(((q.x - r) / cell).rounded(.down)), x1 = Int(((q.x + r) / cell).rounded(.down))
        let y0 = Int(((q.y - r) / cell).rounded(.down)), y1 = Int(((q.y + r) / cell).rounded(.down))
        for cx in x0...x1 {
            for cy in y0...y1 {
                guard let list = cells[key(cx, cy)] else { continue }
                for i in list { body(Int(i)) }
            }
        }
    }
}

// MARK: - A leap, flown beforehand

/// Flies leaps the way the spider flies them, to see where each comes down
/// (see `Spider.updateAirborne`, and `leapBlocked`): what it would catch
/// hold of on the way, found from the surfaces filed by square.
private final class Flight {
    let scale: CGFloat
    let air: CGRect
    private let cell: CGFloat = 32
    private let origin: V2
    private let cols: Int, rows: Int
    // The body lines, to catch hold of.
    private let bodyCells: [[Int32]]
    private let bodyLoop: [Int32], bodySeg: [Int32]
    private let bodyA: [V2], bodyB: [V2]
    private let bodyLen: [CGFloat], bodyCum: [CGFloat]
    // The edges of things, to leap through or not.
    private let edgeCells: [[Int32]]
    private let edgeLoop: [Int32]
    private let edgeA: [V2], edgeB: [V2]
    private let loopBox: [CGRect]
    private var stamp: [Int32]
    private var edgeStamp: [Int32]
    private var mark: Int32 = 0
    private var cands: [Int32] = []

    init(map: SurfaceMap, loops: [SurfaceLoop], scale sc: CGFloat) {
        scale = sc
        air = map.screenFrame(containing: V2(map.worldBounds.midX, map.worldBounds.midY))
        let world = map.worldBounds.insetBy(dx: -200, dy: -200)
        origin = V2(world.minX, world.minY)
        cols = max(1, Int((world.width / cell).rounded(.up)))
        rows = max(1, Int((world.height / cell).rounded(.up)))
        var bl: [Int32] = [], bs: [Int32] = [], ba: [V2] = [], bb: [V2] = [], blen: [CGFloat] = [], bcum: [CGFloat] = []
        var el: [Int32] = [], ea: [V2] = [], eb: [V2] = []
        for (li, l) in loops.enumerated() {
            var c: CGFloat = 0
            for (si, s) in l.segs.enumerated() {
                bl.append(Int32(li)); bs.append(Int32(si)); ba.append(s.a); bb.append(s.b); blen.append(s.len); bcum.append(c)
                c += s.len
            }
            for e in l.edge { el.append(Int32(li)); ea.append(e.a); eb.append(e.b) }
        }
        bodyLoop = bl; bodySeg = bs; bodyA = ba; bodyB = bb; bodyLen = blen; bodyCum = bcum
        edgeLoop = el; edgeA = ea; edgeB = eb
        loopBox = loops.map(\.rect)
        stamp = [Int32](repeating: 0, count: bl.count)
        edgeStamp = [Int32](repeating: 0, count: el.count)
        let (c, o, nx, ny) = (cell, origin, cols, rows)
        func file(_ cells: inout [[Int32]], _ a: V2, _ b: V2, _ i: Int32) {
            for cx in Flight.span(min(a.x, b.x), max(a.x, b.x), o.x, nx, c) {
                for cy in Flight.span(min(a.y, b.y), max(a.y, b.y), o.y, ny, c) { cells[cy * nx + cx].append(i) }
            }
        }
        var bc: [[Int32]] = Array(repeating: [], count: nx * ny)
        var ec: [[Int32]] = Array(repeating: [], count: nx * ny)
        for i in bl.indices { file(&bc, ba[i], bb[i], Int32(i)) }
        for i in el.indices { file(&ec, ea[i], eb[i], Int32(i)) }
        bodyCells = bc
        edgeCells = ec
    }

    /// The squares from `lo` to `hi` along one side.
    private static func span(_ lo: CGFloat, _ hi: CGFloat, _ o: CGFloat, _ n: Int, _ cell: CGFloat) -> ClosedRange<Int> {
        let a = clamp(Int(((lo - o) / cell).rounded(.down)), 0, n - 1)
        let b = clamp(Int(((hi - o) / cell).rounded(.down)), 0, n - 1)
        return a...max(a, b)
    }
    private func range(_ lo: CGFloat, _ hi: CGFloat, _ o: CGFloat, _ n: Int) -> ClosedRange<Int> { Flight.span(lo, hi, o, n, cell) }

    /// `SurfaceMap.nearestSpot`: the nearest point of any body line within
    /// `r` of `p` (not on loop `excluding`) — which, and where.
    private func nearest(to p: V2, within r: CGFloat, excluding: Int32) -> (i: Int, t: CGFloat, d: CGFloat)? {
        mark &+= 1
        var best: (i: Int, t: CGFloat, d: CGFloat)?
        var bestD = r
        cands.removeAll(keepingCapacity: true)
        for cx in range(p.x - r, p.x + r, origin.x, cols) {
            for cy in range(p.y - r, p.y + r, origin.y, rows) {
                for i in bodyCells[cy * cols + cx] where stamp[Int(i)] != mark {
                    stamp[Int(i)] = mark
                    cands.append(i)
                }
            }
        }
        // (In the map's own order, so a tie goes the same way.)
        cands.sort()
        for i in cands {
            let k = Int(i)
            if bodyLoop[k] == excluding { continue }
            let (t, d) = projectOnSegment(p, bodyA[k], bodyB[k])
            if d < bestD { bestD = d; best = (k, t, d) }
        }
        return best
    }

    struct Landing { var loop: Int32; var seg: Int32; var along: CGFloat; var point: V2; var vel: V2 }

    /// Where a leap from `p` launched at `launch` comes down, flown frame by
    /// frame as `Spider.updateAirborne` flies it — if it comes down cleanly
    /// near `target`, passing nothing else it might catch hold of first.
    func fly(from p: V2, launch: V2, launchLoop: Int32, target: V2) -> Landing? {
        let dt: CGFloat = 1.0 / 60
        var pos = p, vel = launch
        var airTime: CGFloat = 0, noAttachFor: CGFloat = 0.1
        let g = Spider.gravityPull
        let pad = 14 * scale
        // (A hair more than its reach: a leap that would only just miss
        // something on the way is not one to count on.)
        let margin: CGFloat = 3
        let near = 40 * scale + 16
        func landing(_ k: Int, _ t: CGFloat) -> Landing {
            let s = bodyA[k] + (bodyB[k] - bodyA[k]).normalized * t
            return Landing(loop: bodyLoop[k], seg: bodySeg[k], along: bodyCum[k] + t, point: s, vel: vel)
        }
        while airTime < 1.5 {
            airTime += dt
            noAttachFor = max(0, noAttachFor - dt)
            vel += g * dt
            vel *= exp(-0.22 * dt)
            pos += vel * dt
            // The tank's rim, as a backstop (see `bounceOffScreens`): a leap
            // doesn't bounce; it takes the nearest spot there.
            let f = air
            let hitRim = (pos.x < f.minX + pad && vel.x < 0) || (pos.x > f.maxX - pad && vel.x > 0)
                || (pos.y > f.maxY - pad && vel.y > 0) || (pos.y < f.minY + pad && vel.y < 0)
            if hitRim {
                guard let s = nearest(to: pos, within: 90, excluding: -1) else { return nil }
                let l = landing(s.i, s.t)
                return l.point.distance(to: target) < near ? l : nil
            }
            guard noAttachFor <= 0 else { continue }
            let reach = max(18 * scale, vel.length * dt * 0.8)
            let excl: Int32 = airTime < 0.28 ? launchLoop : -1
            if let w = nearest(to: pos, within: reach + margin, excluding: excl) {
                let q = landing(w.i, w.t)
                // Anything else, that near on the way: not a clean leap.
                guard q.point.distance(to: target) < near else { return nil }
                if w.d < reach {
                    let toward = (q.point - pos).normalized.dot(vel.normalized)
                    if vel.length < 260 || toward > -0.25 { return q }
                }
            }
        }
        return nil
    }

    /// `SurfaceMap.arcBlocked`, the edges found by square.
    func blocked(from a: V2, launch: V2, to b: V2) -> Bool {
        let gravity = Spider.gravityPull
        var pts: [V2] = []
        var best = CGFloat.greatestFiniteMagnitude
        var t: CGFloat = 0
        while t < 3 {
            let p = a + launch * t + gravity * (0.5 * t * t)
            let d = p.distance(to: b)
            pts.append(p)
            if d < best { best = d } else if d > best + 30 { break }
            t += 1.0 / 30
        }
        guard pts.count >= 2 else { return false }
        let box = Poly.bounds(pts).insetBy(dx: -2, dy: -2)
        var crossings: [CGFloat] = []
        var run: CGFloat = 0
        for i in 1..<pts.count {
            let p = pts[i - 1], q = pts[i]
            let r = q - p, len = r.length
            mark &+= 1
            cands.removeAll(keepingCapacity: true)
            for cx in range(min(p.x, q.x), max(p.x, q.x), origin.x, cols) {
                for cy in range(min(p.y, q.y), max(p.y, q.y), origin.y, rows) {
                    for e in edgeCells[cy * cols + cx] where edgeStamp[Int(e)] != mark {
                        edgeStamp[Int(e)] = mark
                        cands.append(e)
                    }
                }
            }
            for e in cands {
                let k = Int(e)
                let lb = loopBox[Int(edgeLoop[k])]
                guard lb.isNull || lb.insetBy(dx: -4, dy: -4).intersects(box) else { continue }
                let ea = edgeA[k], eb = edgeB[k]
                let s = eb - ea
                let den = r.cross(s)
                guard abs(den) > 1e-9 else { continue }
                let w = ea - p
                let u = w.cross(s) / den, v = w.cross(r) / den
                if u >= 0, u <= 1, v >= 0, v <= 1 { crossings.append(run + u * len) }
            }
            run += len
        }
        let inner = crossings.filter { $0 > 10 && $0 < run - 10 }.sorted()
        var k = 0
        while k + 1 < inner.count {
            if inner[k + 1] - inner[k] >= 6 { return true }
            k += 2
        }
        return false
    }
}

extension SurfaceMap {
    /// Whether a leap launched at `launch` from `a`, meant to come down at
    /// `b`, would pass right through something solid on the way — in one
    /// side and out the other through more than a few points of it (a twig
    /// or a vine it could brush past; a wall, never).
    func arcBlocked(from a: V2, launch: V2, to b: V2) -> Bool {
        let gravity = Spider.gravityPull
        // The arc, a few dozen points along it, as far as its nearest to `b`.
        var pts: [V2] = []
        var best = CGFloat.greatestFiniteMagnitude
        var t: CGFloat = 0
        while t < 3 {
            let p = a + launch * t + gravity * (0.5 * t * t)
            let d = p.distance(to: b)
            pts.append(p)
            if d < best { best = d } else if d > best + 30 { break }
            t += 1.0 / 30
        }
        guard pts.count >= 2 else { return false }
        // Every place it crosses the outline of something, by how far along.
        var crossings: [CGFloat] = []
        var run: CGFloat = 0
        let box = Poly.bounds(pts).insetBy(dx: -2, dy: -2)
        let near = loops.filter { $0.rect.isNull || $0.rect.insetBy(dx: -4, dy: -4).intersects(box) }
        for i in 1..<pts.count {
            let p = pts[i - 1], q = pts[i]
            let r = q - p, len = r.length
            for loop in near {
                for e in loop.edge {
                    guard max(e.a.x, e.b.x) >= box.minX, min(e.a.x, e.b.x) <= box.maxX,
                          max(e.a.y, e.b.y) >= box.minY, min(e.a.y, e.b.y) <= box.maxY else { continue }
                    let s = e.b - e.a
                    let den = r.cross(s)
                    guard abs(den) > 1e-9 else { continue }
                    let w = e.a - p
                    let u = w.cross(s) / den, v = w.cross(r) / den
                    if u >= 0, u <= 1, v >= 0, v <= 1 { crossings.append(run + u * len) }
                }
            }
            run += len
        }
        // (Not what it takes off from or lands on.)
        let inner = crossings.filter { $0 > 10 && $0 < run - 10 }.sorted()
        var k = 0
        while k + 1 < inner.count {
            if inner[k + 1] - inner[k] >= 6 { return true }
            k += 2
        }
        return false
    }
}
