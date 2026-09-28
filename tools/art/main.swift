import AppKit

// Draws the app's icon (an .iconset) and the .dmg window's backdrop (a 1x and
// a 2x PNG) from AppArt, into the directory it is given. tools/art.sh turns
// them into Resources/AppIcon.icns and Resources/dmg-background.tiff.

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/art"

/// The .dmg window, in points; tools/release.sh lays the icons out on it.
let dmgSize = CGSize(width: 660, height: 420)
/// Where Finder centres the two icons, from the window's top left.
let appSpot = CGPoint(x: 180, y: 212)
let appsSpot = CGPoint(x: 480, y: 212)

func png(_ path: String, width: Int, height: Int, draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    g.cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw(g.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: Icon

let iconset = "\(out)/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for side in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = side * scale
        let name = scale == 1 ? "icon_\(side)x\(side).png" : "icon_\(side)x\(side)@2x.png"
        png("\(iconset)/\(name)", width: px, height: px) { AppArt.drawIcon(in: $0, side: CGFloat(px)) }
    }
}

// MARK: The .dmg's backdrop

/// Draws `text` centred on x at `y` down from the top.
func label(_ text: String, size: CGFloat, weight: NSFont.Weight, colour: CGColor, y: CGFloat, rounded: Bool = false) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { font = f }
    let s = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor(cgColor: colour)!])
    let b = s.size()
    s.draw(at: CGPoint(x: (dmgSize.width - b.width) / 2, y: dmgSize.height - y - b.height / 2))
}

func backdrop(in ctx: CGContext) {
    let W = dmgSize.width, H = dmgSize.height
    func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: H - p.y) }

    // Sunlight, as on the icon's tile.
    let wash = CGGradient(colorsSpace: nil, colors: [
        AppArt.cream, CGColor(red: 0.99, green: 0.9, blue: 0.75, alpha: 1),
    ] as CFArray, locations: [0.2, 1])!
    ctx.drawRadialGradient(wash, startCenter: CGPoint(x: W * 0.35, y: H), startRadius: 0,
                           endCenter: CGPoint(x: W * 0.35, y: H), endRadius: W * 0.95, options: [.drawsAfterEndLocation])

    // A web in the top left corner.
    let thread = AppArt.bark.copy(alpha: 0.16)!
    AppArt.drawWeb(in: ctx, hub: CGPoint(x: -14, y: H + 14), radius: 190, from: -.pi / 2 - 0.05, to: 0.05,
                   spokes: 6, rings: 8, width: 1.3, colour: thread, reach: 1.12)

    // One of them, hanging on its line in the other corner (head down).
    let hang = up(CGPoint(x: 596, y: 112))
    let s: CGFloat = 1.25
    let tilt: CGFloat = 0.06
    let spinnerets = CGPoint(x: hang.x - sin(tilt) * 24 * s, y: hang.y + cos(tilt) * 24 * s)
    ctx.setStrokeColor(AppArt.bark.copy(alpha: 0.45)!)
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: spinnerets.x, y: H))
    ctx.addLine(to: spinnerets)
    ctx.strokePath()
    ctx.saveGState()
    ctx.translateBy(x: hang.x, y: hang.y)
    ctx.rotate(by: .pi + tilt)
    ctx.scaleBy(x: s, y: s)
    AppArt.drawGlyph(in: ctx, colour: AppArt.ink)
    ctx.restoreGState()

    NSGraphicsContext.current?.saveGraphicsState()
    label("Spider Buddy", size: 30, weight: .bold, colour: AppArt.ink, y: 56, rounded: true)
    label("Drag the spider into Applications to let it move in.", size: 14, weight: .medium,
          colour: AppArt.bark.copy(alpha: 0.85)!, y: 92)
    label("Then open it from Applications. It lives in your menu bar.", size: 12, weight: .regular,
          colour: AppArt.bark.copy(alpha: 0.65)!, y: 382)
    NSGraphicsContext.current?.restoreGraphicsState()

    // A strand of silk from one icon to the other.
    let a = up(CGPoint(x: appSpot.x + 86, y: appSpot.y - 6))
    let b = up(CGPoint(x: appsSpot.x - 86, y: appsSpot.y - 6))
    let c = up(CGPoint(x: (appSpot.x + appsSpot.x) / 2, y: appSpot.y - 58))
    let strand = AppArt.bark.copy(alpha: 0.5)!
    ctx.setStrokeColor(strand)
    ctx.setLineWidth(2.5)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: [0.1, 8])
    ctx.move(to: a)
    ctx.addQuadCurve(to: b, control: c)
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    // The arrowhead, along the curve's last direction.
    let dir = atan2(b.y - c.y, b.x - c.x)
    ctx.setLineWidth(2.5)
    for turn in [CGFloat(2.6), -2.6] {
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: b.x + cos(dir + turn) * 13, y: b.y + sin(dir + turn) * 13))
    }
    ctx.strokePath()
}

for scale in [1, 2] {
    let name = scale == 1 ? "dmg-background.png" : "dmg-background@2x.png"
    png("\(out)/\(name)", width: Int(dmgSize.width) * scale, height: Int(dmgSize.height) * scale) { ctx in
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        backdrop(in: ctx)
    }
}
// A 1024 preview of the icon, for looking at.
png("\(out)/icon.png", width: 1024, height: 1024) { AppArt.drawIcon(in: $0, side: 1024) }
print(out)
