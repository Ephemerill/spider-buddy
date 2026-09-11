import AppKit

// Measures the cost of one spider frame at the real layer size, so the draw
// code can be optimised against a number instead of a guess.

let scale = 2
let side = Int(SpiderRenderer.spriteSide(for: 0.95))
guard let ctx = CGContext(data: nil, width: side * scale, height: side * scale,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
let bounds = CGRect(x: 0, y: 0, width: side, height: side)

var pose = SpiderPose()
pose.scale = 0.95
func legs(_ t: CGFloat) -> [LegPose] {
    var out: [LegPose] = []
    for i in 0..<SpiderRenderer.legCount {
        do {
            let hip = SpiderRenderer.rig(i).hip
            let rest = SpiderRenderer.rig(i).foot
            let foot = rest + V2(sin(t * 6 + CGFloat(i)) * 3, cos(t * 5 + CGFloat(i)) * 3)
            out.append(LegPose(hip: hip,
                               knee: SpiderRenderer.knee(leg: i, hip: hip, foot: foot, lift: 0),
                               foot: foot, lift: 0))
        }
    }
    return out
}

let frames = 600
// warm up
for i in 0..<30 { pose.legs = legs(CGFloat(i) / 60); SpiderRenderer.draw(pose, in: ctx, bounds: bounds) }

let t0 = Date()
for i in 0..<frames {
    let t = CGFloat(i) / 60
    pose.legs = legs(t)
    pose.heading = t * 0.4
    pose.abdomenSway = sin(t * 3) * 0.2
    ctx.clear(bounds)
    SpiderRenderer.draw(pose, in: ctx, bounds: bounds)
}
let ms = Date().timeIntervalSince(t0) * 1000 / Double(frames)
print("layer \(side)x\(side) @\(scale)x")
print(String(format: "spider frame: %.3f ms  -> %.1f%% of one core at 60fps", ms, ms * 60 / 10))
