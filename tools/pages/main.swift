import AppKit
import QuartzCore

// The page-ledge check (see Sources/DesktopSpider/PageLedges.swift): what
// the spider would climb on a picture of a page.
//
//   Pages see <in.png> <out.png> [scale]   the ledges it finds, drawn over the page
//   Pages time <in.png> [runs]             how long a look takes

func load(_ path: String) -> PagePicture {
    guard let img = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let pic = PagePicture(image: img) else { fatalError("can't read \(path)") }
    return pic
}

func settings(scale: CGFloat) -> PageReader.Settings { PageReader.Settings.forScale(scale) }

let args = CommandLine.arguments
guard args.count >= 3 else { print("usage: Pages see|time <in.png> ..."); exit(1) }
let pic = load(args[2])

switch args[1] {
case "see":
    let scale = args.count > 4 ? CGFloat(Double(args[4]) ?? 0.78) : 0.78
    let s = settings(scale: scale)
    let t0 = CACurrentMediaTime()
    let top = PageReader.pageTop(in: pic)
    let t1 = CACurrentMediaTime()
    let edges = PageReader.edges(in: pic, s, area: CGRect(x: 0, y: max(top - 3, 0), width: pic.width, height: pic.height - max(top - 3, 0)))
    let ms = (CACurrentMediaTime() - t1) * 1000
    print(String(format: "%@: %dx%d, page from %d (%.1f ms), %d edges in %.1f ms (need %d, slot %d, min %d)", args[2], pic.width, pic.height, top, (t1 - t0) * 1000, edges.count, ms, s.need, s.slot, s.minLength))
    for e in edges.sorted(by: { ($0.horizontal ? 0 : 1, $0.pos) < ($1.horizontal ? 0 : 1, $1.pos) }) {
        print("  \(e.horizontal ? "—" : "|") \(e.side) at \(e.pos) \(e.lo)..<\(e.hi) (\(e.length)) room \(e.room) contrast \(e.contrast)")
    }
    // Draw them over a dimmed copy of the page.
    let w = pic.width, h = pic.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let src = NSImage(contentsOfFile: args[2])!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.45))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    // (Image rows run top down; the context's y runs up.)
    for e in edges {
        let color: CGColor
        switch e.side {
        case .above: color = CGColor(red: 0.1, green: 0.75, blue: 0.2, alpha: 1)
        case .below: color = CGColor(red: 0.15, green: 0.35, blue: 1, alpha: 1)
        case .left: color = CGColor(red: 1, green: 0.55, blue: 0, alpha: 1)
        case .right: color = CGColor(red: 0.85, green: 0.1, blue: 0.8, alpha: 1)
        }
        ctx.setStrokeColor(color)
        ctx.setLineWidth(3)
        let room = CGFloat(min(e.room, 60))
        if e.horizontal {
            let y = CGFloat(h - e.pos)
            ctx.move(to: CGPoint(x: CGFloat(e.lo), y: y)); ctx.addLine(to: CGPoint(x: CGFloat(e.hi), y: y)); ctx.strokePath()
            ctx.setFillColor(color.copy(alpha: 0.13)!)
            let dy: CGFloat = e.side == .above ? room : -room
            ctx.fill(CGRect(x: CGFloat(e.lo), y: min(y, y + dy), width: CGFloat(e.length), height: abs(dy)))
        } else {
            let x = CGFloat(e.pos)
            ctx.move(to: CGPoint(x: x, y: CGFloat(h - e.lo))); ctx.addLine(to: CGPoint(x: x, y: CGFloat(h - e.hi))); ctx.strokePath()
            ctx.setFillColor(color.copy(alpha: 0.13)!)
            let dx: CGFloat = e.side == .right ? room : -room
            ctx.fill(CGRect(x: min(x, x + dx), y: CGFloat(h - e.hi), width: abs(dx), height: CGFloat(e.length)))
        }
    }
    // The joined-up paths: a dot at each corner, a ring where a path closes.
    let chains = PageReader.chains(edges, trim: CGFloat(s.trim))
    print("  \(chains.count) paths: " + chains.map { "\($0.sides.count)\($0.closed ? "○" : "")" }.joined(separator: " "))
    for ch in chains where ch.sides.count > 1 {
        ctx.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 1))
        for (k, pt) in ch.points.enumerated() where ch.closed || (k > 0 && k < ch.points.count - 1) {
            ctx.fillEllipse(in: CGRect(x: pt.x - 4, y: CGFloat(h) - pt.y - 4, width: 8, height: 8))
        }
        ctx.setStrokeColor(CGColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.8))
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: ch.points[0].x, y: CGFloat(h) - ch.points[0].y))
        for pt in ch.points.dropFirst() { ctx.addLine(to: CGPoint(x: pt.x, y: CGFloat(h) - pt.y)) }
        if ch.closed { ctx.closePath() }
        ctx.strokePath()
    }
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
case "time":
    let runs = args.count > 3 ? Int(args[3]) ?? 10 : 10
    let s = settings(scale: 0.78)
    var best = Double.infinity, total = 0.0
    for _ in 0..<runs {
        let t0 = CACurrentMediaTime()
        let top = PageReader.pageTop(in: pic)
        _ = PageReader.edges(in: pic, s, area: CGRect(x: 0, y: max(top - 3, 0), width: pic.width, height: pic.height - max(top - 3, 0)))
        let ms = (CACurrentMediaTime() - t0) * 1000
        best = min(best, ms); total += ms
    }
    print(String(format: "%@: best %.1f ms, mean %.1f ms over %d", args[2], best, total / Double(runs), runs))
default:
    print("usage: Pages see|time <in.png> ...")
}
