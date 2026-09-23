import AppKit
import QuartzCore

// MARK: - Welcome

/// The first thing anyone sees: three pages in one window. A hello, with
/// the spider sitting still on the left and only its eyes following the
/// pointer; where it lives (the menu bar icon, and what its menu does);
/// and then the Studio, to make it their own before it comes out. Done in
/// the Studio, and it lets itself down into the desktop from its icon.
final class OnboardingController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let pages = NSView()
    private var page = 0
    private let dots = PageDots()
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let skipButton = NSButton(title: "Skip", target: nil, action: nil)
    private var sitter: SittingSpiderView!
    private let design: SpiderDesign
    private let menu: NSMenu
    private var finished = false

    /// Page two's "Open the Menu": the real menu, from the real icon.
    var onOpenMenu: (() -> Void)?
    /// On to the Studio: handed the window's frame, so the Studio can open
    /// exactly where this one is and take its place.
    var onStudio: ((NSRect) -> Void)?
    /// Closed or skipped before the Studio: the spider comes out anyway.
    var onSkip: (() -> Void)?

    /// Same size as the Studio, so the last step is one window becoming
    /// the other rather than a jump.
    static let size = NSSize(width: 920, height: 600)

    init(design: SpiderDesign, menu: NSMenu) {
        self.design = design
        self.menu = menu
        window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingController.size),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Welcome"
        build()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        sitter.start()
    }

    func windowWillClose(_ notification: Notification) {
        sitter.stop()
        if !finished { finished = true; onSkip?() }
    }

    // MARK: Layout

    private func build() {
        let root = NSVisualEffectView()
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        pages.wantsLayer = true
        pages.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(pages)

        nextButton.target = self
        nextButton.action = #selector(next)
        nextButton.bezelStyle = .rounded
        nextButton.controlSize = .large
        nextButton.keyEquivalent = "\r"
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(nextButton)

        skipButton.target = self
        skipButton.action = #selector(skip)
        skipButton.isBordered = false
        skipButton.contentTintColor = .secondaryLabelColor
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(skipButton)

        dots.count = 3
        dots.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(dots)

        NSLayoutConstraint.activate([
            pages.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pages.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            pages.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            pages.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -16),
            nextButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            nextButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -26),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
            skipButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            skipButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            dots.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            dots.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            dots.widthAnchor.constraint(equalToConstant: 60),
            dots.heightAnchor.constraint(equalToConstant: 10),
        ])
        show(page: 0, animated: false)
    }

    private func welcomePage() -> NSView {
        let v = NSView()
        sitter = SittingSpiderView(look: design.look)
        sitter.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(sitter)

        let name = design.name.isEmpty ? "your spider" : design.name
        let title = label("Say hello to \(name).", size: 34, weight: .bold)
        let body = label("""
            A little jumping spider is moving onto your screen. It walks along the edges of your \
            windows, leaps between them, swings on silk, naps in a hammock it spins itself, and \
            keeps an eye on you the whole time.

            You can pick it up and throw it, stroke it with the pointer, feed it, or just let it \
            get on with its day.
            """, size: 15, weight: .regular, colour: .secondaryLabelColor)
        let text = stack([title, body], spacing: 18)
        v.addSubview(text)

        NSLayoutConstraint.activate([
            sitter.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 30),
            sitter.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            sitter.widthAnchor.constraint(equalToConstant: 400),
            sitter.heightAnchor.constraint(equalToConstant: 420),
            text.leadingAnchor.constraint(equalTo: sitter.trailingAnchor, constant: 24),
            text.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -56),
            text.centerYAnchor.constraint(equalTo: v.centerYAnchor, constant: -10),
        ])
        return v
    }

    private func menuPage() -> NSView {
        let v = NSView()
        let picture = MenuBarPicture(menu: menu)
        picture.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(picture)

        let title = label("It lives in your menu bar.", size: 30, weight: .bold)
        let intro = label("""
            Up at the top of your screen, next to the clock, there is a little spider. \
            Click it for everything your spider can do.
            """, size: 14, weight: .regular, colour: .secondaryLabelColor)
        let rows = stack([
            bullet("Spider Studio", "Change how it looks, how it walks, and who it is."),
            bullet("Behavior", "Ask it to say hi, swing, play peek-a-boo — or feed it a cricket."),
            bullet("Hide and Pause", "Put it away for a while. It waits for you."),
            bullet("Right-click the spider", "The same menu, right where it is."),
        ], spacing: 12)
        let open = NSButton(title: "Open the Menu", target: self, action: #selector(openMenu))
        open.bezelStyle = .rounded
        let text = stack([title, intro, rows, open], spacing: 16)
        v.addSubview(text)

        NSLayoutConstraint.activate([
            picture.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 40),
            picture.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            picture.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            picture.widthAnchor.constraint(equalToConstant: 360),
            text.leadingAnchor.constraint(equalTo: picture.trailingAnchor, constant: 36),
            text.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -48),
            text.centerYAnchor.constraint(equalTo: v.centerYAnchor),
        ])
        return v
    }

    // MARK: Paging

    private lazy var built: [NSView] = [welcomePage(), menuPage()]

    private func show(page i: Int, animated: Bool) {
        page = i
        let incoming = built[i]
        if animated {
            let t = CATransition()
            t.type = .push
            t.subtype = .fromRight
            t.duration = 0.35
            t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pages.layer?.add(t, forKey: "page")
        }
        pages.subviews.forEach { $0.removeFromSuperview() }
        incoming.translatesAutoresizingMaskIntoConstraints = false
        pages.addSubview(incoming)
        NSLayoutConstraint.activate([
            incoming.leadingAnchor.constraint(equalTo: pages.leadingAnchor),
            incoming.trailingAnchor.constraint(equalTo: pages.trailingAnchor),
            incoming.topAnchor.constraint(equalTo: pages.topAnchor),
            incoming.bottomAnchor.constraint(equalTo: pages.bottomAnchor),
        ])
        dots.current = i
        nextButton.title = i == 0 ? "Next" : "Design Your Spider"
    }

    @objc private func next() {
        if page == 0 { show(page: 1, animated: true); return }
        // On to the Studio: this window fades as the Studio opens in its
        // place, and the rest happens there.
        finished = true
        sitter.stop()
        let frame = window.frame
        onStudio?(frame)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.window.orderOut(nil)
            self?.window.alphaValue = 1
        })
    }

    @objc private func skip() {
        finished = true
        sitter.stop()
        window.orderOut(nil)
        onSkip?()
    }

    @objc private func openMenu() { onOpenMenu?() }

    /// Tools only: a picture of the window as it stands, and a turn of the page.
    func debugSnapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    func debugNextPage() { if page == 0 { show(page: 1, animated: false) } }
    func debugAdvance() { next() }

    // MARK: Bits

    private func label(_ s: String, size: CGFloat, weight: NSFont.Weight, colour: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(wrappingLabelWithString: s)
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = colour
        l.lineBreakMode = .byWordWrapping
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    private func bullet(_ head: String, _ text: String) -> NSView {
        let h = label(head, size: 14, weight: .semibold)
        let t = label(text, size: 13, weight: .regular, colour: .secondaryLabelColor)
        return stack([h, t], spacing: 2)
    }

    private func stack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = spacing
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }
}

// MARK: - The spider sitting still

/// The welcome page's spider: sitting on a little ledge, three-quarters
/// round toward you, doing nothing at all but watching the pointer —
/// wherever it is on the screen — and blinking now and then.
final class SittingSpiderView: NSView {
    private let look: SpiderLook
    private var timer: Timer?
    private var gaze = V2.zero
    private var gazeVel = V2.zero
    private var blinkIn: CGFloat = 2
    private var blinkT: CGFloat = -1
    private var time: CGFloat = 0
    private let scale: CGFloat = 3.1

    init(look: SpiderLook) {
        self.look = look
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Where the body sits in the view, and the head within that.
    private var bodyOrigin: V2 { V2(bounds.midX + 10, bounds.midY - 30) }

    private func tick() {
        let dt: CGFloat = 1.0 / 60.0
        time += dt
        // The pointer, wherever it is on the screen, in this view's terms.
        var target = V2.zero
        if let w = window {
            let screenPt = NSEvent.mouseLocation
            let inWindow = w.convertPoint(fromScreen: screenPt)
            let p = V2(convert(inWindow, from: nil))
            let head = bodyOrigin + V2(SpiderRenderer.head.c.x * 0.4, SpiderRenderer.head.c.y) * scale
            let d = p - head
            // Full gaze once the pointer is a little way off; softer close in.
            target = d.normalized * clamp(d.length / 160, 0, 1)
        }
        // A quick, slightly springy eye movement.
        gazeVel += ((target - gaze) * 220 - gazeVel * 22) * dt
        gaze += gazeVel * dt
        if blinkT >= 0 {
            blinkT += dt
            if blinkT > 0.19 { blinkT = -1; blinkIn = CGFloat.random(in: 1.8...5.5) }
        } else {
            blinkIn -= dt
            if blinkIn <= 0 { blinkT = 0 }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let o = bodyOrigin
        // A soft ledge to sit on.
        let ledgeY = o.y + SpiderRenderer.ground * scale
        let ledge = CGRect(x: o.x - 150, y: ledgeY - 16, width: 300, height: 16)
        ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.07).cgColor)
        ctx.addPath(CGPath(roundedRect: ledge, cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.fillPath()

        var pose = SpiderRenderer.restPose(look: look, yaw: 0.45, scale: scale)
        pose.pos = o
        pose.look = gaze.clampedLength(1)
        pose.blink = blinkT >= 0 ? sin(blinkT / 0.19 * .pi) : 0
        pose.time = time
        pose.grounded = 1
        // A camouflaged coat takes on the window behind it.
        if let bg = NSColor.windowBackgroundColor.usingColorSpace(.deviceRGB) {
            pose.surroundings = RGB(bg.redComponent, bg.greenComponent, bg.blueComponent)
        }
        let r = SpiderRenderer.spriteSide(for: scale)
        SpiderRenderer.draw(pose, in: ctx, bounds: CGRect(x: o.x - r / 2, y: o.y - r / 2, width: r, height: r))
    }
}

// MARK: - The menu, pictured

/// A strip of menu bar with the spider's icon lit, and its real menu
/// hanging from it — drawn from the menu itself, so it is never out of date.
final class MenuBarPicture: NSView {
    private let shownMenu: NSMenu

    init(menu: NSMenu) {
        self.shownMenu = menu
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let barH: CGFloat = 26
        // The bar.
        let bar = CGRect(x: 0, y: 0, width: bounds.width, height: barH)
        ctx.setFillColor((dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.93, alpha: 1)).cgColor)
        ctx.addPath(CGPath(roundedRect: bar, cornerWidth: 7, cornerHeight: 7, transform: nil))
        ctx.fillPath()
        // Some other things that live up there, for scale.
        let fg = NSColor.labelColor
        let clock = NSAttributedString(string: "Tue 9:41", attributes: [.font: NSFont.menuBarFont(ofSize: 12), .foregroundColor: fg])
        clock.draw(at: CGPoint(x: bounds.width - clock.size().width - 12, y: 5))
        for (i, name) in ["wifi", "battery.75", "magnifyingglass"].enumerated() {
            if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
                let r = CGRect(x: bounds.width - clock.size().width - 40 - CGFloat(i) * 26, y: 6, width: 15, height: 14)
                img.isTemplate = true
                tint(img, fg).draw(in: r)
            }
        }
        // The spider's icon, lit, as it is when its menu is open.
        let iconX = bounds.width - clock.size().width - 40 - 3 * 26 - 12
        let lit = CGRect(x: iconX - 5, y: 3, width: 28, height: barH - 6)
        ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor)
        ctx.addPath(CGPath(roundedRect: lit, cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.fillPath()
        let icon = SpiderRenderer.statusItemImage(size: 17)
        tint(icon, .white).draw(in: CGRect(x: iconX, y: 4.5, width: 17, height: 17))

        // The menu hanging from it.
        let items = shownMenu.items
        let rowH: CGFloat = 19, sepH: CGFloat = 9
        let height = items.reduce(CGFloat(10)) { $0 + ($1.isSeparatorItem ? sepH : rowH) }
        let width: CGFloat = 250
        let menuRect = CGRect(x: max(6, min(iconX - 8, bounds.width - width - 6)), y: barH + 6, width: width, height: min(height, bounds.height - barH - 10))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 18, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        ctx.setFillColor((dark ? NSColor(white: 0.20, alpha: 0.98) : NSColor(white: 0.97, alpha: 0.98)).cgColor)
        ctx.addPath(CGPath(roundedRect: menuRect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.setStrokeColor(NSColor.separatorColor.cgColor)
        ctx.setLineWidth(0.5)
        ctx.addPath(CGPath(roundedRect: menuRect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.strokePath()

        ctx.saveGState()
        ctx.clip(to: menuRect)
        var y = menuRect.minY + 5
        let font = NSFont.menuFont(ofSize: 12.5)
        for item in items {
            if item.isSeparatorItem {
                ctx.setFillColor(NSColor.separatorColor.cgColor)
                ctx.fill(CGRect(x: menuRect.minX + 12, y: y + sepH / 2, width: width - 24, height: 1))
                y += sepH
                continue
            }
            let colour: NSColor = item.isEnabled ? .labelColor : .tertiaryLabelColor
            NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: colour])
                .draw(at: CGPoint(x: menuRect.minX + 24, y: y + 2))
            if item.state == .on {
                NSAttributedString(string: "✓", attributes: [.font: font, .foregroundColor: colour])
                    .draw(at: CGPoint(x: menuRect.minX + 9, y: y + 2))
            }
            if item.hasSubmenu {
                NSAttributedString(string: "›", attributes: [.font: NSFont.menuFont(ofSize: 15), .foregroundColor: NSColor.secondaryLabelColor])
                    .draw(at: CGPoint(x: menuRect.maxX - 20, y: y))
            } else if !item.keyEquivalent.isEmpty {
                let m = item.keyEquivalentModifierMask
                let key = (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "") + (m.contains(.shift) ? "⇧" : "")
                    + (m.contains(.command) ? "⌘" : "") + item.keyEquivalent.uppercased()
                let k = NSAttributedString(string: key, attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
                k.draw(at: CGPoint(x: menuRect.maxX - 14 - k.size().width, y: y + 2))
            }
            y += rowH
        }
        ctx.restoreGState()
    }

    private func tint(_ img: NSImage, _ colour: NSColor) -> NSImage {
        let out = NSImage(size: img.size)
        out.lockFocus()
        img.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        colour.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}

/// Three little dots: which page this is.
final class PageDots: NSView {
    var count = 3 { didSet { needsDisplay = true } }
    var current = 0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 7, gap: CGFloat = 10
        let total = CGFloat(count) * d + CGFloat(count - 1) * gap
        var x = bounds.midX - total / 2
        for i in 0..<count {
            let c: NSColor = i == current ? .controlAccentColor : NSColor.labelColor.withAlphaComponent(0.2)
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: bounds.midY - d / 2, width: d, height: d)).fill()
            x += d + gap
        }
    }
}
