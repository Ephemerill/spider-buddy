import AppKit
import QuartzCore

// MARK: - A visitor

/// A spider from somewhere else, dropping by for a while. It is not yours:
/// no name, no thoughts, nothing to customise, and it goes when it is ready
/// to. While it is here it plays with your spider and is as taken with the
/// pointer as any spider. Its own small window follows it about, like your
/// spider's does.
final class Visitor {
    /// The most visitors out at once.
    static let most = 5

    let spider: Spider
    /// Its place in the silk window (your spider is 0).
    let slot: Int
    let window: OverlayWindow
    let view: SpiderView
    /// When it means to be off.
    var leaveAt: CFTimeInterval
    /// On its way out: climbing up out of sight, then gone.
    var leaving = false
    var leavingSince: CFTimeInterval = 0
    private var spriteSide: CGFloat = 160
    private var side: CGFloat = 228

    init(map: SurfaceMap, slot: Int, scale: CGFloat, stay: CFTimeInterval) {
        spider = Spider(map: map)
        spider.apply(design: Visitor.randomDesign())
        spider.config.scale = scale
        spider.config.hammocks = false
        self.slot = slot
        leaveAt = CACurrentMediaTime() + stay
        window = OverlayWindow(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view = SpiderView(frame: CGRect(x: 0, y: 0, width: side, height: side))
        view.spider = spider
        window.contentView = view
        resize()
    }

    /// Any look at all, but never a living coat; and none of the parts of
    /// a personality that make a spider yours — no name, nothing to say,
    /// no bed to make.
    static func randomDesign() -> SpiderDesign {
        var d = SpiderDesign.random()
        d.name = ""
        d.packs = []
        d.customPhrases = []
        if d.look.skin == .living {
            d.look.skin = .coat
            d.look.coat = Coat.allCases.randomElement()!
        }
        d.habits.muse = 0
        d.habits.hammock = 0
        d.habits.nap = 0
        d.habits.sleep = 0.2
        d.habits.peekaboo = 0.2
        return d
    }

    func resize() {
        spriteSide = SpiderRenderer.spriteSide(for: spider.config.scale)
        side = spriteSide + 68
        view.resize(sprite: spriteSide, window: side)
        window.setContentSize(CGSize(width: side, height: side))
        view.worldOrigin = window.frame.origin
    }

    /// Moves the window along once the spider has wandered far enough in
    /// it, and draws it. True if anything moved or was redrawn.
    func show(_ pose: SpiderPose, map: SurfaceMap) -> Bool {
        var moved = false
        let frame = window.frame
        let recentreAt = (side - spriteSide) / 2 - 4
        if abs(pose.pos.x - frame.midX) > recentreAt || abs(pose.pos.y - frame.midY) > recentreAt {
            window.setFrameOrigin(CGPoint(x: (pose.pos.x - side / 2).rounded(), y: (pose.pos.y - side / 2).rounded()))
            view.worldOrigin = window.frame.origin
            moved = true
        }
        // Up over the menu bar and the Dock while any of it is in their strip.
        let r = spriteSide / 2
        let sprite = CGRect(x: pose.pos.x - r, y: pose.pos.y - r, width: r * 2, height: r * 2)
        let inStrip = NSScreen.screens.contains { s in
            let bar = s.frame.maxY - s.visibleFrame.maxY
            guard bar > 12 else { return false }
            return sprite.intersects(CGRect(x: s.frame.minX, y: s.frame.maxY - bar, width: s.frame.width, height: bar))
        } || map.dockRects.contains { sprite.intersects($0) }
        let want: NSWindow.Level = inStrip ? .statusBar : .floating
        if window.level != want { window.level = want }
        view.apply(pose)
        return moved || view.didRedraw
    }
}

// MARK: - Playing together

/// Your spider and its visitors notice each other. Meeting, they say hello
/// or have a little dance; now and then a visitor goes over to see your
/// spider, or starts a game of tag with it — whoever is it chases, the
/// other runs and leaps away, and a tag swaps them over. A spider thrown
/// past another gives it a start.
final class Playground {
    private struct Tag {
        weak var it: Spider?
        weak var runner: Spider?
        var until: CFTimeInterval
        /// Just tagged: the new one who is it counts to three first.
        var countUntil: CFTimeInterval
    }
    private var tag: Tag?
    private var nextGameAt = CACurrentMediaTime() + 10
    private var nextLook: CFTimeInterval = 0
    /// When each pair last met, so a hello is not every other second.
    private var lastMet: [Set<ObjectIdentifier>: CFTimeInterval] = [:]
    private var lastStartled: [ObjectIdentifier: CFTimeInterval] = [:]

    /// Whether a game is on (the clock must not throttle through one).
    var busy: Bool { tag != nil }
    /// Tools only: tags so far, hellos and dances so far, and a game on demand.
    private(set) var debugTags = 0
    var debugMeetings: Int { lastMet.count }
    func debugStartTag(it: Spider, runner: Spider) {
        tag = Tag(it: it, runner: runner, until: CACurrentMediaTime() + 20, countUntil: CACurrentMediaTime() + 0.5)
    }

    /// `host` is your spider; `guests` the visitors.
    func update(host: Spider, guests: [Spider], now: CFTimeInterval) {
        let everyone = ([host] + guests).filter { !$0.config.paused }
        guard everyone.count > 1 else { stop([host] + guests); return }
        runTag(now: now)

        guard now >= nextLook else { return }
        nextLook = now + 0.25

        for (i, a) in everyone.enumerated() {
            for b in everyone[(i + 1)...] where a.map === b.map {
                let d = a.worldPos.distance(to: b.worldPos)
                let sc = max(a.config.scale, b.config.scale)
                // Thrown or falling past the other gives it a start.
                for (flier, sitter) in [(a, b), (b, a)] where flier.isAirborne && !sitter.isAirborne && d < 46 * sc
                    && now - (lastStartled[ObjectIdentifier(sitter)] ?? -99) > 3 {
                    lastStartled[ObjectIdentifier(sitter)] = now
                    sitter.startledByFriend()
                }
                // Meeting: a hello, or a little dance together.
                guard tag == nil, a.canPlay, b.canPlay, d < 130 * sc else { continue }
                let key: Set<ObjectIdentifier> = [ObjectIdentifier(a), ObjectIdentifier(b)]
                guard now - (lastMet[key] ?? -99) > 25 else { continue }
                lastMet[key] = now
                if chance(0.65) {
                    a.greetFriend(at: b.worldPos)
                    b.greetFriend(at: a.worldPos)
                } else {
                    a.danceWithFriend()
                    b.danceWithFriend()
                }
            }
        }

        // Now and then a visitor comes to see your spider, or starts a game.
        guard tag == nil, now >= nextGameAt else { return }
        nextGameAt = now + Double(randRange(15, 40) * lerp(1.4, 0.7, host.personality.playfulness))
        guard host.canPlay, let guest = guests.filter({ $0.canPlay && $0.map === host.map }).randomElement() else { return }
        if chance(0.3 + host.personality.playfulness * 0.4) {
            // Tag, and the visitor is it.
            tag = Tag(it: guest, runner: host, until: now + Double(randRange(14, 24)), countUntil: now + 0.8)
        } else {
            guest.visitFriend(at: host.worldPos)
        }
    }

    private func runTag(now: CFTimeInterval) {
        guard var g = tag else { return }
        guard let it = g.it, let runner = g.runner, it.map === runner.map,
              !it.config.paused, !runner.config.paused, !it.isHeld, !runner.isHeld,
              it.laser == nil, now < g.until else {
            endTag(now: now)
            return
        }
        let sc = max(it.config.scale, runner.config.scale)
        runner.friendFlee = it.worldPos
        if now < g.countUntil {
            it.friendChase = nil
        } else {
            it.friendChase = runner.worldPos
            if it.worldPos.distance(to: runner.worldPos) < 40 * sc, !runner.isOnLine, !it.isOnLine {
                it.taggedFriend()
                runner.startledByFriend()
                debugTags += 1
                it.friendChase = nil
                runner.friendFlee = nil
                g = Tag(it: runner, runner: it, until: g.until, countUntil: now + 1.8)
            }
        }
        tag = g
    }

    private func endTag(now: CFTimeInterval) {
        guard let g = tag else { return }
        tag = nil
        let players = [g.it, g.runner].compactMap { $0 }
        for s in players {
            s.friendChase = nil
            s.friendFlee = nil
            if chance(0.6) { s.danceWithFriend() }
        }
        if players.count == 2 { lastMet[Set(players.map(ObjectIdentifier.init))] = now }
        nextGameAt = max(nextGameAt, now + Double(randRange(20, 40)))
    }

    /// Everyone stops playing.
    func stop(_ spiders: [Spider]) {
        tag = nil
        for s in spiders {
            s.friendChase = nil
            s.friendFlee = nil
        }
    }
}
