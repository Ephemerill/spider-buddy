import AppKit

// MARK: - What goes on a page

/// One line of a panel page. Everything reads its value through a closure,
/// so the panel can be brought back in step with the spider at any time
/// (see `PanelController.refresh`).
enum PanelRow {
    /// A setting that is on or off, with a switch. `help` shows on hover.
    case toggle(String, help: String?, get: () -> Bool, set: (Bool) -> Void, enabled: () -> Bool)
    case slider(String, low: String, high: String, get: () -> CGFloat, set: (CGFloat) -> Void, enabled: () -> Bool)
    case choice(options: [String], get: () -> Int, set: (Int) -> Void)
    /// Buttons, two to a row.
    case buttons([PanelButton])
    /// Small grey words, which may change (how many visitors are about).
    case status(() -> String)

    static func toggle(_ title: String, help: String? = nil, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> PanelRow {
        .toggle(title, help: help, get: get, set: set, enabled: { true })
    }
    static func slider(_ title: String, low: String, high: String, get: @escaping () -> CGFloat, set: @escaping (CGFloat) -> Void) -> PanelRow {
        .slider(title, low: low, high: high, get: get, set: set, enabled: { true })
    }
    static func note(_ text: String) -> PanelRow { .status { text } }
}

struct PanelButton {
    var title: () -> String
    var symbol: () -> String
    var action: () -> Void
    var enabled: () -> Bool = { true }
    var shown: () -> Bool = { true }

    init(_ title: String, symbol: String, enabled: @escaping () -> Bool = { true }, shown: @escaping () -> Bool = { true },
         action: @escaping () -> Void) {
        self.init(title: { title }, symbol: { symbol }, enabled: enabled, shown: shown, action: action)
    }
    init(title: @escaping () -> String, symbol: @escaping () -> String, enabled: @escaping () -> Bool = { true },
         shown: @escaping () -> Bool = { true }, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
        self.enabled = enabled
        self.shown = shown
    }
}

/// A card of rows, under a small heading.
struct PanelSection {
    var title: String?
    var rows: [PanelRow]
}

struct PanelPage {
    var title: String
    var symbol: String
    var sections: [PanelSection]
}

// MARK: - The panel

/// What drops down from the menu bar icon: the spider up top, a strip of
/// icons for the pages, the page itself in rounded cards, and the Studio
/// and Quit along the bottom.
final class PanelController: NSObject, NSPopoverDelegate {
    static let width: CGFloat = 340
    private static let inset: CGFloat = 14
    private var inner: CGFloat { PanelController.width - PanelController.inset * 2 }

    let popover = NSPopover()
    private let pages: [PanelPage]
    private let design: () -> SpiderDesign
    private let footer: [PanelButton]
    private var shownDesign: SpiderDesign?
    private var current = 0

    private let root = NSStackView()
    private let portrait = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var tabButtons: [NSButton] = []
    private let pageTitle = NSTextField(labelWithString: "")
    private var pageViews: [NSView] = []
    /// Controls that mirror the settings, re-read on every refresh — one
    /// list per page, plus the footer.
    private var syncers: [[() -> Void]] = []
    private var footerSyncers: [() -> Void] = []
    private var actions: [ObjectIdentifier: (NSControl) -> Void] = [:]

    init(pages: [PanelPage], footer: [PanelButton], design: @escaping () -> SpiderDesign) {
        self.pages = pages
        self.footer = footer
        self.design = design
        super.init()
        build()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let vc = NSViewController()
        vc.view = root
        popover.contentViewController = vc
    }

    var isShown: Bool { popover.isShown }

    func toggle(from button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            refresh()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func close() { popover.performClose(nil) }

    /// Back in step with the spider: every control on the page re-reads.
    func refresh() {
        let d = design()
        if d != shownDesign {
            shownDesign = d
            portrait.image = SpiderRenderer.thumbnail(look: d.look, side: 64, front: true)
            nameLabel.stringValue = d.name.isEmpty ? "Your Spider" : d.name
        }
        for s in syncers[current] { s() }
        for s in footerSyncers { s() }
        fit()
    }

    func show(page i: Int) {
        guard i >= 0, i < pages.count else { return }
        pageViews[current].isHidden = true
        current = i
        pageViews[i].isHidden = false
        pageTitle.stringValue = pages[i].title.uppercased()
        for (j, b) in tabButtons.enumerated() { (b as? PanelTabButton)?.selected = j == i }
        refresh()
    }

    /// Tools only: a page of the panel to a PNG, drawn in an ordinary
    /// window (a popover's contents do not draw into a bitmap). Takes the
    /// panel's view out of the popover for good, so it is the last use.
    func snapshot(to path: String, page: Int, dark: Bool) {
        if popover.isShown { popover.close() }
        let host = NSView()
        host.wantsLayer = true
        host.layer?.backgroundColor = (dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.96, alpha: 1)).cgColor
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        root.removeFromSuperview()
        host.addSubview(root)
        show(page: page)
        root.layoutSubtreeIfNeeded()
        let size = CGSize(width: PanelController.width, height: root.fittingSize.height)
        host.frame = CGRect(origin: .zero, size: size)
        root.frame = host.bounds
        let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.contentView = host
        w.appearance = host.appearance
        host.layoutSubtreeIfNeeded()
        host.display()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func fit() {
        root.layoutSubtreeIfNeeded()
        let size = CGSize(width: PanelController.width, height: root.fittingSize.height)
        if popover.contentSize != size { popover.contentSize = size }
    }

    // MARK: Building

    private func build() {
        root.orientation = .vertical
        root.alignment = .centerX
        root.spacing = 12
        let i = PanelController.inset
        root.edgeInsets = NSEdgeInsets(top: 14, left: i, bottom: i, right: i)
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: PanelController.width).isActive = true

        // The spider, and its name.
        portrait.imageScaling = .scaleProportionallyUpOrDown
        portrait.translatesAutoresizingMaskIntoConstraints = false
        portrait.widthAnchor.constraint(equalToConstant: 64).isActive = true
        portrait.heightAnchor.constraint(equalToConstant: 64).isActive = true
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        let head = NSStackView(views: [portrait, nameLabel])
        head.orientation = .vertical
        head.spacing = 2
        root.addArrangedSubview(head)

        // The strip of page icons.
        let strip = CardView()
        strip.radius = 12
        let icons = NSStackView()
        icons.spacing = 4
        icons.distribution = .fillEqually
        icons.translatesAutoresizingMaskIntoConstraints = false
        strip.addSubview(icons)
        NSLayoutConstraint.activate([
            icons.leadingAnchor.constraint(equalTo: strip.leadingAnchor, constant: 6),
            icons.trailingAnchor.constraint(equalTo: strip.trailingAnchor, constant: -6),
            icons.topAnchor.constraint(equalTo: strip.topAnchor, constant: 6),
            icons.bottomAnchor.constraint(equalTo: strip.bottomAnchor, constant: -6),
            strip.widthAnchor.constraint(equalToConstant: inner),
        ])
        for (n, page) in pages.enumerated() {
            let b = PanelTabButton(symbol: page.symbol, title: page.title)
            b.tag = n
            b.target = self
            b.action = #selector(tabPicked(_:))
            icons.addArrangedSubview(b)
            tabButtons.append(b)
        }
        root.addArrangedSubview(strip)

        // The page's name, small and in capitals, as in System Settings.
        pageTitle.font = .systemFont(ofSize: 11, weight: .semibold)
        pageTitle.textColor = .secondaryLabelColor
        let titleRow = NSStackView(views: [pageTitle])
        titleRow.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.widthAnchor.constraint(equalToConstant: inner).isActive = true
        root.addArrangedSubview(titleRow)

        for page in pages {
            var pageSync: [() -> Void] = []
            let v = NSStackView()
            v.orientation = .vertical
            v.alignment = .leading
            v.spacing = 10
            for section in page.sections {
                v.addArrangedSubview(card(section, syncers: &pageSync))
            }
            v.isHidden = true
            root.addArrangedSubview(v)
            pageViews.append(v)
            syncers.append(pageSync)
        }

        // Along the bottom, on every page.
        let foot = NSStackView()
        foot.spacing = 10
        foot.distribution = .fillEqually
        foot.translatesAutoresizingMaskIntoConstraints = false
        foot.widthAnchor.constraint(equalToConstant: inner).isActive = true
        for spec in footer { foot.addArrangedSubview(button(spec, height: 34, syncers: &footerSyncers)) }
        root.addArrangedSubview(foot)

        pageViews[0].isHidden = false
        pageTitle.stringValue = pages.first?.title.uppercased() ?? ""
        (tabButtons.first as? PanelTabButton)?.selected = true
    }

    @objc private func tabPicked(_ b: NSButton) { show(page: b.tag) }

    /// Wires a control to a closure; after it runs, everything re-reads.
    private func wire(_ c: NSControl, _ f: @escaping (NSControl) -> Void) {
        c.target = self
        c.action = #selector(controlChanged(_:))
        actions[ObjectIdentifier(c)] = f
    }

    @objc private func controlChanged(_ c: NSControl) {
        actions[ObjectIdentifier(c)]?(c)
        refresh()
    }

    private func card(_ section: PanelSection, syncers: inout [() -> Void]) -> NSView {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 6
        if let t = section.title {
            let l = NSTextField(labelWithString: t)
            l.font = .systemFont(ofSize: 12, weight: .semibold)
            l.textColor = .secondaryLabelColor
            let row = NSStackView(views: [l])
            row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
            outer.addArrangedSubview(row)
        }
        let c = CardView()
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(rows)
        let pad: CGFloat = 12
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: pad),
            rows.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -pad),
            rows.topAnchor.constraint(equalTo: c.topAnchor, constant: pad),
            rows.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -pad),
            c.widthAnchor.constraint(equalToConstant: inner),
        ])
        let w = inner - pad * 2
        for row in section.rows { rows.addArrangedSubview(view(for: row, width: w, syncers: &syncers)) }
        outer.addArrangedSubview(c)
        return outer
    }

    private func view(for row: PanelRow, width w: CGFloat, syncers: inout [() -> Void]) -> NSView {
        switch row {
        case .toggle(let title, let help, let get, let set, let enabled):
            let l = NSTextField(labelWithString: title)
            l.font = .systemFont(ofSize: 13)
            let sw = NSSwitch()
            sw.controlSize = .small
            wire(sw) { set(($0 as? NSSwitch)?.state == .on) }
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let r = NSStackView(views: [l, spacer, sw])
            r.translatesAutoresizingMaskIntoConstraints = false
            r.widthAnchor.constraint(equalToConstant: w).isActive = true
            r.toolTip = help
            l.toolTip = help
            syncers.append { [weak sw, weak l] in
                sw?.state = get() ? .on : .off
                sw?.isEnabled = enabled()
                l?.textColor = enabled() ? .labelColor : .disabledControlTextColor
            }
            return r

        case .slider(let title, let low, let high, let get, let set, let enabled):
            let t = NSTextField(labelWithString: title)
            t.font = .systemFont(ofSize: 13)
            let lo = NSTextField(labelWithString: low)
            let hi = NSTextField(labelWithString: high)
            for x in [lo, hi] {
                x.font = .systemFont(ofSize: 11)
                x.textColor = .secondaryLabelColor
            }
            let s = NSSlider(value: Double(get()), minValue: 0, maxValue: 1, target: nil, action: nil)
            s.controlSize = .small
            s.isContinuous = true
            s.setContentHuggingPriority(.defaultLow, for: .horizontal)
            wire(s) { set(CGFloat(($0 as? NSSlider)?.doubleValue ?? 0)) }
            let line = NSStackView(views: [lo, s, hi])
            line.spacing = 8
            line.translatesAutoresizingMaskIntoConstraints = false
            line.widthAnchor.constraint(equalToConstant: w).isActive = true
            let col = NSStackView(views: [t, line])
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 3
            syncers.append { [weak s, weak t] in
                guard let s, let t else { return }
                if abs(s.doubleValue - Double(get())) > 0.001 { s.doubleValue = Double(get()) }
                s.isEnabled = enabled()
                t.textColor = enabled() ? .labelColor : .disabledControlTextColor
            }
            return col

        case .choice(let options, let get, let set):
            let seg = NSSegmentedControl(labels: options, trackingMode: .selectOne, target: nil, action: nil)
            seg.segmentDistribution = .fillEqually
            seg.controlSize = .small
            seg.font = .systemFont(ofSize: 11)
            seg.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            seg.translatesAutoresizingMaskIntoConstraints = false
            seg.widthAnchor.constraint(equalToConstant: w).isActive = true
            wire(seg) { set(($0 as? NSSegmentedControl)?.selectedSegment ?? 0) }
            syncers.append { [weak seg] in seg?.selectedSegment = get() }
            return seg

        case .buttons(let specs):
            // Two to a row, of whichever are showing: laid out afresh when
            // that changes, so a lone one keeps to half the width like the
            // rest.
            let col = NSStackView()
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 8
            let buttons = specs.map { button($0, height: 30, syncers: &syncers) }
            var laidOut: [Bool]?
            syncers.append { [weak col] in
                guard let col else { return }
                let shown = specs.map { $0.shown() }
                guard shown != laidOut else { return }
                laidOut = shown
                for v in col.arrangedSubviews { col.removeArrangedSubview(v); v.removeFromSuperview() }
                let showing = zip(buttons, shown).filter(\.1).map(\.0)
                col.isHidden = showing.isEmpty
                var i = 0
                while i < showing.count {
                    let r = NSStackView()
                    r.spacing = 8
                    r.distribution = .fillEqually
                    r.translatesAutoresizingMaskIntoConstraints = false
                    r.widthAnchor.constraint(equalToConstant: w).isActive = true
                    for b in showing[i..<min(i + 2, showing.count)] { r.addArrangedSubview(b) }
                    if i + 1 >= showing.count { r.addArrangedSubview(NSView()) }
                    col.addArrangedSubview(r)
                    i += 2
                }
            }
            return col

        case .status(let text):
            let n = NSTextField(wrappingLabelWithString: text())
            n.font = .systemFont(ofSize: 11)
            n.textColor = .secondaryLabelColor
            n.translatesAutoresizingMaskIntoConstraints = false
            n.widthAnchor.constraint(equalToConstant: w).isActive = true
            syncers.append { [weak n] in
                let s = text()
                if n?.stringValue != s { n?.stringValue = s }
            }
            return n
        }
    }

    private func button(_ spec: PanelButton, height: CGFloat, syncers: inout [() -> Void]) -> NSView {
        let b = PanelActionButton()
        b.translatesAutoresizingMaskIntoConstraints = false
        b.heightAnchor.constraint(equalToConstant: height).isActive = true
        wire(b) { _ in spec.action() }
        syncers.append { [weak b] in
            guard let b else { return }
            b.set(title: spec.title(), symbol: spec.symbol())
            b.isEnabled = spec.enabled()
        }
        b.set(title: spec.title(), symbol: spec.symbol())
        return b
    }
}

// MARK: - Pieces

/// A soft rounded panel behind a group of rows, a shade off the popover.
final class CardView: NSView {
    var radius: CGFloat = 12
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// An icon in the page strip: tinted and on a soft accent tile when its
/// page is showing.
final class PanelTabButton: NSButton {
    var selected = false { didSet { needsDisplay = true; contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor } }

    init(symbol: String, title: String) {
        super.init(frame: .zero)
        isBordered = false
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        imagePosition = .imageOnly
        toolTip = title
        contentTintColor = .secondaryLabelColor
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor.controlAccentColor.withAlphaComponent(0.2).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 9, yRadius: 9).fill()
        }
        super.draw(dirtyRect)
    }
}

/// A wide soft button with an icon before its title, like the Settings
/// and Quit buttons of a menu bar app.
final class PanelActionButton: NSButton {
    private var shownTitle = ""
    private var shownSymbol = ""
    private var pressed = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        isBordered = false
        imagePosition = .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: 12.5, weight: .medium)
        contentTintColor = .labelColor
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(title t: String, symbol s: String) {
        if t != shownTitle { shownTitle = t; title = " " + t }
        if s != shownSymbol {
            shownSymbol = s
            image = NSImage(systemSymbolName: s, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        }
    }

    override var isEnabled: Bool { didSet { needsDisplay = true; alphaValue = isEnabled ? 1 : 0.45 } }

    override func mouseDown(with event: NSEvent) {
        pressed = true
        super.mouseDown(with: event)
        pressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        NSColor.labelColor.withAlphaComponent(pressed ? 0.16 : 0.08).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.1).setStroke()
        path.stroke()
        super.draw(dirtyRect)
    }
}
