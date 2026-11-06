import AppKit

// Image exporter: every Studio option, and a set of hand-built poses, each as
// its own PNG (transparent background, sRGB, 2 pixels per point), plus an
// index.json naming them. The Windows port renders the same inputs and compares
// image by image. For the poses it also writes the pose itself as JSON, so the
// Windows renderer is fed the identical input.
//
//   ./tools/imagedump.sh [outdir]          (default build/images)
//
//   thumbs/<row>/<NN>-<case>.png           Studio option thumbnails, the way the Studio draws
//                                          them (SpiderRenderer.thumbnail), at two sizes
//   poses/<name>.png  + <name>.pose.json   whole sprites at scale 0.95 (some at 0.62 and 1.55)
//   index.json

setvbuf(stdout, nil, _IONBF, 0)
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/images"
let fm = FileManager.default
for sub in ["thumbs", "poses"] { try? fm.createDirectory(atPath: "\(outDir)/\(sub)", withIntermediateDirectories: true) }

var index: [String] = []

/// A PNG of whatever `body` draws in a `side` x `side` point square, `px` pixels per point.
func png(side: Int, px: Int = 2, _ body: (CGContext) -> Void) -> Data? {
    let w = side * px
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: nil, width: w, height: w, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.scaleBy(x: CGFloat(px), y: CGFloat(px))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    body(ctx)
    NSGraphicsContext.restoreGraphicsState()
    guard let img = ctx.makeImage() else { return nil }
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])
}
func clean(_ s: String) -> String {
    String(s.map { $0.isLetter || $0.isNumber ? $0 : "-" })
}

// MARK: Studio option thumbnails (the rows of tools/gallery/main.swift)

enum FuzzLevels: Int, CaseIterable { case a = 0, b, c }
var fancy = SpiderLook()
fancy.pattern = .spots; fancy.accent = .cream
let thumbSides = [88, 184]

func dump<T: CaseIterable>(_ row: String, _ type: T.Type, front: Bool = false, closeUp: Bool = false,
                           base: SpiderLook = SpiderLook(), label: (T) -> String, apply: (inout SpiderLook, T) -> Void) {
    let dir = "\(outDir)/thumbs/\(clean(row))"
    try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (i, opt) in type.allCases.enumerated() {
        var look = base
        apply(&look, opt)
        for side in thumbSides {
            let name = String(format: "%02d-%@-%d", i, clean(String(describing: opt)), side)
            let data = png(side: side) { _ in
                SpiderRenderer.thumbnail(look: look, side: CGFloat(side), front: front, closeUp: closeUp)
                    .draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            }
            let path = "thumbs/\(clean(row))/\(name).png"
            try? data?.write(to: URL(fileURLWithPath: "\(outDir)/\(path)"))
            index.append("{\"kind\":\"thumb\",\"row\":\(encodeJSON(row)),\"case\":\(encodeJSON(String(describing: opt))),\"label\":\(encodeJSON(label(opt))),\"side\":\(side),\"front\":\(front),\"closeUp\":\(closeUp),\"file\":\(encodeJSON(path))}")
        }
    }
}

dump("Body", BodyShape.self, label: { $0.label }) { $0.body = $1 }
dump("Fuzz", FuzzLevels.self, label: { "fuzz \($0.rawValue)" }) { $0.fuzz = $1.rawValue }
dump("Eyes", EyeStyle.self, front: true, closeUp: true, label: { $0.label }) { $0.eyes = $1 }
dump("Brows", BrowStyle.self, front: true, closeUp: true, label: { $0.label }) { $0.brows = $1 }
dump("Mouth", FangStyle.self, front: true, closeUp: true, label: { $0.label }) { $0.fangs = $1 }
dump("Mouth side", FangStyle.self, label: { $0.label }) { $0.fangs = $1 }
dump("Legs", LegStyle.self, base: fancy, label: { $0.label }) { $0.legs = $1 }
dump("Coat", Coat.self, base: fancy, label: { $0.label }) { $0.skin = .coat; $0.coat = $1 }
dump("Gradients", GradientCoat.self, base: fancy, label: { $0.label }) { $0.skin = .gradient; $0.gradient = $1 }
dump("Living coats", LivingCoat.self, base: fancy, label: { $0.label }) { $0.skin = .living; $0.living = $1 }
dump("Living coats front", LivingCoat.self, front: true, base: fancy, label: { $0.label }) { $0.skin = .living; $0.living = $1 }
dump("Accent", Accent.self, base: fancy, label: { $0.label }) { $0.accent = $1; $0.legs = .banded }
dump("Markings", Pattern.self, label: { $0.label }) { $0.pattern = $1 }
dump("Markings front", Pattern.self, front: true, label: { $0.label }) { $0.pattern = $1 }
dump("Hats", Hat.self, label: { $0.label }) { $0.hat = $1 }
dump("Hats front", Hat.self, front: true, label: { $0.label }) { $0.hat = $1 }
dump("Extras", Accessory.self, label: { $0.label }) { $0.accessory = $1 }
dump("Extras front", Accessory.self, front: true, label: { $0.label }) { $0.accessory = $1 }

// MARK: Whole-sprite poses

/// Eight legs at rest (the bench tool's, at time zero), so the pose is the same every run.
func restLegs() -> [LegPose] {
    (0..<SpiderRenderer.legCount).map { i in
        let hip = SpiderRenderer.rig(i).hip
        let foot = SpiderRenderer.rig(i).foot + V2(sin(CGFloat(i)) * 3, cos(CGFloat(i)) * 3)
        return LegPose(hip: hip, knee: SpiderRenderer.knee(leg: i, hip: hip, foot: foot, lift: 0), foot: foot, lift: 0)
    }
}

func basePose(scale: CGFloat) -> SpiderPose {
    var p = SpiderPose()
    p.scale = scale
    p.legs = restLegs()
    // ID_NO_TEXT=1 leaves the name tag out: text is compared by layout, since the fonts differ across platforms.
    p.nameTag = ProcessInfo.processInfo.environment["ID_NO_TEXT"] == "1" ? 0 : 1
    p.name = "Mocha"
    p.time = 1.25
    return p
}

func pose(_ name: String, scale: CGFloat = 0.95, _ edit: (inout SpiderPose) -> Void = { _ in }) {
    var p = basePose(scale: scale)
    edit(&p)
    let side = Int(SpiderRenderer.spriteSide(for: p.scale))
    let data = png(side: side) { ctx in
        SpiderRenderer.draw(p, in: ctx, bounds: CGRect(x: 0, y: 0, width: side, height: side))
    }
    let file = "poses/\(clean(name))"
    try? data?.write(to: URL(fileURLWithPath: "\(outDir)/\(file).png"))
    try? encodeJSON(p).write(toFile: "\(outDir)/\(file).pose.json", atomically: true, encoding: .utf8)
    index.append("{\"kind\":\"pose\",\"name\":\(encodeJSON(name)),\"scale\":\(Double(p.scale)),\"side\":\(side),\"file\":\(encodeJSON(file + ".png")),\"pose\":\(encodeJSON(file + ".pose.json"))}")
}

for s in [0.62, 0.78, 0.95, 1.2, 1.55] { pose("stand-\(s)", scale: CGFloat(s)) }
pose("facing-left") { $0.facing = -1 }
pose("front-view") { $0.facing = 0 }
pose("turning-half") { $0.facing = 0.5 }
pose("heading-up") { $0.heading = .pi / 2 }
pose("heading-down") { $0.heading = -.pi / 2 }
pose("upside-down") { $0.heading = .pi }
pose("blink") { $0.blink = 1 }
pose("happy") { $0.happy = 1 }
pose("startled") { $0.startled = 1 }
pose("asleep") { $0.sleep = 1 }
pose("grabbed") { $0.grabbed = 1 }
pose("wink") { $0.wink = 1 }
pose("chew") { $0.chew = 0.6 }
pose("head-tilt-up") { $0.headTilt = 0.3 }
pose("head-cock") { $0.headCock = 0.3 }
pose("head-turn") { $0.headTurn = 0.5 }
pose("palps") { $0.palpNear = 1; $0.palpFar = 0.6 }
pose("body-pitch") { $0.bodyPitch = 0.3 }
pose("abdomen-tilt") { $0.abdomenTilt = 0.3 }
pose("stretched") { $0.stretch = 1.22; $0.fatten = 0.66 }
pose("ball") { $0.ball = 1 }
pose("ball-half-spun") { $0.ball = 1; $0.spin = 1.2 }
pose("airborne") { $0.grounded = 0 }
pose("look-up-right") { $0.look = V2(0.7, 0.7) }
// Weather on the spider.
pose("wet") { $0.wet = 1 }
pose("snow") { $0.snow = 1 }
pose("dust") { $0.dust = 1 }
pose("chill") { $0.chill = 1 }
// Peek-a-boo: a window in front covers its left half; the front feet grip its edge.
pose("hidden-by-window") { $0.hiddenBy = [CGRect(x: -140, y: -100, width: 140, height: 200)]; $0.peekGrip = [V2(-4, -6), V2(-4, -12)] }
// Emotes (each half way through its time) and every thought.
for (name, e) in [("hearts", Emote.hearts), ("zzz", .zzz), ("surprise", .surprise), ("sparkle", .sparkle),
                  ("question", .question), ("note", .note), ("exclaim", .exclaim), ("charge", .charge)] {
    pose("emote-\(name)") { $0.emote = e; $0.emoteT = 0.5; $0.emoteClock = 0.5 }
}
let thoughts: [(String, Thought)] = [("heart", .heart), ("hungry", .hungry), ("rain", .rain), ("sun", .sun), ("moon", .moon),
    ("music", .music), ("star", .star), ("bug", .bug), ("home", .home), ("snow", .snow), ("wind", .wind),
    ("storm", .storm), ("rainbow", .rainbow), ("dots", .dots),
    ("text-short", .text("Hello!")), ("text-long", .text("I wonder what is behind that window, and whether it has flies."))]
for (name, th) in thoughts {
    pose("thought-\(name)") { $0.emote = .thought; $0.thought = th; $0.emoteT = 0.5; $0.emoteClock = 0.5 }
}
// Outfits on the full sprite (animated coats move with `time`).
for t in [0.0, 1.5] { pose("living-time-\(t)") { var l = SpiderLook(); l.skin = .living; l.living = LivingCoat.allCases.first!; $0.outfit = l; $0.time = CGFloat(t) } }

let doc = "{\"thumbSides\":\(thumbSides),\"px\":2,\"items\":[\n" + index.joined(separator: ",\n") + "\n]}"
try? doc.write(toFile: "\(outDir)/index.json", atomically: true, encoding: .utf8)
print("wrote \(index.count) images to \(outDir)")
