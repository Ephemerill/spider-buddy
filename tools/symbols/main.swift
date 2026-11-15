// Builds the Windows stand-in's symbol table: Fluent System Icons drawn where the Mac draws SF Symbols.
//
// For every SF Symbol name in fluent-map.txt, and every symbol configuration the app asks for,
// it measures on this Mac what AppKit gives: the image's size and where the ink sits in it.
// It then works out, per weight, how far to thicken the Fluent outline so it carries as much ink
// as the SF Symbol does. The Fluent outlines go in as plain absolute path commands (arcs turned
// into curves), so the Windows side needs no SVG parser.
//
// usage: main <fluent-map.txt> <fluent icons dir> <out.swift> <contact-sheet.png>
import AppKit

let args = CommandLine.arguments
guard args.count == 5 else { print("usage: main map icons out.swift sheet.png"); exit(2) }
let mapPath = args[1], iconDir = args[2], outPath = args[3], sheetPath = args[4]

// MARK: SVG paths

enum Seg { case m(CGPoint), l(CGPoint), q(CGPoint, CGPoint), c(CGPoint, CGPoint, CGPoint), z }

struct PathScanner {
    let s: [UInt8]; var i = 0
    init(_ d: String) { s = Array(d.utf8) }
    mutating func skip() { while i < s.count, s[i] == 32 || s[i] == 44 || s[i] == 10 || s[i] == 13 || s[i] == 9 { i += 1 } }
    mutating func command() -> UInt8? {
        skip()
        guard i < s.count else { return nil }
        let c = s[i]
        if (c >= 65 && c <= 90) || (c >= 97 && c <= 122), c != 101, c != 69 { i += 1; return c }
        return nil
    }
    var atNumber: Bool {
        mutating get {
            skip()
            guard i < s.count else { return false }
            let c = s[i]
            return (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46
        }
    }
    mutating func number() -> CGFloat {
        skip()
        let start = i
        if i < s.count, s[i] == 45 || s[i] == 43 { i += 1 }
        var dot = false
        while i < s.count {
            let c = s[i]
            if c >= 48 && c <= 57 { i += 1 }
            else if c == 46, !dot { dot = true; i += 1 }
            else if c == 101 || c == 69 {
                i += 1
                if i < s.count, s[i] == 45 || s[i] == 43 { i += 1 }
                while i < s.count, s[i] >= 48 && s[i] <= 57 { i += 1 }
                break
            } else { break }
        }
        return CGFloat(Double(String(decoding: s[start..<i], as: UTF8.self))!)
    }
    /// An arc flag: one character, maybe run together with what follows.
    mutating func flag() -> Bool { skip(); let c = s[i]; i += 1; return c == 49 }
}

/// SVG's endpoint arc as cubic curves (SVG 1.1 appendix F.6).
func arc(from p0: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rot: CGFloat, large: Bool, sweep: Bool, to p: CGPoint) -> [Seg] {
    if p0 == p { return [] }
    var rx = abs(rx0), ry = abs(ry0)
    if rx == 0 || ry == 0 { return [.l(p)] }
    let phi = rot * .pi / 180, cp = cos(phi), sp = sin(phi)
    let dx = (p0.x - p.x) / 2, dy = (p0.y - p.y) / 2
    let x1 = cp * dx + sp * dy, y1 = -sp * dx + cp * dy
    let lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
    let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    var k = sqrt(max(0, num / den))
    if large == sweep { k = -k }
    let cx1 = k * rx * y1 / ry, cy1 = -k * ry * x1 / rx
    let cx = cp * cx1 - sp * cy1 + (p0.x + p.x) / 2, cy = sp * cx1 + cp * cy1 + (p0.y + p.y) / 2
    func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
        let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a
    }
    let t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    var dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if !sweep, dt > 0 { dt -= 2 * .pi } else if sweep, dt < 0 { dt += 2 * .pi }
    let n = max(1, Int(ceil(abs(dt) / (.pi / 2) - 1e-9)))
    let step = dt / CGFloat(n)
    let a = 4.0 / 3.0 * tan(step / 4)
    func pt(_ t: CGFloat) -> CGPoint {
        CGPoint(x: cx + rx * cos(t) * cp - ry * sin(t) * sp, y: cy + rx * cos(t) * sp + ry * sin(t) * cp)
    }
    func der(_ t: CGFloat) -> CGPoint {
        CGPoint(x: -rx * sin(t) * cp - ry * cos(t) * sp, y: -rx * sin(t) * sp + ry * cos(t) * cp)
    }
    var out: [Seg] = []
    var t = t1
    for j in 0..<n {
        let t2 = t + step
        let s0 = pt(t), e = j == n - 1 ? p : pt(t2), d0 = der(t), d1 = der(t2)
        out.append(.c(CGPoint(x: s0.x + a * d0.x, y: s0.y + a * d0.y), CGPoint(x: e.x - a * d1.x, y: e.y - a * d1.y), e))
        t = t2
    }
    return out
}

func parse(_ d: String) -> [Seg] {
    var sc = PathScanner(d)
    var out: [Seg] = []
    var cur = CGPoint.zero, start = CGPoint.zero
    var lastC: CGPoint?, lastQ: CGPoint?
    var cmd: UInt8 = 0
    while true {
        if let c = sc.command() { cmd = c } else if !sc.atNumber { break }
        let rel = cmd >= 97
        func P() -> CGPoint { let x = sc.number(), y = sc.number(); return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
        var nc: CGPoint?, nq: CGPoint?
        switch cmd | 32 {
        case 109: // m
            cur = P(); start = cur; out.append(.m(cur))
            cmd = rel ? 108 : 76 // later pairs are line-tos
        case 108: cur = P(); out.append(.l(cur))
        case 104: let x = sc.number(); cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); out.append(.l(cur))
        case 118: let y = sc.number(); cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); out.append(.l(cur))
        case 99:
            let a = P(), b = P(), e = P()
            out.append(.c(a, b, e)); nc = b; cur = e
        case 115:
            let a = lastC.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
            let b = P(), e = P()
            out.append(.c(a, b, e)); nc = b; cur = e
        case 113:
            let a = P(), e = P()
            out.append(.q(a, e)); nq = a; cur = e
        case 116:
            let a = lastQ.map { CGPoint(x: 2 * cur.x - $0.x, y: 2 * cur.y - $0.y) } ?? cur
            let e = P()
            out.append(.q(a, e)); nq = a; cur = e
        case 97:
            let rx = sc.number(), ry = sc.number(), rot = sc.number()
            let large = sc.flag(), sweep = sc.flag()
            let e = P()
            out += arc(from: cur, rx: rx, ry: ry, rot: rot, large: large, sweep: sweep, to: e)
            cur = e
        case 122: out.append(.z); cur = start
        default: fatalError("path command \(cmd) in \(d.prefix(60))")
        }
        lastC = nc; lastQ = nq
    }
    return out
}

func cgPath(_ segs: [Seg]) -> CGMutablePath {
    let p = CGMutablePath()
    for s in segs {
        switch s {
        case .m(let a): p.move(to: a)
        case .l(let a): p.addLine(to: a)
        case .q(let a, let b): p.addQuadCurve(to: b, control: a)
        case .c(let a, let b, let e): p.addCurve(to: e, control1: a, control2: b)
        case .z: p.closeSubpath()
        }
    }
    return p
}

func num(_ v: CGFloat) -> String {
    var s = String(format: "%.3f", Double(v))
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s == "-0" ? "0" : s
}
func encode(_ segs: [Seg]) -> String {
    var parts: [String] = []
    for s in segs {
        switch s {
        case .m(let a): parts.append("M\(num(a.x)) \(num(a.y))")
        case .l(let a): parts.append("L\(num(a.x)) \(num(a.y))")
        case .q(let a, let b): parts.append("Q\(num(a.x)) \(num(a.y)) \(num(b.x)) \(num(b.y))")
        case .c(let a, let b, let e): parts.append("C\(num(a.x)) \(num(a.y)) \(num(b.x)) \(num(b.y)) \(num(e.x)) \(num(e.y))")
        case .z: parts.append("Z")
        }
    }
    return parts.joined()
}

// MARK: The map

struct Entry { let sf: String; let fluent: String; let style: String }
var entries: [Entry] = []
for line in try! String(contentsOfFile: mapPath, encoding: .utf8).split(separator: "\n") {
    let t = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard let first = t.first, !first.hasPrefix("#"), t.count >= 2 else { continue }
    let style = t.count > 2 ? t[2] : (first.hasSuffix(".fill") || first.hasSuffix(".filled") ? "filled" : "regular")
    entries.append(Entry(sf: first, fluent: t[1], style: style))
}

/// Fluent's designs of one icon: its box size (16, 20, 24) to its outline, in that box's units, y down.
var designs: [String: [Int: [Seg]]] = [:]
for e in entries {
    let key = "\(e.fluent)_\(e.style)"
    if designs[key] != nil { continue }
    var d: [Int: [Seg]] = [:]
    for box in [16, 20, 24] {
        let f = "\(iconDir)/\(e.fluent)_\(box)_\(e.style).svg"
        guard let svg = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
        guard let r = svg.range(of: "d=\""), let end = svg[r.upperBound...].firstIndex(of: "\"") else { fatalError("no path in \(f)") }
        d[box] = parse(String(svg[r.upperBound..<end]))
    }
    guard d[20] != nil else { fatalError("no 20-point design of \(key)") }
    designs[key] = d
}

// MARK: Measuring

struct Config: Hashable { let key: String; let size: CGFloat?; let weight: NSFont.Weight }
let weightKey: [NSFont.Weight: String] = [.regular: "r", .medium: "m", .semibold: "s"]
/// What the app asks for (grep withSymbolConfiguration in Sources), and the plain image.
let configs: [Config] = [Config(key: "d", size: nil, weight: .regular)] + [
    (11, NSFont.Weight.semibold), (12, .regular), (12, .medium), (12.5, .semibold), (13, .regular), (13, .medium), (13, .semibold),
    (14, .regular), (14, .medium), (16, .medium), (16, .semibold), (17, .medium), (20, .regular), (21, .medium), (22, .regular), (24, .medium),
].map { Config(key: "\(num($0.0))\(weightKey[$0.1]!)", size: $0.0, weight: $0.1) }

let px: CGFloat = 8 // pixels per point when measuring

struct Bitmap {
    let w: Int, h: Int, ctx: CGContext
    init(size: CGSize) {
        w = max(1, Int((size.width * px).rounded(.up))); h = max(1, Int((size.height * px).rounded(.up)))
        ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: px, y: px)
    }
    var alpha: UnsafeBufferPointer<UInt8> { UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: w * h * 4) }
    /// Ink in square points.
    var coverage: CGFloat {
        var s = 0
        let a = alpha
        for i in stride(from: 3, to: a.count, by: 4) { s += Int(a[i]) }
        return CGFloat(s) / 255 / (px * px)
    }
    /// The inked rectangle in points, y up from the bottom.
    var ink: CGRect {
        let a = alpha
        var x0 = w, x1 = -1, y0 = h, y1 = -1
        for y in 0..<h { for x in 0..<w where a[(y * w + x) * 4 + 3] > 24 { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
        guard x1 >= 0 else { return .zero }
        // Rows run top-down in memory.
        return CGRect(x: CGFloat(x0) / px, y: CGFloat(h - 1 - y1) / px, width: CGFloat(x1 - x0 + 1) / px, height: CGFloat(y1 - y0 + 1) / px)
    }
}

func sfImage(_ name: String, _ c: Config) -> NSImage {
    let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
    guard let s = c.size else { return base }
    return base.withSymbolConfiguration(.init(pointSize: s, weight: c.weight))!
}
func drawSF(_ im: NSImage, in b: Bitmap) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: b.ctx, flipped: false)
    im.draw(in: CGRect(origin: .zero, size: im.size))
    NSGraphicsContext.restoreGraphicsState()
}
/// Fluent's outline fitted into `r` (y up), thickened by `t` points on every side.
func drawFluent(_ segs: [Seg], box: Int, in r: CGRect, t: CGFloat, ctx: CGContext) {
    let path = cgPath(segs)
    let bb = path.boundingBoxOfPath
    let inner = r.insetBy(dx: t, dy: t)
    guard inner.width > 0, inner.height > 0 else { return }
    let s = min(inner.width / bb.width, inner.height / bb.height)
    ctx.saveGState()
    ctx.translateBy(x: inner.midX, y: inner.midY)
    ctx.scaleBy(x: s, y: -s)
    ctx.translateBy(x: -bb.midX, y: -bb.midY)
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    if t > 0 {
        ctx.addPath(path)
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.setLineWidth(2 * t / s)
        ctx.setLineJoin(.round)
        ctx.strokePath()
    }
    ctx.restoreGState()
}

var sizeLines: [String] = []
var weightLines: [String] = []
var heavier: [String] = []
struct Sample { let name: String; let sf: NSImage; let fl: [Seg]; let ink: CGRect; let t: CGFloat }
var samples: [Sample] = []

for e in entries {
    guard NSImage(systemSymbolName: e.sf, accessibilityDescription: nil) != nil else { fatalError("not an SF Symbol: \(e.sf)") }
    let fl = designs["\(e.fluent)_\(e.style)"]![20]!
    for c in configs {
        let im = sfImage(e.sf, c)
        let b = Bitmap(size: im.size)
        drawSF(im, in: b)
        let r = b.ink
        let a = im.alignmentRect
        sizeLines.append("\(e.sf) \(c.key) \(num(im.size.width)) \(num(im.size.height)) \(num(r.minX)) \(num(r.minY)) \(num(r.width)) \(num(r.height)) \(num(a.minX)) \(num(a.minY)) \(num(a.width)) \(num(a.height))")
    }
    // How much to thicken Fluent's outline, per weight, at 16 points.
    for w in [NSFont.Weight.regular, .medium, .semibold] {
        let c = Config(key: "", size: 16, weight: w)
        let im = sfImage(e.sf, c)
        let b = Bitmap(size: im.size)
        drawSF(im, in: b)
        let target = b.coverage, r = b.ink
        func fluentCoverage(_ t: CGFloat) -> CGFloat {
            let f = Bitmap(size: im.size)
            drawFluent(fl, box: 20, in: r, t: t, ctx: f.ctx)
            return f.coverage
        }
        var lo: CGFloat = 0, hi: CGFloat = 1.6
        if fluentCoverage(0) >= target { hi = 0; heavier.append("\(e.sf)/\(weightKey[w]!)") }
        else {
            for _ in 0..<22 { let mid = (lo + hi) / 2; if fluentCoverage(mid) < target { lo = mid } else { hi = mid } }
        }
        weightLines.append("\(e.sf) \(weightKey[w]!) \(num(hi / 16 * 1000))")
        if w == .medium { samples.append(Sample(name: e.sf, sf: im, fl: fl, ink: r, t: hi)) }
    }
}

// MARK: Output

var out = """
// Generated by tools/symbols/run.sh from tools/symbols/fluent-map.txt and Fluent System Icons
// (https://github.com/microsoft/fluentui-system-icons, MIT licence, see THIRD_PARTY_NOTICES.md).
// Sizes and ink rectangles are measured from SF Symbols on a Mac. Do not edit by hand.

enum SymbolData {
    /// "sf-name fluent-key": which Fluent icon stands in for each SF Symbol.
    static let names = #\"\"\"

"""
for e in entries { out += "\(e.sf) \(e.fluent)_\(e.style)\n" }
out += "\"\"\"#\n\n"
out += "    /// \"fluent-key box path\": Fluent's outline in its box's units, y down; M L Q C Z, absolute.\n"
out += "    static let outlines = #\"\"\"\n"
for k in designs.keys.sorted() { for (box, segs) in designs[k]!.sorted(by: { $0.key < $1.key }) { out += "\(k) \(box) \(encode(segs))\n" } }
out += "\"\"\"#\n\n"
out += "    /// \"sf-name config width height inkX inkY inkW inkH alignX alignY alignW alignH\" in points, y up from the bottom.\n"
out += "    /// The alignment rectangle is AppKit's (baseline to cap height): layout lines that up, not the image's box.\n"
out += "    /// Configs: d is the plain image, else point size and r, m or s for regular, medium, semibold.\n"
out += "    static let sizes = #\"\"\"\n"
out += sizeLines.joined(separator: "\n") + "\n\"\"\"#\n\n"
out += "    /// \"sf-name weight outset\": how far to thicken the outline, in thousandths of the point size.\n"
out += "    static let weights = #\"\"\"\n"
out += weightLines.joined(separator: "\n") + "\n\"\"\"#\n}\n"
try! out.write(toFile: outPath, atomically: true, encoding: .utf8)
print("\(entries.count) symbols, \(designs.count) Fluent icons, \(sizeLines.count) sizes")
if !heavier.isEmpty { print("Fluent already heavier than SF (no thickening): \(heavier.joined(separator: " "))") }

// MARK: Contact sheet: SF at 16 pt medium, then Fluent as Windows will draw it.

let cols = 4, cellW: CGFloat = 230, cellH: CGFloat = 30, k: CGFloat = 3
let rows = (samples.count + cols - 1) / cols
let W = Int(CGFloat(cols) * cellW * k), H = Int(CGFloat(rows) * cellH * k)
let sheet = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
sheet.setFillColor(CGColor(gray: 1, alpha: 1)); sheet.fill(CGRect(x: 0, y: 0, width: W, height: H))
sheet.scaleBy(x: k, y: k)
NSGraphicsContext.current = NSGraphicsContext(cgContext: sheet, flipped: false)
for (i, s) in samples.enumerated() {
    let cx = CGFloat(i % cols) * cellW, cy = CGFloat(rows - 1 - i / cols) * cellH
    let o = CGPoint(x: cx + 4, y: cy + (cellH - s.sf.size.height) / 2)
    s.sf.draw(in: CGRect(origin: o, size: s.sf.size))
    let o2 = CGPoint(x: cx + 30, y: o.y)
    drawFluent(s.fl, box: 20, in: s.ink.offsetBy(dx: o2.x, dy: o2.y), t: s.t, ctx: sheet)
    (s.name as NSString).draw(at: CGPoint(x: cx + 56, y: cy + 9), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.black])
}
let rep = NSBitmapImageRep(cgImage: sheet.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: sheetPath))
print("contact sheet: \(sheetPath)")
