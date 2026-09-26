import AppKit

// Renders a contact sheet of poses to a PNG so the drawing can be inspected
// without running the app.  Usage: ./tools/preview.sh [out.png]

func restLegs(_ transform: (Int, V2, V2) -> V2) -> [LegPose] {
    var out: [LegPose] = []
    for i in 0..<SpiderRenderer.legCount {
        do {
            let hip = SpiderRenderer.rig(i).hip
            let rest = SpiderRenderer.rig(i).foot
            let foot = transform(i, hip, rest)
            out.append(LegPose(hip: hip,
                               knee: SpiderRenderer.knee(leg: i, hip: hip, foot: foot, lift: 0),
                               foot: foot, lift: 0))
        }
    }
    return out
}

var poses: [(String, SpiderPose)] = []

func base(_ name: String, _ mutate: (inout SpiderPose) -> Void) {
    var p = SpiderPose()
    p.scale = 2.6
    p.legs = restLegs { _, _, r in r }
    p.look = .zero
    mutate(&p)
    poses.append((name, p))
}

base("idle") { _ in }
base("look up-left") { $0.look = V2(-0.6, 0.8) }
base("blink") { $0.blink = 0.55 }
base("happy") { $0.happy = 1.0 }
base("startled") { $0.startled = 1.0; $0.emote = .surprise; $0.emoteT = 0.4 }
base("asleep") { $0.blink = 1; $0.sleep = 1; $0.emote = .zzz; $0.emoteT = 0.4
    $0.legs = restLegs { _, h, r in h + (r - h) * 0.72 } }
base("petted") { $0.happy = 1; $0.emote = .hearts; $0.emoteT = 0.45 }
base("charger in") { $0.happy = 1; $0.emote = .charge; $0.emoteT = 0.35; $0.emoteClock = 0.5 }
base("charger, a flicker on") { $0.happy = 1; $0.emote = .charge; $0.emoteT = 0.5; $0.emoteClock = 0.9; $0.heading = .pi / 2 }
base("mid-jump") { $0.stretch = 1.15; $0.fatten = 0.88; $0.grounded = 0; $0.heading = 0.5
    $0.legs = restLegs { i, h, r in h + (r - h) * 1.15 + V2(i % 4 < 2 ? 5 : -5, 6) } }
base("landing squash") { $0.stretch = 1.22; $0.fatten = 0.72 }
base("dangling") { $0.grounded = 0; $0.legs = restLegs { _, h, r in h + (r - h) * 0.55 + V2(0, 3) } }
base("held") { $0.startled = 0.8; $0.grabbed = 1
    $0.grounded = 0; $0.legs = restLegs { i, h, r in h + (r - h) * 0.45 + V2(sin(CGFloat(i)) * 3, cos(CGFloat(i) * 1.3) * 3) } }
base("facing left") { $0.facing = -1 }
base("on a wall") { $0.heading = .pi / 2 }
base("mid-turn") { $0.facing = 0.3 }
base("actual 0.78x") { $0.scale = 0.78 }
base("actual 0.95x") { $0.scale = 0.95 }
base("actual 1.2x") { $0.scale = 1.2 }
base("hanging under") { $0.heading = .pi }
// The extremes the model can actually reach at once: fully splayed legs, the
// stretch clamp, and an emote overhead. The sprite has to contain this.
base("worst case") { $0.stretch = 1.22; $0.fatten = 0.66
    $0.emote = .hearts; $0.heading = 0.85
    $0.legs = restLegs { i, h, r in h + (r - h) * 1.15 + V2(i % 4 < 2 ? 5 : -5, 6) } }

if CommandLine.arguments.contains("--single") {
    poses = [poses[0]]
    poses[0].1.scale = 7.0
}

// --- sprite extent check ----------------------------------------------------
// The live layer is sized from SpiderRenderer.drawRadius. Rather than guess a
// margin, render every pose into an oversized buffer and measure how far the
// furthest drawn pixel actually is from the centre, in body units.
if CommandLine.arguments.contains("--cliptest") {
    let side = 340, px = 2
    guard let c = CGContext(data: nil, width: side * px, height: side * px,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { exit(1) }
    c.scaleBy(x: CGFloat(px), y: CGFloat(px))
    let b = CGRect(x: 0, y: 0, width: side, height: side)
    let scale: CGFloat = 2.0            // measure big, report in body units
    var worst: CGFloat = 0
    var worstName = ""

    // Measure in the plainest outfit and in the one that sticks out furthest.
    var tall = SpiderLook()
    tall.hat = .wizard; tall.legs = .long; tall.body = .chonk; tall.fuzz = 2; tall.accessory = .backpack
    var balloon = SpiderLook()
    balloon.hat = .bunnyEars; balloon.legs = .spindly; balloon.body = .chonk; balloon.accessory = .balloon
    var wide = SpiderLook()
    wide.hat = .sombrero; wide.legs = .spindly; wide.body = .bean; wide.accessory = .batWings
    for (name, base) in poses {
        for (outfitName, outfit) in [("classic", SpiderLook()), ("wizard/long/chonk", tall),
                                     ("bunny/spindly/balloon", balloon), ("sombrero/spindly/batwings", wide)] {
        for heading in stride(from: 0.0, to: 6.28, by: 0.26) {
            var p = base
            p.scale = scale
            p.heading = CGFloat(heading)
            p.emoteT = 0.5
            p.outfit = outfit
            p.name = "Sprocket"
            p.nameTag = 1
            c.clear(b)
            SpiderRenderer.draw(p, in: c, bounds: b)
            guard let data = c.data else { continue }
            let bpr = c.bytesPerRow
            let w = side * px, h = side * px
            let cx = CGFloat(w) / 2, cy = CGFloat(h) / 2
            let buf = data.assumingMemoryBound(to: UInt8.self)
            var far: CGFloat = 0
            for y in 0..<h {
                let row = y * bpr
                for x in 0..<w where buf[row + x * 4 + 3] > 8 {
                    // Chebyshev distance: the layer is square.
                    let d = max(abs(CGFloat(x) - cx), abs(CGFloat(y) - cy))
                    if d > far { far = d }
                }
            }
            let units = far / CGFloat(px) / scale
            if units > worst { worst = units; worstName = "\(name) (\(outfitName)) @ \(String(format: "%.2f", heading))" }
        }
        }
    }
    let need = worst.rounded(.up)
    print(String(format: "sprite extent: %.1f body units (worst: %@)", Double(worst), worstName as NSString))
    if SpiderRenderer.drawRadius >= need {
        print("drawRadius \(Int(SpiderRenderer.drawRadius)) is enough (needs \(Int(need)))")
        exit(0)
    }
    print("drawRadius \(Int(SpiderRenderer.drawRadius)) is TOO SMALL — needs \(Int(need))")
    exit(1)
}

let cell: CGFloat = CommandLine.arguments.contains("--single") ? 620 : 210
let cols = CommandLine.arguments.contains("--single") ? 1 : 4
let rows = (poses.count + cols - 1) / cols
let W = Int(cell * CGFloat(cols)), H = Int(cell * CGFloat(rows))

guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
// Checkerboard so light pixels and alpha are both visible.
for gy in 0..<(H / 20 + 1) {
    for gx in 0..<(W / 20 + 1) {
        let dark = (gx + gy) % 2 == 0
        ctx.setFillColor(gray: dark ? 0.30 : 0.38, alpha: 1)
        ctx.fill(CGRect(x: gx * 20, y: gy * 20, width: 20, height: 20))
    }
}

let font = CTFontCreateWithName("Menlo" as CFString, 11, nil)
for (i, entry) in poses.enumerated() {
    let cx = CGFloat(i % cols) * cell
    let cy = CGFloat(rows - 1 - i / cols) * cell
    let rect = CGRect(x: cx, y: cy, width: cell, height: cell)
    ctx.setStrokeColor(gray: 0.55, alpha: 0.8)
    ctx.setLineWidth(1)
    ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    SpiderRenderer.draw(entry.1, in: ctx, bounds: rect.insetBy(dx: 0, dy: 10))

    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: entry.0, attributes: attrs))
    ctx.textPosition = CGPoint(x: cx + 8, y: cy + 8)
    CTLineDraw(line, ctx)
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "preview.png"
guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(W)x\(H))")

