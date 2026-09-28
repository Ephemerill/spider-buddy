import AppKit

// MARK: - Where things are, round the habitat
//
// Four coordinate spaces meet at the tank, and they are never mixed:
//
//  • screen — AppKit's global points, y up: the desktop, where the spider
//    lives outside the tank, and where the pointer is
//    (`NSEvent.mouseLocation`). Window frames are in it.
//  • window — the tank window's own points (`NSEvent.locationInWindow`).
//  • view — the scene view's bounds: the glass itself, one point to a
//    screen point, its origin at the glass's bottom-left corner.
//  • world — the habitat: fixed, one point to a screen point (the spider
//    is the same size in there as on the desktop), its origin at the
//    tank's bottom-left inside corner, the lid at the top of it. Inside the
//    tank the spider, its prey, the furniture, its surfaces and everything
//    lying about live here, whatever the window is doing.
//
// The camera below is the world point at the view's origin. The scene
// view holds the only conversions between the four ("Coordinate spaces"
// in HabitatScene.swift); nothing else adds or takes away offsets of its
// own. Moving the window moves the whole tank; resizing it shows more or
// less of the world; the camera moving shows another part of it — and
// none of those touch anything in the world.

/// Which part of the habitat's world the glass shows, and how that changes:
/// quietly following the spider about, left where you pan it to, or gliding
/// somewhere (back to the spider, or to a spot picked in the overview).
///
/// Following has a wide dead zone — the middle of the glass, about half of
/// it each way — and the camera only moves once the spider is out of it,
/// easing over until the spider is comfortably inside again (with more room
/// ahead of it than behind) and then stopping. Most of the time nothing
/// moves at all, the way you would watch a tank.
final class HabitatCamera {
    /// The world point at the glass's bottom-left.
    private(set) var origin = V2.zero
    /// The glass, in points.
    private(set) var view = CGSize(width: 860, height: 516)
    private(set) var world = CGSize(width: 3000, height: 1200)

    enum Mode: Equatable {
        /// Easing after the spider whenever it strays out of the dead zone.
        case follow
        /// Where you put it: it stays there (coasting to a stop after a
        /// flick), the spider going about its business wherever it is.
        case free
        /// On its way somewhere: back to the spider (and then following
        /// it), or to a spot (and then left there).
        case glide(thenFollow: Bool)
    }
    private(set) var mode = Mode.follow

    private var target = V2.zero
    private var vel = V2.zero
    /// Following: easing toward `target` since the spider left the dead zone.
    private var engaged = false
    /// A flick's momentum, after a pan.
    private var coast = V2.zero
    private var lastTouched = CACurrentMediaTime()

    /// How fast it eases (a critically damped spring of this frequency, in
    /// radians a second) — a couple of seconds to settle a half-glass move.
    private static let omega: CGFloat = 2.5
    /// It is never in more of a hurry than this.
    private static let maxSpeed: CGFloat = 1600
    /// Left alone somewhere with the spider out of sight this long, it
    /// drifts back to it.
    static let returnAfter: CFTimeInterval = 90

    /// What the glass shows, in the world.
    var visible: CGRect { CGRect(x: origin.x, y: origin.y, width: view.width, height: view.height) }

    /// The middle of the glass, where the spider may go where it likes
    /// without the camera stirring: 56% of it across, half of it up.
    var deadZone: CGRect { visible.insetBy(dx: view.width * 0.22, dy: view.height * 0.25) }

    /// Near enough the middle that, panned there, it goes back to following.
    private var comfortZone: CGRect { visible.insetBy(dx: view.width * 0.3, dy: view.height * 0.3) }

    /// Still: nothing to ease, nothing coasting.
    var resting: Bool {
        switch mode {
        case .glide: return false
        case .free: return coast.lengthSquared < 1
        case .follow: return !engaged
        }
    }

    // MARK: Sizes

    func setWorld(_ size: CGSize) {
        world = size
        origin = clamped(origin)
        target = clamped(target)
    }

    /// The glass was resized; `shift` is how far its bottom-left moved on
    /// the screen, so the world stays put where the glass grew or shrank.
    func setView(_ size: CGSize, shift: V2 = .zero) {
        guard size.width > 1, size.height > 1 else { return }
        view = size
        origin = clamped(origin + shift)
        target = clamped(target + shift)
    }

    // MARK: Moving it

    /// Straight there, no easing (opening the tank, restoring it).
    func jump(to o: V2) {
        origin = clamped(o)
        target = origin
        vel = .zero
        coast = .zero
        engaged = false
    }

    /// The origin that puts `p` in the middle of the glass.
    func centring(_ p: V2) -> V2 { clamped(p - V2(view.width / 2, view.height / 2)) }

    /// Eases over to put `p` in the middle, then follows the spider (if
    /// `follow`: `p` is where the spider is) or stays there.
    func glide(toCentre p: V2, thenFollow follow: Bool) {
        target = centring(p)
        coast = .zero
        mode = .glide(thenFollow: follow)
        lastTouched = CACurrentMediaTime()
    }

    /// Back to the spider, and following it again.
    func recall(to spider: V2) { glide(toCentre: spider, thenFollow: true) }

    /// A drag across the glass: the world goes with the pointer.
    func beginPan() {
        mode = .free
        engaged = false
        coast = .zero
        vel = .zero
        lastTouched = CACurrentMediaTime()
    }

    /// Moves it by `d` in the world (a pan by `-d` on the glass).
    func pan(by d: V2) {
        if mode != .free { beginPan() }
        origin = clamped(origin + d)
        target = origin
        lastTouched = CACurrentMediaTime()
    }

    /// Let go of mid-flick: it coasts on and slows to a stop.
    func endPan(velocity v: V2) {
        coast = v.clampedLength(3000)
        if coast.length < 40 { coast = .zero }
        lastTouched = CACurrentMediaTime()
    }

    /// Something was done in the tank by hand: not the moment to wander off.
    func touched() { lastTouched = CACurrentMediaTime() }

    /// Moves it on for this frame. `spider`: where the spider is in the
    /// world, if it is in there to follow (not out on the desktop, not in
    /// your hand); `follows`: whether following is wanted at all just now
    /// (not while decorating). True if it moved.
    @discardableResult
    func update(dt: CGFloat, spider: V2?, follows: Bool) -> Bool {
        let was = origin
        switch mode {
        case .free:
            if coast.lengthSquared >= 1 {
                let before = origin
                origin = clamped(origin + coast * dt)
                // Against the end of the tank, that way stops.
                if abs(origin.x - (before.x + coast.x * dt)) > 0.01 { coast.x = 0 }
                if abs(origin.y - (before.y + coast.y * dt)) > 0.01 { coast.y = 0 }
                coast = coast * exp(-4.5 * dt)
                if coast.length < 8 { coast = .zero }
                target = origin
            }
            if follows, let s = spider, coast.lengthSquared < 1 {
                if comfortZone.contains(s.point) {
                    // Panned to where the spider is: following again.
                    mode = .follow
                    engaged = false
                } else if !visible.insetBy(dx: -40, dy: -40).contains(s.point),
                          CACurrentMediaTime() - lastTouched > HabitatCamera.returnAfter {
                    recall(to: s)
                }
            }
        case .glide(let follow):
            if follow, let s = spider { target = centring(s) }
            if step(dt) {
                mode = follow ? .follow : .free
                engaged = false
                lastTouched = CACurrentMediaTime()
            }
        case .follow:
            if follows, let s = spider {
                let dz = deadZone
                if !dz.contains(s.point) {
                    var t = engaged ? target : origin
                    // It comes to rest with more room ahead of the spider than behind.
                    if s.x > dz.maxX { t.x = s.x - view.width * 0.4 } else if s.x < dz.minX { t.x = s.x - view.width * 0.6 }
                    if s.y > dz.maxY { t.y = s.y - view.height * 0.4 } else if s.y < dz.minY { t.y = s.y - view.height * 0.6 }
                    target = clamped(t)
                    engaged = true
                }
            }
            if engaged, step(dt) { engaged = false }
        }
        return (origin - was).lengthSquared > 1e-6
    }

    /// Eases toward `target`; true once it is there and still.
    private func step(_ dt: CGFloat) -> Bool {
        let k = HabitatCamera.omega * HabitatCamera.omega, c = 2 * HabitatCamera.omega
        vel += ((target - origin) * k - vel * c) * dt
        vel = vel.clampedLength(HabitatCamera.maxSpeed)
        let before = origin + vel * dt
        origin = clamped(before)
        if abs(origin.x - before.x) > 0.01 { vel.x = 0 }
        if abs(origin.y - before.y) > 0.01 { vel.y = 0 }
        if (target - origin).length < 0.8, vel.length < 8 {
            origin = target
            vel = .zero
            return true
        }
        return false
    }

    /// Inside the world: the glass never looks past the tank's ends, top or
    /// bottom (a glass bigger than the world is centred on it).
    private func clamped(_ o: V2) -> V2 {
        func fit(_ v: CGFloat, _ span: CGFloat, _ glass: CGFloat) -> CGFloat {
            span <= glass ? (span - glass) / 2 : min(max(v, 0), span - glass)
        }
        return V2(fit(o.x, world.width, view.width), fit(o.y, world.height, view.height))
    }

    // MARK: Keeping it

    static let saveKey = "habitatCamera"

    /// Where it was looking, for next time the tank opens.
    func save() {
        UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: HabitatCamera.saveKey)
    }

    static func saved() -> V2? {
        guard let a = UserDefaults.standard.array(forKey: saveKey) as? [Double], a.count == 2 else { return nil }
        return V2(CGFloat(a[0]), CGFloat(a[1]))
    }
}

extension SpiderPose {
    /// The same pose `d` further along: for moving one drawn in the world
    /// out onto the screen (in your hand, over the desktop).
    func shifted(by d: V2) -> SpiderPose {
        var p = self
        p.pos += d
        p.silkAttach += d
        if let w = web { p.web = (w.anchor + d, w.alpha, w.slack) }
        p.webPoints = webPoints.map { $0 + d }
        p.hiddenBy = hiddenBy.map { $0.offsetBy(dx: d.x, dy: d.y) }
        return p
    }
}
