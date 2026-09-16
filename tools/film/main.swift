import AppKit

// Renders the real walk cycle, driven by the real model, along each screen
// edge — so the animation can be judged instead of guessed at.

let W = 1400, H = 900
let map = SurfaceMap()
map.standoff = 22 * (CommandLine.arguments.contains("--cycle") ? 2.0 : 1.0)
// A plain box of a screen (no menu bar), so all four edges exist to film.
map.debugRebuild(screen: NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900), menuBarHeight: 0, windows: [])
guard let screenLoop = map.loops.first(where: { $0.id.hasPrefix("screen") }) else { exit(1) }
let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1512, height: 982)

struct Shot { var title: String; var seg: Int; var dir: CGFloat }
let cycleMode = CommandLine.arguments.contains("--cycle")
let shots = cycleMode ? [
    Shot(title: "one gait cycle, bottom edge", seg: 0, dir: 1),
    Shot(title: "one gait cycle, right edge", seg: 1, dir: 1),
] : [
    Shot(title: "bottom edge, walking right", seg: 0, dir: 1),
    Shot(title: "right edge, walking up", seg: 1, dir: 1),
    Shot(title: "top edge, walking left", seg: 2, dir: 1),
    Shot(title: "left edge, walking down", seg: 3, dir: 1),
]

let cols = cycleMode ? 9 : 8
let cell: CGFloat = cycleMode ? 260 : 165
let rowH: CGFloat = cell + 22
let width = Int(cell * CGFloat(cols))
let height = Int(rowH * CGFloat(shots.count))

guard let ctx = CGContext(data: nil, width: width * 2, height: height * 2,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.scaleBy(x: 2, y: 2)
ctx.setFillColor(gray: 0.22, alpha: 1)
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

let font = CTFontCreateWithName("Menlo" as CFString, 10, nil)
func label(_ s: String, _ x: CGFloat, _ y: CGFloat, _ color: NSColor = .white) {
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color]))
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, ctx)
}

for (row, shot) in shots.enumerated() {
    let spider = Spider(map: map)
    spider.config.scale = cycleMode ? 2.0 : 1.0
    let seg = screenLoop.segs[shot.seg]
    spider.debugAttach(loopID: screenLoop.id, segIdx: shot.seg, t: seg.len * 0.35, dir: shot.dir)
    spider.debugWalk(for: 30)

    let dt: CGFloat = 1.0 / 60.0
    // let the gait spin up
    for _ in 0..<40 { spider.setCursor(V2(-9e4, -9e4)); spider.update(dt: dt) }

    // In cycle mode, sample exactly one full gait cycle across the strip.
    let cyclePeriod = 28 * spider.config.scale / spider.config.walkSpeed
    let stepsPerCell = cycleMode ? max(1, Int((cyclePeriod / dt).rounded()) / cols) : 7
    var offsets: [CGFloat] = []
    let baseY = CGFloat(height) - CGFloat(row + 1) * rowH
    label(shot.title, 6, baseY + cell + 6, .init(white: 0.75, alpha: 1))

    for col in 0..<cols {
        for _ in 0..<stepsPerCell { spider.setCursor(V2(-9e4, -9e4)); spider.update(dt: dt) }
        let pose = spider.pose()
        // Perpendicular distance from the edge it is supposed to be gripping.
        let n = screenLoop.segs[shot.seg].normal
        let a = screenLoop.segs[shot.seg].a
        let perp = (pose.pos - a).dot(n)
        offsets.append(perp)
        let box = CGRect(x: CGFloat(col) * cell, y: baseY, width: cell, height: cell)

        ctx.saveGState()
        ctx.addRect(box.insetBy(dx: 1, dy: 1))
        ctx.clip()
        // Draw the screen edge the spider is meant to be walking on, in the
        // same frame as the spider, so the relationship is visible.
        ctx.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor)
        ctx.setLineWidth(2)
        let toBox = { (p: V2) -> CGPoint in
            CGPoint(x: box.midX + (p.x - pose.pos.x), y: box.midY + (p.y - pose.pos.y))
        }
        let e0 = V2(screen.minX, screen.minY), e1 = V2(screen.maxX, screen.minY)
        let e2 = V2(screen.maxX, screen.maxY), e3 = V2(screen.minX, screen.maxY)
        ctx.beginPath()
        for (a, b) in [(e0, e1), (e1, e2), (e2, e3), (e3, e0)] {
            ctx.move(to: toBox(a)); ctx.addLine(to: toBox(b))
        }
        ctx.strokePath()
        SpiderRenderer.draw(pose, in: ctx, bounds: box)
        ctx.restoreGState()

        ctx.setStrokeColor(gray: 0.4, alpha: 1)
        ctx.setLineWidth(1)
        ctx.stroke(box.insetBy(dx: 0.5, dy: 0.5))
    }
    let lo = offsets.min() ?? 0, hi = offsets.max() ?? 0
    print(String(format: "%-28@ standoff %.1f .. %.1f  (drift %.1f)",
                 shot.title as NSString, Double(lo), Double(hi), Double(hi - lo)))
}

// --- sequences: one activity into the next -----------------------------------
// `--seq walk,look,greet:2,turn` runs the activities back to back (each 1.4 s
// unless given `:seconds`) and lays out every 4th frame in a grid, so the
// hand-off from one to the next can be looked at frame by frame.
if let idx = CommandLine.arguments.firstIndex(of: "--seq"), idx + 1 < CommandLine.arguments.count {
    let items = CommandLine.arguments[idx + 1].split(separator: ",").map { item -> (String, CGFloat) in
        let parts = item.split(separator: ":")
        return (String(parts[0]), parts.count > 1 ? CGFloat(Double(parts[1]) ?? 1.4) : 1.4)
    }
    let dt: CGFloat = 1.0 / 60.0
    let sm = SurfaceMap()
    sm.standoff = 22 * 1.0
    let win = CGRect(x: 250, y: 200, width: 380, height: 240)
    sm.debugRebuild(screen: CGRect(x: 0, y: 0, width: 900, height: 620), menuBarHeight: 0,
                    windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock")])
    let sp = Spider(map: sm)
    sp.config.scale = 1.0
    sp.config.followCursor = false
    sp.debugAttach(loopID: "win:9", segIdx: 0, t: 150, dir: 1)
    for _ in 0..<30 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
    let cols = 12
    let cell: CGFloat = 150
    let every = Int(ProcessInfo.processInfo.environment["SEQ_EVERY"] ?? "4") ?? 4
    let total = items.reduce(0) { $0 + Int($1.1 / dt) }
    let rows = (total / every + cols - 1) / cols
    let W = Int(cell * CGFloat(cols)), H = Int(cell) * rows
    guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(gray: 0.22, alpha: 1)
    c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    var f = 0
    var n = 0
    var states: [String] = []
    for (name, dur) in items {
        sp.debugActivity(name, for: dur)
        for _ in 0..<Int(dur / dt) {
            sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt)
            let st = sp.debugState
            if states.last != st { states.append(st) }
            if ProcessInfo.processInfo.environment["SEQ_TRACE"] != nil {
                let pz = sp.pose()
                print(String(format: "%3d %@ yaw %.2f pitch %.2f L0 %.1f,%.1f L4 %.1f,%.1f lift %.2f", f, st as NSString, pz.facing, pz.bodyPitch, pz.legs[0].foot.x, pz.legs[0].foot.y, pz.legs[4].foot.x, pz.legs[4].foot.y, pz.legs[0].lift))
            }
            if f % every == 0, n < cols * rows {
                let pose = sp.pose()
                let box = CGRect(x: CGFloat(n % cols) * cell, y: CGFloat(rows - 1 - n / cols) * cell, width: cell, height: cell)
                c.saveGState(); c.addRect(box); c.clip()
                c.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor)
                c.setLineWidth(2)
                let ly = box.midY + (win.maxY - pose.pos.y)
                c.beginPath(); c.move(to: CGPoint(x: box.minX, y: ly)); c.addLine(to: CGPoint(x: box.maxX, y: ly)); c.strokePath()
                SpiderRenderer.draw(pose, in: c, bounds: box)
                c.restoreGState()
                c.setStrokeColor(gray: 0.4, alpha: 1); c.setLineWidth(1)
                c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
                n += 1
            }
            f += 1
        }
    }
    print("states: " + states.joined(separator: " > "))
    guard let img = c.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/seq.png"))
    print("wrote build/seq.png")
    exit(0)
}

// --- strips: corner walk, turn, and every activity --------------------------
// `--strip corner` walks it round a window corner; `--strip turn` films a
// turn-around; `--strip <activity>` films that activity. Frames are laid out in
// world space for the corner (so the path is visible) and as a filmstrip for
// the rest.
if let idx = CommandLine.arguments.firstIndex(of: "--strip"), idx + 1 < CommandLine.arguments.count {
    let what = CommandLine.arguments[idx + 1]
    let dt: CGFloat = 1.0 / 60.0
    let sm = SurfaceMap()
    sm.standoff = 22 * 1.0
    let deskRect = CGRect(x: 0, y: 0, width: 900, height: 620)
    let win = CGRect(x: 250, y: 200, width: 380, height: 240)
    sm.debugRebuild(screen: deskRect, menuBarHeight: 0,
                    windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock")])
    let sp = Spider(map: sm)
    sp.config.scale = 1.0
    sp.config.followCursor = false

    if what == "corner" {
        // Start near the end of the top edge, walking right, and film in place.
        sp.debugAttach(loopID: "win:9", segIdx: 0, t: win.width - 60, dir: 1)
        sp.debugWalk(for: 30)
        for _ in 0..<30 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        let W = 520, H = 420
        guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        c.scaleBy(x: 2, y: 2)
        c.translateBy(x: -(win.maxX - 260), y: -(win.maxY - 260))
        c.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
        c.fill(CGRect(x: -1000, y: -1000, width: 3000, height: 3000))
        c.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
        c.fill(win)
        c.setFillColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
        c.fill(CGRect(x: win.minX, y: win.maxY - 30, width: win.width, height: 30))
        var trail: [CGPoint] = []
        for f in 0..<170 {
            sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt)
            trail.append(sp.worldPos.point)
            if f % 12 == 0 {
                let pose = sp.pose()
                SpiderRenderer.draw(pose, in: c, bounds: CGRect(x: pose.pos.x - 100, y: pose.pos.y - 100, width: 200, height: 200))
            }
        }
        c.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.35).cgColor)
        c.setLineWidth(1.2)
        c.beginPath(); c.addLines(between: trail); c.strokePath()
        guard let img = c.makeImage() else { exit(1) }
        try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: "build/strip-corner.png"))
        print("wrote build/strip-corner.png")
        exit(0)
    }

    // Filmstrip of one activity on the window's top edge.
    sp.debugAttach(loopID: "win:9", segIdx: 0, t: 150, dir: 1)
    for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
    var dur: CGFloat = 1.4
    if idx + 2 < CommandLine.arguments.count, let d = Double(CommandLine.arguments[idx + 2]) { dur = CGFloat(d) }
    sp.debugActivity(what, for: dur)
    let cols = 12
    let cell: CGFloat = 190
    let W = Int(cell * CGFloat(cols)), H = Int(cell)
    guard let c = CGContext(data: nil, width: W * 2, height: H * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(gray: 0.22, alpha: 1)
    c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    let frames = Int(dur / dt) + 12
    let per = max(1, frames / cols)
    var col = 0
    for f in 0..<frames {
        sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt)
        if f % per == 0 && col < cols {
            let pose = sp.pose()
            let box = CGRect(x: CGFloat(col) * cell, y: 0, width: cell, height: cell)
            c.saveGState(); c.addRect(box); c.clip()
            // ledge line, relative to the spider
            c.setStrokeColor(NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.9, alpha: 1).cgColor)
            c.setLineWidth(2)
            let ly = box.midY + (win.maxY - pose.pos.y)
            c.beginPath(); c.move(to: CGPoint(x: box.minX, y: ly)); c.addLine(to: CGPoint(x: box.maxX, y: ly)); c.strokePath()
            SpiderRenderer.draw(pose, in: c, bounds: box)
            c.restoreGState()
            c.setStrokeColor(gray: 0.4, alpha: 1); c.setLineWidth(1)
            c.stroke(box.insetBy(dx: 0.5, dy: 0.5))
            col += 1
        }
    }
    guard let img = c.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/strip-\(what).png"))
    print("wrote build/strip-\(what).png")
    exit(0)
}

// --- hang -------------------------------------------------------------------
if CommandLine.arguments.contains("--hang") {
    let dt: CGFloat = 1.0 / 60.0
    let dw = 700, dh = 620
    let deskRect = CGRect(x: 0, y: 0, width: CGFloat(dw), height: CGFloat(dh))
    let hm = SurfaceMap()
    hm.standoff = 22 * 1.0
    hm.debugRebuild(screen: deskRect, menuBarHeight: 30, windows: [])
    guard let c = CGContext(data: nil, width: dw * 2, height: dh * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
    c.fill(deskRect)
    c.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.55).cgColor)
    c.fill(CGRect(x: 0, y: CGFloat(dh) - 30, width: CGFloat(dw), height: 30))

    let sp = Spider(map: hm)
    sp.debugCalm = true
    sp.config.scale = 1.0
    sp.config.followCursor = false
    sp.debugAttach(loopID: "menu:0", segIdx: 0, t: 250, dir: 1)
    for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
    sp.scroll(-4)   // rappel
    // three columns: descending, hanging, climbing — drawn side by side
    var col = 0
    var frame = 0
    var phase = "down"
    while col < 3 && frame < 60 * 12 {
        sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt)
        frame += 1
        let pose = sp.pose()
        let shiftX = CGFloat(col) * 220 - 120
        if frame % 10 == 0 {
            c.saveGState()
            c.translateBy(x: shiftX, y: 0)
            if let web = pose.web, let path = SpiderRenderer.silkPath(pose) {
                c.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.5 * Double(web.alpha)).cgColor)
                c.setLineWidth(1)
                c.beginPath(); c.addPath(path); c.strokePath()
            }
            SpiderRenderer.draw(pose, in: c, bounds: CGRect(x: pose.pos.x - 100, y: pose.pos.y - 100, width: 200, height: 200))
            c.restoreGState()
        }
        if phase == "down" && frame > 60 * 2 { phase = "hang"; col = 1; sp.scroll(0); }
        if phase == "hang" && frame > 60 * 4 { phase = "climb"; col = 2; for _ in 0..<40 { sp.scroll(6) } }
    }
    print("hang: \(sp.debugState)")
    guard let img = c.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/hang.png"))
    print("wrote build/hang.png")

    // A close-up strip of the climb and the descent, every 5th frame at 2x,
    // with the line drawn in, so the hand-over-hand can be judged.
    let cellW: CGFloat = 150, cellH: CGFloat = 260, n = 14
    guard let st = CGContext(data: nil, width: Int(cellW) * n * 2, height: Int(cellH) * 2 * 2, bitsPerComponent: 8,
                             bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    st.scaleBy(x: 2, y: 2)
    st.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
    st.fill(CGRect(x: 0, y: 0, width: cellW * CGFloat(n), height: cellH * 2))
    let sp2 = Spider(map: hm)
    sp2.debugCalm = true
    sp2.config.scale = 2.0
    hm.standoff = 44
    hm.debugRebuild(screen: deskRect, menuBarHeight: 30, windows: [])
    sp2.config.followCursor = false
    sp2.debugAttach(loopID: "menu:0", segIdx: 0, t: 250, dir: 1)
    for _ in 0..<20 { sp2.setCursor(V2(-9e4, -9e4)); sp2.update(dt: dt) }
    sp2.scroll(-4); sp2.scroll(-4); sp2.scroll(-4)
    for _ in 0..<240 { sp2.setCursor(V2(-9e4, -9e4)); sp2.update(dt: dt) }   // well down the line
    for row in 0..<2 {
        if row == 0 { for _ in 0..<8 { sp2.scroll(6) } }       // climb a bit
        else { for _ in 0..<8 { sp2.scroll(-6) } }              // descend a bit
        for _ in 0..<10 { sp2.setCursor(V2(-9e4, -9e4)); sp2.update(dt: dt) }
        for i in 0..<n {
            for _ in 0..<4 { sp2.setCursor(V2(-9e4, -9e4)); sp2.update(dt: dt) }
            let pose = sp2.pose()
            if ProcessInfo.processInfo.environment["FILM_DEBUG"] != nil {
                print("row \(row) cell \(i): \(sp2.debugState) pos=\(pose.pos) attach=\(pose.silkAttach) web=\(String(describing: pose.web?.anchor)) pts=\(pose.webPoints.count) head=\(pose.webPoints.first ?? .zero) tail=\(pose.webPoints.last ?? .zero) heading=\(pose.heading)")
            }
            st.saveGState()
            let cx = cellW * CGFloat(i) + cellW / 2, cy = cellH * CGFloat(1 - row) + cellH / 2
            st.translateBy(x: cx - pose.pos.x, y: cy - pose.pos.y)
            if pose.web != nil, let path = SpiderRenderer.silkPath(pose) {
                st.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.6).cgColor)
                st.setLineWidth(1.4)
                st.beginPath(); st.addPath(path); st.strokePath()
            }
            SpiderRenderer.draw(pose, in: st, bounds: CGRect(x: pose.pos.x - 130, y: pose.pos.y - 130, width: 260, height: 260))
            st.restoreGState()
        }
    }
    guard let si = st.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: si).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/hang_strip.png"))
    print("wrote build/hang_strip.png (top: climbing, bottom: descending)")
    exit(0)
}

// --- jump -------------------------------------------------------------------
// Drawn along its real trajectory in world space, so the arc, the mid-air
// orientation and the landing can all be judged at once.
if CommandLine.arguments.contains("--jump") {
    let dt: CGFloat = 1.0 / 60.0
    let dw = 900, dh = 620
    let deskRect = CGRect(x: 0, y: 0, width: CGFloat(dw), height: CGFloat(dh))
    let jm = SurfaceMap()
    jm.standoff = 22 * 1.0
    // `--under`: the window hangs above it and it leaps up to the underside.
    let under = CommandLine.arguments.contains("--under")
    let win = under ? CGRect(x: 60, y: 230, width: 330, height: 250)
                    : CGRect(x: 470, y: 250, width: 330, height: 250)
    jm.debugRebuild(screen: deskRect, menuBarHeight: 0,
                    windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock")])
    let target = under ? V2(win.midX + 40, win.minY - 22) : V2(win.minX - 32, win.midY)

    guard let j = CGContext(data: nil, width: dw * 2, height: dh * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    j.scaleBy(x: 2, y: 2)
    j.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
    j.fill(deskRect)
    j.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
    j.fill(win)
    j.setFillColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
    j.fill(CGRect(x: win.minX, y: win.maxY - 30, width: win.width, height: 30))

    let sp = Spider(map: jm)
    sp.config.scale = 1.0
    sp.debugAttach(loopID: "screen:0", segIdx: 0, t: 150, dir: 1)
    for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
    sp.debugJump(to: target)

    var trail: [CGPoint] = []
    var frame = 0
    var landedAt = -1
    var flew = false
    while frame < 240 {
        sp.setCursor(V2(-9e4, -9e4))
        sp.update(dt: dt)
        frame += 1
        trail.append(sp.worldPos.point)
        if !flew, sp.debugState == "jump" { flew = true }
        if landedAt < 0 && flew && sp.debugState.hasPrefix("attached") { landedAt = frame }
        if landedAt > 0 && frame > landedAt + 25 { break }
    }
    // trajectory
    j.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.25).cgColor)
    j.setLineWidth(1.5)
    j.beginPath()
    j.addLines(between: trail)
    j.strokePath()

    // replay, drawing the spider every few frames
    let sp2 = Spider(map: jm)
    sp2.config.scale = 1.0
    sp2.debugAttach(loopID: "screen:0", segIdx: 0, t: 150, dir: 1)
    for _ in 0..<20 { sp2.setCursor(V2(-9e4, -9e4)); sp2.update(dt: dt) }
    sp2.debugJump(to: target)
    let stop = landedAt > 0 ? landedAt + 22 : 200
    for f in 0..<stop {
        sp2.setCursor(V2(-9e4, -9e4))
        sp2.update(dt: dt)
        if f % (under ? 4 : 7) == 0 || f == stop - 1 {
            let pose = sp2.pose()
            let box = CGRect(x: pose.pos.x - 110, y: pose.pos.y - 110, width: 220, height: 220)
            SpiderRenderer.draw(pose, in: j, bounds: box)
        }
    }
    print("landed after \(landedAt) frames — \(sp.debugState)")
    let jumpOut = under ? "build/jump_under.png" : "build/jump.png"
    guard let ji = j.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: ji).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: jumpOut))
    print("wrote build/jump.png")
    exit(0)
}

// --- hunt -------------------------------------------------------------------
// `--hunt cricket|worm|fly` releases prey on a mock desktop and films the
// chase: the trail of both, the spider every few frames, and a close-up
// strip of the pounce and the meal.
if let hi = CommandLine.arguments.firstIndex(of: "--hunt") {
    let kindName = hi + 1 < CommandLine.arguments.count ? CommandLine.arguments[hi + 1] : "cricket"
    let kind: PreyKind = kindName.hasPrefix("w") ? .worm : (kindName.hasPrefix("f") ? .fruitFly : .cricket)
    let dt: CGFloat = 1.0 / 60.0
    let dw = 900, dh = 620
    let deskRect = CGRect(x: 0, y: 0, width: CGFloat(dw), height: CGFloat(dh))
    let hm = SurfaceMap()
    hm.standoff = 22 * 1.0
    let win = CGRect(x: 420, y: 160, width: 330, height: 220)
    hm.debugRebuild(screen: deskRect, menuBarHeight: 24,
                    windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock")])
    guard let c = CGContext(data: nil, width: dw * 2, height: dh * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
    c.fill(deskRect)
    c.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
    c.fill(win)
    c.setFillColor(NSColor(calibratedWhite: 0.85, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: CGFloat(dh) - 24, width: CGFloat(dw), height: 24))

    let sp = Spider(map: hm)
    sp.config.scale = 1.0
    sp.config.followCursor = false
    sp.debugAttach(loopID: "screen:0", segIdx: 0, t: 120, dir: 1)
    for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
    let prey = sp.release(kind)
    var frame = 0
    var log: [String] = []
    var closeups: [(SpiderPose, Prey?)] = []
    var lastState = ""
    var spiderTrail: [CGPoint] = []
    var preyTrail: [CGPoint] = []
    while frame < 60 * 120 {
        sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt); frame += 1
        let st = sp.debugState
        if log.last != st { log.append(st) }
        spiderTrail.append(sp.worldPos.point)
        preyTrail.append(prey.pos.point)
        let pose = sp.pose()
        if frame % 20 == 0 {
            // The prey, then the spider, in place.
            c.saveGState()
            c.translateBy(x: prey.pos.x, y: prey.pos.y)
            PreyRenderer.draw(prey, in: c)
            c.restoreGState()
            let box = CGRect(x: pose.pos.x - 110, y: pose.pos.y - 110, width: 220, height: 220)
            SpiderRenderer.draw(pose, in: c, bounds: box)
        }
        // Close-ups of the interesting bits: the pounce and the meal.
        let interesting = st.hasPrefix("jump") || st.contains(":eat") || st.contains(":crouch")
        if interesting, frame % 6 == 0, closeups.count < 16 {
            closeups.append((pose, prey))
        }
        if ProcessInfo.processInfo.environment["FILM_DEBUG"] != nil, st != lastState, st.hasPrefix("jump") || st.contains(":crouch") || st.contains(":eat") {
            print("  f\(frame) \(st) spider=\(Int(sp.worldPos.x)),\(Int(sp.worldPos.y)) prey=\(Int(prey.pos.x)),\(Int(prey.pos.y)) on=\(prey.anchor?.loopID ?? "air") fear=\(String(format: "%.2f", prey.fear)) v=\(Int(prey.vel.length))")
        }
        lastState = st
        if prey.state == .eaten, prey.alpha <= 0 { break }
    }
    _ = lastState
    c.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.25).cgColor)
    c.setLineWidth(1)
    c.beginPath(); c.addLines(between: spiderTrail); c.strokePath()
    c.setStrokeColor(NSColor(calibratedRed: 1, green: 0.8, blue: 0.4, alpha: 0.5).cgColor)
    c.beginPath(); c.addLines(between: preyTrail); c.strokePath()
    // Close-up strip along the bottom.
    let cell: CGFloat = 110
    for (i, (pose, p)) in closeups.enumerated() {
        let x = 4 + CGFloat(i % 8) * cell, y = 4 + CGFloat(i / 8) * cell
        c.saveGState()
        c.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.85).cgColor)
        c.fill(CGRect(x: x, y: y, width: cell - 4, height: cell - 4))
        c.clip(to: CGRect(x: x, y: y, width: cell - 4, height: cell - 4))
        c.translateBy(x: x + cell / 2 - pose.pos.x * 1.6, y: y + cell / 2 - pose.pos.y * 1.6)
        c.scaleBy(x: 1.6, y: 1.6)
        if let p, p.alpha > 0 {
            c.saveGState(); c.translateBy(x: p.pos.x, y: p.pos.y); PreyRenderer.draw(p, in: c); c.restoreGState()
        }
        SpiderRenderer.draw(pose, in: c, bounds: CGRect(x: pose.pos.x - 60, y: pose.pos.y - 60, width: 120, height: 120))
        c.restoreGState()
    }
    print("hunt \(kind.label): \(frame / 60)s  " + log.suffix(8).joined(separator: " > "))
    if ProcessInfo.processInfo.environment["FILM_DEBUG"] != nil { print(log.joined(separator: " > ")) }
    guard let img = c.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/hunt.png"))
    print("wrote build/hunt.png")
    exit(0)
}

// --- peek-a-boo ---------------------------------------------------------------
// `--peekaboo` films the game: a window over part of another window's top
// edge, the pointer near by, and the spider on the back window's shelf
// hiding behind the front window's edge and popping out.
if CommandLine.arguments.contains("--peekaboo") {
    let dt: CGFloat = 1.0 / 60.0
    let dw = 900, dh = 500
    let deskRect = CGRect(x: 0, y: 0, width: CGFloat(dw), height: CGFloat(dh))
    let pm = SurfaceMap()
    pm.standoff = 22 * 1.0
    let back = CGRect(x: 80, y: 60, width: 700, height: 160)
    let win = CGRect(x: 420, y: 40, width: 380, height: 260)
    pm.debugRebuild(screen: deskRect, menuBarHeight: 24,
                    windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock"),
                              TrackedWindow(id: 8, frame: back, depth: 1, owner: "Back")])
    guard let c = CGContext(data: nil, width: dw * 2, height: dh * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.scaleBy(x: 2, y: 2)
    let sp = Spider(map: pm)
    sp.config.scale = 1.0
    sp.config.followCursor = true
    sp.debugAttach(loopID: "win:8", segIdx: 0, t: 200, dir: 1)
    for _ in 0..<20 { sp.setCursor(V2(300, 120)); sp.update(dt: dt) }
    sp.debugActivity("peekaboo", for: 0)
    // A strip of moments: every 0.4 s, each cell the scene around the edge.
    let cols = 10, rows = 3
    let cellW = CGFloat(dw) / CGFloat(cols), cellH = CGFloat(dh) / CGFloat(rows)
    var shots = 0
    var frame = 0
    var log: [String] = []
    var stageLog: [String] = []
    while shots < cols * rows, frame < 60 * 40 {
        sp.setCursor(V2(300, 120)); sp.update(dt: dt); frame += 1
        let st = sp.debugState
        if log.last != st { log.append(st) }
        if frame % 24 == 0 {
            let pose = sp.pose()
            let col = shots % cols, row = shots / cols
            let ox = CGFloat(col) * cellW, oy = CGFloat(rows - 1 - row) * cellH
            c.saveGState()
            c.clip(to: CGRect(x: ox, y: oy, width: cellW, height: cellH))
            c.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
            c.fill(CGRect(x: ox, y: oy, width: cellW, height: cellH))
            // World -> cell: centred on the edge, 1x.
            c.translateBy(x: ox + cellW / 2 - win.minX, y: oy + cellH / 2 - back.maxY)
            // The window it stands on, behind it.
            c.setFillColor(NSColor(calibratedWhite: 0.22, alpha: 1).cgColor)
            c.fill(back)
            let box = CGRect(x: pose.pos.x - 110, y: pose.pos.y - 110, width: 220, height: 220)
            SpiderRenderer.draw(pose, in: c, bounds: box)
            // The window on top, as it would be.
            c.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
            c.fill(win)
            c.setStrokeColor(NSColor(calibratedWhite: 0.5, alpha: 1).cgColor)
            c.setLineWidth(1)
            c.stroke(win)
            c.restoreGState()
            stageLog.append("\(Int(pose.pos.x))")
            shots += 1
        }
        if !st.contains("peekaboo") && frame > 120 && shots > 4 { break }
    }
    print("peekaboo: " + log.suffix(6).joined(separator: " > "))
    print("x per cell: " + stageLog.joined(separator: " "))
    guard let img = c.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/peekaboo.png"))
    print("wrote build/peekaboo.png")
    exit(0)
}

// --- thoughts -----------------------------------------------------------------
// `--thoughts` draws every kind of thought bubble, plus the "!!" burst.
if CommandLine.arguments.contains("--thoughts") {
    let dt: CGFloat = 1.0 / 60.0
    let cellW = 230, cellH = 170, cols = 4
    let thoughts: [Thought] = [.heart, .hungry, .rain, .sun, .moon, .music, .star, .bug, .home,
                               .text("hi!"), .text("you've got this"),
                               .text("\u{201C}The LORD is my shepherd; I shall not want.\u{201D} \u{2014} Psalm 23:1")]
    let rows = (thoughts.count + 1 + cols - 1) / cols
    guard let c = CGContext(data: nil, width: cellW * cols * 2, height: cellH * rows * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    c.scaleBy(x: 2, y: 2)
    c.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
    c.fill(CGRect(x: 0, y: 0, width: cellW * cols, height: cellH * rows))
    let hm = SurfaceMap()
    hm.standoff = 22 * 1.4
    hm.debugRebuild(screen: CGRect(x: 0, y: 0, width: 900, height: 600), menuBarHeight: 0, windows: [])
    for (i, th) in (thoughts.map { Optional($0) } + [nil]).enumerated() {
        let sp = Spider(map: hm)
        sp.config.scale = 1.4
        sp.config.followCursor = false
        sp.debugAttach(loopID: "screen:0", segIdx: 0, t: 300, dir: 1)
        for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        if let th { sp.think(th, for: 4) } else { sp.debugActivity("hop", for: 0.42); sp.debugEmote("exclaim") }
        for _ in 0..<(th == nil ? 8 : 60) { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        let pose = sp.pose()
        let col = i % cols, row = i / cols
        let ox = CGFloat(col * cellW) + CGFloat(cellW) / 2, oy = CGFloat((rows - 1 - row) * cellH) + 40
        c.saveGState()
        c.translateBy(x: ox - pose.pos.x, y: oy - pose.pos.y)
        SpiderRenderer.draw(pose, in: c, bounds: CGRect(x: pose.pos.x - 140, y: pose.pos.y - 140, width: 280, height: 280))
        c.restoreGState()
    }
    guard let img = c.makeImage() else { exit(1) }
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: "build/thoughts.png"))
    print("wrote build/thoughts.png")
    exit(0)
}

// --- swing / hammock --------------------------------------------------------
// `--swing` onion-skins a swing on a line from the floor up past a window;
// `--hammock` films the hammock being spun in a corner and slept in.
if CommandLine.arguments.contains("--swing") || CommandLine.arguments.contains("--hammock") {
    let hammockMode = CommandLine.arguments.contains("--hammock")
    let dt: CGFloat = 1.0 / 60.0
    let dw = 900, dh = 620
    let deskRect = CGRect(x: 0, y: 0, width: CGFloat(dw), height: CGFloat(dh))
    let jm = SurfaceMap()
    jm.standoff = 22 * 1.0
    let win = CGRect(x: 120, y: 120, width: 330, height: 250)
    jm.debugRebuild(screen: deskRect, menuBarHeight: 24,
                    windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock")])
    guard let j = CGContext(data: nil, width: dw * 2, height: dh * 2, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    j.scaleBy(x: 2, y: 2)
    j.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
    j.fill(deskRect)
    j.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
    j.fill(win)
    j.setFillColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
    j.fill(CGRect(x: win.minX, y: win.maxY - 30, width: win.width, height: 30))
    j.setFillColor(NSColor(calibratedWhite: 0.85, alpha: 1).cgColor)
    j.fill(CGRect(x: 0, y: CGFloat(dh) - 24, width: CGFloat(dw), height: 24))

    let sp = Spider(map: jm)
    sp.config.scale = 1.0
    sp.config.followCursor = false
    NSGraphicsContext.current = NSGraphicsContext(cgContext: j, flipped: false)
    let hv = HammockView(frame: CGRect(x: 0, y: 0, width: 190, height: 130))

    if hammockMode {
        // Start on the left wall, part-way up, and set it building. Eight
        // panels of the corner as it spins — the walls drawn in, the live
        // thread from its spinnerets — then the tie-off and a nap, big.
        if let sl = jm.loops.first(where: { $0.id == "screen:0" }), let wall = sl.segs.firstIndex(where: { $0.facing == .right }) {
            let seg = sl.segs[wall]
            sp.debugAttach(loopID: "screen:0", segIdx: wall, t: seg.len * 0.5, dir: 1)
        }
        for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        sp.debugActivity("build", for: 0)
        var frame = 0
        var shots = 0
        var lastShot = -100
        var log: [String] = []
        let panelW: CGFloat = 220, panelH: CGFloat = 170
        // The corner of the world each panel shows: the hammock's rect plus
        // room below and beside it.
        func drawPanel(_ idx: Int, _ pose: SpiderPose, _ h: Hammock) {
            let col = idx % 4, row = idx / 4
            let panel = CGRect(x: 8 + CGFloat(col) * (panelW + 6), y: CGFloat(dh) - 34 - CGFloat(row + 1) * (panelH + 6), width: panelW, height: panelH)
            _ = row
            let world = CGRect(x: h.rect.minX - 10, y: h.rect.maxY - panelH + 30, width: panelW, height: panelH)
            j.saveGState()
            j.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
            j.fill(panel)
            j.clip(to: panel)
            j.translateBy(x: panel.minX - world.minX, y: panel.minY - world.minY)
            // The menu bar and the wall.
            j.setFillColor(NSColor(calibratedWhite: 0.85, alpha: 1).cgColor)
            j.fill(CGRect(x: world.minX, y: CGFloat(dh) - 24, width: world.width, height: 24))
            j.setFillColor(NSColor(calibratedWhite: 0.3, alpha: 1).cgColor)
            j.fill(CGRect(x: world.minX, y: world.minY, width: 10, height: world.height))
            hv.hammock = h
            j.saveGState()
            j.translateBy(x: h.rect.minX, y: h.rect.minY)
            hv.frame = CGRect(x: 0, y: 0, width: h.rect.width, height: h.rect.height)
            hv.draw(hv.bounds)
            j.restoreGState()
            if let silk = SpiderRenderer.silkPath(pose) {
                j.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.8))
                j.setLineWidth(0.9)
                j.addPath(silk)
                j.strokePath()
            }
            let box = CGRect(x: pose.pos.x - 70, y: pose.pos.y - 70, width: 140, height: 140)
            SpiderRenderer.draw(pose, in: j, bounds: box)
            j.restoreGState()
            j.setStrokeColor(CGColor(gray: 0.5, alpha: 1)); j.setLineWidth(1)
            j.stroke(panel.insetBy(dx: 0.5, dy: 0.5))
        }
        var everySpinning = 0
        var drapeShots = 0
        // A close-up strip of it on the silk: the tie-off (top row) and
        // walking in to bed (bottom row), every 6th frame at 2x.
        let sc: CGFloat = 1.3
        let cellW: CGFloat = 200, cellH: CGFloat = 170
        let stripCols = 12
        guard let sctx = CGContext(data: nil, width: Int(cellW) * stripCols * 2, height: Int(cellH) * 2 * 2, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        sctx.scaleBy(x: 2, y: 2)
        sctx.setFillColor(NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.33, alpha: 1).cgColor)
        sctx.fill(CGRect(x: 0, y: 0, width: cellW * CGFloat(stripCols), height: cellH * 2))
        var stripCount = [0, 0]
        var stripLast = [-100, -100]
        func stripShot(_ row: Int, _ pose: SpiderPose, _ h: Hammock) {
            let n = stripCount[row]
            guard n < stripCols else { return }
            stripCount[row] += 1
            let cell = CGRect(x: CGFloat(n) * cellW, y: CGFloat(1 - row) * cellH, width: cellW, height: cellH)
            sctx.saveGState()
            sctx.clip(to: cell)
            sctx.translateBy(x: cell.midX - pose.pos.x * sc, y: cell.midY - pose.pos.y * sc)
            sctx.scaleBy(x: sc, y: sc)
            hv.hammock = h
            sctx.saveGState()
            sctx.translateBy(x: h.rect.minX, y: h.rect.minY)
            hv.frame = CGRect(x: 0, y: 0, width: h.rect.width, height: h.rect.height)
            let keep = NSGraphicsContext.current
            NSGraphicsContext.current = NSGraphicsContext(cgContext: sctx, flipped: false)
            hv.draw(hv.bounds)
            NSGraphicsContext.current = keep
            sctx.restoreGState()
            let box = CGRect(x: pose.pos.x - 60, y: pose.pos.y - 60, width: 120, height: 120)
            SpiderRenderer.draw(pose, in: sctx, bounds: box)
            sctx.restoreGState()
            sctx.setStrokeColor(CGColor(gray: 0.45, alpha: 1)); sctx.setLineWidth(1)
            sctx.stroke(cell.insetBy(dx: 0.5, dy: 0.5))
        }
        while frame < 60 * 120 {
            sp.setCursor(V2(-9e4, -9e4))
            sp.update(dt: dt)
            frame += 1
            let st = sp.debugState
            if log.last != st { log.append(st) }
            let spinning = st.contains("[spinning]") || st == "jump" && (log.last(where: { $0 != "jump" })?.contains("[spinning]") ?? false)
            if spinning { everySpinning += 1 }
            // The first strand draping is the moment to watch closely.
            let draping = (sp.hammock?.drape.first).map { $0 < 1 } ?? false
            let want = (draping && drapeShots < 4 && frame - lastShot > 30)
                || (spinning && frame - lastShot > 240) || (st == "building" && frame - lastShot > 90)
            if want, draping, drapeShots < 4 { drapeShots += 1 }
            if want, shots < 8, let h = sp.hammock {
                lastShot = frame
                shots += 1
                drawPanel(shots - 1, sp.pose(), h)
            }
            if st == "building", frame - stripLast[0] >= 12, let h = sp.hammock { stripLast[0] = frame; stripShot(0, sp.pose(), h) }
            if !spinning && st != "building" && st != "jump" && everySpinning > 60 && sp.hammock?.progress ?? 0 >= 1 { break }
            if sp.hammock == nil && everySpinning > 60 { break }
        }
        print("build took \(frame / 60)s, \(shots) panels")
        // Then a nap in it, drawn big in the middle of the picture so the
        // curled-up pose and the silk over it can be judged.
        if sp.debugState != "nesting" { sp.napInHammock() }
        for _ in 0..<60 * 25 {
            sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt)
            if sp.debugState == "nesting", frame - stripLast[1] >= 10, let h = sp.hammock { stripLast[1] = frame; stripShot(1, sp.pose(), h) }
            frame += 1
            if sp.debugState == "nesting" && sp.hammock?.load ?? 0 > 0.95 { break }
        }
        if let img = sctx.makeImage() {
            try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "build/hammock_strip.png"))
            print("wrote build/hammock_strip.png (top: tying off, bottom: in to bed)")
        }
        for _ in 0..<60 * 3 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        let pose = sp.pose()
        if let h = sp.hammock {
            hv.hammock = h
            j.saveGState()
            // 2.5x, hammock centred in the lower middle of the frame.
            let k: CGFloat = 1.8
            j.translateBy(x: 450 - h.rect.midX * k, y: 150 - h.rect.midY * k)
            j.scaleBy(x: k, y: k)
            let box = CGRect(x: pose.pos.x - 110, y: pose.pos.y - 110, width: 220, height: 220)
            SpiderRenderer.draw(pose, in: j, bounds: box)
            j.saveGState()
            j.translateBy(x: h.rect.minX, y: h.rect.minY)
            hv.frame = CGRect(x: 0, y: 0, width: h.rect.width, height: h.rect.height)
            hv.draw(hv.bounds)
            j.restoreGState()
            j.restoreGState()
            print("nap: \(sp.debugState) style \(h.style.label) load \(h.load)")
        }
        print("states: " + log.joined(separator: " > "))
    } else {
        let fromHang = CommandLine.arguments.contains("--fromhang")
        if fromHang {
            // Rappel from the menu bar, hang a while, then work up a swing.
            sp.debugCalm = true
            sp.debugAttach(loopID: "menu:0", segIdx: 0, t: 600, dir: 1)
            for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
            sp.scroll(-4); sp.scroll(-4); sp.scroll(-4)
            for _ in 0..<240 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        } else if CommandLine.arguments.contains("--floor") {
            sp.debugAttach(loopID: "screen:0", segIdx: 0, t: 120, dir: 1)
        } else {
            sp.debugAttach(loopID: "win:9", segIdx: 0, t: 40, dir: 1)   // top of the window, heading right
        }
        for _ in 0..<20 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        sp.debugActivity("swing", for: 0)
        var trail: [CGPoint] = []
        var frame = 0
        var log: [String] = []
        var done = -1
        var peaks: [String] = []
        var lastVx: CGFloat = 0
        while frame < (fromHang ? 1500 : 400) {
            sp.setCursor(V2(-9e4, -9e4))
            sp.update(dt: dt)
            frame += 1
            trail.append(sp.worldPos.point)
            let st = sp.debugState
            let vx = sp.pose().pos.x - (trail.count > 1 ? CGFloat(trail[trail.count - 2].x) : sp.pose().pos.x)
            if st == "swinging", lastVx != 0, (vx >= 0) != (lastVx >= 0) { peaks.append(String(format: "%.0f", sp.pose().pos.x)) }
            if vx != 0 { lastVx = vx }
            if log.last != st { log.append(st) }
            let pose = sp.pose()
            if frame % 6 == 0, pose.web != nil, let path = SpiderRenderer.silkPath(pose) {
                j.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.35).cgColor)
                j.setLineWidth(1)
                j.beginPath(); j.addPath(path); j.strokePath()
            }
            if frame % (fromHang ? 12 : 6) == 0 {
                let box = CGRect(x: pose.pos.x - 110, y: pose.pos.y - 110, width: 220, height: 220)
                SpiderRenderer.draw(pose, in: j, bounds: box)
            }
            if ProcessInfo.processInfo.environment["FILM_DEBUG"] != nil, st == "jump" || (done > 0) {
                print("f\(frame) \(st) web=\(pose.web.map { "a=\($0.alpha)" } ?? "nil") pts=\(pose.webPoints.count) tail=\(pose.webPoints.last ?? .zero) head=\(pose.webPoints.first ?? .zero)")
            }
            if done < 0, frame > 30, st.hasPrefix("attached") { done = frame }
            if done > 0, frame > done + 12 { break }
        }
        j.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.3).cgColor)
        j.setLineWidth(1.5)
        j.beginPath(); j.addLines(between: trail); j.strokePath()
        print("states: " + log.joined(separator: " > "))
        print("swing reversals at x: " + peaks.joined(separator: " "))
    }
    guard let ji = j.makeImage() else { exit(1) }
    let out = hammockMode ? "build/hammock.png" : "build/swing.png"
    try NSBitmapImageRep(cgImage: ji).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: out))
    print("wrote \(out)")
    exit(0)
}

// --- mock desktop ----------------------------------------------------------
// Judge it the way it is actually seen: real size, on a real-looking desktop.
if CommandLine.arguments.contains("--desk") {
    let dt: CGFloat = 1.0 / 60.0
    let dw = 1100, dh = 700
    guard let d = CGContext(data: nil, width: dw * 2, height: dh * 2,
                            bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    d.scaleBy(x: 2, y: 2)
    let deskRect = CGRect(x: 0, y: 0, width: dw, height: dh)

    // Wallpaper
    if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [NSColor(calibratedRed: 0.16, green: 0.22, blue: 0.34, alpha: 1).cgColor,
                                   NSColor(calibratedRed: 0.35, green: 0.30, blue: 0.42, alpha: 1).cgColor] as CFArray,
                          locations: [0, 1]) {
        d.drawLinearGradient(g, start: CGPoint(x: 0, y: dh), end: CGPoint(x: dw, y: 0), options: [])
    }
    // Menu bar
    d.setFillColor(NSColor(calibratedWhite: 0.12, alpha: 0.55).cgColor)
    d.fill(CGRect(x: 0, y: CGFloat(dh) - 30, width: CGFloat(dw), height: 30))
    // A window
    let win = CGRect(x: 210, y: 170, width: 620, height: 400)
    d.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
    d.fill(win)
    d.setFillColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
    d.fill(CGRect(x: win.minX, y: win.maxY - 34, width: win.width, height: 34))
    for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        d.setFillColor(c.cgColor)
        d.fillEllipse(in: CGRect(x: win.minX + 14 + CGFloat(i) * 18, y: win.maxY - 22, width: 11, height: 11))
    }

    // A second window behind the first, overlapping it.
    let back = CGRect(x: 640, y: 80, width: 400, height: 300)
    d.setFillColor(NSColor(calibratedWhite: 0.17, alpha: 1).cgColor)
    d.fill(back)
    d.setFillColor(NSColor(calibratedWhite: 0.24, alpha: 1).cgColor)
    d.fill(CGRect(x: back.minX, y: back.maxY - 34, width: back.width, height: 34))
    // redraw the front window over it
    d.setFillColor(NSColor(calibratedWhite: 0.13, alpha: 1).cgColor)
    d.fill(win)
    d.setFillColor(NSColor(calibratedWhite: 0.20, alpha: 1).cgColor)
    d.fill(CGRect(x: win.minX, y: win.maxY - 34, width: win.width, height: 34))

    let deskMap = SurfaceMap()
    deskMap.standoff = 22 * 0.95
    // Pretend this canvas is the screen.
    deskMap.debugRebuild(screen: deskRect, menuBarHeight: 30,
                         windows: [TrackedWindow(id: 9, frame: win, depth: 0, owner: "Mock"),
                                   TrackedWindow(id: 8, frame: back, depth: 1, owner: "Back")])

    struct Spot { var loop: String; var seg: Int; var t: CGFloat }
    let spots = [
        Spot(loop: "screen:0", seg: 0, t: 150),    // bottom edge
        Spot(loop: "screen:0", seg: 1, t: 260),    // right edge
        Spot(loop: "screen:0", seg: 3, t: 260),    // left edge
        Spot(loop: "menu:0", seg: 0, t: 640),      // under the menu bar
        Spot(loop: "win:9", seg: 0, t: 130),       // on the top shelf
        Spot(loop: "win:9", seg: 0, t: 450),       // further along it
        Spot(loop: "win:9", seg: 2, t: 300),       // under the bottom lip
        Spot(loop: "win:9", seg: 3, t: 200),       // on the left edge
        Spot(loop: "win:9", seg: 1, t: 120)        // on the right edge
    ]
    // Every allowed spot on the back window, so the covered stretch shows as
    // a gap.
    var placed: [Spot] = spots
    for l in deskMap.loops where l.id == "win:8" {
        for (i, seg) in l.segs.enumerated() {
            var t: CGFloat = 40
            while t < seg.len - 30 {
                if seg.isOpen(at: t) { placed.append(Spot(loop: l.id, seg: i, t: t)) }
                t += 95
            }
        }
    }
    for spot in placed {
        let sp = Spider(map: deskMap)
        sp.config.scale = 0.95
        sp.debugAttach(loopID: spot.loop, segIdx: spot.seg, t: spot.t, dir: 1)
        sp.debugWalk(for: 30)
        for _ in 0..<70 { sp.setCursor(V2(-9e4, -9e4)); sp.update(dt: dt) }
        let pose = sp.pose()
        let box = CGRect(x: pose.pos.x - 100, y: pose.pos.y - 100, width: 200, height: 200)
        SpiderRenderer.draw(pose, in: d, bounds: box)
    }

    guard let di = d.makeImage() else { exit(1) }
    let r = NSBitmapImageRep(cgImage: di)
    try r.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "build/desk.png"))
    print("wrote build/desk.png (\(dw)x\(dh))")
    exit(0)
}

guard let img = ctx.makeImage() else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/film.png"
let rep = NSBitmapImageRep(cgImage: img)
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) (\(width)x\(height))")
