import AppKit
import CoreGraphics

/// Draws the spider from a pose, in body-local units:
///   +x is forward (the way it faces), +y is to its left.
/// One local unit is one point at scale 1. The whole critter is ~46 units long.
enum SpiderRenderer {

    // MARK: Palette (sampled from the reference art)

    static let outline   = CGColor(red: 0.298, green: 0.180, blue: 0.086, alpha: 1)
    static let bodyFill  = CGColor(red: 0.878, green: 0.604, blue: 0.333, alpha: 1)
    static let bodyLight = CGColor(red: 0.945, green: 0.729, blue: 0.486, alpha: 1)
    static let headFill  = CGColor(red: 0.898, green: 0.655, blue: 0.392, alpha: 1)
    static let legFill   = CGColor(red: 0.788, green: 0.518, blue: 0.278, alpha: 1)
    static let legLight  = CGColor(red: 0.855, green: 0.596, blue: 0.345, alpha: 1)
    /// Legs on the far side of the body sit in its shadow.
    static let legFar    = CGColor(red: 0.690, green: 0.435, blue: 0.220, alpha: 1)
    static let outlineFar = CGColor(red: 0.255, green: 0.150, blue: 0.070, alpha: 1)
    static let eyeDark   = CGColor(red: 0.239, green: 0.129, blue: 0.055, alpha: 1)
    static let white     = CGColor(red: 1, green: 1, blue: 1, alpha: 1)

    /// Palettes are derived from the coat, so cache them per colourway.
    private static var paletteCache: [String: Palette] = [:]
    static func palette(for look: SpiderLook) -> Palette {
        let key = look.coat.rawValue + "/" + look.accent.rawValue
        if let p = paletteCache[key] { return p }
        let p = Palette(coat: look.coat, accent: look.accent)
        paletteCache[key] = p
        return p
    }

    // MARK: Metrics
    //
    // The spider is drawn in profile, standing on a ledge: +x is the way it is
    // facing, +y is up off the ledge, and the origin is the body centre. Its
    // feet reach down to `ground`. Seen from the side, a spider on a shelf
    // reads as standing on the shelf; seen from above it reads as crawling
    // across whatever is behind it.

    static let ground: CGFloat = -22
    /// What the body leans about: a point between the hips.
    static let leanPivot = V2(1, -8)
    static let abdomen = (c: V2(-14.0, 3.0), rx: CGFloat(14.0), ry: CGFloat(13.0))
    static let head    = (c: V2(9.5, 0.5), r: CGFloat(13.0))

    /// Face is turned three-quarters toward the viewer, so all four front eyes
    /// show even though the body is in profile.
    static let eyes: [(c: V2, r: CGFloat, big: Bool)] = [
        (V2(16.2, 1.2), 4.7, true),     // near anterior median
        (V2(10.0, 3.6), 3.8, true),     // far anterior median
        (V2(19.6, 6.4), 2.5, false),    // near lateral
        (V2(5.6, 7.0), 2.1, false),     // far lateral
    ]

    // MARK: Leg rig

    struct LegRig {
        var hip: V2
        var knee: V2
        var foot: V2
    }

    /// The classic side-on spider silhouette: each leg rises from the hip to a
    /// knee above the body line and drops to the ledge. Near-side legs are
    /// drawn in front of the body, far-side legs behind it and a shade darker,
    /// with the feet staggered so all eight are visible.
    static let nearLegs: [LegRig] = [
        LegRig(hip: V2(9, -9), knee: V2(24, 2), foot: V2(30, ground)),     // reaches ahead of the face
        LegRig(hip: V2(6, -10), knee: V2(15, -8), foot: V2(18, ground)),   // short, tucked under the chin
        LegRig(hip: V2(1, -10), knee: V2(-6, -5), foot: V2(-6, ground)),
        LegRig(hip: V2(-3, -9), knee: V2(-17, -1), foot: V2(-24, ground)),
    ]
    static let farLegs: [LegRig] = [
        LegRig(hip: V2(7, -7), knee: V2(21, 5), foot: V2(26, ground)),
        LegRig(hip: V2(4, -8), knee: V2(11, 1), foot: V2(13, ground)),
        LegRig(hip: V2(-1, -8), knee: V2(-11, 2), foot: V2(-13, ground)),
        LegRig(hip: V2(-5, -7), knee: V2(-21, 3), foot: V2(-30, ground)),
    ]

    /// Legs 0-3 are the near side, 4-7 the far side, front to back.
    static func rig(_ index: Int) -> LegRig {
        index < 4 ? nearLegs[index] : farLegs[index - 4]
    }
    static let legCount = 8

    // MARK: Front view
    //
    // Turning round is drawn as a real turn: the profile swings through a
    // front view (the pose of the reference art) and out the other side. Every
    // layout below is interpolated between profile and front by `profile`
    // (1 = side on, 0 = facing you).

    static let frontAbdomen = (c: V2(0, 7.0), rx: CGFloat(13.5), ry: CGFloat(12.5))
    static let frontHead    = (c: V2(0, -1.0), r: CGFloat(13.0))
    /// Same order as `eyes`: near AME, far AME, near lateral, far lateral.
    static let frontEyes: [(c: V2, r: CGFloat, big: Bool)] = [
        (V2(4.8, 0.2), 4.5, true),
        (V2(-4.8, 0.2), 4.5, true),
        (V2(11.6, 1.4), 2.9, false),
        (V2(-11.6, 1.4), 2.9, false),
    ]
    /// Indexed like the profile rig. Each leg's front-view spot is the one
    /// nearest its profile spot, so feet only shuffle a few units in a turn;
    /// and the layout is symmetric under i <-> 7-i, which is what lets the
    /// sprite mirror at the front view without any foot jumping.
    static let frontLegs: [LegRig] = [
        LegRig(hip: V2(8, -8), knee: V2(31, -4), foot: V2(38, ground)),
        LegRig(hip: V2(7, -9), knee: V2(18, 0), foot: V2(22, ground)),
        LegRig(hip: V2(-5, -9), knee: V2(-11, -3), foot: V2(-14, ground)),
        LegRig(hip: V2(-8, -8), knee: V2(-25, -1), foot: V2(-31, ground)),
        LegRig(hip: V2(8, -8), knee: V2(25, -1), foot: V2(31, ground)),
        LegRig(hip: V2(5, -9), knee: V2(11, -3), foot: V2(14, ground)),
        LegRig(hip: V2(-7, -9), knee: V2(-18, 0), foot: V2(-22, ground)),
        LegRig(hip: V2(-8, -8), knee: V2(-31, -4), foot: V2(-38, ground)),
    ]

    static func rig(_ index: Int, profile: CGFloat, look: SpiderLook = SpiderLook()) -> LegRig {
        let a = rig(index), b = frontLegs[index]
        let f = clamp(profile, 0, 1)
        var r = LegRig(hip: V2.lerp(b.hip, a.hip, f), knee: V2.lerp(b.knee, a.knee, f),
                       foot: V2.lerp(b.foot, a.foot, f))
        // Leg styles stretch or shorten the reach from the hip; the feet stay
        // on the ledge, so a long-legged spider stands wider and higher-kneed.
        let m = look.legs.metrics
        if m.reach != 1 || m.knee != 0 {
            r.foot.x = r.hip.x + (r.foot.x - r.hip.x) * m.reach
            r.knee = r.hip + (r.knee - r.hip) * m.reach + V2(0, m.knee)
        }
        return r
    }

    /// Abdomen and head metrics for a body shape, in profile.
    static func abdomen(for look: SpiderLook) -> (c: V2, rx: CGFloat, ry: CGFloat) {
        let m = look.body.metrics
        return (abdomen.c, abdomen.rx * m.arx, abdomen.ry * m.ary)
    }
    static func head(for look: SpiderLook) -> (c: V2, r: CGFloat) {
        (head.c, head.r * look.body.metrics.head)
    }

    /// Eased blend so the turn dwells briefly at the front view.
    static func profileAmount(yaw: CGFloat) -> CGFloat {
        smoothstep(abs(yaw))
    }

    /// Where the knee goes for a leg whose foot has moved away from its rest
    /// position: the rest shape swung about the hip and stretched to reach.
    /// A leg in the air folds up — the crook deepens rather than the limb
    /// lengthening — which is what a raised leg looks like.
    static func knee(leg index: Int, hip: V2, foot: V2, lift: CGFloat, profile: CGFloat = 1,
                     look: SpiderLook = SpiderLook()) -> V2 {
        let r = rig(index, profile: profile, look: look)
        let restVec = r.foot - r.hip
        let curVec = foot - hip
        let restLen = max(restVec.length, 0.01)
        let swing = angleDelta(restVec.angle, curVec.angle)
        let reach = clamp(curVec.length / restLen, 0.5, 1.3)
        var off = (r.knee - r.hip).rotated(by: swing) * reach
        if lift > 0.001 {
            let bulge: CGFloat = restVec.cross(r.knee - r.hip) >= 0 ? 1 : -1
            off = off.rotated(by: bulge * lift * 0.18)
        }
        return hip + off
    }

    /// Two-bone IK for a leg holding something: femur and tibia keep their
    /// rest lengths and the knee goes to whichever side of the hip-foot line
    /// `away` points, so a leg wrapped round a thread bends outward from it.
    /// Beyond full stretch the knee sits on the line and the tibia reaches.
    static func kneeIK(leg index: Int, hip: V2, foot: V2, away: V2, profile: CGFloat = 1,
                       look: SpiderLook = SpiderLook()) -> V2 {
        let r = rig(index, profile: profile, look: look)
        let a = max((r.knee - r.hip).length, 1)
        let b = max((r.foot - r.knee).length, 1)
        var d = foot - hip
        var dist = d.length
        if dist < 0.01 { d = V2(1, 0); dist = 1 }
        let dir = d / dist
        let reach = clamp(dist, abs(a - b) + 0.5, a + b - 0.5)
        let x = (a * a - b * b + reach * reach) / (2 * reach)
        let h = max(a * a - x * x, 0).squareRoot()
        let perp = dir.perp
        let side: CGFloat = perp.dot(away) >= 0 ? 1 : -1
        return hip + dir * x + perp * (h * side)
    }

    /// A smooth curve through the line's points, in world space; a plain
    /// sagging thread when there are none.
    static func silkPath(_ pose: SpiderPose, origin: V2 = .zero) -> CGPath? {
        guard let web = pose.web else { return nil }
        let p = CGMutablePath()
        let pts = pose.webPoints.count >= 2 ? pose.webPoints : [web.anchor, pose.silkAttach]
        let a = (pts[0] - origin).point
        if pts.count == 2 {
            let b = (pts[1] - origin).point
            let sag = 4 + web.slack * 36
            p.move(to: a)
            p.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 - sag))
        } else {
            // Catmull-Rom through the points, as cubic Beziers.
            p.move(to: a)
            let n = pts.count
            for i in 0..<(n - 1) {
                let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, n - 1)]
                let c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6
                p.addCurve(to: (p2 - origin).point, control1: (c1 - origin).point, control2: (c2 - origin).point)
            }
        }
        // Anchor tuft
        for i in 0..<3 {
            let ang = CGFloat(i) * 2.1 + 0.5
            p.move(to: a)
            p.addLine(to: CGPoint(x: a.x + cos(ang) * 4.5, y: a.y + sin(ang) * 3.0))
        }
        return p
    }

    /// The stretch of line it is holding, drawn in the sprite between the
    /// far legs and the body, so the far feet sit behind it and the near
    /// feet in front. With it, any loose silk trailing from the spinnerets.
    private static func drawThread(_ pose: SpiderPose, in ctx: CGContext) {
        guard let th = pose.thread, th.alpha > 0.01 else { return }
        let w = 1.1 / max(pose.scale, 0.2)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: Double(0.28 * th.alpha)))
        ctx.setLineWidth(w * 2.4)
        ctx.beginPath(); ctx.move(to: th.a.point); ctx.addLine(to: th.b.point); ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: Double(0.62 * th.alpha)))
        ctx.setLineWidth(w)
        ctx.beginPath(); ctx.move(to: th.a.point); ctx.addLine(to: th.b.point); ctx.strokePath()
        if th.tail > 0.01 {
            // Gathered silk hanging on behind, wavering a little.
            let back = (th.a - th.b).normalized
            let side = back.perp
            let t = pose.time
            let len = 34 * th.tail
            let p = CGMutablePath()
            p.move(to: th.a.point)
            let c1 = th.a + back * (len * 0.35) + side * (sin(t * 4.1) * 1.6)
            let c2 = th.a + back * (len * 0.7) + side * (sin(t * 3.3 + 1.7) * 2.4)
            let e = th.a + back * len + side * (sin(t * 2.6 + 0.9) * 3.0)
            p.addCurve(to: e.point, control1: c1.point, control2: c2.point)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: Double(0.45 * th.alpha * th.tail)))
            ctx.setLineWidth(w * 0.9)
            ctx.addPath(p); ctx.strokePath()
        }
    }

    /// The furthest anything is drawn from the body origin, in body units.
    /// `./build/Preview x --cliptest` measures the real figure; raise this if
    /// that ever reports it is too small.
    static let drawRadius: CGFloat = 72

    /// Side of the layer the spider is drawn into. Single source of truth: the
    /// app and the clip check both use it, so they cannot drift apart.
    static func spriteSide(for scale: CGFloat) -> CGFloat {
        max(100, (drawRadius * 2 * scale).rounded())
    }

    // MARK: Entry point

    /// `bounds` is the layer's rect; the body origin is drawn at its centre.
    static func draw(_ pose: SpiderPose, in ctx: CGContext, bounds: CGRect) {
        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.translateBy(x: bounds.midX, y: bounds.midY)
        // Normalise to y-up regardless of how the backing context is oriented.
        if ctx.ctm.d < 0 { ctx.scaleBy(x: 1, y: -1) }

        // Whatever falls inside a window in front of it is behind that
        // window: cut it out of everything drawn from here on.
        if !pose.hiddenBy.isEmpty {
            let big = CGRect(x: -bounds.width, y: -bounds.height, width: bounds.width * 2, height: bounds.height * 2)
            let p = CGMutablePath()
            p.addRect(big)
            for r in pose.hiddenBy {
                p.addRect(r.offsetBy(dx: -pose.pos.x, dy: -pose.pos.y).intersection(big))
            }
            ctx.addPath(p)
            ctx.clip(using: .evenOdd)
        }

        // Emotes ride above the spider in screen space, so draw them before the
        // body transform is applied.
        drawEmote(pose, in: ctx)
        drawNameTag(pose, in: ctx)
        let look = pose.outfit
        let pal = palette(for: look)

        ctx.saveGState()
        ctx.rotate(by: pose.heading)
        // `facing` is a yaw: its sign picks the mirror, its magnitude how far
        // toward profile (1) or the front view (0) the body has turned.
        let mirror: CGFloat = pose.facing >= 0 ? 1 : -1
        ctx.scaleBy(x: pose.scale * mirror, y: pose.scale)
        // Squash and stretch: along the body when leaping, vertically when it
        // lands, with the feet as the pivot so it squashes *onto* the ledge.
        ctx.translateBy(x: 0, y: ground)
        ctx.scaleBy(x: pose.stretch, y: pose.fatten)
        ctx.translateBy(x: 0, y: -ground)

        let profile = profileAmount(yaw: pose.facing)
        drawGroundShadow(pose, in: ctx)
        if pose.spin != 0 {
            // Rolling: the body turns about its own middle.
            ctx.translateBy(x: -3, y: 0)
            ctx.rotate(by: pose.spin)
            ctx.translateBy(x: 3, y: 0)
        }
        // The lean turns the body, face and hat about the hips; the legs are
        // drawn outside it, from hips the pose has already moved, so planted
        // feet stay on the ground while the body leans over them.
        func lean(_ ctx: CGContext) {
            let pv = leanPivot
            ctx.translateBy(x: pv.x + pose.bodyShift.x, y: pv.y + pose.bodyShift.y)
            ctx.rotate(by: pose.bodyPitch)
            ctx.translateBy(x: -pv.x, y: -pv.y)
        }
        drawLegs(pose, far: true, profile: profile, look: look, pal: pal, in: ctx)
        ctx.saveGState()
        lean(ctx)
        drawThread(pose, in: ctx)
        drawBody(pose, profile: profile, look: look, pal: pal, in: ctx)
        ctx.restoreGState()
        drawLegs(pose, far: false, profile: profile, look: look, pal: pal, in: ctx)
        ctx.saveGState()
        lean(ctx)
        let hcN = V2.lerp(frontHead.c, head.c, profile)
        let hrN = lerp(frontHead.r, head.r, profile) * look.body.metrics.head
        headTurn(pose, hc: hcN, hr: hrN, profile: profile, in: ctx)
        drawFace(pose, profile: profile, look: look, pal: pal, in: ctx)
        drawFaceAccessory(pose, profile: profile, look: look, pal: pal, in: ctx)
        drawHat(pose, profile: profile, look: look, pal: pal, in: ctx)
        ctx.restoreGState()

        ctx.restoreGState()
        ctx.restoreGState()
    }

    // MARK: Shapes

    /// An ellipse with a soft scalloped rim — the "fuzzy" silhouette of the art.
    static func fuzzyEllipse(_ c: V2, _ rx: CGFloat, _ ry: CGFloat,
                             bumps: Int, amp: CGFloat, phase: CGFloat = 0) -> CGPath {
        let path = CGMutablePath()
        let steps = max(bumps * 5, 48)
        var pts: [CGPoint] = []
        pts.reserveCapacity(steps)
        for i in 0..<steps {
            let a = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let m = 1 + amp * sin(a * CGFloat(bumps) + phase)
            pts.append(CGPoint(x: c.x + cos(a) * rx * m, y: c.y + sin(a) * ry * m))
        }
        path.move(to: midpoint(pts[pts.count - 1], pts[0]))
        for i in 0..<pts.count {
            let cur = pts[i]
            let next = pts[(i + 1) % pts.count]
            path.addQuadCurve(to: midpoint(cur, next), control: cur)
        }
        path.closeSubpath()
        return path
    }

    private static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// A soft highlight faked with concentric fills: clipping a gradient to the
    /// outline looks marginally better and costs several times more.
    private static func sheen(_ ctx: CGContext, at c: V2, rx: CGFloat, ry: CGFloat, alpha: CGFloat,
                              colour: CGColor = bodyLight) {
        let rings = 4
        for i in 0..<rings {
            let f = CGFloat(i + 1) / CGFloat(rings)
            ctx.setFillColor(colour.copy(alpha: alpha / CGFloat(rings))!)
            ctx.fillEllipse(in: CGRect(x: c.x - rx * f, y: c.y - ry * f,
                                       width: rx * f * 2, height: ry * f * 2))
        }
    }

    // MARK: Pieces

    private static func drawGroundShadow(_ pose: SpiderPose, in ctx: CGContext) {
        // A contact shadow along the ledge, under the feet.
        guard pose.grounded > 0.01 else { return }
        ctx.setFillColor(CGColor(red: 0.20, green: 0.12, blue: 0.05, alpha: Double(0.05 * pose.grounded)))
        for i in 0..<3 {
            let grow = CGFloat(3 - i) * 2.2
            ctx.fillEllipse(in: CGRect(x: -30 - grow, y: ground - 3.5 - grow * 0.35,
                                       width: 60 + grow * 2, height: 7 + grow * 0.7))
        }
    }

    private static func drawLegs(_ pose: SpiderPose, far: Bool, profile: CGFloat,
                                 look: SpiderLook, pal: Palette, in ctx: CGContext) {
        // Back legs first so the front pair sits on top.
        let order = far ? [7, 6, 5, 4] : [3, 2, 1, 0]
        for idx in order where idx < pose.legs.count {
            drawLeg(pose.legs[idx], far: far, profile: profile, look: look, pal: pal, in: ctx)
        }
    }

    private static func mix(_ a: CGColor, _ b: CGColor, _ t: CGFloat) -> CGColor {
        let ca = a.components ?? [0, 0, 0, 1], cb = b.components ?? [0, 0, 0, 1]
        return CGColor(red: lerp(ca[0], cb[0], t), green: lerp(ca[1], cb[1], t),
                       blue: lerp(ca[2], cb[2], t), alpha: 1)
    }

    private static func drawLeg(_ leg: LegPose, far: Bool, profile: CGFloat,
                                look: SpiderLook, pal: Palette, in ctx: CGContext) {
        let hip = leg.hip.point
        let knee = leg.knee.point
        let foot = leg.foot.point

        // Far-side legs are thinner and darker in profile; the difference
        // fades away as it turns to face you.
        let shade = far ? profile : 0
        let wm = look.legs.metrics.width
        let femurW: CGFloat = lerp(5.6, 4.8, shade) * wm
        let tibiaW: CGFloat = lerp(4.4, 3.8, shade) * wm
        let ow: CGFloat = 2.3
        let rim = mix(pal.outline, pal.outlineFar, shade)
        // A lifted foot is lit a touch more, blended by how far it is lifted
        // rather than switched, so nothing pops.
        let fill = mix(mix(pal.legFill, pal.legFar, shade), pal.legLight, clamp(leg.lift, 0, 1) * (1 - shade) * 0.8)

        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Fuzzy legs: a fringe of short hairs along each segment, under the outline.
        if look.legs == .fuzzy || look.fuzz == 2 {
            ctx.setStrokeColor(rim)
            ctx.setLineWidth(1.1)
            let n = look.legs == .fuzzy ? 5 : 3
            for (a, b) in [(hip, knee), (knee, foot)] {
                let d = V2(b.x - a.x, b.y - a.y)
                let len = max(d.length, 0.01)
                let perp = V2(-d.y / len, d.x / len)
                let hair: CGFloat = look.legs == .fuzzy ? 3.2 : 2.2
                for i in 0..<n {
                    let u = (CGFloat(i) + 0.5) / CGFloat(n)
                    let p = V2(a.x + d.x * u, a.y + d.y * u)
                    for side in [CGFloat(1), -1] {
                        let tip = p + perp * (side * ((femurW + ow) / 2 + hair)) + d * (0.04 / len * 10)
                        ctx.beginPath(); ctx.move(to: p.point); ctx.addLine(to: tip.point); ctx.strokePath()
                    }
                }
            }
        }

        ctx.setStrokeColor(rim)
        ctx.setLineWidth(femurW + ow)
        ctx.beginPath(); ctx.move(to: hip); ctx.addLine(to: knee); ctx.strokePath()
        ctx.setLineWidth(tibiaW + ow)
        ctx.beginPath(); ctx.move(to: knee); ctx.addLine(to: foot); ctx.strokePath()

        let padR = tibiaW * 0.62
        ctx.setFillColor(rim)
        ctx.fillEllipse(in: CGRect(x: foot.x - padR - ow / 2, y: foot.y - padR - ow / 2,
                                   width: (padR + ow / 2) * 2, height: (padR + ow / 2) * 2))

        ctx.setStrokeColor(fill)
        ctx.setLineWidth(femurW)
        ctx.beginPath(); ctx.move(to: hip); ctx.addLine(to: knee); ctx.strokePath()
        ctx.setLineWidth(tibiaW)
        ctx.beginPath(); ctx.move(to: knee); ctx.addLine(to: foot); ctx.strokePath()
        ctx.setFillColor(fill)
        ctx.fillEllipse(in: CGRect(x: foot.x - padR, y: foot.y - padR,
                                   width: padR * 2, height: padR * 2))

        // Markings, painted inside the leg's own width.
        switch look.legs {
        case .banded:
            let accent = mix(pal.accent, pal.legFar, shade * 0.5)
            ctx.setStrokeColor(accent)
            ctx.setLineCap(.butt)
            for (a, b, w) in [(hip, knee, femurW), (knee, foot, tibiaW)] {
                let d = V2(b.x - a.x, b.y - a.y)
                ctx.setLineWidth(w)
                for u in [CGFloat(0.35), 0.62] {
                    let p0 = V2(a.x + d.x * (u - 0.07), a.y + d.y * (u - 0.07))
                    let p1 = V2(a.x + d.x * (u + 0.07), a.y + d.y * (u + 0.07))
                    ctx.beginPath(); ctx.move(to: p0.point); ctx.addLine(to: p1.point); ctx.strokePath()
                }
            }
            ctx.setLineCap(.round)
        case .socks:
            let accent = mix(pal.accent, pal.legFar, shade * 0.5)
            ctx.setStrokeColor(accent)
            ctx.setLineWidth(tibiaW)
            let d = V2(foot.x - knee.x, foot.y - knee.y)
            let p0 = V2(knee.x + d.x * 0.62, knee.y + d.y * 0.62)
            ctx.beginPath(); ctx.move(to: p0.point); ctx.addLine(to: foot); ctx.strokePath()
            ctx.setFillColor(accent)
            ctx.fillEllipse(in: CGRect(x: foot.x - padR, y: foot.y - padR, width: padR * 2, height: padR * 2))
        default:
            break
        }
    }

    private static func drawBody(_ pose: SpiderPose, profile f: CGFloat,
                                 look: SpiderLook, pal: Palette, in ctx: CGContext) {
        let bm = look.body.metrics
        let ac = V2.lerp(frontAbdomen.c, abdomen.c, f)
        let arx = lerp(frontAbdomen.rx, abdomen.rx, f) * bm.arx
        let ary = lerp(frontAbdomen.ry, abdomen.ry, f) * bm.ary
        let hc = V2.lerp(frontHead.c, head.c, f)
        let hr = lerp(frontHead.r, head.r, f) * bm.head
        let amp: CGFloat = [0.012, 0.030, 0.048][clamp(look.fuzz, 0, 2)]

        // Wings rise from behind the body.
        if look.accessory == .wings {
            drawBackwear(look, pose: pose, ac: ac, arx: arx, ary: ary, hc: hc, hr: hr, profile: f, pal: pal, in: ctx)
        }

        // The abdomen bobs a touch as it walks, hinged where it meets the head.
        ctx.saveGState()
        ctx.translateBy(x: ac.x + arx * 0.6 * f, y: ac.y)
        ctx.rotate(by: pose.abdomenSway * 0.18 * f)
        ctx.translateBy(x: -(ac.x + arx * 0.6 * f), y: -ac.y)
        let abPath = fuzzyEllipse(ac, arx, ary, bumps: 15, amp: amp, phase: 0.4)
        if look.fuzz == 2 { drawHairs(ac, arx, ary, count: 22, colour: pal.outline, in: ctx) }
        ctx.addPath(abPath)
        ctx.setFillColor(pal.bodyFill)
        ctx.fillPath()
        sheen(ctx, at: V2(ac.x - 2 * f, ac.y + 5), rx: arx * 0.7, ry: ary * 0.68, alpha: 0.30, colour: pal.bodyLight)
        drawPattern(look, ac: ac, arx: arx, ary: ary, profile: f, path: abPath, pal: pal, in: ctx)
        ctx.addPath(abPath)
        ctx.setStrokeColor(pal.outline)
        ctx.setLineWidth(2.5)
        ctx.strokePath()
        if look.accessory == .backpack { drawBackpack(ac: ac, arx: arx, ary: ary, profile: f, pal: pal, in: ctx) }
        if look.accessory == .satchel { drawSatchel(ac: ac, arx: arx, ary: ary, profile: f, pal: pal, in: ctx) }
        if look.accessory == .cape { drawBackwear(look, pose: pose, ac: ac, arx: arx, ary: ary, hc: hc, hr: hr, profile: f, pal: pal, in: ctx) }
        ctx.restoreGState()

        // Neckwear sits between the two body segments, under the head.
        if look.accessory == .scarf || look.accessory == .bandana || look.accessory == .collar
            || look.accessory == .necktie || look.accessory == .lei {
            drawNeckwear(look, hc: hc, hr: hr, ac: ac, ary: ary, profile: f, pal: pal, in: ctx)
        }

        // The head (with the palps, face and hat) can tip up on its neck,
        // separately from the body's own lean — that is the look of it
        // gazing up at something.
        ctx.saveGState()
        headTurn(pose, hc: hc, hr: hr, profile: f, in: ctx)
        defer { ctx.restoreGState() }

        // Pedipalps: two little paddles held out in front of the face. Side by
        // side in profile, either side of the chin from the front.
        let palps: [(V2, V2, CGFloat)] = [
            (V2.lerp(V2(3.5, -9), V2(head.c.x + 7.5, -7.0), f),
             V2.lerp(V2(4.5, -14.5), V2(head.c.x + 14.5, -10.5 - pose.happy * 1.2), f), 1.0),
            (V2.lerp(V2(-3.5, -9), V2(head.c.x + 7.5, -4.5), f),
             V2.lerp(V2(-4.5, -14.5), V2(head.c.x + 14.5, -8.0 - pose.happy * 1.2), f), 0.8),
        ]
        for (base, tip, w) in palps {
            ctx.setLineCap(.round)
            ctx.setStrokeColor(pal.outline)
            ctx.setLineWidth(5.6 * w)
            ctx.beginPath(); ctx.move(to: base.point); ctx.addLine(to: tip.point); ctx.strokePath()
            ctx.setStrokeColor(pal.legFill)
            ctx.setLineWidth(3.6 * w)
            ctx.beginPath(); ctx.move(to: base.point); ctx.addLine(to: tip.point); ctx.strokePath()
        }

        let hdPath = fuzzyEllipse(hc, hr, hr, bumps: 12, amp: amp * 0.9, phase: 2.0)
        if look.fuzz == 2 { drawHairs(hc, hr, hr, count: 14, colour: pal.outline, in: ctx) }
        ctx.addPath(hdPath)
        ctx.setFillColor(pal.headFill)
        ctx.fillPath()
        sheen(ctx, at: V2(hc.x - 2 * f, hc.y + 4), rx: hr * 0.66, ry: hr * 0.66, alpha: 0.28, colour: pal.bodyLight)
        ctx.addPath(hdPath)
        ctx.setStrokeColor(pal.outline)
        ctx.setLineWidth(2.5)
        ctx.strokePath()
    }

    /// Where the head joins the body: the head tips about this.
    static func neck(hc: V2, hr: CGFloat, profile f: CGFloat) -> V2 {
        V2(hc.x - hr * 0.55 * f, hc.y - hr * 0.35)
    }

    /// Rotates the context for the head's tilt, nose up for a positive tilt.
    static func headTurn(_ pose: SpiderPose, hc: V2, hr: CGFloat, profile f: CGFloat, in ctx: CGContext) {
        guard abs(pose.headTilt) > 0.0005 else { return }
        let n = neck(hc: hc, hr: hr, profile: f)
        ctx.translateBy(x: n.x, y: n.y)
        ctx.rotate(by: pose.headTilt * max(f, 0.35))
        ctx.translateBy(x: -n.x, y: -n.y)
    }

    /// Short hairs standing off an ellipse's rim.
    private static func drawHairs(_ c: V2, _ rx: CGFloat, _ ry: CGFloat, count: Int,
                                  colour: CGColor, in ctx: CGContext) {
        ctx.setStrokeColor(colour.copy(alpha: 0.75)!)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.round)
        for i in 0..<count {
            let a = (CGFloat(i) + 0.5) / CGFloat(count) * 2 * .pi
            let n = V2(cos(a) * ry, sin(a) * rx).normalized
            let p = V2(c.x + cos(a) * rx, c.y + sin(a) * ry)
            let len = 2.2 + sin(a * 3.7 + CGFloat(count)) * 0.8
            let tip = p + n * len + V2(0, 0.4)
            ctx.beginPath(); ctx.move(to: p.point); ctx.addLine(to: tip.point); ctx.strokePath()
        }
    }

    /// Markings on the abdomen, clipped to it. Patterns are laid out in the
    /// abdomen's own frame (u toward the head, v up), and squeezed onto the
    /// centre line as the body turns to the front view, so they never jump
    /// when the sprite mirrors.
    private static func drawPattern(_ look: SpiderLook, ac: V2, arx: CGFloat, ary: CGFloat,
                                    profile f: CGFloat, path: CGPath, pal: Palette, in ctx: CGContext) {
        guard look.pattern != .plain else { return }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.translateBy(x: ac.x, y: ac.y)
        // The layout narrows toward the front view, and a mirrored copy fades
        // in there, so at the moment the sprite mirrors the marking is
        // already symmetric and nothing jumps.
        let squeeze = lerp(0.55, 1, f)
        let mirrorAlpha = 1 - smoothstep(f)
        paintPattern(look.pattern, arx: arx * squeeze, ary: ary, alpha: 1, pal: pal, in: ctx)
        if mirrorAlpha > 0.01 {
            paintPattern(look.pattern, arx: -arx * squeeze, ary: ary, alpha: mirrorAlpha, pal: pal, in: ctx)
        }
        ctx.restoreGState()
    }

    /// One copy of a marking in the abdomen's unit frame (u toward the head,
    /// v up), scaled by the given radii. A negative `arx` mirrors it.
    private static func paintPattern(_ pattern: Pattern, arx: CGFloat, ary: CGFloat, alpha: CGFloat,
                                     pal: Palette, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.scaleBy(x: arx, y: ary)
        ctx.setFillColor(pal.accent)
        ctx.setStrokeColor(pal.accent)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let sx = abs(arx)
        func ellipse(_ u: CGFloat, _ v: CGFloat, _ ru: CGFloat, _ rv: CGFloat) {
            ctx.fillEllipse(in: CGRect(x: u - ru, y: v - rv, width: ru * 2, height: rv * 2))
        }
        switch pattern {
        case .plain:
            break
        case .stripe:
            ellipse(0.05, 0.95, 0.78, 0.5)
        case .spots:
            ellipse(0.35, 0.35, 0.22, 0.22)
            ellipse(-0.32, 0.18, 0.17, 0.17)
            ellipse(0.06, -0.36, 0.15, 0.15)
            ellipse(-0.5, -0.4, 0.12, 0.12)
        case .chevron:
            ctx.setLineWidth(0.2)
            for du in [CGFloat(0), -0.45] {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: du - 0.25, y: 0.62))
                ctx.addLine(to: CGPoint(x: du + 0.22, y: 0.05))
                ctx.addLine(to: CGPoint(x: du - 0.25, y: -0.55))
                ctx.strokePath()
            }
        case .heart:
            ctx.saveGState()
            ctx.scaleBy(x: 1 / sx, y: 1 / ary)
            drawHeart(at: CGPoint(x: 0, y: -ary * 0.02), size: min(sx, ary) * 0.42, colour: pal.accent, in: ctx)
            ctx.restoreGState()
        case .star:
            ctx.saveGState()
            ctx.scaleBy(x: 1 / sx, y: 1 / ary)
            drawStar(at: CGPoint(x: 0, y: 0), size: min(sx, ary) * 0.55, colour: pal.accent, in: ctx)
            ctx.restoreGState()
        case .saddle:
            ellipse(0.05, 0.55, 0.86, 0.6)
        case .bands:
            for u in [CGFloat(-0.55), 0, 0.55] {
                ctx.fill(CGRect(x: u - 0.09, y: -1.3, width: 0.18, height: 2.6))
            }
        case .diamond:
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: 0.6))
            ctx.addLine(to: CGPoint(x: 0.5, y: 0))
            ctx.addLine(to: CGPoint(x: 0, y: -0.6))
            ctx.addLine(to: CGPoint(x: -0.5, y: 0))
            ctx.closePath()
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    private static func drawBackpack(ac: V2, arx: CGFloat, ary: CGFloat, profile f: CGFloat,
                                     pal: Palette, in ctx: CGContext) {
        // A little pack riding on top of the abdomen, with a flap and a strap.
        let c = V2(ac.x + 1 * f, ac.y + ary * 0.55)
        let w: CGFloat = 12, h: CGFloat = 9.5
        let body = CGRect(x: c.x - w / 2, y: c.y, width: w, height: h)
        let p = CGPath(roundedRect: body, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.setStrokeColor(pal.outline)
        ctx.setLineWidth(3.8)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x - w * 0.3, y: c.y + 1))
        ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.3, y: c.y + 1), control: CGPoint(x: c.x, y: c.y - ary * 0.7))
        ctx.strokePath()
        ctx.setLineWidth(2.2)
        ctx.addPath(p); ctx.setFillColor(pal.accent); ctx.fillPath()
        ctx.addPath(p); ctx.strokePath()
        let flap = CGRect(x: c.x - w / 2, y: c.y + h * 0.55, width: w, height: h * 0.45)
        let fp = CGPath(roundedRect: flap, cornerWidth: 3, cornerHeight: 3, transform: nil)
        ctx.addPath(fp); ctx.setFillColor(pal.accentRGB.darker(0.3).cg); ctx.fillPath()
        ctx.addPath(fp); ctx.strokePath()
        ctx.setFillColor(pal.outline)
        ctx.fillEllipse(in: CGRect(x: c.x - 1.3, y: c.y + h * 0.55 - 1.3, width: 2.6, height: 2.6))
    }

    private static func drawNeckwear(_ look: SpiderLook, hc: V2, hr: CGFloat, ac: V2, ary: CGFloat,
                                     profile f: CGFloat, pal: Palette, in ctx: CGContext) {
        // Wrapped where the two segments meet: a vertical band in profile that
        // the head then covers the front half of.
        let x = lerp(0, 0.5, f)
        let top = V2.lerp(V2(-11, hc.y + hr * 0.55), V2(x, 9.5), f)
        let bot = V2.lerp(V2(11, hc.y + hr * 0.55), V2(x, -9), f)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(pal.outline)
        ctx.setLineWidth(9.5)
        ctx.beginPath(); ctx.move(to: top.point); ctx.addLine(to: bot.point); ctx.strokePath()
        ctx.setStrokeColor(pal.accent)
        ctx.setLineWidth(7.2)
        ctx.beginPath(); ctx.move(to: top.point); ctx.addLine(to: bot.point); ctx.strokePath()
        switch look.accessory {
        case .scarf:
            // A tail trailing back over the abdomen.
            let a = V2.lerp(V2(-6, hc.y + hr * 0.4), V2(x - 1, 6), f)
            let b = V2.lerp(V2(-10, hc.y + hr * 1.3), V2(x - 11, 13 + ary * 0.15), f)
            let cpt = V2.lerp(V2(-9, hc.y + hr * 0.7), V2(x - 4, 12), f)
            for (col, w) in [(pal.outline, 7.4), (pal.accent, 5.2)] {
                ctx.setStrokeColor(col)
                ctx.setLineWidth(w)
                ctx.beginPath(); ctx.move(to: a.point)
                ctx.addQuadCurve(to: b.point, control: cpt.point)
                ctx.strokePath()
            }
            ctx.setStrokeColor(pal.accentRGB.darker(0.35).cg)
            ctx.setLineWidth(1.4)
            for k in 0..<3 {
                let u = 0.3 + CGFloat(k) * 0.25
                let q = V2.lerp(V2.lerp(a, cpt, u), V2.lerp(cpt, b, u), u)
                ctx.beginPath(); ctx.move(to: (q + V2(-2, 0)).point); ctx.addLine(to: (q + V2(2, 0)).point)
                ctx.strokePath()
            }
        case .bandana:
            // The knotted triangle hangs below the neck.
            let p0 = V2.lerp(V2(-8, hc.y + hr * 0.55), V2(x - 3, -6), f)
            let p1 = V2.lerp(V2(8, hc.y + hr * 0.55), V2(x + 4, -8), f)
            let p2 = V2.lerp(V2(0, hc.y - hr * 0.2), V2(x - 2, -19), f)
            for (col, fill) in [(pal.outline, false), (pal.accent, true)] {
                ctx.beginPath(); ctx.move(to: p0.point); ctx.addLine(to: p1.point); ctx.addLine(to: p2.point); ctx.closePath()
                if fill { ctx.setFillColor(col); ctx.fillPath() }
                else { ctx.setStrokeColor(col); ctx.setLineWidth(4.5); ctx.setLineJoin(.round); ctx.strokePath() }
            }
            ctx.setFillColor(pal.accentRGB.lighter(0.5).cg)
            let m = (p0 + p1 + p2) / 3
            ctx.fillEllipse(in: CGRect(x: m.x - 1.2, y: m.y - 1.2, width: 2.4, height: 2.4))
        case .collar:
            // A little bell hanging under the chin.
            let b = V2.lerp(V2(2, -13), V2(hc.x - hr * 0.25, hc.y - hr * 1.0), f)
            let gold = CGColor(red: 0.96, green: 0.78, blue: 0.28, alpha: 1)
            ctx.setFillColor(gold)
            ctx.setStrokeColor(pal.outline)
            ctx.setLineWidth(1.4)
            ctx.fillEllipse(in: CGRect(x: b.x - 3.2, y: b.y - 3.2, width: 6.4, height: 6.4))
            ctx.strokeEllipse(in: CGRect(x: b.x - 3.2, y: b.y - 3.2, width: 6.4, height: 6.4))
            ctx.setFillColor(pal.outline)
            ctx.fillEllipse(in: CGRect(x: b.x - 0.9, y: b.y - 3.6, width: 1.8, height: 1.8))
            ctx.beginPath(); ctx.move(to: CGPoint(x: b.x - 2.6, y: b.y - 0.8)); ctx.addLine(to: CGPoint(x: b.x + 2.6, y: b.y - 0.8)); ctx.strokePath()
        case .necktie:
            // Hangs down from the knot, swinging a touch.
            let k = V2.lerp(V2(1, -12), V2(hc.x - hr * 0.35, hc.y - hr * 0.85), f)
            let tip = k + V2(lerp(0, -3, f), -11)
            let tie = CGMutablePath()
            tie.move(to: CGPoint(x: k.x - 2.4, y: k.y))
            tie.addLine(to: CGPoint(x: k.x + 2.4, y: k.y))
            tie.addLine(to: CGPoint(x: tip.x + 3.2, y: tip.y + 3))
            tie.addLine(to: CGPoint(x: tip.x, y: tip.y))
            tie.addLine(to: CGPoint(x: tip.x - 3.2, y: tip.y + 3))
            tie.closeSubpath()
            ctx.setLineJoin(.round)
            ctx.addPath(tie); ctx.setFillColor(pal.accentRGB.darker(0.25).cg); ctx.fillPath()
            ctx.addPath(tie); ctx.setStrokeColor(pal.outline); ctx.setLineWidth(1.6); ctx.strokePath()
            ctx.setFillColor(pal.accentRGB.lighter(0.3).cg)
            ctx.fill(CGRect(x: k.x - 2.4, y: k.y - 1.5, width: 4.8, height: 3))
        case .lei:
            // Flowers all round the neck, alternating colours.
            let cols = [pal.accent, CGColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), pal.accentRGB.lighter(0.5).cg]
            // Round the neck: in profile an arc under and in front of the
            // head; face on, across the chest.
            let centre = V2(hc.x - hr * 0.45, hc.y - hr * 0.15)
            for k in 0..<7 {
                let u = CGFloat(k) / 6
                let a = lerp(3.6, 5.9, u)
                let arc = centre + V2.angle(a) * (hr * 0.95)
                let flat = V2.lerp(top, bot, u) + V2(-2, -6)
                let c = V2.lerp(flat, arc, f)
                ctx.setFillColor(cols[k % 3])
                ctx.setStrokeColor(pal.outline)
                ctx.setLineWidth(0.9)
                for q in 0..<5 {
                    let a = CGFloat(q) / 5 * 2 * .pi + u * 4
                    let pc = c + V2.angle(a) * 2.8
                    ctx.fillEllipse(in: CGRect(x: pc.x - 2, y: pc.y - 2, width: 4, height: 4))
                }
                ctx.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.7, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: c.x - 1.4, y: c.y - 1.4, width: 2.8, height: 2.8))
            }
        default:
            break
        }
    }

    /// A satchel slung low on the side of the abdomen, on a strap.
    private static func drawSatchel(ac: V2, arx: CGFloat, ary: CGFloat, profile f: CGFloat,
                                    pal: Palette, in ctx: CGContext) {
        let c = V2(ac.x - 3 * f, ac.y - ary * 0.2)
        let w: CGFloat = 15, h: CGFloat = 11
        // The strap goes up over the top of the abdomen.
        ctx.setStrokeColor(pal.outline)
        ctx.setLineCap(.round)
        ctx.setLineWidth(3.2)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x - w * 0.3, y: c.y + h * 0.4))
        ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.35, y: c.y + h * 0.4), control: CGPoint(x: c.x + 3, y: c.y + ary * 1.3))
        ctx.strokePath()
        ctx.setStrokeColor(CGColor(red: 0.45, green: 0.28, blue: 0.15, alpha: 1))
        ctx.setLineWidth(1.6)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x - w * 0.3, y: c.y + h * 0.4))
        ctx.addQuadCurve(to: CGPoint(x: c.x + w * 0.35, y: c.y + h * 0.4), control: CGPoint(x: c.x + 3, y: c.y + ary * 1.3))
        ctx.strokePath()
        ctx.setStrokeColor(pal.outline)
        let brown = CGColor(red: 0.62, green: 0.42, blue: 0.24, alpha: 1)
        let body = CGPath(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        ctx.setLineWidth(2)
        ctx.addPath(body); ctx.setFillColor(brown); ctx.fillPath()
        ctx.addPath(body); ctx.strokePath()
        let flap = CGPath(roundedRect: CGRect(x: c.x - w / 2, y: c.y - 0.5, width: w, height: h / 2 + 0.5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
        ctx.addPath(flap); ctx.setFillColor(CGColor(red: 0.45, green: 0.28, blue: 0.15, alpha: 1)); ctx.fillPath()
        ctx.addPath(flap); ctx.strokePath()
        ctx.setFillColor(CGColor(red: 0.96, green: 0.78, blue: 0.28, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: c.x - 1.2, y: c.y - 2, width: 2.4, height: 2.4))
    }

    /// A cape flowing back from the shoulders, or a pair of fairy wings —
    /// both drawn behind the body.
    private static func drawBackwear(_ look: SpiderLook, pose: SpiderPose, ac: V2, arx: CGFloat, ary: CGFloat,
                                     hc: V2, hr: CGFloat, profile f: CGFloat, pal: Palette, in ctx: CGContext) {
        switch look.accessory {
        case .cape:
            // Pinned at the neck, draped over the top of the abdomen and
            // streaming back past it, lifting with the abdomen's sway.
            let lift = pose.abdomenSway * 30
            let neck = V2.lerp(V2(0, 9), V2(ac.x + arx * 0.75, ac.y + ary * 0.55), f)
            let crest = V2.lerp(V2(-6, 12), V2(ac.x - arx * 0.2, ac.y + ary * 1.05), f)
            let tail = V2.lerp(V2(-13, -12), V2(ac.x - arx * 1.7, ac.y - ary * 0.35 + lift), f)
            let hem = V2.lerp(V2(-10, -14), V2(ac.x - arx * 1.0, ac.y - ary * 0.95), f)
            let p = CGMutablePath()
            p.move(to: neck.point)
            p.addQuadCurve(to: tail.point, control: crest.point)
            p.addQuadCurve(to: hem.point, control: CGPoint(x: (tail.x + hem.x) / 2 - 2, y: (tail.y + hem.y) / 2 - 3))
            p.addQuadCurve(to: neck.point, control: CGPoint(x: lerp(-2, ac.x - arx * 0.1, f), y: lerp(-2, ac.y - ary * 0.1, f)))
            p.closeSubpath()
            ctx.setLineJoin(.round)
            ctx.addPath(p); ctx.setFillColor(pal.accentRGB.darker(0.1).cg); ctx.fillPath()
            ctx.addPath(p); ctx.setStrokeColor(pal.outline); ctx.setLineWidth(2.2); ctx.strokePath()
            // A fold line, and the clasp.
            ctx.setStrokeColor(pal.accentRGB.darker(0.4).cg)
            ctx.setLineWidth(1.2)
            ctx.beginPath(); ctx.move(to: CGPoint(x: neck.x - 3, y: neck.y - 2))
            ctx.addQuadCurve(to: CGPoint(x: tail.x + 4, y: tail.y + 3), control: CGPoint(x: crest.x, y: crest.y - 6)); ctx.strokePath()
            ctx.setFillColor(CGColor(red: 0.96, green: 0.78, blue: 0.28, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: neck.x - 2, y: neck.y - 2, width: 4, height: 4))
            ctx.setStrokeColor(pal.outline); ctx.setLineWidth(1)
            ctx.strokeEllipse(in: CGRect(x: neck.x - 2, y: neck.y - 2, width: 4, height: 4))
        case .wings:
            // Two translucent wings rising from the back, fluttering gently.
            let base = V2.lerp(V2(0, 6), V2(ac.x + arx * 0.3, ac.y + ary * 0.5), f)
            let flutter = sin(pose.odometer * 0.9 + pose.abdomenSway * 4) * 0.08
            let tint = CGColor(red: 0.78, green: 0.93, blue: 1, alpha: 0.7)
            let rim = CGColor(red: 0.45, green: 0.68, blue: 0.95, alpha: 0.95)
            for side in [CGFloat(-1), 1] {
                let sw = lerp(side, 1, f)          // in profile both trail the same way
                let dir = V2.lerp(V2(sw * 22, 24), V2(-20 * (side > 0 ? 1 : 0.75), 22 + (side > 0 ? 6 : 0)), f)
                ctx.saveGState()
                ctx.translateBy(x: base.x, y: base.y)
                ctx.rotate(by: flutter * (side > 0 ? 1 : -1))
                let w = CGMutablePath()
                w.move(to: .zero)
                w.addQuadCurve(to: CGPoint(x: dir.x, y: dir.y), control: CGPoint(x: dir.x * 0.2, y: dir.y * 1.1))
                w.addQuadCurve(to: CGPoint(x: dir.x * 0.85, y: dir.y * 0.25), control: CGPoint(x: dir.x * 1.25, y: dir.y * 0.7))
                w.addQuadCurve(to: .zero, control: CGPoint(x: dir.x * 0.5, y: -1))
                w.closeSubpath()
                ctx.addPath(w); ctx.setFillColor(tint); ctx.fillPath()
                ctx.addPath(w); ctx.setStrokeColor(rim); ctx.setLineWidth(1.2); ctx.strokePath()
                ctx.setStrokeColor(CGColor(red: 0.55, green: 0.75, blue: 0.95, alpha: 0.45))
                ctx.setLineWidth(0.8)
                ctx.beginPath(); ctx.move(to: .zero); ctx.addLine(to: CGPoint(x: dir.x * 0.7, y: dir.y * 0.7)); ctx.strokePath()
                ctx.restoreGState()
            }
        default:
            break
        }
    }

    private static func drawFace(_ pose: SpiderPose, profile f: CGFloat,
                                 look: SpiderLook, pal: Palette, in ctx: CGContext) {
        let grow = (1 + pose.startled * 0.16) * look.eyes.sizeMul
        let happy = pose.happy
        let blink = clamp(max(pose.blink, look.eyes.lid), 0, 1)
        // The gaze is a screen-space direction; undo the mirror so a glance to
        // the left stays a glance to the left whichever way it faces.
        let look2 = V2(pose.look.x * (pose.facing >= 0 ? 1 : -1), pose.look.y).clampedLength(1)
        let hc = V2.lerp(frontHead.c, head.c, f)
        let hr = lerp(frontHead.r, head.r, f) * look.body.metrics.head
        let hm = look.body.metrics.head

        // Blush, when it is pleased with you.
        if happy > 0.25 {
            let a = Double(0.42 * (happy - 0.25) / 0.75)
            ctx.setFillColor(CGColor(red: 0.898, green: 0.451, blue: 0.325, alpha: a))
            let b1 = V2.lerp(V2(7.5, -6.5), V2(15.0, -5.0), f)
            let b2 = V2.lerp(V2(-7.5, -6.5), V2(4.7, -3.0), f)
            ctx.fillEllipse(in: CGRect(x: b1.x - 3.5, y: b1.y - 2, width: 7.0, height: 4.2))
            ctx.fillEllipse(in: CGRect(x: b2.x - 2.7, y: b2.y - 1.7, width: 5.4, height: 3.4))
        }

        let squint = happy > 0.5 ? remap(happy, 0.5, 1, 0, 1) : 0
        var eyeSpots: [(c: V2, r: CGFloat)] = []

        for (i, side) in eyes.enumerated() {
            let front = frontEyes[i]
            // Eyes ride out with a bigger head.
            let ec = V2.lerp(front.c, side.c, f)
            let e = (c: hc + (ec - hc) * hm, r: lerp(front.r, side.r, f) * hm, big: side.big)
            let r = e.r * grow
            eyeSpots.append((e.c, r))
            if squint > 0.55 {
                // Happy eyes: an upturned crescent.
                ctx.setStrokeColor(pal.eyeDark)
                ctx.setLineWidth(e.big ? 2.3 : 1.8)
                ctx.setLineCap(.round)
                ctx.beginPath()
                ctx.addArc(center: CGPoint(x: e.c.x, y: e.c.y - r * 0.5), radius: r * 1.1,
                           startAngle: 0.5, endAngle: .pi - 0.5, clockwise: false)
                ctx.strokePath()
                continue
            }

            let ry = r * look.eyes.squash
            let rect = CGRect(x: e.c.x - r, y: e.c.y - ry, width: r * 2, height: ry * 2)
            ctx.setFillColor(pal.eyeDark)
            ctx.fillEllipse(in: rect)

            // Glints slide toward whatever it is watching.
            var gaze = look2
            if look.eyes == .cross, e.big {
                // Each big eye looks at the other one.
                gaze = V2(i == 0 ? -0.9 : 0.9, -0.2)
            }
            let off = gaze * (r * 0.28)
            ctx.setFillColor(white)
            let g1 = r * (look.eyes == .beady ? 0.34 : 0.42)
            ctx.fillEllipse(in: CGRect(x: e.c.x + off.x - r * 0.22 - g1,
                                       y: e.c.y + off.y + r * 0.24 - g1,
                                       width: g1 * 2, height: g1 * 2))
            if e.big {
                let g2 = r * 0.19
                ctx.fillEllipse(in: CGRect(x: e.c.x + off.x + r * 0.34 - g2,
                                           y: e.c.y + off.y - r * 0.30 - g2,
                                           width: g2 * 2, height: g2 * 2))
                if look.eyes == .sparkly {
                    drawStar(at: CGPoint(x: e.c.x + off.x + r * 0.30, y: e.c.y + off.y + r * 0.35),
                             size: r * 0.4, colour: white, in: ctx)
                }
            }

            // Lid comes down from above.
            if blink > 0.01 {
                ctx.saveGState()
                ctx.addEllipse(in: rect.insetBy(dx: -0.7, dy: -0.7))
                ctx.clip()
                let top = e.c.y + ry + 1.2
                let coverH = (ry * 2 + 2.4) * blink
                ctx.setFillColor(pal.headFill)
                ctx.fill(CGRect(x: e.c.x - r - 1.5, y: top - coverH,
                                width: r * 2 + 3, height: coverH))
                ctx.setStrokeColor(pal.outline.copy(alpha: 0.55)!)
                ctx.setLineWidth(1.0)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: e.c.x - r - 1, y: top - coverH))
                ctx.addLine(to: CGPoint(x: e.c.x + r + 1, y: top - coverH))
                ctx.strokePath()
                ctx.restoreGState()
            }
        }

        drawBrows(look, eyes: eyeSpots, profile: f, pal: pal, in: ctx)
        drawMouth(look, pose: pose, hc: hc, hr: hr, profile: f, pal: pal, in: ctx)
    }

    private static func drawBrows(_ look: SpiderLook, eyes: [(c: V2, r: CGFloat)], profile f: CGFloat,
                                  pal: Palette, in ctx: CGContext) {
        guard look.brows != .none, eyes.count >= 2 else { return }
        ctx.setStrokeColor(pal.outline)
        ctx.setLineCap(.round)
        ctx.setLineWidth(look.brows == .thick ? 3.4 : 2.1)
        if look.brows == .unibrow {
            let a = eyes[1].c + V2(-eyes[1].r * 0.9, eyes[1].r * 1.5)
            let b = eyes[0].c + V2(eyes[0].r * 0.9, eyes[0].r * 1.5)
            let m = (a + b) * 0.5 + V2(0, 1.8)
            ctx.setLineWidth(3.0)
            ctx.beginPath(); ctx.move(to: a.point); ctx.addQuadCurve(to: b.point, control: m.point); ctx.strokePath()
            return
        }
        for (i, e) in eyes.prefix(2).enumerated() {
            // "Inner" is toward the other big eye.
            let other = eyes[1 - i].c
            let inward: CGFloat = other.x > e.c.x ? 1 : -1
            let y = e.c.y + e.r * 1.45
            let half = e.r * 0.85
            let inner = V2(e.c.x + inward * half, y)
            let outer = V2(e.c.x - inward * half, y)
            var ctrl = V2(e.c.x, y + e.r * 0.3)
            var pIn = inner, pOut = outer
            switch look.brows {
            case .soft: ctrl.y = y + e.r * 0.25
            case .thick: ctrl.y = y + e.r * 0.3
            case .arched: ctrl.y = y + e.r * 0.9
            case .stern: pIn.y -= e.r * 0.35; pOut.y += e.r * 0.3; ctrl = (pIn + pOut) * 0.5
            case .worried: pIn.y += e.r * 0.4; pOut.y -= e.r * 0.2; ctrl = (pIn + pOut) * 0.5 + V2(0, e.r * 0.2)
            default: break
            }
            ctx.beginPath(); ctx.move(to: pOut.point); ctx.addQuadCurve(to: pIn.point, control: ctrl.point); ctx.strokePath()
        }
    }

    private static func drawMouth(_ look: SpiderLook, pose: SpiderPose, hc: V2, hr: CGFloat, profile f: CGFloat,
                                  pal: Palette, in ctx: CGContext) {
        guard look.fangs != .none else { return }
        // Fangs hang under the front of the face, between the palps.
        var chin = V2.lerp(V2(0, hc.y - hr * 0.62), V2(hc.x + hr * 0.62, hc.y - hr * 0.62), f)
        // Chewing: the fangs work in and out and the chin bobs.
        chin.y -= pose.chew * 1.2
        let spread: CGFloat = lerp(3.4, 2.4, f) - pose.chew * 1.1
        ctx.setLineJoin(.round)
        switch look.fangs {
        case .none:
            break
        case .tiny, .big:
            let len: CGFloat = look.fangs == .tiny ? 3.6 : 6.5
            let w: CGFloat = look.fangs == .tiny ? 1.6 : 2.4
            for side in [CGFloat(-1), 1] {
                let x = chin.x + side * spread
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x - w, y: chin.y + 0.5))
                ctx.addLine(to: CGPoint(x: x + w, y: chin.y + 0.5))
                ctx.addLine(to: CGPoint(x: x + side * 0.4, y: chin.y - len))
                ctx.closePath()
                ctx.setFillColor(white); ctx.fillPath()
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x - w, y: chin.y + 0.5))
                ctx.addLine(to: CGPoint(x: x + side * 0.4, y: chin.y - len))
                ctx.addLine(to: CGPoint(x: x + w, y: chin.y + 0.5))
                ctx.setStrokeColor(pal.outline); ctx.setLineWidth(1.0); ctx.strokePath()
            }
        case .tusks:
            for side in [CGFloat(-1), 1] {
                let x = chin.x + side * (spread + 1.5)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: chin.y + 1))
                ctx.addQuadCurve(to: CGPoint(x: x + side * 4.5, y: chin.y - 7.5),
                                 control: CGPoint(x: x + side * 0.5, y: chin.y - 6))
                ctx.setStrokeColor(pal.outline); ctx.setLineCap(.round); ctx.setLineWidth(4.2); ctx.strokePath()
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x, y: chin.y + 1))
                ctx.addQuadCurve(to: CGPoint(x: x + side * 4.5, y: chin.y - 7.5),
                                 control: CGPoint(x: x + side * 0.5, y: chin.y - 6))
                ctx.setStrokeColor(white); ctx.setLineWidth(2.4); ctx.strokePath()
            }
        case .emerald:
            // The iridescent chelicerae of a bold jumper.
            let green = CGColor(red: 0.16, green: 0.72, blue: 0.48, alpha: 1)
            let light = CGColor(red: 0.55, green: 0.95, blue: 0.72, alpha: 1)
            for side in [CGFloat(-1), 1] {
                let x = chin.x + side * spread
                let rect = CGRect(x: x - 3.2, y: chin.y - 6.5, width: 6.4, height: 8.5)
                let p = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(p); ctx.setStrokeColor(pal.outline); ctx.setLineWidth(2.2); ctx.strokePath()
                ctx.addPath(p); ctx.setFillColor(green); ctx.fillPath()
                ctx.setFillColor(light)
                ctx.fillEllipse(in: CGRect(x: x - 1.8, y: chin.y - 2.5, width: 2.2, height: 3))
                ctx.setFillColor(white)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x - 1.2, y: chin.y - 6.2))
                ctx.addLine(to: CGPoint(x: x + 1.2, y: chin.y - 6.2))
                ctx.addLine(to: CGPoint(x: x + side * 0.6, y: chin.y - 9))
                ctx.closePath(); ctx.fillPath()
            }
        case .smile:
            // A little curve, wider when it is happy.
            let w = 3.5 + pose.happy * 2.5
            let m = V2.lerp(V2(0, hc.y - hr * 0.55), V2(hc.x + hr * 0.7, hc.y - hr * 0.5), f)
            ctx.setStrokeColor(pal.eyeDark)
            ctx.setLineCap(.round)
            ctx.setLineWidth(1.6)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: m.x - w, y: m.y + 1))
            ctx.addQuadCurve(to: CGPoint(x: m.x + w, y: m.y + 1), control: CGPoint(x: m.x, y: m.y - 2.2 - pose.happy * 2))
            ctx.strokePath()
        }
    }

    private static func drawFaceAccessory(_ pose: SpiderPose, profile f: CGFloat,
                                          look: SpiderLook, pal: Palette, in ctx: CGContext) {
        let hm = look.body.metrics.head
        let hc = V2.lerp(frontHead.c, head.c, f)
        let hr = lerp(frontHead.r, head.r, f) * hm
        func eye(_ i: Int) -> (c: V2, r: CGFloat) {
            let ec = V2.lerp(frontEyes[i].c, eyes[i].c, f)
            return (hc + (ec - hc) * hm, lerp(frontEyes[i].r, eyes[i].r, f) * hm * look.eyes.sizeMul)
        }
        let dark = CGColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1)
        switch look.accessory {
        case .glasses, .sunglasses:
            let e0 = eye(0), e1 = eye(1)
            let r0 = e0.r * 1.3, r1 = e1.r * 1.3
            ctx.setLineCap(.round)
            if look.accessory == .sunglasses {
                ctx.setFillColor(dark)
                ctx.fillEllipse(in: CGRect(x: e0.c.x - r0, y: e0.c.y - r0 * 0.9, width: r0 * 2, height: r0 * 1.8))
                ctx.fillEllipse(in: CGRect(x: e1.c.x - r1, y: e1.c.y - r1 * 0.9, width: r1 * 2, height: r1 * 1.8))
                ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.35))
                ctx.fillEllipse(in: CGRect(x: e0.c.x - r0 * 0.6, y: e0.c.y + r0 * 0.15, width: r0 * 0.7, height: r0 * 0.35))
                ctx.fillEllipse(in: CGRect(x: e1.c.x - r1 * 0.6, y: e1.c.y + r1 * 0.15, width: r1 * 0.7, height: r1 * 0.35))
            }
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(1.7)
            ctx.strokeEllipse(in: CGRect(x: e0.c.x - r0, y: e0.c.y - r0 * 0.9, width: r0 * 2, height: r0 * 1.8))
            ctx.strokeEllipse(in: CGRect(x: e1.c.x - r1, y: e1.c.y - r1 * 0.9, width: r1 * 2, height: r1 * 1.8))
            // Bridge between the two, and an arm back toward the ear.
            let a = e1.c.x < e0.c.x ? (e1.c + V2(r1, 0)) : (e1.c - V2(r1, 0))
            let b = e1.c.x < e0.c.x ? (e0.c - V2(r0, 0)) : (e0.c + V2(r0, 0))
            ctx.beginPath(); ctx.move(to: a.point)
            ctx.addQuadCurve(to: b.point, control: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + 1.5))
            ctx.strokePath()
            if f > 0.3 {
                ctx.setStrokeColor(dark.copy(alpha: Double(f))!)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: e1.c.x - r1, y: e1.c.y + r1 * 0.2))
                ctx.addLine(to: CGPoint(x: hc.x - hr * 0.75, y: hc.y + hr * 0.15))
                ctx.strokePath()
            }
        case .monocle:
            let e = eye(0)
            let r = e.r * 1.32
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.68, blue: 0.25, alpha: 1))
            ctx.setLineWidth(1.8)
            ctx.strokeEllipse(in: CGRect(x: e.c.x - r, y: e.c.y - r, width: r * 2, height: r * 2))
            ctx.setLineWidth(1.0)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: e.c.x - r * 0.7, y: e.c.y - r * 0.7))
            ctx.addQuadCurve(to: CGPoint(x: e.c.x - r * 1.1, y: e.c.y - r * 2.6),
                             control: CGPoint(x: e.c.x - r * 1.5, y: e.c.y - r * 1.4))
            ctx.strokePath()
        case .bowTie:
            let c = V2.lerp(V2(0, hc.y - hr * 0.95), V2(hc.x + hr * 0.15, hc.y - hr * 0.98), f)
            let w: CGFloat = 6.0, h: CGFloat = 3.6
            for (col, stroke) in [(pal.outline, true), (pal.accent, false)] {
                ctx.beginPath()
                ctx.move(to: c.point)
                ctx.addLine(to: CGPoint(x: c.x - w, y: c.y + h)); ctx.addLine(to: CGPoint(x: c.x - w, y: c.y - h)); ctx.closePath()
                ctx.move(to: c.point)
                ctx.addLine(to: CGPoint(x: c.x + w, y: c.y + h)); ctx.addLine(to: CGPoint(x: c.x + w, y: c.y - h)); ctx.closePath()
                if stroke { ctx.setStrokeColor(col); ctx.setLineWidth(3.2); ctx.setLineJoin(.round); ctx.strokePath() }
                else { ctx.setFillColor(col); ctx.fillPath() }
            }
            ctx.setFillColor(pal.accentRGB.darker(0.35).cg)
            ctx.fillEllipse(in: CGRect(x: c.x - 1.6, y: c.y - 1.6, width: 3.2, height: 3.2))
        case .headphones:
            let cupNear = V2.lerp(V2(hr * 0.98, hc.y - 1), V2(hc.x - hr * 0.62, hc.y - hr * 0.1), f)
            let cupFar = V2.lerp(V2(-hr * 0.98, hc.y - 1), V2(hc.x + hr * 0.95, hc.y - hr * 0.05), f)
            let top = V2(hc.x, hc.y + hr * 1.12)
            ctx.setStrokeColor(dark)
            ctx.setLineWidth(2.6)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.move(to: cupFar.point)
            ctx.addQuadCurve(to: top.point, control: CGPoint(x: (cupFar.x + top.x) / 2 - 2 * f, y: top.y + 1))
            ctx.addQuadCurve(to: cupNear.point, control: CGPoint(x: (cupNear.x + top.x) / 2, y: top.y + 1))
            ctx.strokePath()
            for (c, big) in [(cupFar, false), (cupNear, true)] {
                let r: CGFloat = big ? 4.6 : 3.6
                ctx.setFillColor(dark)
                ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.setFillColor(pal.accent)
                ctx.fillEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.55, width: r * 1.1, height: r * 1.1))
            }
        default:
            break
        }
    }

    private static func drawHat(_ pose: SpiderPose, profile f: CGFloat,
                                look: SpiderLook, pal: Palette, in ctx: CGContext) {
        guard look.hat != .none else { return }
        let hc = V2.lerp(frontHead.c, head.c, f)
        let hr = lerp(frontHead.r, head.r, f) * look.body.metrics.head
        let top = V2(hc.x, hc.y + hr * 0.9)
        let w = hr
        let accent = pal.accent
        let dark = CGColor(red: 0.16, green: 0.12, blue: 0.10, alpha: 1)
        let gold = CGColor(red: 0.96, green: 0.78, blue: 0.28, alpha: 1)
        ctx.saveGState()
        ctx.translateBy(x: top.x, y: top.y)
        // Hats tilt forward a touch in profile; the tilt fades in the front view.
        ctx.rotate(by: -0.10 * f)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(pal.outline)
        ctx.setLineWidth(2.2)

        func outlined(_ path: CGPath, fill: CGColor) {
            ctx.addPath(path); ctx.setFillColor(fill); ctx.fillPath()
            ctx.addPath(path); ctx.strokePath()
        }

        switch look.hat {
        case .none:
            break
        case .topHat:
            let brim = CGPath(roundedRect: CGRect(x: -w * 1.05, y: -1.5, width: w * 2.1, height: 3.4),
                              cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)
            let crown = CGPath(roundedRect: CGRect(x: -w * 0.7, y: 1, width: w * 1.4, height: w * 1.35),
                               cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            outlined(crown, fill: dark)
            ctx.setFillColor(accent)
            ctx.fill(CGRect(x: -w * 0.7 + 1, y: 2.4, width: w * 1.4 - 2, height: 3.2))
            outlined(brim, fill: dark)
        case .partyHat:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.65, y: 0))
            p.addLine(to: CGPoint(x: w * 0.65, y: 0))
            p.addLine(to: CGPoint(x: 0.5, y: w * 1.75))
            p.closeSubpath()
            outlined(p, fill: accent)
            ctx.saveGState()
            ctx.addPath(p); ctx.clip()
            ctx.setFillColor(pal.accentRGB.lighter(0.5).cg)
            for k in 0..<3 {
                let y = CGFloat(k) * w * 0.55 + w * 0.2
                ctx.fill(CGRect(x: -w, y: y, width: w * 2, height: w * 0.18))
            }
            ctx.restoreGState()
            ctx.setFillColor(pal.accentRGB.lighter(0.5).cg)
            ctx.fillEllipse(in: CGRect(x: 0.5 - 2.6, y: w * 1.75 - 2.2, width: 5.2, height: 5.2))
            ctx.strokeEllipse(in: CGRect(x: 0.5 - 2.6, y: w * 1.75 - 2.2, width: 5.2, height: 5.2))
        case .crown:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.8, y: 0))
            p.addLine(to: CGPoint(x: w * 0.8, y: 0))
            p.addLine(to: CGPoint(x: w * 0.8, y: w * 0.9))
            p.addLine(to: CGPoint(x: w * 0.4, y: w * 0.45))
            p.addLine(to: CGPoint(x: 0, y: w * 1.0))
            p.addLine(to: CGPoint(x: -w * 0.4, y: w * 0.45))
            p.addLine(to: CGPoint(x: -w * 0.8, y: w * 0.9))
            p.closeSubpath()
            outlined(p, fill: gold)
            ctx.setFillColor(accent)
            for x in [-w * 0.45, 0, w * 0.45] {
                ctx.fillEllipse(in: CGRect(x: x - 1.6, y: w * 0.2 - 1.6, width: 3.2, height: 3.2))
            }
        case .beanie:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 1.05, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 1.05, y: 0), control: CGPoint(x: 0, y: w * 2.1))
            p.closeSubpath()
            outlined(p, fill: accent)
            ctx.setFillColor(pal.accentRGB.darker(0.3).cg)
            ctx.fill(CGRect(x: -w * 1.05 + 1, y: -1, width: w * 2.1 - 2, height: w * 0.35))
            ctx.setStrokeColor(pal.outline)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -w * 1.05 + 1, y: w * 0.35))
            ctx.addLine(to: CGPoint(x: w * 1.05 - 1, y: w * 0.35))
            ctx.strokePath()
            ctx.setFillColor(pal.accentRGB.lighter(0.55).cg)
            ctx.fillEllipse(in: CGRect(x: -3, y: w * 1.02 - 3, width: 6, height: 6))
            ctx.strokeEllipse(in: CGRect(x: -3, y: w * 1.02 - 3, width: 6, height: 6))
        case .flower:
            let c = V2(w * 0.35 * f, w * 0.05)
            ctx.setFillColor(accent)
            for k in 0..<6 {
                let a = CGFloat(k) / 6 * 2 * .pi + 0.3
                let pc = c + V2.angle(a) * (w * 0.36)
                let r = w * 0.24
                ctx.fillEllipse(in: CGRect(x: pc.x - r, y: pc.y - r, width: r * 2, height: r * 2))
                ctx.strokeEllipse(in: CGRect(x: pc.x - r, y: pc.y - r, width: r * 2, height: r * 2))
            }
            ctx.setFillColor(accent)
            for k in 0..<6 {
                let a = CGFloat(k) / 6 * 2 * .pi + 0.3
                let pc = c + V2.angle(a) * (w * 0.36)
                let r = w * 0.24
                ctx.fillEllipse(in: CGRect(x: pc.x - r, y: pc.y - r, width: r * 2, height: r * 2))
            }
            ctx.setFillColor(gold)
            ctx.fillEllipse(in: CGRect(x: c.x - w * 0.2, y: c.y - w * 0.2, width: w * 0.4, height: w * 0.4))
            ctx.strokeEllipse(in: CGRect(x: c.x - w * 0.2, y: c.y - w * 0.2, width: w * 0.4, height: w * 0.4))
        case .bow:
            for side in [CGFloat(-1), 1] {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: w * 0.2))
                p.addQuadCurve(to: CGPoint(x: side * w * 0.75, y: w * 0.75), control: CGPoint(x: side * w * 0.9, y: -w * 0.1))
                p.addQuadCurve(to: CGPoint(x: 0, y: w * 0.2), control: CGPoint(x: side * w * 0.7, y: w * 1.1))
                p.closeSubpath()
                outlined(p, fill: accent)
            }
            ctx.setFillColor(pal.accentRGB.darker(0.3).cg)
            ctx.fillEllipse(in: CGRect(x: -2.2, y: w * 0.2 - 2.2, width: 4.4, height: 4.4))
            ctx.strokeEllipse(in: CGRect(x: -2.2, y: w * 0.2 - 2.2, width: 4.4, height: 4.4))
        case .cap:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.95, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 0.95, y: 0), control: CGPoint(x: 0, y: w * 1.6))
            p.closeSubpath()
            outlined(p, fill: accent)
            // Visor points forward; from the front it sticks out toward you,
            // so it shortens to a lip.
            let visor = CGMutablePath()
            visor.move(to: CGPoint(x: w * 0.3, y: 1))
            visor.addQuadCurve(to: CGPoint(x: w * (0.95 + 0.9 * f), y: -1.5), control: CGPoint(x: w * (0.9 + 0.5 * f), y: 2.5))
            visor.addLine(to: CGPoint(x: w * (0.9 + 0.7 * f), y: -3.5))
            visor.addQuadCurve(to: CGPoint(x: w * 0.3, y: -2), control: CGPoint(x: w * 0.7, y: -3.5))
            visor.closeSubpath()
            outlined(visor, fill: pal.accentRGB.darker(0.3).cg)
            ctx.setFillColor(pal.accentRGB.lighter(0.4).cg)
            ctx.fillEllipse(in: CGRect(x: -1.5, y: w * 0.78 - 1.5, width: 3, height: 3))
        case .halo:
            ctx.setStrokeColor(CGColor(red: 1, green: 0.93, blue: 0.55, alpha: 0.55))
            ctx.setLineWidth(4.5)
            ctx.strokeEllipse(in: CGRect(x: -w * 0.85, y: w * 0.55, width: w * 1.7, height: w * 0.42))
            ctx.setStrokeColor(gold)
            ctx.setLineWidth(2.4)
            ctx.strokeEllipse(in: CGRect(x: -w * 0.85, y: w * 0.55, width: w * 1.7, height: w * 0.42))
        case .wizard:
            let brim = CGPath(ellipseIn: CGRect(x: -w * 1.35, y: -2.5, width: w * 2.7, height: 5.5), transform: nil)
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: -w * 0.75, y: 0))
            cone.addLine(to: CGPoint(x: w * 0.75, y: 0))
            cone.addQuadCurve(to: CGPoint(x: -w * 0.35, y: w * 2.35), control: CGPoint(x: w * 0.35, y: w * 1.3))
            cone.addQuadCurve(to: CGPoint(x: -w * 0.75, y: 0), control: CGPoint(x: -w * 0.5, y: w * 1.2))
            cone.closeSubpath()
            let purple = CGColor(red: 0.36, green: 0.26, blue: 0.62, alpha: 1)
            outlined(brim, fill: purple)
            outlined(cone, fill: purple)
            drawStar(at: CGPoint(x: -w * 0.05, y: w * 0.55), size: w * 0.22, colour: accent, in: ctx)
            drawStar(at: CGPoint(x: -w * 0.3, y: w * 1.35), size: w * 0.15, colour: accent, in: ctx)
        case .propeller:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.95, y: 0))
            p.addQuadCurve(to: CGPoint(x: w * 0.95, y: 0), control: CGPoint(x: 0, y: w * 1.5))
            p.closeSubpath()
            outlined(p, fill: accent)
            ctx.setFillColor(pal.accentRGB.darker(0.3).cg)
            for k in 0..<3 {
                ctx.beginPath()
                let a0 = CGFloat(k) / 3 * .pi - .pi / 2, a1 = a0 + .pi / 3
                ctx.move(to: CGPoint(x: 0, y: w * 0.2))
                ctx.addArc(center: CGPoint(x: 0, y: w * 0.2), radius: w * 0.95, startAngle: a0, endAngle: a1, clockwise: false)
                ctx.closePath()
                ctx.fillPath()
            }
            // The blades turn with distance travelled, so they only spin
            // while it is on the move.
            let stem = CGPoint(x: 0, y: w * 0.72)
            ctx.setStrokeColor(pal.outline)
            ctx.setLineWidth(2.2)
            ctx.beginPath(); ctx.move(to: stem); ctx.addLine(to: CGPoint(x: 0, y: w * 1.2)); ctx.strokePath()
            let spin = cos(pose.odometer * 0.35)
            let bladeW = w * 1.15 * spin
            let blade = CGPath(roundedRect: CGRect(x: -abs(bladeW), y: w * 1.2 - 1.6, width: abs(bladeW) * 2, height: 3.2),
                               cornerWidth: 1.6, cornerHeight: 1.6, transform: nil)
            outlined(blade, fill: bladeW >= 0 ? gold : pal.accentRGB.lighter(0.4).cg)
        case .cowboy:
            // A wide brim curled up at the sides, a dented crown, a band.
            let tan = CGColor(red: 0.72, green: 0.52, blue: 0.3, alpha: 1)
            let brim = CGMutablePath()
            brim.move(to: CGPoint(x: -w * 1.45, y: 2.5))
            brim.addQuadCurve(to: CGPoint(x: -w * 0.5, y: -1.5), control: CGPoint(x: -w * 1.1, y: -2.5))
            brim.addLine(to: CGPoint(x: w * 0.5, y: -1.5))
            brim.addQuadCurve(to: CGPoint(x: w * 1.45, y: 2.5), control: CGPoint(x: w * 1.1, y: -2.5))
            brim.addQuadCurve(to: CGPoint(x: -w * 1.45, y: 2.5), control: CGPoint(x: 0, y: 1))
            brim.closeSubpath()
            let crown = CGMutablePath()
            crown.move(to: CGPoint(x: -w * 0.72, y: 0))
            crown.addLine(to: CGPoint(x: -w * 0.62, y: w * 1.15))
            crown.addQuadCurve(to: CGPoint(x: 0, y: w * 0.95), control: CGPoint(x: -w * 0.3, y: w * 1.25))
            crown.addQuadCurve(to: CGPoint(x: w * 0.62, y: w * 1.15), control: CGPoint(x: w * 0.3, y: w * 1.25))
            crown.addLine(to: CGPoint(x: w * 0.72, y: 0))
            crown.closeSubpath()
            outlined(crown, fill: tan)
            ctx.setFillColor(pal.accentRGB.darker(0.2).cg)
            ctx.fill(CGRect(x: -w * 0.7, y: 1.5, width: w * 1.4, height: 3.2))
            outlined(brim, fill: tan)
        case .chef:
            // A tall white toque, puffed at the top.
            let white = CGColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1)
            let band = CGPath(roundedRect: CGRect(x: -w * 0.85, y: -1, width: w * 1.7, height: w * 0.55), cornerWidth: 2, cornerHeight: 2, transform: nil)
            let puff = CGMutablePath()
            puff.move(to: CGPoint(x: -w * 0.8, y: w * 0.45))
            puff.addQuadCurve(to: CGPoint(x: -w * 0.3, y: w * 1.9), control: CGPoint(x: -w * 1.35, y: w * 1.5))
            puff.addQuadCurve(to: CGPoint(x: w * 0.3, y: w * 1.9), control: CGPoint(x: 0, y: w * 2.35))
            puff.addQuadCurve(to: CGPoint(x: w * 0.8, y: w * 0.45), control: CGPoint(x: w * 1.35, y: w * 1.5))
            puff.closeSubpath()
            outlined(puff, fill: white)
            outlined(band, fill: white)
        case .bucket:
            // A soft bucket hat, brim sloping down all round.
            let cloth = pal.accentRGB.darker(0.1).cg
            let brim = CGMutablePath()
            brim.move(to: CGPoint(x: -w * 1.3, y: -4))
            brim.addLine(to: CGPoint(x: -w * 0.85, y: 1))
            brim.addLine(to: CGPoint(x: w * 0.85, y: 1))
            brim.addLine(to: CGPoint(x: w * 1.3, y: -4))
            brim.addQuadCurve(to: CGPoint(x: -w * 1.3, y: -4), control: CGPoint(x: 0, y: -6))
            brim.closeSubpath()
            let crown = CGMutablePath()
            crown.move(to: CGPoint(x: -w * 0.85, y: 0))
            crown.addLine(to: CGPoint(x: -w * 0.7, y: w * 1.05))
            crown.addQuadCurve(to: CGPoint(x: w * 0.7, y: w * 1.05), control: CGPoint(x: 0, y: w * 1.35))
            crown.addLine(to: CGPoint(x: w * 0.85, y: 0))
            crown.closeSubpath()
            outlined(crown, fill: cloth)
            outlined(brim, fill: cloth)
            ctx.setStrokeColor(pal.accentRGB.darker(0.4).cg)
            ctx.setLineWidth(1)
            ctx.beginPath(); ctx.move(to: CGPoint(x: -w * 0.75, y: w * 0.35)); ctx.addLine(to: CGPoint(x: w * 0.75, y: w * 0.35)); ctx.strokePath()
        case .viking:
            // A rounded helmet with a rim and two horns.
            let iron = CGColor(red: 0.6, green: 0.62, blue: 0.66, alpha: 1)
            let bone = CGColor(red: 0.96, green: 0.93, blue: 0.85, alpha: 1)
            for side in [CGFloat(-1), 1] {
                let horn = CGMutablePath()
                horn.move(to: CGPoint(x: side * w * 0.55, y: w * 0.35))
                horn.addQuadCurve(to: CGPoint(x: side * w * 1.35, y: w * 1.35), control: CGPoint(x: side * w * 1.35, y: w * 0.35))
                horn.addQuadCurve(to: CGPoint(x: side * w * 0.75, y: w * 0.75), control: CGPoint(x: side * w * 1.05, y: w * 0.65))
                horn.closeSubpath()
                outlined(horn, fill: bone)
            }
            let dome = CGMutablePath()
            dome.move(to: CGPoint(x: -w * 0.95, y: 0))
            dome.addQuadCurve(to: CGPoint(x: w * 0.95, y: 0), control: CGPoint(x: 0, y: w * 1.9))
            dome.closeSubpath()
            outlined(dome, fill: iron)
            outlined(CGPath(roundedRect: CGRect(x: -w * 1.0, y: -1.5, width: w * 2.0, height: 3.5), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil), fill: gold)
            ctx.setStrokeColor(pal.outline)
            ctx.setLineWidth(1.2)
            ctx.beginPath(); ctx.move(to: CGPoint(x: 0, y: 2)); ctx.addLine(to: CGPoint(x: 0, y: w * 0.95)); ctx.strokePath()
        case .tiara:
            // A slim band with three points, jewelled.
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 0.75, y: 0))
            p.addLine(to: CGPoint(x: w * 0.75, y: 0))
            p.addLine(to: CGPoint(x: w * 0.6, y: w * 0.35))
            p.addLine(to: CGPoint(x: w * 0.32, y: w * 0.2))
            p.addLine(to: CGPoint(x: 0, y: w * 0.75))
            p.addLine(to: CGPoint(x: -w * 0.32, y: w * 0.2))
            p.addLine(to: CGPoint(x: -w * 0.6, y: w * 0.35))
            p.closeSubpath()
            ctx.setLineWidth(1.6)
            outlined(p, fill: CGColor(red: 0.85, green: 0.88, blue: 0.95, alpha: 1))
            ctx.setFillColor(accent)
            ctx.fillEllipse(in: CGRect(x: -1.8, y: w * 0.42 - 1.8, width: 3.6, height: 3.6))
            for x in [-w * 0.32, w * 0.32] {
                ctx.fillEllipse(in: CGRect(x: x - 1.1, y: w * 0.12 - 1.1, width: 2.2, height: 2.2))
            }
        case .pirate:
            // A tricorn, brim turned up at the sides, skull and crossbones.
            let black = CGColor(red: 0.13, green: 0.12, blue: 0.14, alpha: 1)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -w * 1.4, y: w * 0.9))
            p.addQuadCurve(to: CGPoint(x: 0, y: w * 0.3), control: CGPoint(x: -w * 0.6, y: -w * 0.2))
            p.addQuadCurve(to: CGPoint(x: w * 1.4, y: w * 0.9), control: CGPoint(x: w * 0.6, y: -w * 0.2))
            p.addQuadCurve(to: CGPoint(x: 0, y: w * 1.35), control: CGPoint(x: w * 0.75, y: w * 1.15))
            p.addQuadCurve(to: CGPoint(x: -w * 1.4, y: w * 0.9), control: CGPoint(x: -w * 0.75, y: w * 1.15))
            p.closeSubpath()
            outlined(p, fill: black)
            ctx.setStrokeColor(gold)
            ctx.setLineWidth(1.2)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: -w * 1.3, y: w * 0.85))
            ctx.addQuadCurve(to: CGPoint(x: 0, y: w * 1.2), control: CGPoint(x: -w * 0.7, y: w * 1.05))
            ctx.addQuadCurve(to: CGPoint(x: w * 1.3, y: w * 0.85), control: CGPoint(x: w * 0.7, y: w * 1.05))
            ctx.strokePath()
            let white = CGColor(red: 0.98, green: 0.98, blue: 0.96, alpha: 1)
            ctx.setFillColor(white)
            ctx.fillEllipse(in: CGRect(x: -2.6, y: w * 0.55, width: 5.2, height: 5))
            ctx.setStrokeColor(white)
            ctx.setLineWidth(1.1)
            for sgn in [CGFloat(-1), 1] {
                ctx.beginPath(); ctx.move(to: CGPoint(x: sgn * -3.5, y: w * 0.4)); ctx.addLine(to: CGPoint(x: sgn * 3.5, y: w * 0.5 + 5.5)); ctx.strokePath()
            }
            ctx.setFillColor(black)
            ctx.fillEllipse(in: CGRect(x: -1.8, y: w * 0.55 + 2.2, width: 1.4, height: 1.6))
            ctx.fillEllipse(in: CGRect(x: 0.4, y: w * 0.55 + 2.2, width: 1.4, height: 1.6))
        case .mushroom:
            // A red toadstool cap with white spots.
            let red = CGColor(red: 0.85, green: 0.2, blue: 0.16, alpha: 1)
            let cap = CGMutablePath()
            cap.move(to: CGPoint(x: -w * 1.3, y: 0))
            cap.addQuadCurve(to: CGPoint(x: w * 1.3, y: 0), control: CGPoint(x: 0, y: w * 2.3))
            cap.addQuadCurve(to: CGPoint(x: -w * 1.3, y: 0), control: CGPoint(x: 0, y: -w * 0.25))
            cap.closeSubpath()
            outlined(cap, fill: red)
            ctx.setFillColor(CGColor(red: 0.98, green: 0.96, blue: 0.9, alpha: 1))
            for (x, y, r) in [(-w * 0.6, w * 0.45, 2.4), (w * 0.15, w * 0.85, 3.0), (w * 0.75, w * 0.35, 2.0), (-w * 0.1, w * 0.25, 1.5)] {
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
        ctx.restoreGState()
    }

    // MARK: Name tag

    private static func drawNameTag(_ pose: SpiderPose, in ctx: CGContext) {
        guard pose.nameTag > 0.02, !pose.name.isEmpty else { return }
        let s = max(pose.scale, 0.7)
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 10 * s, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.07, alpha: 1),
        ]
        let str = NSAttributedString(string: pose.name, attributes: attrs)
        var line = CTLineCreateWithAttributedString(str)
        let maxW = spriteSide(for: pose.scale) - 14
        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(maxW) {
            let ell = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attrs))
            line = CTLineCreateTruncatedLine(line, Double(maxW), .end, ell) ?? line
        }
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let h = ascent + descent
        let a = clamp(pose.nameTag, 0, 1)
        let pad: CGFloat = 5 * s
        let y = -(34 * pose.scale) - h
        let pill = CGRect(x: -width / 2 - pad, y: y - 2.5 * s, width: width + pad * 2, height: h + 5 * s)
        ctx.saveGState()
        ctx.setAlpha(a)
        let p = CGPath(roundedRect: pill, cornerWidth: pill.height / 2, cornerHeight: pill.height / 2, transform: nil)
        ctx.addPath(p)
        ctx.setFillColor(CGColor(red: 1, green: 0.97, blue: 0.90, alpha: 0.92))
        ctx.fillPath()
        ctx.addPath(p)
        ctx.setStrokeColor(CGColor(red: 0.30, green: 0.18, blue: 0.09, alpha: 0.8))
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.textPosition = CGPoint(x: -width / 2, y: y + descent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    // MARK: Emotes

    private static func drawEmote(_ pose: SpiderPose, in ctx: CGContext) {
        guard pose.emote != .none else { return }
        let s = pose.scale
        let t = pose.emoteT
        let fade = t < 0.12 ? t / 0.12 : (t > 0.75 ? (1 - t) / 0.25 : 1)
        let alpha = clamp(fade, 0, 1)
        guard alpha > 0.01 else { return }

        ctx.saveGState()
        ctx.translateBy(x: 0, y: 30 * s)
        // The little emotes (hearts, notes, Z's, sparkles, "!" and "?") are
        // drawn half as big again as the sprite's own scale, so they read
        // from across the room; a thought bubble sizes itself.
        let boost: CGFloat = pose.emote == .thought ? 1.45 : 1.55
        ctx.scaleBy(x: s * boost, y: s * boost)

        switch pose.emote {
        case .hearts:
            for i in 0..<3 {
                let ph = CGFloat(i) * 0.33
                let lt = (t * 1.4 + ph).truncatingRemainder(dividingBy: 1)
                let a = alpha * (1 - lt) * 0.95
                let x = CGFloat(i - 1) * 7 + sin(lt * 5 + ph * 6) * 2.5
                let y = lt * 16
                drawHeart(at: CGPoint(x: x, y: y), size: 4.2 * (0.7 + 0.5 * (1 - lt)), alpha: a, in: ctx)
            }
        case .zzz:
            // Z's that rise out of it one after another, drifting to the
            // side, each growing as it goes and fading at the top.
            for i in 0..<3 {
                let ph = CGFloat(i) * 0.33
                let lt = (t * 0.9 + ph).truncatingRemainder(dividingBy: 1)
                let a = alpha * (1 - lt * lt) * 0.85
                let x = 3 + lt * 13 + sin(lt * 7 + ph * 5) * 2.5
                drawZ(at: CGPoint(x: x, y: 2 + lt * 24), size: 3.2 + lt * 4.5, alpha: a, in: ctx)
            }
        case .surprise:
            let pop = easeOutBack(min(t * 4, 1))
            ctx.saveGState()
            ctx.translateBy(x: 0, y: 2)
            ctx.scaleBy(x: pop, y: pop)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: Double(alpha)))
            ctx.setStrokeColor(CGColor(red: 0.357, green: 0.227, blue: 0.114, alpha: Double(alpha)))
            ctx.setLineWidth(1.1)
            let bar = CGRect(x: -1.5, y: 3.2, width: 3.0, height: 8.0)
            let p = CGPath(roundedRect: bar, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            ctx.addPath(p); ctx.fillPath(); ctx.addPath(p); ctx.strokePath()
            ctx.fillEllipse(in: CGRect(x: -1.6, y: -0.4, width: 3.2, height: 3.2))
            ctx.strokeEllipse(in: CGRect(x: -1.6, y: -0.4, width: 3.2, height: 3.2))
            ctx.restoreGState()
        case .sparkle:
            for i in 0..<4 {
                let a0 = CGFloat(i) * 1.57 + t * 2.2
                let r = 9 + sin(t * 6 + CGFloat(i)) * 2.5
                let p = CGPoint(x: cos(a0) * r, y: 4 + sin(a0) * r * 0.55)
                drawStar(at: p, size: 2.6 + sin(t * 9 + CGFloat(i) * 2) * 0.8,
                         alpha: alpha * 0.9, in: ctx)
            }
        case .question:
            // "?" that pops up, hangs, then drifts off.
            let pop = easeOutBack(min(t * 3.5, 1))
            ctx.saveGState()
            ctx.translateBy(x: 2, y: 2 + t * 4)
            ctx.scaleBy(x: pop, y: pop)
            ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: Double(alpha)))
            ctx.setLineWidth(2.2)
            ctx.setLineCap(.round)
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: 0, y: 7), radius: 3.6, startAngle: .pi, endAngle: -0.5, clockwise: true)
            ctx.addLine(to: CGPoint(x: 0, y: 2.2))
            ctx.strokePath()
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: Double(alpha)))
            ctx.fillEllipse(in: CGRect(x: -1.4, y: -2.6, width: 2.8, height: 2.8))
            // dark rim so it reads on light desktops
            ctx.setStrokeColor(CGColor(red: 0.298, green: 0.180, blue: 0.086, alpha: Double(alpha * 0.8)))
            ctx.setLineWidth(0.8)
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: 0, y: 7), radius: 4.7, startAngle: .pi, endAngle: -0.5, clockwise: true)
            ctx.strokePath()
            ctx.restoreGState()
        case .exclaim:
            // Three little "!" that pop out at angles and drift up and away.
            let pop = easeOutBack(min(t * 4, 1))
            ctx.setFillColor(CGColor(red: 1, green: 0.88, blue: 0.3, alpha: Double(alpha)))
            ctx.setStrokeColor(CGColor(red: 0.357, green: 0.227, blue: 0.114, alpha: Double(alpha)))
            ctx.setLineWidth(1.0)
            for i in 0..<3 {
                let ang = CGFloat(i - 1) * 0.55
                let dist = (6 + t * 10) * pop
                ctx.saveGState()
                ctx.translateBy(x: sin(ang) * dist, y: 2 + cos(ang) * dist)
                ctx.rotate(by: -ang * 0.8)
                let sc = (0.7 + 0.3 * CGFloat(i % 2)) * pop
                ctx.scaleBy(x: sc, y: sc)
                let bar = CGRect(x: -1.4, y: 3, width: 2.8, height: 7.5)
                let p = CGPath(roundedRect: bar, cornerWidth: 1.4, cornerHeight: 1.4, transform: nil)
                ctx.addPath(p); ctx.fillPath(); ctx.addPath(p); ctx.strokePath()
                ctx.fillEllipse(in: CGRect(x: -1.5, y: -0.6, width: 3, height: 3))
                ctx.strokeEllipse(in: CGRect(x: -1.5, y: -0.6, width: 3, height: 3))
                ctx.restoreGState()
            }
        case .thought:
            drawThought(pose, alpha: alpha, in: ctx)
        case .note:
            // A couple of music notes bobbing upward.
            for i in 0..<2 {
                let ph = CGFloat(i) * 0.5
                let lt = (t * 1.2 + ph).truncatingRemainder(dividingBy: 1)
                let a = alpha * (1 - lt) * 0.95
                let x = CGFloat(i) * 9 - 4 + sin(lt * 6 + ph * 3) * 2
                let y = lt * 14
                let c = CGColor(red: 0.98, green: 0.88, blue: 0.55, alpha: Double(a))
                ctx.setFillColor(c)
                ctx.setStrokeColor(c)
                ctx.fillEllipse(in: CGRect(x: x - 2.6, y: y - 1.6, width: 5.2, height: 3.6))
                ctx.setLineWidth(1.4)
                ctx.setLineCap(.round)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x + 2.2, y: y))
                ctx.addLine(to: CGPoint(x: x + 2.2, y: y + 9))
                ctx.addQuadCurve(to: CGPoint(x: x + 6.5, y: y + 6), control: CGPoint(x: x + 5.5, y: y + 9.5))
                ctx.strokePath()
            }
        case .none:
            break
        }
        ctx.restoreGState()
    }

    private static func drawHeart(at c: CGPoint, size: CGFloat, alpha: CGFloat, in ctx: CGContext) {
        drawHeart(at: c, size: size, colour: CGColor(red: 0.941, green: 0.388, blue: 0.451, alpha: Double(alpha)), in: ctx)
    }

    private static func drawHeart(at c: CGPoint, size: CGFloat, colour: CGColor, in ctx: CGContext) {
        let p = CGMutablePath()
        let s = size
        p.move(to: CGPoint(x: c.x, y: c.y - s))
        p.addCurve(to: CGPoint(x: c.x - s * 1.05, y: c.y + s * 0.45),
                   control1: CGPoint(x: c.x - s * 0.7, y: c.y - s * 0.45),
                   control2: CGPoint(x: c.x - s * 1.05, y: c.y - s * 0.1))
        p.addArc(center: CGPoint(x: c.x - s * 0.5, y: c.y + s * 0.5), radius: s * 0.55,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        p.addArc(center: CGPoint(x: c.x + s * 0.5, y: c.y + s * 0.5), radius: s * 0.55,
                 startAngle: .pi, endAngle: 0, clockwise: true)
        p.addCurve(to: CGPoint(x: c.x, y: c.y - s),
                   control1: CGPoint(x: c.x + s * 1.05, y: c.y - s * 0.1),
                   control2: CGPoint(x: c.x + s * 0.7, y: c.y - s * 0.45))
        p.closeSubpath()
        ctx.addPath(p)
        ctx.setFillColor(colour)
        ctx.fillPath()
    }

    /// A thought bubble: a cloud above and a little behind the head, two
    /// small puffs leading up to it, with a picture or some words inside.
    /// Drawn in the emote frame (already scaled by the sprite's scale, origin
    /// 30 units above the body), so it grows with the spider.
    private static func drawThought(_ pose: SpiderPose, alpha: CGFloat, in ctx: CGContext) {
        let t = pose.emoteT
        let pop = easeOutBack(min(t * 3, 1))
        // Size the cloud to what is in it.
        var textLines: [CTLine] = []
        var textW: CGFloat = 0, textH: CGFloat = 0
        let ink = NSColor(calibratedRed: 0.22, green: 0.14, blue: 0.08, alpha: 1)
        if case .text(let str) = pose.thought {
            let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, 8.5, nil)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
            let maxW: CGFloat = 96
            // Word-wrap by hand: greedy lines up to maxW, at most four.
            var lines: [String] = []
            var cur = ""
            for word in str.split(separator: " ").map(String.init) {
                let trial = cur.isEmpty ? word : cur + " " + word
                let w = CTLineGetTypographicBounds(CTLineCreateWithAttributedString(NSAttributedString(string: trial, attributes: attrs)), nil, nil, nil)
                if w > Double(maxW), !cur.isEmpty { lines.append(cur); cur = word } else { cur = trial }
            }
            if !cur.isEmpty { lines.append(cur) }
            if lines.count > 4 { lines = Array(lines.prefix(3)) + [lines[3] + "…"] }
            for l in lines {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: l, attributes: attrs))
                textLines.append(line)
                textW = max(textW, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)))
            }
            textH = CGFloat(lines.count) * 10.5
        }
        let innerW = max(18, textW + 4), innerH = max(16, textH + 2)
        let cw = innerW + 14, ch = innerH + 10
        // The cloud sits up and back over the head.
        let cx: CGFloat = -6, cy: CGFloat = 18 + ch / 2
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        ctx.scaleBy(x: pop, y: pop)
        ctx.translateBy(x: -cx, y: -cy)
        let fill = CGColor(red: 1, green: 0.98, blue: 0.94, alpha: Double(alpha * 0.96))
        let rim = CGColor(red: 0.30, green: 0.18, blue: 0.09, alpha: Double(alpha * 0.85))
        ctx.setFillColor(fill)
        ctx.setStrokeColor(rim)
        ctx.setLineWidth(1.1)
        // Trail puffs from the head to the cloud.
        for (i, r) in [(0, CGFloat(1.6)), (1, CGFloat(2.6))] {
            let p = CGPoint(x: 2 - CGFloat(i) * 4, y: 4 + CGFloat(i) * 6)
            ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            ctx.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
        }
        // The cloud: a rounded body with bumps round the rim.
        let body = CGRect(x: cx - cw / 2, y: cy - ch / 2, width: cw, height: ch)
        let cloud = CGMutablePath()
        cloud.addRoundedRect(in: body, cornerWidth: min(9, ch / 2 - 1), cornerHeight: min(9, ch / 2 - 1))
        let bumps = max(6, Int(cw / 9))
        for k in 0..<bumps {
            let u = (CGFloat(k) + 0.5) / CGFloat(bumps)
            let r = 4.0 + CGFloat(k % 2) * 1.5
            cloud.addEllipse(in: CGRect(x: body.minX + u * cw - r, y: body.maxY - r * 0.7, width: r * 2, height: r * 2))
            cloud.addEllipse(in: CGRect(x: body.minX + u * cw - r, y: body.minY - r * 1.3, width: r * 2, height: r * 2))
        }
        for k in 0..<2 {
            let r: CGFloat = 4.5
            let y = body.minY + (CGFloat(k) + 0.5) / 2 * ch
            cloud.addEllipse(in: CGRect(x: body.minX - r * 1.2, y: y - r, width: r * 2, height: r * 2))
            cloud.addEllipse(in: CGRect(x: body.maxX - r * 0.8, y: y - r, width: r * 2, height: r * 2))
        }
        ctx.addPath(cloud); ctx.fillPath()
        // Outline only the outside: stroke, then paint the interior over it.
        ctx.addPath(cloud); ctx.strokePath()
        ctx.addPath(cloud); ctx.setFillColor(fill); ctx.fillPath()
        ctx.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.94, alpha: Double(alpha * 0.96)))
        ctx.fill(body.insetBy(dx: 1.5, dy: 1.5))

        // What it is thinking.
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy)
        switch pose.thought {
        case .text:
            let total = CGFloat(textLines.count) * 10.5
            for (i, line) in textLines.enumerated() {
                let w = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                ctx.textPosition = CGPoint(x: -w / 2, y: total / 2 - 8.5 - CGFloat(i) * 10.5)
                ctx.setAlpha(alpha)
                CTLineDraw(line, ctx)
            }
        case .heart:
            drawHeart(at: CGPoint(x: 0, y: 0), size: 5.5 + sin(t * 12) * 0.5, alpha: alpha, in: ctx)
        case .star:
            drawStar(at: CGPoint(x: 0, y: 0), size: 5, colour: CGColor(red: 1, green: 0.85, blue: 0.3, alpha: Double(alpha)), in: ctx)
        case .music:
            drawNote(at: CGPoint(x: -2, y: -3), size: 5, alpha: alpha, in: ctx)
        case .sun:
            ctx.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.2, alpha: Double(alpha)))
            ctx.setStrokeColor(CGColor(red: 0.85, green: 0.55, blue: 0.1, alpha: Double(alpha)))
            ctx.setLineWidth(1.2)
            for k in 0..<8 {
                let a = CGFloat(k) / 8 * 2 * .pi + t * 0.8
                ctx.beginPath()
                ctx.move(to: CGPoint(x: cos(a) * 5.5, y: sin(a) * 5.5))
                ctx.addLine(to: CGPoint(x: cos(a) * 8, y: sin(a) * 8))
                ctx.strokePath()
            }
            ctx.fillEllipse(in: CGRect(x: -4.5, y: -4.5, width: 9, height: 9))
            ctx.strokeEllipse(in: CGRect(x: -4.5, y: -4.5, width: 9, height: 9))
        case .rain:
            // A grey cloud with drops falling from it.
            ctx.setFillColor(CGColor(red: 0.62, green: 0.66, blue: 0.74, alpha: Double(alpha)))
            ctx.setStrokeColor(CGColor(red: 0.35, green: 0.38, blue: 0.48, alpha: Double(alpha)))
            ctx.setLineWidth(1)
            let cl = CGMutablePath()
            cl.addEllipse(in: CGRect(x: -7, y: 0, width: 8, height: 7))
            cl.addEllipse(in: CGRect(x: -3, y: 2, width: 9, height: 8))
            cl.addEllipse(in: CGRect(x: 1, y: 0, width: 7, height: 6.5))
            cl.addRect(CGRect(x: -6, y: 0, width: 13, height: 3.5))
            ctx.addPath(cl); ctx.fillPath()
            ctx.setStrokeColor(CGColor(red: 0.35, green: 0.55, blue: 0.9, alpha: Double(alpha)))
            ctx.setLineWidth(1.4)
            ctx.setLineCap(.round)
            for k in 0..<3 {
                let fall = (t * 2.5 + CGFloat(k) * 0.33).truncatingRemainder(dividingBy: 1)
                let x = CGFloat(k - 1) * 4.5
                let y = -1 - fall * 7
                ctx.beginPath(); ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x - 0.8, y: y - 2.5)); ctx.strokePath()
            }
        case .moon:
            ctx.setFillColor(CGColor(red: 1, green: 0.92, blue: 0.55, alpha: Double(alpha)))
            ctx.setStrokeColor(CGColor(red: 0.6, green: 0.5, blue: 0.2, alpha: Double(alpha)))
            ctx.setLineWidth(1)
            // A crescent: a disc with a bite taken out of it by the bubble.
            ctx.fillEllipse(in: CGRect(x: -6.5, y: -6.5, width: 13, height: 13))
            ctx.strokeEllipse(in: CGRect(x: -6.5, y: -6.5, width: 13, height: 13))
            ctx.setFillColor(CGColor(red: 1, green: 0.98, blue: 0.94, alpha: Double(alpha)))
            ctx.fillEllipse(in: CGRect(x: -1.5, y: -5, width: 11, height: 11))
            drawStar(at: CGPoint(x: 6, y: 5), size: 1.6, colour: CGColor(red: 1, green: 0.92, blue: 0.55, alpha: Double(alpha)), in: ctx)
        case .hungry:
            // A juicy cricket: what it would like.
            ctx.setFillColor(CGColor(red: 0.55, green: 0.47, blue: 0.24, alpha: Double(alpha)))
            ctx.setStrokeColor(CGColor(red: 0.16, green: 0.12, blue: 0.06, alpha: Double(alpha)))
            ctx.setLineWidth(1)
            ctx.fillEllipse(in: CGRect(x: -7, y: -3, width: 11, height: 5.5)); ctx.strokeEllipse(in: CGRect(x: -7, y: -3, width: 11, height: 5.5))
            ctx.fillEllipse(in: CGRect(x: 2.5, y: -2.5, width: 5, height: 5)); ctx.strokeEllipse(in: CGRect(x: 2.5, y: -2.5, width: 5, height: 5))
            ctx.setLineWidth(1.4)
            ctx.beginPath(); ctx.move(to: CGPoint(x: -3, y: -2)); ctx.addLine(to: CGPoint(x: -7, y: 3)); ctx.addLine(to: CGPoint(x: -5, y: -4)); ctx.strokePath()
            ctx.setLineWidth(0.8)
            for a in [CGFloat(0.5), 1.1] {
                ctx.beginPath(); ctx.move(to: CGPoint(x: 6, y: 1)); ctx.addLine(to: CGPoint(x: 6 + cos(a) * 6, y: 1 + sin(a) * 6)); ctx.strokePath()
            }
            // and a little drool.
            ctx.setFillColor(CGColor(red: 0.6, green: 0.8, blue: 1, alpha: Double(alpha * 0.9)))
            ctx.fillEllipse(in: CGRect(x: 8, y: -7 + sin(t * 6) * 0.5, width: 2.2, height: 3))
        case .bug:
            // A fly buzzing about.
            let a = t * 9
            let c = CGPoint(x: cos(a) * 3, y: sin(a * 1.3) * 2)
            ctx.setFillColor(CGColor(red: 0.85, green: 0.9, blue: 1, alpha: Double(alpha * 0.7)))
            ctx.fillEllipse(in: CGRect(x: c.x - 7, y: c.y + 1, width: 7, height: 3.6))
            ctx.fillEllipse(in: CGRect(x: c.x, y: c.y + 1, width: 7, height: 3.6))
            ctx.setFillColor(CGColor(red: 0.28, green: 0.2, blue: 0.14, alpha: Double(alpha)))
            ctx.fillEllipse(in: CGRect(x: c.x - 5, y: c.y - 2.5, width: 10, height: 5))
            ctx.fillEllipse(in: CGRect(x: c.x + 3.5, y: c.y - 2, width: 4, height: 4))
            ctx.setFillColor(CGColor(red: 0.85, green: 0.15, blue: 0.1, alpha: Double(alpha)))
            ctx.fillEllipse(in: CGRect(x: c.x + 5.2, y: c.y - 0.6, width: 1.8, height: 1.8))
        case .home:
            // Its hammock: a sagging sling with a sleeping shape in it.
            ctx.setStrokeColor(CGColor(red: 0.5, green: 0.5, blue: 0.6, alpha: Double(alpha)))
            ctx.setLineWidth(1)
            for k in 0..<3 {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: -9, y: 5))
                ctx.addQuadCurve(to: CGPoint(x: 9, y: 5), control: CGPoint(x: 0, y: -8 - CGFloat(k) * 2))
                ctx.strokePath()
            }
            ctx.setFillColor(CGColor(red: 0.85, green: 0.6, blue: 0.35, alpha: Double(alpha)))
            ctx.fillEllipse(in: CGRect(x: -4, y: -3.5, width: 8, height: 5))
        }
        ctx.restoreGState()
        ctx.restoreGState()
    }

    private static func drawNote(at c: CGPoint, size: CGFloat, alpha: CGFloat, in ctx: CGContext) {
        let col = CGColor(red: 0.98, green: 0.8, blue: 0.35, alpha: Double(alpha))
        ctx.setFillColor(col); ctx.setStrokeColor(col)
        ctx.fillEllipse(in: CGRect(x: c.x - size * 0.55, y: c.y - size * 0.35, width: size * 1.1, height: size * 0.75))
        ctx.setLineWidth(size * 0.3)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x + size * 0.45, y: c.y))
        ctx.addLine(to: CGPoint(x: c.x + size * 0.45, y: c.y + size * 1.9))
        ctx.addQuadCurve(to: CGPoint(x: c.x + size * 1.35, y: c.y + size * 1.3), control: CGPoint(x: c.x + size * 1.15, y: c.y + size * 2))
        ctx.strokePath()
    }

    private static func drawZ(at c: CGPoint, size: CGFloat, alpha: CGFloat, in ctx: CGContext) {
        let s = size
        ctx.setStrokeColor(CGColor(red: 0.42, green: 0.47, blue: 0.62, alpha: Double(alpha)))
        ctx.setLineWidth(max(1.0, s * 0.32))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: c.x - s / 2, y: c.y + s / 2))
        ctx.addLine(to: CGPoint(x: c.x + s / 2, y: c.y + s / 2))
        ctx.addLine(to: CGPoint(x: c.x - s / 2, y: c.y - s / 2))
        ctx.addLine(to: CGPoint(x: c.x + s / 2, y: c.y - s / 2))
        ctx.strokePath()
    }

    private static func drawStar(at c: CGPoint, size: CGFloat, alpha: CGFloat, in ctx: CGContext) {
        drawStar(at: c, size: size, colour: CGColor(red: 1, green: 0.93, blue: 0.62, alpha: Double(alpha)), in: ctx)
    }

    private static func drawStar(at c: CGPoint, size: CGFloat, colour: CGColor, in ctx: CGContext) {
        let p = CGMutablePath()
        let s = size
        p.move(to: CGPoint(x: c.x, y: c.y + s))
        p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: CGPoint(x: c.x + s * 0.22, y: c.y + s * 0.22))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: CGPoint(x: c.x + s * 0.22, y: c.y - s * 0.22))
        p.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: CGPoint(x: c.x - s * 0.22, y: c.y - s * 0.22))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: CGPoint(x: c.x - s * 0.22, y: c.y + s * 0.22))
        ctx.addPath(p)
        ctx.setFillColor(colour)
        ctx.fillPath()
    }

    // MARK: Menu bar icon

    static func statusItemImage(size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.translateBy(x: rect.midX, y: rect.midY)
            let s = size / 46
            ctx.scaleBy(x: s, y: s)
            ctx.rotate(by: .pi / 2)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            // Legs
            for side in [CGFloat(1), CGFloat(-1)] {
                let feet: [(V2, V2)] = [
                    (V2(8, side * 5), V2(21, side * 15)),
                    (V2(4, side * 6), V2(12, side * 23)),
                    (V2(0, side * 6), V2(-6, side * 24)),
                    (V2(-4, side * 5), V2(-19, side * 17)),
                ]
                for (h, f) in feet {
                    let knee = V2((h.x + f.x) / 2 + side * 0, (h.y + f.y) / 2 + side * 5)
                    ctx.setLineWidth(4.4)
                    ctx.beginPath()
                    ctx.move(to: h.point); ctx.addLine(to: knee.point); ctx.addLine(to: f.point)
                    ctx.strokePath()
                }
            }
            ctx.fillEllipse(in: CGRect(x: -24, y: -13, width: 27, height: 26))
            ctx.fillEllipse(in: CGRect(x: -5, y: -11.5, width: 24, height: 23))
            return true
        }
        img.isTemplate = true
        return img
    }
}
