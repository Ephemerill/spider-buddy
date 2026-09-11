import AppKit

// A contact sheet of every part the studio offers, thumbnailed the way the
// studio shows them, plus a row of random designs walking.

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/studio.png"
let cell: CGFloat = CommandLine.arguments.count > 2 ? CGFloat(Double(CommandLine.arguments[2]) ?? 96) : 96
let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)

struct Row { let title: String; let front: Bool; var closeUp = false; let looks: [(String, SpiderLook)] }
func row<T: CaseIterable>(_ title: String, _ type: T.Type, front: Bool = false, closeUp: Bool = false, base: SpiderLook = SpiderLook(),
                          label: (T) -> String, apply: (inout SpiderLook, T) -> Void) -> Row {
    Row(title: title, front: front, closeUp: closeUp, looks: type.allCases.map { opt in
        var l = base; apply(&l, opt); return (label(opt), l)
    })
}
var fancy = SpiderLook()
fancy.pattern = .spots; fancy.accent = .cream
enum FuzzLevels: Int, CaseIterable { case a = 0, b, c }
let rows: [Row] = [
    row("Body", BodyShape.self, label: { $0.label }) { $0.body = $1 },
    row("Fuzz", FuzzLevels.self, label: { "fuzz \($0.rawValue)" }) { $0.fuzz = $1.rawValue },
    row("Eyes", EyeStyle.self, front: true, closeUp: true, label: { $0.label }) { $0.eyes = $1 },
    row("Brows", BrowStyle.self, front: true, closeUp: true, label: { $0.label }) { $0.brows = $1 },
    row("Mouth", FangStyle.self, front: true, closeUp: true, label: { $0.label }) { $0.fangs = $1 },
    row("Mouth (side)", FangStyle.self, label: { $0.label }) { $0.fangs = $1 },
    row("Legs", LegStyle.self, base: fancy, label: { $0.label }) { $0.legs = $1 },
    row("Coat", Coat.self, base: fancy, label: { $0.label }) { $0.coat = $1 },
    row("Markings", Pattern.self, label: { $0.label }) { $0.pattern = $1 },
    row("Markings (front)", Pattern.self, front: true, label: { $0.label }) { $0.pattern = $1 },
    row("Hats", Hat.self, label: { $0.label }) { $0.hat = $1 },
    row("Hats (front)", Hat.self, front: true, label: { $0.label }) { $0.hat = $1 },
    row("Extras", Accessory.self, label: { $0.label }) { $0.accessory = $1 },
    row("Extras (front)", Accessory.self, front: true, label: { $0.label }) { $0.accessory = $1 },
]

let randoms = (0..<7).map { _ in SpiderDesign.random() }
let maxCols = max(rows.map { $0.looks.count }.max() ?? 1, randoms.count)
let W = Int(cell * CGFloat(maxCols)) + 20
let rowH = cell + 26
let H = Int(rowH * CGFloat(rows.count + 1)) + 20

guard let ctx = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: 2, y: 2)
ctx.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.90, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
func label(_ s: String, _ x: CGFloat, _ y: CGFloat) {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor.black]))
    ctx.textPosition = CGPoint(x: x, y: y); CTLineDraw(line, ctx)
}

NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
for (r, row) in rows.enumerated() {
    let y = CGFloat(H) - 10 - rowH * CGFloat(r + 1)
    label(row.title, 8, y + cell + 8)
    for (c, (name, look)) in row.looks.enumerated() {
        let x = 10 + cell * CGFloat(c)
        let img = SpiderRenderer.thumbnail(look: look, side: cell - 8, front: row.front, closeUp: row.closeUp)
        img.draw(in: CGRect(x: x, y: y + 4, width: cell - 8, height: cell - 8))
        label(name, x + 2, y - 4)
    }
}

// Random designs, mid-walk on a ledge, so hats and legs are seen in motion.
let y = CGFloat(H) - 10 - rowH * CGFloat(rows.count + 1)
label("random designs, walking", 8, y + cell + 8)
for (c, d) in randoms.enumerated() {
    let map = SurfaceMap()
    map.standoff = 22
    map.debugRebuild(screen: CGRect(x: 0, y: 0, width: 400, height: 300), menuBarHeight: 0, windows: [])
    let sp = Spider(map: map)
    sp.config.followCursor = false
    sp.apply(design: d)
    sp.debugAttach(loopID: "screen:0", segIdx: 0, t: 100, dir: 1)
    sp.debugWalk(for: 10)
    for _ in 0..<(40 + c * 5) { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: 1 / 60) }
    var pose = sp.pose()
    pose.heading = 0
    pose.scale = 0.7
    pose.nameTag = 1
    let x = 10 + cell * CGFloat(c)
    SpiderRenderer.draw(pose, in: ctx, bounds: CGRect(x: x, y: y + 14, width: cell - 8, height: cell - 8))
    label("\(d.name) · \(d.look.coat.rawValue)/\(d.look.hat.rawValue)", x + 2, y - 4)
}

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(W)x\(H))")
