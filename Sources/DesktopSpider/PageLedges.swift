import CoreGraphics
import Foundation

// MARK: - Ledges in a picture of a page
//
// A browser that fills its screen leaves no desktop and no other windows
// to climb, so the spider climbs the page instead: the edges of the
// things drawn on it. What counts is what can be seen — a page is only
// ever looked at, never read — so the rules are about the picture:
//
//   • a line: a straight run where the colour changes sharply (the edge
//     of a card, a bar, a box), or a thin line drawn across (a divider),
//     with the thing it is the edge of even along it (not the bottoms of
//     a row of letters);
//   • room: on one side of it, flat open space — no text, no icons, no
//     other lines — deep enough for the spider's body, for a good
//     stretch along it; and not a narrow slot between two parallel lines
//     (the inside of a text field, the gap between two cards).
//
// A horizontal line with room above is a ledge to stand on; with room
// below, one to hang beneath; an upright one with room beside is a wall.
//
// Everything here is plain pixels in, geometry out, on whatever thread
// asks: the picture is in points (one pixel a point), rows from the top.

/// A picture of a page: one pixel a point, rows from the top, each pixel
/// 0x00RRGGBB.
struct PagePicture {
    let width: Int
    let height: Int
    var pixels: [UInt32]

    init(width: Int, height: Int, pixels: [UInt32]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// The pixels of an image, one for one (a window picture taken at its
    /// nominal resolution is already a pixel a point).
    init?(image: CGImage) {
        let w = image.width, h = image.height
        guard w > 8, h > 8 else { return nil }
        // A window's picture is 32-bit, little-endian, alpha first: already
        // just what is wanted, so the bytes are copied as they are (drawing
        // it into a context of our own would cost more than looking at it).
        let order = image.bitmapInfo.intersection(.byteOrderMask)
        let alpha = image.alphaInfo
        if image.bitsPerPixel == 32, image.bitsPerComponent == 8, order == .byteOrder32Little,
           [.premultipliedFirst, .first, .noneSkipFirst].contains(alpha),
           image.bytesPerRow >= w * 4, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data),
           CFDataGetLength(data) >= image.bytesPerRow * h {
            var px = [UInt32](repeating: 0, count: w * h)
            let stride = image.bytesPerRow
            px.withUnsafeMutableBufferPointer { out in
                for y in 0..<h {
                    let row = UnsafeRawPointer(bytes + y * stride)
                    for x in 0..<w { out[y * w + x] = row.loadUnaligned(fromByteOffset: x * 4, as: UInt32.self) & 0x00FF_FFFF }
                }
            }
            self.init(width: w, height: h, pixels: px)
            return
        }
        var px = [UInt32](repeating: 0, count: w * h)
        let space = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpaceCreateDeviceRGB()
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            // Little-endian with the unused byte first: each UInt32 reads
            // back as 0xXXRRGGBB.
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            else { return false }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        for i in px.indices { px[i] &= 0x00FF_FFFF }
        self.init(width: w, height: h, pixels: px)
    }

    @inline(__always) func at(_ x: Int, _ y: Int) -> UInt32 { pixels[y * width + x] }
}

/// Which side of a line the room is on, and so how the spider is on it:
/// room above, it stands on the line; below, it hangs from it; left or
/// right, it climbs it as a wall with its body out that side.
enum PageSide: Equatable {
    case above, below, left, right
}

/// A straight edge in a picture, with room on one side of it.
struct PageEdge: Equatable {
    /// Across the page (a ledge or an underside) or up and down it (a wall).
    var horizontal: Bool
    /// The boundary it is on: for a horizontal edge the line between rows
    /// `pos - 1` and `pos`; for an upright one between columns.
    var pos: Int
    /// Its extent along the line, in pixels: `lo..<hi`.
    var lo: Int
    var hi: Int
    /// The side the room is on.
    var side: PageSide
    /// The least room along it, in pixels (capped: see `PageReader.Settings`).
    var room: Int
    /// How sharp the line is: the colour step across it, 0...255.
    var contrast: Int

    var length: Int { hi - lo }
}

enum PageReader {
    struct Settings {
        /// Room it needs beside a line, in pixels: about the spider's height.
        var need: Int = 34
        /// Room it needs between two parallel lines — in a slot, the far
        /// side is a line all along (the inside of a search field, the gap
        /// between two cards), and the spider wants headroom there.
        var slot: Int = 55
        /// The shortest stretch worth walking, in pixels.
        var minLength: Int = 50
        /// Taken off a stretch's end where something stops it (text, an
        /// icon), so its body does not poke into it at the end of the ledge.
        var trim: Int = 12
        /// The least colour step that makes a line (0...255 in any channel).
        /// Flat web design goes very subtle: a white panel on #f8fafd is 7.
        var contrast: Int32 = 6
        /// Open space is smooth: neighbouring pixels within this (a flat
        /// colour, a gentle gradient, a blurred photograph behind frosted
        /// glass — never the sharp strokes of text or an icon)…
        var flat: Int32 = 5
        /// …and within this of where the space starts.
        var drift: Int32 = 28
        /// A soft shadow along a line: up to this many pixels of gentle
        /// steps before the open space begins.
        var softBand: Int = 7
        var softStep: Int32 = 9
        /// A step this sharp along the thing a line is the edge of is a
        /// stroke of something drawn there (text, an icon)…
        var sharp: Int32 = 32
        /// …and this share of them along it means it is not a line at all
        /// (the bottoms of a word's letters, say).
        var busy: Double = 0.1
        /// How far to look for room (enough for the biggest spider).
        var maxRoom: Int = 160
        /// A line broken by gaps longer than this is two lines.
        var gap: Int = 2
        /// Runs shorter than this are not looked at (the strokes of text).
        var seed: Int = 24
        /// The most edges kept, longest first.
        var most: Int = 120

        /// Settings for a spider of a given size (its `config.scale`).
        static func forScale(_ scale: CGFloat) -> Settings {
            var s = Settings()
            s.need = Int((44 * scale).rounded())
            s.slot = Int((70 * scale).rounded())
            s.minLength = Int(max(40, 64 * scale).rounded())
            s.trim = Int((16 * scale).rounded())
            return s
        }
    }

    @inline(__always) static func dist(_ a: UInt32, _ b: UInt32) -> Int32 {
        if a == b { return 0 }
        let dr = abs(Int32((a >> 16) & 0xFF) - Int32((b >> 16) & 0xFF))
        let dg = abs(Int32((a >> 8) & 0xFF) - Int32((b >> 8) & 0xFF))
        let db = abs(Int32(a & 0xFF) - Int32(b & 0xFF))
        return max(dr, max(dg, db))
    }

    /// Where the page starts under the browser's own bars (tabs, address,
    /// bookmarks, and any message bar): the lowest line right across the
    /// window in the top `within` rows. 0 if there is none (full screen,
    /// with the bars hidden).
    static func pageTop(in pic: PagePicture, within: Int = 200, _ s: Settings = Settings()) -> Int {
        var top = 0
        pic.pixels.withUnsafeBufferPointer { px in
            let reader = Reader(px: px, width: pic.width, height: pic.height, s: s,
                                x0: 0, x1: pic.width, y0: 0, y1: pic.height)
            let ax = reader.acrossAxis
            let margin = pic.width / 40
            let span = pic.width - margin * 2
            for c in 4..<min(within, pic.height - 4) {
                var hits = 0
                for a in stride(from: margin, to: pic.width - margin, by: 2) where reader.strength(ax, a, c) > 0 { hits += 1 }
                if hits * 2 * 10 >= span * 9 { top = c }
            }
        }
        return top
    }

    /// Every edge in the picture that is a line with room beside it —
    /// within `area` (in picture pixels), if given.
    static func edges(in pic: PagePicture, _ s: Settings = Settings(), area: CGRect? = nil) -> [PageEdge] {
        var out: [PageEdge] = []
        let full = CGRect(x: 0, y: 0, width: pic.width, height: pic.height)
        let r = (area ?? full).intersection(full).integral
        guard r.width > 16, r.height > 16 else { return [] }
        pic.pixels.withUnsafeBufferPointer { px in
            var reader = Reader(px: px, width: pic.width, height: pic.height, s: s,
                                x0: Int(r.minX), x1: Int(r.maxX), y0: Int(r.minY), y1: Int(r.maxY))
            reader.across(into: &out)
            reader.upright(into: &out)
        }
        out = merged(out)
        if out.count > s.most {
            out.sort { $0.length * min($0.room, 80) > $1.length * min($1.room, 80) }
            out = Array(out.prefix(s.most))
        }
        return out
    }

    /// The looking itself, over one picture.
    private struct Reader {
        let px: UnsafeBufferPointer<UInt32>
        let width: Int, height: Int
        let s: Settings
        /// The part of the picture looked at: `x0..<x1`, `y0..<y1`.
        let x0: Int, x1: Int, y0: Int, y1: Int
        /// Room at each place along the line being looked at.
        var rooms: [Int]
        var valid: [Bool]

        init(px: UnsafeBufferPointer<UInt32>, width: Int, height: Int, s: Settings, x0: Int, x1: Int, y0: Int, y1: Int) {
            self.px = px
            self.width = width
            self.height = height
            self.s = s
            self.x0 = x0; self.x1 = x1; self.y0 = y0; self.y1 = y1
            rooms = [Int](repeating: 0, count: max(width, height))
            valid = [Bool](repeating: false, count: max(width, height))
        }

        /// A line, looked at along its length: `a` along it, `c` across.
        struct Axis {
            let horizontal: Bool
            /// Strides in the pixel buffer along and across.
            let sa: Int, sc: Int
            /// The range looked at along and across.
            let aLo: Int, aHi: Int, cLo: Int, cHi: Int
        }

        var acrossAxis: Axis { Axis(horizontal: true, sa: 1, sc: width, aLo: x0, aHi: x1, cLo: y0, cHi: y1) }
        var uprightAxis: Axis { Axis(horizontal: false, sa: width, sc: 1, aLo: y0, aHi: y1, cLo: x0, cHi: x1) }

        @inline(__always) func p(_ ax: Axis, _ a: Int, _ c: Int) -> UInt32 { px[a * ax.sa + c * ax.sc] }

        /// How strongly the colour changes across the boundary before
        /// `c`, at `a` along it — 0 unless this is where a line is: one
        /// sharp change (drawn across a pixel or two, where a line falls
        /// between pixels), and the sharpest step of it. A gradient changes
        /// as much, a little at a time, and is no line; nor is a stretch of
        /// a blurred photograph.
        @inline(__always) func strength(_ ax: Axis, _ a: Int, _ c: Int) -> Int32 {
            let p0 = p(ax, a, c - 1), p1 = p(ax, a, c)
            if p0 == p1 { return 0 }
            // The channel that changes most, and which way.
            let dr = channel(p1, 16) - channel(p0, 16), dg = channel(p1, 8) - channel(p0, 8), db = channel(p1, 0) - channel(p0, 0)
            var shift: UInt32 = 16, d = dr
            if abs(dg) > abs(d) { shift = 8; d = dg }
            if abs(db) > abs(d) { shift = 0; d = db }
            let m = abs(d)
            let q = max(s.contrast / 3, 2)
            guard m >= q else { return 0 }
            // The rest of this change, a pixel either side: steps the same
            // way that count (a faint shadow's do not).
            let counts = max(q, m / 3)
            var total = m, width = 1
            var prev = p0, k = c - 2
            while k >= ax.cLo, width <= 3 {
                let v = p(ax, a, k)
                let e = channel(prev, shift) - channel(v, shift)
                guard e * d > 0, abs(e) >= counts else { break }
                if abs(e) >= m { return 0 }      // the sharper step is further on
                total += abs(e); width += 1
                prev = v; k -= 1
            }
            prev = p1; k = c + 1
            while k < ax.cHi, width <= 3 {
                let v = p(ax, a, k)
                let e = channel(v, shift) - channel(prev, shift)
                guard e * d > 0, abs(e) >= counts else { break }
                if abs(e) > m { return 0 }
                total += abs(e); width += 1
                prev = v; k += 1
            }
            guard width <= 3 else { return 0 }
            return total >= s.contrast ? total : 0
        }

        @inline(__always) func channel(_ v: UInt32, _ shift: UInt32) -> Int32 { Int32((v >> shift) & 0xFF) }

        /// Lines across the page: each boundary between two rows, walked
        /// along for runs of sharp change.
        mutating func across(into out: inout [PageEdge]) {
            let ax = acrossAxis
            for c in max(ax.cLo, 3)..<min(ax.cHi, height - 3) {
                var start = -1, last = -100, peak: Int32 = 0
                for a in ax.aLo..<ax.aHi {
                    let st = strength(ax, a, c)
                    guard st > 0 else { continue }
                    if start < 0 || a - last > s.gap + 1 {
                        if start >= 0, last + 1 - start >= s.seed { examine(ax, c, start, last + 1, Int(peak), into: &out) }
                        start = a
                        peak = 0
                    }
                    last = a
                    peak = max(peak, st)
                }
                if start >= 0, last + 1 - start >= s.seed { examine(ax, c, start, last + 1, Int(peak), into: &out) }
            }
        }

        /// Upright lines: the same, a boundary between two columns — but
        /// read a row at a time (the picture is stored in rows), keeping a
        /// run going for every column.
        mutating func upright(into out: inout [PageEdge]) {
            let ax = uprightAxis
            let cLo = max(ax.cLo, 3), cHi = min(ax.cHi, width - 3)
            guard cHi > cLo else { return }
            var start = [Int](repeating: -1, count: width)
            var last = [Int](repeating: -100, count: width)
            var peak = [Int32](repeating: 0, count: width)
            for a in ax.aLo..<ax.aHi {
                for c in cLo..<cHi {
                    let st = strength(ax, a, c)
                    if st > 0 {
                        if start[c] < 0 || a - last[c] > s.gap + 1 {
                            if start[c] >= 0, last[c] + 1 - start[c] >= s.seed { examine(ax, c, start[c], last[c] + 1, Int(peak[c]), into: &out) }
                            start[c] = a
                            peak[c] = 0
                        }
                        last[c] = a
                        peak[c] = max(peak[c], st)
                    } else if start[c] >= 0, a - last[c] > s.gap + 1 {
                        if last[c] + 1 - start[c] >= s.seed { examine(ax, c, start[c], last[c] + 1, Int(peak[c]), into: &out) }
                        start[c] = -1
                    }
                }
            }
            for c in cLo..<cHi where start[c] >= 0 && last[c] + 1 - start[c] >= s.seed {
                examine(ax, c, start[c], last[c] + 1, Int(peak[c]), into: &out)
            }
        }

        /// Room on one side of the boundary before `c`, at `a` along: the
        /// depth of flat open space there (0 if there is none), up to `most`.
        func room(_ ax: Axis, _ c: Int, _ a: Int, before: Bool, most: Int) -> Int {
            let dir = before ? -1 : 1
            let first = before ? c - 1 : c
            // Past the line itself (a blended pixel row) and any soft shadow
            // along it, to where the open space starts.
            var k = first, start = -1
            for step in 0..<s.softBand {
                let k1 = k + dir, k2 = k + 2 * dir
                guard k2 >= ax.cLo, k2 < ax.cHi else { return 0 }
                let v0 = p(ax, a, k), v1 = p(ax, a, k1), v2 = p(ax, a, k2)
                let d01 = dist(v0, v1)
                if d01 <= s.flat, dist(v1, v2) <= s.flat { start = k; break }
                if step > 0, d01 > s.softStep { return 0 }
                k = k1
            }
            guard start >= 0 else { return 0 }
            let ref = p(ax, a, start)
            var prev = ref
            var r = start
            let end = before ? max(first - most, ax.cLo - 1) : min(first + most, ax.cHi)
            let hasBefore = a > ax.aLo, hasAfter = a < ax.aHi - 1
            while r != end {
                let v = p(ax, a, r)
                if dist(v, prev) > s.flat || dist(v, ref) > s.drift { break }
                // Flat along the line too: nothing crossing it.
                if hasBefore, dist(v, p(ax, a - 1, r)) > s.flat { break }
                if hasAfter, dist(v, p(ax, a + 1, r)) > s.flat { break }
                prev = v
                r += dir
            }
            return abs(r - first)
        }

        /// Whether the thing a line is the edge of is even along it — a
        /// bar, a box, a border — rather than a row of separate strokes.
        /// `before`: the room is before the boundary, so the thing is after.
        func evenAlong(_ ax: Axis, _ c: Int, _ a0: Int, _ a1: Int, roomBefore before: Bool) -> Bool {
            // (A pixel in from the boundary, past any blending.)
            let rows = before ? [c + 1, c + 2] : [c - 2, c - 3]
            var strokes = 0
            for r in rows where r >= ax.cLo && r < ax.cHi {
                var prev = p(ax, a0, r)
                for a in (a0 + 1)..<a1 {
                    let v = p(ax, a, r)
                    if dist(v, prev) > s.sharp { strokes += 1 }
                    prev = v
                }
            }
            return Double(strokes) <= Double(a1 - a0) * s.busy * Double(rows.count) + 1
        }

        /// Whether a run is a drawn line, as steady as one: nearly all of it
        /// a step at least half as sharp as it typically is. The edges of
        /// things in a photograph come and go along their length.
        func steady(_ ax: Axis, _ c: Int, _ a0: Int, _ a1: Int) -> Bool {
            var hist = [Int](repeating: 0, count: 33)
            for a in a0..<a1 { hist[min(Int(strength(ax, a, c)) / 8, 32)] += 1 }
            let n = a1 - a0
            var seen = 0, median = 0
            for (i, k) in hist.enumerated() {
                seen += k
                if seen * 2 >= n { median = i * 8 + 4; break }
            }
            let floor = max(Int(s.contrast), median / 2)
            var weak = 0
            for a in a0..<a1 where Int(strength(ax, a, c)) < floor { weak += 1 }
            return weak * 100 <= n * 15
        }

        /// A run of line from `a0` to `a1` on the boundary before `c`: the
        /// stretches of it with room, on each side, into `out`.
        mutating func examine(_ ax: Axis, _ c: Int, _ a0: Int, _ a1: Int, _ contrast: Int, into out: inout [PageEdge]) {
            // (The cheap tests first: most runs in a busy picture are not
            // lines at all.)
            guard steady(ax, c, a0, a1) else { return }
            for before in [true, false] {
                guard evenAlong(ax, c, a0, a1, roomBefore: before) else { continue }
                // A stretch long enough to keep has room at every eighth
                // pixel or so along it: look there first.
                var any = false
                var a = a0 + 3
                while a < a1 {
                    if room(ax, c, a, before: before, most: s.need) >= s.need { any = true; break }
                    a += 8
                }
                guard any else { continue }
                // (Deep enough to tell a slot from open space is all it
                // needs to know.)
                let most = min(max(s.slot, s.need) + 2, s.maxRoom)
                for a in a0..<a1 { rooms[a] = room(ax, c, a, before: before, most: most) }
                // Room ended by a line parallel to this one (the same depth
                // all along) is a slot: that needs more.
                let w = 12
                for a in a0..<a1 {
                    let r = rooms[a]
                    guard r >= s.need else { valid[a] = false; continue }
                    guard r < s.slot else { valid[a] = true; continue }
                    let lo = max(a0, a - w), hi = min(a1, a + w + 1)
                    var same = 0
                    for b in lo..<hi where abs(rooms[b] - r) <= 1 { same += 1 }
                    valid[a] = same * 10 < (hi - lo) * 8
                }
                // Stretches with room enough all along (a pixel's dip is
                // forgiven: the corner of a glyph, a speck).
                a = a0
                while a < a1 {
                    guard valid[a] else { a += 1; continue }
                    var e = a, least = Int.max
                    while e < a1 {
                        if valid[e] { least = min(least, rooms[e]); e += 1; continue }
                        if e + 1 < a1, valid[e + 1], e > a { e += 1; continue }
                        break
                    }
                    var lo = a, hi = e
                    // Stopped by something (not by the line ending): keep
                    // clear of it.
                    if lo > a0 { lo += s.trim }
                    if hi < a1 { hi -= s.trim }
                    if hi - lo >= s.minLength {
                        let side: PageSide = ax.horizontal ? (before ? .above : .below) : (before ? .left : .right)
                        out.append(PageEdge(horizontal: ax.horizontal, pos: c, lo: lo, hi: hi, side: side,
                                            room: least == Int.max ? 0 : least, contrast: contrast))
                    }
                    a = max(e, a + 1)
                }
            }
        }
    }

    /// One edge per line: a line drawn half in one pixel row and half in the
    /// next, a thin line both of whose sides qualify, or a line with a soft
    /// shadow, turns up more than once a pixel or few apart. Stood on, the
    /// top one is kept; hung from, the bottom one (and walls the same,
    /// sideways).
    private static func merged(_ edges: [PageEdge]) -> [PageEdge] {
        var out: [PageEdge] = []
        let sorted = edges.sorted { ($0.pos, $0.lo) < ($1.pos, $1.lo) }
        for e in sorted {
            if let i = out.lastIndex(where: { o in
                o.side == e.side && o.horizontal == e.horizontal && abs(o.pos - e.pos) <= 4
                    && o.lo < e.hi && e.lo < o.hi
            }) {
                var o = out[i]
                let keepFirst = e.side == .above || e.side == .left
                o.pos = keepFirst ? min(o.pos, e.pos) : max(o.pos, e.pos)
                o.lo = min(o.lo, e.lo)
                o.hi = max(o.hi, e.hi)
                o.room = min(o.room, e.room)
                o.contrast = max(o.contrast, e.contrast)
                out[i] = o
            } else {
                out.append(e)
            }
        }
        return out
    }
}

// MARK: - Joining edges up

/// Edges that meet at corners, joined into one path the spider can walk
/// from end to end (or round and round): over the top of a card, round
/// its corner and down its side, the way it goes round a window.
struct PageChain: Equatable {
    /// The path's corners, in picture pixels (x right, y down): one more
    /// than `sides` for an open path, as many for a closed one.
    var points: [CGPoint]
    /// The room side of each stretch, from `points[i]` to the next.
    var sides: [PageSide]
    var closed: Bool

    var bounds: CGRect {
        points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}

extension PageSide {
    /// The way along a line of this side the spider's path runs, in
    /// picture pixels (y down) — always with the room on its left, going
    /// clockwise round a box seen from outside: along the top to the
    /// right, down the right side, back along the bottom, up the left.
    var travel: (dx: CGFloat, dy: CGFloat) {
        switch self {
        case .above: return (1, 0)
        case .right: return (0, 1)
        case .below: return (-1, 0)
        case .left: return (0, -1)
        }
    }
}

extension PageEdge {
    /// Where the path along it starts and ends (see `PageSide.travel`).
    var start: CGPoint {
        let t = side.travel
        if horizontal { return CGPoint(x: t.dx > 0 ? lo : hi, y: pos) }
        return CGPoint(x: pos, y: t.dy > 0 ? lo : hi)
    }
    var end: CGPoint {
        let t = side.travel
        if horizontal { return CGPoint(x: t.dx > 0 ? hi : lo, y: pos) }
        return CGPoint(x: pos, y: t.dy > 0 ? hi : lo)
    }
}

extension PageReader {
    /// The edges joined into paths wherever one ends near a corner where
    /// the next starts. At a rounded corner the two stop short of it by
    /// about the same — the rounding, up to `radius`; inside a square one
    /// (a floor meeting a wall) either may stop up to `trim` short, having
    /// been kept clear of the other.
    static func chains(_ edges: [PageEdge], radius: CGFloat = 24, trim: CGFloat = 12) -> [PageChain] {
        let n = edges.count
        func corner(_ a: PageEdge, _ b: PageEdge) -> CGPoint {
            a.horizontal ? CGPoint(x: b.pos, y: a.pos) : CGPoint(x: a.pos, y: b.pos)
        }
        // Every way one edge could lead on into another, nearest first.
        var joins: [(from: Int, to: Int, cost: CGFloat)] = []
        for i in 0..<n {
            let a = edges[i]
            for j in 0..<n where j != i {
                let b = edges[j]
                guard a.horizontal != b.horizontal else { continue }
                let c = corner(a, b)
                let ta = a.side.travel, tb = b.side.travel
                // The corner is on past the end of the first (not back
                // along it) and before the start of the second.
                let pastA = (c.x - a.end.x) * ta.dx + (c.y - a.end.y) * ta.dy
                let beforeB = (b.start.x - c.x) * tb.dx + (b.start.y - c.y) * tb.dy
                guard pastA >= -2, beforeB >= -2 else { continue }
                // A rounded corner, inside or out, cuts both short by about
                // the same; inside a square one (turning left, in picture
                // pixels, y down), a floor is kept a little clear of the wall.
                let rounded = pastA <= radius && beforeB <= radius && abs(pastA - beforeB) <= 8
                let inside = ta.dx * tb.dy - ta.dy * tb.dx < 0
                guard rounded || (inside && pastA <= trim + 4 && beforeB <= trim + 4) else { continue }
                joins.append((i, j, max(pastA, 0) + max(beforeB, 0)))
            }
        }
        joins.sort { $0.cost < $1.cost }
        var next = [Int?](repeating: nil, count: n), prev = [Int?](repeating: nil, count: n)
        for j in joins where next[j.from] == nil && prev[j.to] == nil {
            next[j.from] = j.to
            prev[j.to] = j.from
        }
        var used = [Bool](repeating: false, count: n)
        var out: [PageChain] = []
        func build(_ order: [Int], closed: Bool) {
            var points: [CGPoint] = []
            let sides = order.map { edges[$0].side }
            if closed {
                for (k, i) in order.enumerated() { points.append(corner(edges[order[(k + order.count - 1) % order.count]], edges[i])) }
            } else {
                points.append(edges[order[0]].start)
                for k in 1..<order.count { points.append(corner(edges[order[k - 1]], edges[order[k]])) }
                points.append(edges[order[order.count - 1]].end)
            }
            out.append(PageChain(points: points, sides: sides, closed: closed))
        }
        // Open paths from their first edge…
        for i in 0..<n where prev[i] == nil {
            var order = [i]
            used[i] = true
            var k = i
            while let m = next[k], !used[m] { order.append(m); used[m] = true; k = m }
            build(order, closed: false)
        }
        // …and whatever is left goes round in a loop.
        for i in 0..<n where !used[i] {
            var order = [i]
            used[i] = true
            var k = i
            while let m = next[k], !used[m] { order.append(m); used[m] = true; k = m }
            build(order, closed: next[k] == i)
        }
        return out
    }
}
