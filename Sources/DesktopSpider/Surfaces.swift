import AppKit
import CoreGraphics

// MARK: - Surface model
//
// Everything the spider can cling to is a polyline of segments in AppKit global
// coordinates (origin bottom-left of the primary display, +y up).
//
// A loop's geometry is the *body centreline*, not the raw edge: screen borders
// are inset so the spider stays visible, window borders are straddled so the
// legs grip both sides, and the menu bar / dock lines are offset so the body
// sits just under / just above them.

enum SurfaceKind {
    case screenBorder
    case windowEdge
    case dock
    case menuBar

    /// How much the spider likes to hang out here when picking a jump target.
    var appeal: CGFloat {
        switch self {
        case .screenBorder: return 1.0
        case .windowEdge:   return 1.7
        case .dock:         return 1.35
        case .menuBar:      return 1.25
        }
    }
}

/// Which way the segment's edge faces. Used for orienting webs and for deciding
/// whether the spider is standing on top of something or hanging beneath it.
enum EdgeFacing {
    case up      // spider stands on top of this edge
    case down    // spider hangs beneath this edge (good web anchor)
    case left
    case right

    var normal: V2 {
        switch self {
        case .up:    return V2(0, 1)
        case .down:  return V2(0, -1)
        case .left:  return V2(-1, 0)
        case .right: return V2(1, 0)
        }
    }
}

struct Seg {
    let a: V2
    let b: V2
    let facing: EdgeFacing
    let dir: V2
    let len: CGFloat
    /// Stretches of this edge, as t-ranges, that a window in front covers.
    /// The spider cannot walk into them, so an edge that disappears behind
    /// another window ends there — it turns back or jumps, and is never drawn
    /// on top of something it is supposed to be behind. Sorted and merged.
    var blocked: [(lo: CGFloat, hi: CGFloat)] = []

    /// Endpoints are ordered so that the outward normal is always 90 degrees
    /// counter-clockwise of the direction of travel. The spider's sprite frame
    /// is built from that relationship — +x along the edge, +y away from it —
    /// so an edge wired up backwards would stand it on its head.
    init(_ a: V2, _ b: V2, _ facing: EdgeFacing) {
        let forward = (b - a).normalized
        let flip = forward.rotated(by: .pi / 2).dot(facing.normal) < 0
        self.a = flip ? b : a
        self.b = flip ? a : b
        self.facing = facing
        let d = self.b - self.a
        self.len = d.length
        self.dir = d.normalized
    }

    func point(at t: CGFloat) -> V2 { a + dir * clamp(t, 0, len) }
    var normal: V2 { facing.normal }
    /// Heading angle when travelling in +t.
    var angle: CGFloat { dir.angle }

    func isOpen(at t: CGFloat) -> Bool {
        !blocked.contains { t > $0.lo && t < $0.hi }
    }

    /// How far along the edge you can get from `t` heading in `dir` before a
    /// covered stretch (or the end of the edge) stops you.
    func limit(from t: CGFloat, dir: CGFloat) -> CGFloat {
        if dir > 0 {
            var lim = len
            for b in blocked where b.lo >= t - 0.01 && b.lo < lim { lim = b.lo }
            return max(lim, t)
        } else {
            var lim: CGFloat = 0
            for b in blocked where b.hi <= t + 0.01 && b.hi > lim { lim = b.hi }
            return min(lim, t)
        }
    }

    /// The t-range of this edge that lies inside a rect, if any.
    func span(inside r: CGRect) -> (CGFloat, CGFloat)? {
        var lo: CGFloat = 0, hi = len
        for (p0, d, mn, mx) in [(a.x, dir.x, r.minX, r.maxX), (a.y, dir.y, r.minY, r.maxY)] {
            if abs(d) < 1e-9 {
                if p0 < mn || p0 > mx { return nil }
            } else {
                var t0 = (mn - p0) / d, t1 = (mx - p0) / d
                if t0 > t1 { swap(&t0, &t1) }
                lo = max(lo, t0)
                hi = min(hi, t1)
            }
        }
        return lo < hi ? (lo, hi) : nil
    }

    mutating func block(_ range: (CGFloat, CGFloat)) {
        blocked.append((lo: range.0, hi: range.1))
        blocked.sort { $0.lo < $1.lo }
        var merged: [(lo: CGFloat, hi: CGFloat)] = []
        for b in blocked {
            if let last = merged.last, b.lo <= last.hi {
                merged[merged.count - 1].hi = max(last.hi, b.hi)
            } else {
                merged.append(b)
            }
        }
        blocked = merged
    }
}

struct SurfaceLoop {
    let id: String
    let kind: SurfaceKind
    /// The path the body's origin follows: the edge, stood off by the height
    /// of the body.
    let segs: [Seg]
    /// The edge itself, where the feet go.
    var edge: [Seg] = []
    /// A closed loop lets the spider walk around corners forever.
    let closed: Bool
    /// Occlusion order. Smaller is closer to the viewer.
    let depth: Int
    /// Source rect, for window loops (used to detect movement).
    let rect: CGRect

    var perimeter: CGFloat { segs.reduce(0) { $0 + $1.len } }
}

/// A resolved spot on a surface.
struct Anchor {
    var loopID: String
    var segIdx: Int
    var t: CGFloat
    /// +1 walking toward seg.b, -1 toward seg.a
    var dir: CGFloat = 1
}

// MARK: - Surface map

final class SurfaceMap {
    private(set) var loops: [SurfaceLoop] = []
    private(set) var byID: [String: SurfaceLoop] = [:]
    /// Front-to-back window rects for occlusion tests.
    private(set) var occluders: [(rect: CGRect, depth: Int)] = []
    /// Union of all screens.
    private(set) var worldBounds: CGRect = .zero
    private(set) var screenFrames: [CGRect] = []

    /// Height of the body's origin above the surface it is standing on. Loops
    /// store that line rather than the raw edge, so the spider's feet land on
    /// the edge itself. Set from the size setting.
    var standoff: CGFloat = 22

    func rebuild(windows: [TrackedWindow]) {
        let off = standoff
        var newLoops: [SurfaceLoop] = []
        var frames: [CGRect] = []

        // --- Screens ---------------------------------------------------------
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            frames.append(f)
            let r = f.insetBy(dx: off, dy: off)
            guard r.width > 60, r.height > 60 else { continue }

            let bl = V2(r.minX, r.minY), br = V2(r.maxX, r.minY)
            let tr = V2(r.maxX, r.maxY), tl = V2(r.minX, r.maxY)
            // Walking the inside of the frame: along the bottom, up the right,
            // back along the top, down the left.
            let segs = [
                Seg(bl, br, .up),
                Seg(br, tr, .left),
                Seg(tr, tl, .down),
                Seg(tl, bl, .right),
            ]
            var screenLoop = SurfaceLoop(id: "screen:\(i)", kind: .screenBorder, segs: segs,
                                         closed: true, depth: 1_000_000, rect: r)
            screenLoop.edge = SurfaceMap.rectEdge(f, inside: true)
            newLoops.append(screenLoop)

            // --- Menu bar (hang from its lower lip) --------------------------
            let vf = screen.visibleFrame
            let menuBarHeight = f.maxY - vf.maxY
            if menuBarHeight > 12 {
                let y = vf.maxY - off
                let inset: CGFloat = 90 // stay clear of the notch / status items edge
                let seg = Seg(V2(f.minX + inset, y), V2(f.maxX - inset, y), .down)
                if seg.len > 100 {
                    var loop = SurfaceLoop(id: "menu:\(i)", kind: .menuBar, segs: [seg],
                                           closed: false, depth: -20, rect: .zero)
                    loop.edge = [Seg(V2(f.minX, vf.maxY), V2(f.maxX, vf.maxY), .down)]
                    newLoops.append(loop)
                }
            }
        }
        screenFrames = frames
        worldBounds = frames.reduce(CGRect.null) { $0.union($1) }

        // --- Dock ------------------------------------------------------------
        for (i, dock) in dockStrips().enumerated() {
            // Only the top surface is interesting: the spider walks on the dock.
            let y = dock.maxY + off
            let seg = Seg(V2(dock.minX + 6, y), V2(dock.maxX - 6, y), .up)
            if seg.len > 60 {
                var loop = SurfaceLoop(id: "dock:\(i)", kind: .dock, segs: [seg],
                                       closed: false, depth: -10, rect: dock)
                loop.edge = [Seg(V2(dock.minX, dock.maxY), V2(dock.maxX, dock.maxY), .up)]
                newLoops.append(loop)
            }
        }

        // --- Windows ---------------------------------------------------------
        var occ: [(CGRect, Int)] = []
        for w in windows {
            let r = w.frame
            occ.append((r, w.depth))
            guard r.width > 130, r.height > 90 else { continue }
            // The whole perimeter, as one loop: it walks along the top like a
            // shelf, round the corner and down the side, and hangs under the
            // bottom. The path stands off the border by the height of the body
            // so the feet land on the edge itself and nothing covers content.
            // Clockwise on screen with normals pointing outward, which is what
            // makes the sprite stand on the top and hang beneath the bottom.
            let o = r.insetBy(dx: -off, dy: -off)
            let tl = V2(o.minX, o.maxY), tr = V2(o.maxX, o.maxY)
            let br = V2(o.maxX, o.minY), bl = V2(o.minX, o.minY)
            let segs = [
                Seg(tl, tr, .up),
                Seg(tr, br, .right),
                Seg(br, bl, .down),
                Seg(bl, tl, .left),
            ]
            var loop = SurfaceLoop(id: "win:\(w.id)", kind: .windowEdge, segs: segs,
                                   closed: true, depth: w.depth, rect: r)
            loop.edge = SurfaceMap.rectEdge(r, inside: false)
            newLoops.append(loop)
        }
        occluders = occ.map { (rect: $0.0, depth: $0.1) }

        applyBlocks(to: &newLoops)

        loops = newLoops
        var map: [String: SurfaceLoop] = [:]
        for l in newLoops { map[l.id] = l }
        byID = map
    }

    /// Anything in front of an edge blocks it. Rects are grown by about the
    /// body's reach so it stops short of the covering window rather than
    /// walking up to it with its abdomen poking over the top.
    private func applyBlocks(to newLoops: inout [SurfaceLoop]) {
        let grow = standoff * 1.4
        for li in newLoops.indices {
            let depth = newLoops[li].depth
            var segs = newLoops[li].segs
            for o in occluders where o.depth < depth {
                let r = o.rect.insetBy(dx: -grow, dy: -grow)
                for si in segs.indices {
                    if let span = segs[si].span(inside: r) { segs[si].block(span) }
                }
            }
            var rebuilt = SurfaceLoop(id: newLoops[li].id, kind: newLoops[li].kind, segs: segs,
                                      closed: newLoops[li].closed, depth: depth,
                                      rect: newLoops[li].rect)
            rebuilt.edge = newLoops[li].edge
            newLoops[li] = rebuilt
        }
    }

    /// The four sides of a rect as edge segments, with normals pointing in
    /// (a screen you are inside) or out (a window you are on).
    static func rectEdge(_ r: CGRect, inside: Bool) -> [Seg] {
        let bl = V2(r.minX, r.minY), br = V2(r.maxX, r.minY)
        let tr = V2(r.maxX, r.maxY), tl = V2(r.minX, r.maxY)
        if inside {
            return [Seg(bl, br, .up), Seg(br, tr, .left), Seg(tr, tl, .down), Seg(tl, bl, .right)]
        }
        return [Seg(tl, tr, .up), Seg(tr, br, .right), Seg(br, bl, .down), Seg(bl, tl, .left)]
    }

    /// The nearest point on the actual edge of a loop — where a foot should
    /// rest. Around a corner this wraps onto the next side, which is what
    /// keeps the feet on the window while the body swings round it.
    func snapToEdge(_ p: V2, loopID: String) -> V2? {
        guard let loop = byID[loopID] else { return nil }
        var best: V2?
        var bestD = CGFloat.greatestFiniteMagnitude
        for s in loop.edge {
            let (t, d) = projectOnSegment(p, s.a, s.b)
            if d < bestD {
                bestD = d
                best = s.point(at: t)
            }
        }
        return best
    }

    /// Builds a map for an arbitrary rectangle instead of the real displays,
    /// so tooling can lay the spider out on a mock desktop.
    func debugRebuild(screen: CGRect, menuBarHeight: CGFloat, windows: [TrackedWindow]) {
        let off = standoff
        var newLoops: [SurfaceLoop] = []
        let r = screen.insetBy(dx: off, dy: off)
        var screenLoop = SurfaceLoop(id: "screen:0", kind: .screenBorder,
                                     segs: SurfaceMap.rectEdge(r, inside: true),
                                     closed: true, depth: 1_000_000, rect: r)
        screenLoop.edge = SurfaceMap.rectEdge(screen, inside: true)
        newLoops.append(screenLoop)
        if menuBarHeight > 12 {
            let y = screen.maxY - menuBarHeight - off
            var loop = SurfaceLoop(id: "menu:0", kind: .menuBar,
                                   segs: [Seg(V2(screen.minX + 90, y), V2(screen.maxX - 90, y), .down)],
                                   closed: false, depth: -20, rect: .zero)
            loop.edge = [Seg(V2(screen.minX, y + off), V2(screen.maxX, y + off), .down)]
            newLoops.append(loop)
        }
        for w in windows {
            var loop = SurfaceLoop(id: "win:\(w.id)", kind: .windowEdge,
                                   segs: SurfaceMap.rectEdge(w.frame.insetBy(dx: -off, dy: -off), inside: false),
                                   closed: true, depth: w.depth, rect: w.frame)
            loop.edge = SurfaceMap.rectEdge(w.frame, inside: false)
            newLoops.append(loop)
        }
        occluders = windows.map { (rect: $0.frame, depth: $0.depth) }
        screenFrames = [screen]
        worldBounds = screen
        applyBlocks(to: &newLoops)
        loops = newLoops
        byID = Dictionary(uniqueKeysWithValues: newLoops.map { ($0.id, $0) })
    }

    /// Dock strips, in AppKit coords. Falls back to visibleFrame insets.
    private func dockStrips() -> [CGRect] {
        var found: [CGRect] = []
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                              kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        for dict in info {
            guard let owner = dict[kCGWindowOwnerName as String] as? String, owner == "Dock",
                  let layer = dict[kCGWindowLayer as String] as? Int, layer >= 18, layer <= 22,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: CGFloat],
                  let cg = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            let r = CGRect(x: cg.minX, y: primaryTop - cg.maxY, width: cg.width, height: cg.height)
            guard r.width > 60, r.height > 30, r.width * r.height > 8000 else { continue }
            // The dock strip hugs a screen edge.
            let hugs = NSScreen.screens.contains { s in
                abs(r.minY - s.frame.minY) < 4 || abs(r.minX - s.frame.minX) < 4
                    || abs(r.maxX - s.frame.maxX) < 4
            }
            if hugs { found.append(r) }
        }
        if !found.isEmpty {
            // Prefer the biggest strip per screen.
            return found.sorted { $0.width * $0.height > $1.width * $1.height }.prefix(2).map { $0 }
        }
        // Fallback: infer from visibleFrame.
        for s in NSScreen.screens {
            let f = s.frame, vf = s.visibleFrame
            let bottomGap = vf.minY - f.minY
            if bottomGap > 20 {
                let w = f.width * 0.6
                found.append(CGRect(x: f.midX - w / 2, y: f.minY, width: w, height: bottomGap))
            }
        }
        return found
    }

    // MARK: Queries

    func loop(_ id: String) -> SurfaceLoop? { byID[id] }

    func seg(_ anchor: Anchor) -> Seg? {
        guard let l = byID[anchor.loopID], anchor.segIdx >= 0, anchor.segIdx < l.segs.count else { return nil }
        return l.segs[anchor.segIdx]
    }

    func worldPoint(_ anchor: Anchor) -> V2? { seg(anchor)?.point(at: anchor.t) }

    struct SurfacePoint {
        var pos: V2
        var tangent: V2
        var normal: V2
    }

    /// Position and frame at an anchor, with the loop's corners rounded off.
    /// The raw loops meet at right angles, and a body following them turns on
    /// the spot with a visible kink; blending the last `radius` of one edge into
    /// the first `radius` of the next with a quadratic curve turns each corner
    /// into a smooth swing. Parameter t is unchanged, so walking logic is none
    /// the wiser.
    func resolve(_ a: Anchor, cornerRadius: CGFloat) -> SurfacePoint? {
        guard let loop = byID[a.loopID], a.segIdx >= 0, a.segIdx < loop.segs.count else { return nil }
        let n = loop.segs.count
        let seg = loop.segs[a.segIdx]
        let hasNext = loop.closed || a.segIdx + 1 < n
        let hasPrev = loop.closed || a.segIdx > 0

        func blend(_ A: V2, _ C: V2, _ B: V2, _ u: CGFloat) -> SurfacePoint {
            let w = clamp(u, 0, 1)
            let pos = A * ((1 - w) * (1 - w)) + C * (2 * w * (1 - w)) + B * (w * w)
            let tangent = ((C - A) * (2 * (1 - w)) + (B - C) * (2 * w)).normalized
            return SurfacePoint(pos: pos, tangent: tangent, normal: tangent.rotated(by: .pi / 2))
        }

        if hasNext {
            let next = loop.segs[(a.segIdx + 1) % n]
            let r = min(cornerRadius, seg.len * 0.45, next.len * 0.45)
            if r > 1, a.t > seg.len - r {
                let A = seg.point(at: seg.len - r)
                let B = next.point(at: r)
                return blend(A, seg.b, B, (a.t - (seg.len - r)) / (2 * r))
            }
        }
        if hasPrev {
            let prev = loop.segs[(a.segIdx - 1 + n) % n]
            let r = min(cornerRadius, seg.len * 0.45, prev.len * 0.45)
            if r > 1, a.t < r {
                let A = prev.point(at: prev.len - r)
                let B = seg.point(at: r)
                return blend(A, seg.a, B, 0.5 + a.t / (2 * r))
            }
        }
        return SurfacePoint(pos: seg.point(at: a.t), tangent: seg.dir, normal: seg.normal)
    }

    /// Is this point visible, i.e. not covered by anything in front of `depth`?
    func isVisible(_ p: V2, depth: Int) -> Bool {
        for o in occluders where o.depth < depth {
            if o.rect.insetBy(dx: -2, dy: -2).contains(p.point) { return false }
        }
        return true
    }

    /// The underside of the menu bar on a screen, if it has one.
    func menuBarBottom(for screen: CGRect) -> CGFloat? {
        for l in loops where l.kind == .menuBar {
            if let e = l.edge.first, screen.contains(CGPoint(x: screen.midX, y: e.a.y - 1)) { return e.a.y }
        }
        return nil
    }

    func isOnScreen(_ p: V2, slack: CGFloat = 0) -> Bool {
        for f in screenFrames where f.insetBy(dx: -slack, dy: -slack).contains(p.point) { return true }
        return false
    }

    func screenFrame(containing p: V2) -> CGRect {
        for f in screenFrames where f.contains(p.point) { return f }
        // Nearest screen by centre distance.
        return screenFrames.min(by: {
            V2($0.midX, $0.midY).distance(to: p) < V2($1.midX, $1.midY).distance(to: p)
        }) ?? worldBounds
    }

    /// Every reachable spot, sampled along all loops.
    func sampleSpots(spacing: CGFloat = 34, visibleOnly: Bool = true) -> [(anchor: Anchor, point: V2, loop: SurfaceLoop, seg: Seg)] {
        var out: [(Anchor, V2, SurfaceLoop, Seg)] = []
        out.reserveCapacity(400)
        for l in loops {
            for (i, s) in l.segs.enumerated() {
                guard s.len > 8 else { continue }
                let n = max(1, Int(s.len / spacing))
                let step = s.len / CGFloat(n)
                var t = step * 0.5
                while t < s.len {
                    let p = s.point(at: t)
                    if !visibleOnly || (isOnScreen(p, slack: 4) && s.isOpen(at: t)) {
                        out.append((Anchor(loopID: l.id, segIdx: i, t: t), p, l, s))
                    }
                    t += step
                }
            }
        }
        return out
    }

    /// Nearest attachable spot to a point, within a radius.
    func nearestSpot(to p: V2, within radius: CGFloat, excluding excludeLoop: String? = nil)
        -> (anchor: Anchor, point: V2, seg: Seg, loop: SurfaceLoop)? {
        var best: (Anchor, V2, Seg, SurfaceLoop)?
        var bestD = radius
        for l in loops {
            if l.id == excludeLoop { continue }
            for (i, s) in l.segs.enumerated() {
                let (t, d) = projectOnSegment(p, s.a, s.b)
                if d < bestD, s.isOpen(at: t) {
                    bestD = d
                    best = (Anchor(loopID: l.id, segIdx: i, t: t), s.point(at: t), s, l)
                }
            }
        }
        guard let b = best else { return nil }
        return (b.0, b.1, b.2, b.3)
    }

    /// Closest downward-facing edge above `p` — where a web can be anchored.
    func ceiling(above p: V2, maxRise: CGFloat = 900) -> V2? {
        var best: V2?
        var bestDy = maxRise
        for l in loops {
            for s in l.segs where s.facing == .down {
                let minX = min(s.a.x, s.b.x), maxX = max(s.a.x, s.b.x)
                guard p.x > minX - 4, p.x < maxX + 4 else { continue }
                let y = s.a.y
                let dy = y - p.y
                if dy > 12, dy < bestDy, isVisible(V2(p.x, y), depth: l.depth) {
                    bestDy = dy
                    // Silk attaches to the edge itself, not to the body line.
                    best = V2(clamp(p.x, minX, maxX), y + standoff)
                }
            }
        }
        if best == nil {
            // Fall back to the top of the screen we are over.
            let f = screenFrame(containing: p)
            let y = f.maxY - 4
            if y - p.y > 12 { return V2(p.x, y) }
        }
        return best
    }
}
