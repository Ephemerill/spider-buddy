import AppKit
import QuartzCore

// MARK: - Showing someone round the habitat

/// A short tour of the tank, the first time it opens (and again from its
/// ? button): the window dims, and a spotlight goes from one thing to the
/// next — the glass, the Map, Feed, Weather, Decorate, Let Out — with a few
/// words by each. Decorating has a tour of its own, the first time.
///
/// Like the welcome, it is the same for everyone: "your spider", never its
/// name.
final class HabitatTour: NSObject {
    enum Kind { case tank, decorating }

    struct Step {
        var title: String
        var text: String
        var symbol: String
        /// What it is about, in the window's own coordinates (nil: nothing
        /// in particular — the words sit in the middle).
        var target: () -> CGRect?
        /// Done as the step comes up (a tab shown, say).
        var enter: (() -> Void)? = nil
    }

    let kind: Kind
    private weak var controller: HabitatController?
    private let overlay: TourWindow
    private let view: TourView
    private let steps: [Step]
    private var index = 0
    var onFinish: (() -> Void)?

    static let seenKey = "habitatTourSeen"
    static let decoratingSeenKey = "habitatDecorateTourSeen"

    /// Tests and tools don't want it popping up in the middle of them: any
    /// SPIDER_… hook turns it off, except SPIDER_HABITAT_TOUR (its own).
    static var suppressed: Bool {
        let env = ProcessInfo.processInfo.environment
        if env["SPIDER_HABITAT_TOUR"] != nil { return false }
        return env.keys.contains { $0.hasPrefix("SPIDER_") }
    }

    static func seen(_ k: Kind) -> Bool {
        UserDefaults.standard.bool(forKey: k == .tank ? seenKey : decoratingSeenKey)
    }

    init(kind: Kind, controller: HabitatController) {
        self.kind = kind
        self.controller = controller
        overlay = TourWindow(contentRect: controller.window.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        view = TourView(frame: CGRect(origin: .zero, size: controller.window.frame.size))
        steps = kind == .tank ? HabitatTour.tankSteps(controller) : HabitatTour.decoratingSteps(controller)
        super.init()
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.contentView = view
        overlay.appearance = NSAppearance(named: .darkAqua)
        view.onNext = { [weak self] in self?.next() }
        view.onBack = { [weak self] in self?.back() }
        view.onSkip = { [weak self] in self?.finish() }
    }

    // MARK: The steps

    private static func rect(_ v: NSView?) -> CGRect? {
        guard let v, v.window != nil, !v.isHiddenOrHasHiddenAncestor, v.bounds.width > 1 else { return nil }
        return v.convert(v.bounds, to: nil)
    }

    private static func tankSteps(_ c: HabitatController) -> [Step] {
        let glass: () -> CGRect? = { [weak c] in rect(c?.scene).map { $0.insetBy(dx: 2, dy: 2) } }
        return [
            Step(title: "Welcome to the habitat",
                 text: "This is your spider’s very own tank — a little world, much bigger than the window. In here it explores, climbs, hunts, shelters from the weather and sleeps, all on its own.",
                 symbol: "leaf.fill", target: { nil }),
            Step(title: "Look around",
                 text: "Drag the glass to look round the tank (or scroll sideways, or use the arrow keys). You can pick your spider up, too — carry it out through the glass to put it back on your desktop.",
                 symbol: "hand.draw.fill", target: glass),
            Step(title: "The map",
                 text: "The whole tank at a glance. Click anywhere on it to go there — your spider is marked, so you can always find it.",
                 symbol: "map.fill", target: { [weak c] in rect(c?.mapButton) }),
            Step(title: "Feeding time",
                 text: "Let a fly, a cricket or a moth loose for your spider to hunt. Creatures find their own way in now and then, too — what comes depends on what’s in the tank.",
                 symbol: "fork.knife", target: { [weak c] in rect(c?.feedButton) }),
            Step(title: "Weather",
                 text: "The tank has weather of its own, and your spider feels it: it gets soaked in the rain and runs for cover when it pours. Bring some in now, or choose what comes and how often.",
                 symbol: "cloud.sun.rain.fill", target: { [weak c] in rect(c?.weatherButton) }),
            Step(title: "Make it yours",
                 text: "Decorate the tank: change the scenery, add plants, rocks, logs and even a little house — and save your habitats to come back to later.",
                 symbol: "paintbrush.pointed.fill", target: { [weak c] in rect(c?.decorateButton) }),
            Step(title: "Letting it out",
                 text: "When you’re done, let your spider back out onto your desktop. Closing the window does the same — the tank stays just as you left it.",
                 symbol: "door.left.hand.open", target: { [weak c] in rect(c?.letOutButton) }),
            Step(title: "That’s it!",
                 text: "If you ever want to see this again, it’s here.",
                 symbol: "questionmark", target: { [weak c] in rect(c?.helpButton) }),
        ]
    }

    private static func decoratingSteps(_ c: HabitatController) -> [Step] {
        let glass: () -> CGRect? = { [weak c] in rect(c?.scene).map { $0.insetBy(dx: 2, dy: 2) } }
        func tab(_ t: DecorPanel.Tab) -> () -> CGRect? {
            { [weak c] in
                guard let p = c?.decorPanelIfBuilt, p.window != nil else { return nil }
                return p.convert(p.tabRect(t), to: nil)
            }
        }
        return [
            Step(title: "Add things",
                 text: "Pick something here to drop it into the tank — plants, rocks, logs, shelters, even furniture for a little house. Search for something, or show just one kind.",
                 symbol: "plus.square.fill", target: tab(.add), enter: { [weak c] in c?.scene.select(nil); c?.decorPanelIfBuilt?.showTab(.add) }),
            Step(title: "Move things about",
                 text: "Click anything in the tank to pick it. Drag it to move it; drag a corner to make it bigger or smaller. Pieces click together where they meet — hold ⌥ to place something freely.",
                 symbol: "hand.point.up.left.fill", target: glass, enter: { [weak c] in c?.pickSomethingToShow() }),
            Step(title: "Change what you picked",
                 text: "What you’ve picked shows down here: flip it, make another, put it in front of your spider or behind it, or take it out.",
                 symbol: "slider.horizontal.3", target: { [weak c] in rect(c?.decorPanelIfBuilt?.inspectorView) },
                 enter: { [weak c] in c?.pickSomethingToShow() }),
            Step(title: "Scenery",
                 text: "The backdrop behind the glass — a forest, a desert, a beach… Everything in the tank stays where it is.",
                 symbol: "photo.fill", target: tab(.scenery), enter: { [weak c] in c?.scene.select(nil); c?.decorPanelIfBuilt?.showTab(.scenery) }),
            Step(title: "My Habitats",
                 text: "Save the tank as it is, and come back to it whenever you like — have a few, and swap between them. Or start afresh from a ready-made one.",
                 symbol: "square.stack.fill", target: tab(.habitats), enter: { [weak c] in c?.decorPanelIfBuilt?.showTab(.habitats) }),
            Step(title: "Changed your mind?",
                 text: "Undo takes anything back (⌘Z).",
                 symbol: "arrow.uturn.backward", target: { [weak c] in rect(c?.decorPanelIfBuilt?.undoView) }),
            Step(title: "All done?",
                 text: "Click Done when you’re happy. The tank keeps itself just as you leave it.",
                 symbol: "checkmark", target: { [weak c] in rect(c?.decorateButton) },
                 enter: { [weak c] in c?.decorPanelIfBuilt?.showTab(.add) }),
        ]
    }

    // MARK: Going round

    func start() {
        guard let c = controller else { return }
        overlay.setFrame(c.window.frame, display: false)
        c.window.addChildWindow(overlay, ordered: .above)
        overlay.makeKeyAndOrderFront(nil)
        overlay.makeFirstResponder(view)
        view.alphaValue = 0
        show(0, animated: false)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            view.animator().alphaValue = 1
        }
    }

    /// The window changed size: the dimming, and the spotlight, with it.
    func windowResized() {
        guard let c = controller else { return }
        overlay.setFrame(c.window.frame, display: true)
        view.frame = CGRect(origin: .zero, size: c.window.frame.size)
        show(index, animated: false)
    }

    private func show(_ i: Int, animated: Bool) {
        index = i
        let s = steps[i]
        s.enter?()
        view.layoutSubtreeIfNeeded()
        controller?.window.contentView?.layoutSubtreeIfNeeded()
        view.show(title: s.title, text: s.text, symbol: s.symbol, spot: s.target(), step: i, of: steps.count, animated: animated)
    }

    private func next() {
        if index + 1 < steps.count { show(index + 1, animated: true) } else { finish() }
    }

    private func back() {
        if index > 0 { show(index - 1, animated: true) }
    }

    /// Tools only: straight to a step.
    func debugShow(_ i: Int) { show(min(i, steps.count - 1), animated: false) }
    var stepCount: Int { steps.count }
    var overlayWindow: NSWindow { overlay }

    func finish() {
        UserDefaults.standard.set(true, forKey: kind == .tank ? HabitatTour.seenKey : HabitatTour.decoratingSeenKey)
        if kind == .decorating { controller?.scene.select(nil); controller?.decorPanelIfBuilt?.showTab(.add) }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            view.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.overlay.parent?.removeChildWindow(self.overlay)
            self.overlay.orderOut(nil)
            self.controller?.window.makeKeyAndOrderFront(nil)
            self.onFinish?()
        })
    }
}

/// The dimming over the tank: it takes the keys, for the tour.
final class TourWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// The dimming, with a hole where the spotlight is, and the words by it.
final class TourView: NSView {
    var onNext: (() -> Void)?
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?

    private let dim = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let card = NSView()
    private let badge = NSView()
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let text = NSTextField(wrappingLabelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip Tour", target: nil, action: nil)
    private var spot: CGRect?
    static let cardWidth: CGFloat = 330

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        dim.fillRule = .evenOdd
        dim.fillColor = CGColor(gray: 0, alpha: 0.55)
        ring.fillColor = nil
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        ring.lineWidth = 2.5
        ring.shadowColor = NSColor.controlAccentColor.cgColor
        ring.shadowOpacity = 0.9
        ring.shadowRadius = 8
        ring.shadowOffset = .zero
        layer?.addSublayer(dim)
        layer?.addSublayer(ring)
        let pulse = CABasicAnimation(keyPath: "shadowRadius")
        pulse.fromValue = 4
        pulse.toValue = 12
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        ring.add(pulse, forKey: "pulse")

        card.wantsLayer = true
        card.layer?.backgroundColor = CGColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 0.98)
        card.layer?.cornerRadius = 16
        card.layer?.borderWidth = 1
        card.layer?.borderColor = CGColor(gray: 1, alpha: 0.12)
        card.shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor(white: 0, alpha: 0.5)
            s.shadowBlurRadius = 24
            s.shadowOffset = CGSize(width: 0, height: -6)
            return s
        }()
        addSubview(card)

        badge.wantsLayer = true
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.layer?.cornerRadius = 18
        icon.contentTintColor = .white
        icon.imageScaling = .scaleProportionallyDown
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .white
        text.font = .systemFont(ofSize: 13)
        text.textColor = NSColor(white: 1, alpha: 0.78)
        text.preferredMaxLayoutWidth = TourView.cardWidth - 40
        counter.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        counter.textColor = NSColor(white: 1, alpha: 0.45)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(backTapped)
        skipButton.isBordered = false
        skipButton.contentTintColor = NSColor(white: 1, alpha: 0.55)
        skipButton.font = .systemFont(ofSize: 12)
        skipButton.target = self
        skipButton.action = #selector(skipTapped)
        for v in [badge, title, text, counter, nextButton, backButton, skipButton] as [NSView] { card.addSubview(v) }
        badge.addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    // (Everything under the dimming waits for the tour.)
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func scrollWheel(with event: NSEvent) {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onSkip?()                       // escape
        case 124, 49: onNext?()                  // → and space
        case 123: onBack?()                      // ←
        default: super.keyDown(with: event)
        }
    }

    @objc private func nextTapped() { onNext?() }
    @objc private func backTapped() { onBack?() }
    @objc private func skipTapped() { onSkip?() }

    func show(title t: String, text s: String, symbol: String, spot target: CGRect?, step: Int, of count: Int, animated: Bool) {
        title.stringValue = t
        text.stringValue = s
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .semibold))
        counter.stringValue = "\(step + 1) of \(count)"
        let last = step == count - 1
        nextButton.title = last ? "Got It" : "Next"
        backButton.isHidden = step == 0
        skipButton.isHidden = last
        spot = target.map { $0.insetBy(dx: -6, dy: -6) }

        // The card's own layout: badge and title, the words, then the buttons.
        let w = TourView.cardWidth, inset: CGFloat = 20
        let textSize = text.sizeThatFits(CGSize(width: w - inset * 2, height: 1000))
        let h = inset + 36 + 12 + ceil(textSize.height) + 18 + 30 + inset
        var y = h - inset - 36
        badge.frame = CGRect(x: inset, y: y, width: 36, height: 36)
        icon.frame = badge.bounds.insetBy(dx: 7, dy: 7)
        title.frame = CGRect(x: inset + 48, y: y + 7, width: w - inset * 2 - 48, height: 22)
        y -= 12 + ceil(textSize.height)
        text.frame = CGRect(x: inset, y: y, width: w - inset * 2, height: ceil(textSize.height))
        nextButton.sizeToFit()
        backButton.sizeToFit()
        skipButton.sizeToFit()
        let nw = max(nextButton.frame.width, 84)
        nextButton.frame = CGRect(x: w - inset - nw, y: inset - 2, width: nw, height: 30)
        backButton.frame = CGRect(x: nextButton.frame.minX - 8 - max(backButton.frame.width, 70), y: inset - 2,
                                  width: max(backButton.frame.width, 70), height: 30)
        skipButton.frame = CGRect(x: inset - 4, y: inset + 4, width: skipButton.frame.width, height: 18)
        counter.sizeToFit()
        counter.frame.origin = CGPoint(x: skipButton.isHidden ? inset : skipButton.frame.maxX + 8, y: inset + 6)

        let frame = cardFrame(size: CGSize(width: w, height: h))
        let dimPath = CGMutablePath()
        dimPath.addRect(bounds)
        let ringPath: CGPath
        if let r = spot {
            let radius = min(12, r.height / 2)
            dimPath.addRoundedRect(in: r, cornerWidth: radius, cornerHeight: radius)
            ringPath = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        } else {
            ringPath = CGPath(rect: CGRect(x: bounds.midX, y: bounds.midY, width: 0, height: 0), transform: nil)
        }
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.35)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            for (l, p) in [(dim, dimPath as CGPath), (ring, ringPath)] {
                let a = CABasicAnimation(keyPath: "path")
                a.fromValue = l.presentation()?.path ?? l.path
                a.toValue = p
                l.add(a, forKey: "path")
            }
        } else {
            CATransaction.setDisableActions(true)
        }
        dim.frame = bounds
        ring.frame = bounds
        dim.path = dimPath
        ring.path = ringPath
        ring.opacity = spot == nil ? 0 : 1
        CATransaction.commit()
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                ctx.allowsImplicitAnimation = true
                card.animator().frame = frame
            }
        } else {
            card.frame = frame
        }
        window?.makeFirstResponder(self)
    }

    /// Next to the spotlight — under it if there is room (the lid's
    /// buttons), else beside it or over it; in the middle of a big one
    /// (the glass), or with nothing lit up.
    private func cardFrame(size: CGSize) -> CGRect {
        let m: CGFloat = 14, gap: CGFloat = 14
        let area = bounds.insetBy(dx: m, dy: m)
        func fit(_ r: CGRect) -> CGRect {
            CGRect(x: min(max(r.minX, area.minX), area.maxX - r.width), y: min(max(r.minY, area.minY), area.maxY - r.height),
                   width: r.width, height: r.height)
        }
        let centre = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        guard let s = spot else { return centre }
        if s.width > bounds.width * 0.5 && s.height > bounds.height * 0.4 {
            return fit(CGRect(x: s.midX - size.width / 2, y: s.midY - size.height / 2, width: size.width, height: size.height))
        }
        let below = CGRect(x: s.midX - size.width / 2, y: s.minY - gap - size.height, width: size.width, height: size.height)
        if below.minY >= area.minY { return fit(below) }
        let left = CGRect(x: s.minX - gap - size.width, y: s.midY - size.height / 2, width: size.width, height: size.height)
        if left.minX >= area.minX { return fit(left) }
        let right = CGRect(x: s.maxX + gap, y: s.midY - size.height / 2, width: size.width, height: size.height)
        if right.maxX <= area.maxX { return fit(right) }
        let above = CGRect(x: s.midX - size.width / 2, y: s.maxY + gap, width: size.width, height: size.height)
        if above.maxY <= area.maxY { return fit(above) }
        return fit(centre)
    }
}
