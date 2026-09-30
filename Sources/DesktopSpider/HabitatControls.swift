import AppKit

// MARK: - Bits the habitat's panels share

/// Headings, notes and grids of tiles, the same in every panel.
enum PanelKit {
    static func sectionLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s.uppercased())
        l.font = .systemFont(ofSize: 10.5, weight: .semibold)
        l.textColor = NSColor(white: 1, alpha: 0.5)
        return l
    }

    static func note(_ s: String, width: CGFloat) -> NSTextField {
        let n = NSTextField(wrappingLabelWithString: s)
        n.font = .systemFont(ofSize: 11.5)
        n.textColor = NSColor(white: 1, alpha: 0.6)
        n.translatesAutoresizingMaskIntoConstraints = false
        n.widthAnchor.constraint(equalToConstant: width).isActive = true
        return n
    }

    /// Tiles in rows of `columns`.
    static func grid(_ tiles: [NSView], columns: Int, width: CGFloat, spacing: CGFloat = 8) -> NSView {
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = spacing
        let w = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var i = 0
        while i < tiles.count {
            let row = NSStackView()
            row.spacing = spacing
            for t in tiles[i..<min(i + columns, tiles.count)] {
                t.translatesAutoresizingMaskIntoConstraints = false
                t.widthAnchor.constraint(equalToConstant: w).isActive = true
                row.addArrangedSubview(t)
            }
            rows.addArrangedSubview(row)
            i += columns
        }
        return rows
    }

    /// A row of buttons sharing a width equally.
    static func row(_ views: [NSView], width: CGFloat) -> NSStackView {
        let r = NSStackView(views: views)
        r.distribution = .fillEqually
        r.spacing = 8
        r.translatesAutoresizingMaskIntoConstraints = false
        r.widthAnchor.constraint(equalToConstant: width).isActive = true
        return r
    }

    /// The tiles' pictures, painted off the main thread and put on each tile
    /// as it comes — the panel is there at once, and nothing waits on them.
    private static let painter = DispatchQueue(label: "habitat.thumbnails", qos: .userInitiated)

    /// `still`: whether the picture is still wanted when it is ready.
    static func paintLater(_ set: @escaping (NSImage) -> Void, still: @escaping () -> Bool = { true }, _ paint: @escaping () -> NSImage) {
        painter.async {
            let img = paint()
            DispatchQueue.main.async {
                guard still() else { return }
                set(img)
            }
        }
    }
}

// MARK: - The weather

/// Everything about the tank's weather, in one place: what it is doing and
/// changing it now, then what weather comes to it — and how often — for
/// good. Drops down from the Weather button.
final class WeatherPanel: NSView {
    weak var controller: HabitatController?
    static let width: CGFloat = 360
    private let pad: CGFloat = 16

    private let nowIcon = NSImageView()
    private let nowTitle = NSTextField(labelWithString: "")
    private let nowDetail = NSTextField(wrappingLabelWithString: "")
    private let bringButton = HabitatButton(title: "Bring Weather", symbol: "cloud.bolt.rain", menu: true)
    private let clearButton = HabitatButton(title: "Clear the Sky", symbol: "sun.max")
    private let mode = NSSegmentedControl(labels: ["Comes & Goes", "Always the Same", "Like Outside"], trackingMode: .selectOne, target: nil, action: nil)
    private var tiles: [(kind: WeatherKind, tile: TileButton)] = []
    private var tileGrid = NSView()
    private var tilesBiome: Biome?
    private var listNote = NSTextField(wrappingLabelWithString: "")
    private let resetButton = HabitatButton(title: "Back to Its Own", symbol: "arrow.counterclockwise")
    private let paceSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let amountSlider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private var paceRow = NSView(), amountRow = NSView()
    private var outsideNote = NSTextField(wrappingLabelWithString: "")
    private let outsideButton = HabitatButton(title: "Look Up the Weather Outside", symbol: "location")

    override var isFlipped: Bool { true }

    init(controller: HabitatController) {
        self.controller = controller
        super.init(frame: CGRect(x: 0, y: 0, width: WeatherPanel.width, height: 400))
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        let inner = WeatherPanel.width - pad * 2

        // What it is doing now.
        nowIcon.translatesAutoresizingMaskIntoConstraints = false
        nowIcon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        nowIcon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        nowIcon.contentTintColor = .white
        nowTitle.font = .systemFont(ofSize: 15, weight: .bold)
        nowTitle.textColor = .white
        nowDetail.font = .systemFont(ofSize: 11.5)
        nowDetail.textColor = NSColor(white: 1, alpha: 0.6)
        nowDetail.translatesAutoresizingMaskIntoConstraints = false
        nowDetail.widthAnchor.constraint(equalToConstant: inner - 46).isActive = true
        let words = NSStackView(views: [nowTitle, nowDetail])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 1
        let now = NSStackView(views: [nowIcon, words])
        now.spacing = 10
        now.alignment = .centerY

        bringButton.target = self
        bringButton.action = #selector(showBringMenu)
        bringButton.toolTip = "Have some weather come in right now"
        clearButton.target = controller
        clearButton.action = #selector(HabitatController.weatherClear)
        clearButton.toolTip = "Clear the weather away, for now"
        let nowButtons = PanelKit.row([bringButton, clearButton], width: inner)

        // What comes, for good.
        mode.segmentDistribution = .fillEqually
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.font = .systemFont(ofSize: 12)
        mode.translatesAutoresizingMaskIntoConstraints = false
        mode.widthAnchor.constraint(equalToConstant: inner).isActive = true
        mode.setToolTip("Weather rolls in now and then, and clears again", forSegment: 0)
        mode.setToolTip("Keep one kind of weather for good", forSegment: 1)
        mode.setToolTip("The weather where you are", forSegment: 2)

        listNote = PanelKit.note("", width: inner)
        // Clear skies go last: they only show while keeping one kind.
        let kinds = WeatherKind.allCases.filter { $0 != .clear } + [.clear]
        let columns = 4
        let tileW = (inner - 8 * CGFloat(columns - 1)) / CGFloat(columns)
        let thumb = CGSize(width: tileW - 10, height: ((tileW - 10) * HabitatLayout.aspect).rounded())
        tiles = kinds.map { k in
            let t = TileButton(image: NSImage(size: thumb), title: k.label, subtitle: nil, imageSize: thumb, titleSize: 10)
            t.onClick = { [weak self] in self?.tileClicked(k) }
            t.toolTip = k.blurb
            return (k, t)
        }
        tileGrid = PanelKit.grid(tiles.map { $0.tile }, columns: columns, width: inner)

        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        resetButton.toolTip = "Only the weather that comes to this scenery by itself"

        func sliderRow(_ title: String, low: String, high: String, _ s: NSSlider, action: Selector) -> NSView {
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 12)
            label.textColor = NSColor(white: 1, alpha: 0.78)
            s.controlSize = .small
            s.isContinuous = true
            s.target = self
            s.action = action
            s.translatesAutoresizingMaskIntoConstraints = false
            s.widthAnchor.constraint(equalToConstant: inner).isActive = true
            func caption(_ t: String) -> NSTextField {
                let c = NSTextField(labelWithString: t)
                c.font = .systemFont(ofSize: 10)
                c.textColor = NSColor(white: 1, alpha: 0.45)
                return c
            }
            let gap = NSView()
            gap.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let ends = NSStackView(views: [caption(low), gap, caption(high)])
            ends.translatesAutoresizingMaskIntoConstraints = false
            ends.widthAnchor.constraint(equalToConstant: inner).isActive = true
            let col = NSStackView(views: [label, s, ends])
            col.orientation = .vertical
            col.alignment = .leading
            col.spacing = 3
            return col
        }
        paceRow = sliderRow("How Often It Changes", low: "Slowly", high: "Often", paceSlider, action: #selector(paceChanged))
        amountRow = sliderRow("How Much Weather", low: "Now and then", high: "Most of the time", amountSlider, action: #selector(amountChanged))

        outsideNote = PanelKit.note("", width: inner)
        outsideButton.target = self
        outsideButton.action = #selector(outsideTapped)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: inner).isActive = true

        let col = NSStackView(views: [now, nowButtons, divider, PanelKit.sectionLabel("What Weather Comes"), mode, listNote, tileGrid,
                                      resetButton, paceRow, amountRow, outsideNote, outsideButton])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 10
        col.setCustomSpacing(14, after: nowButtons)
        col.setCustomSpacing(14, after: divider)
        col.setCustomSpacing(6, after: col.arrangedSubviews[3])
        col.edgeInsets = NSEdgeInsets(top: pad, left: pad, bottom: pad, right: pad)
        col.translatesAutoresizingMaskIntoConstraints = false
        addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: topAnchor),
            col.leadingAnchor.constraint(equalTo: leadingAnchor),
            col.trailingAnchor.constraint(equalTo: trailingAnchor),
            col.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(equalToConstant: WeatherPanel.width),
        ])
        refresh()
    }

    /// Back in step with the tank's weather.
    func refresh() {
        guard let c = controller else { return }
        let s = c.weather.settings
        let b = c.scene.habitat.biome
        let k = c.weather.current
        mode.selectedSegment = s.mode == .changing ? 0 : (s.mode == .always ? 1 : 2)
        nowIcon.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: k.label)?
            .withSymbolConfiguration(.init(pointSize: 24, weight: .medium))
        nowTitle.stringValue = k == .clear ? "Clear Skies" : k.label
        nowDetail.stringValue = c.weather.summary()
        clearButton.isEnabled = k != .clear
        // The tiles show this scenery, with each kind of weather on it.
        if tilesBiome != b {
            tilesBiome = b
            for (k, t) in tiles {
                let size = t.imageSize
                PanelKit.paintLater({ [weak t] in t?.setImage($0) }, still: { [weak self] in self?.tilesBiome == b }) {
                    WeatherArt.thumbnail(k, biome: b, size: size)
                }
            }
        }
        let list = s.rotation(b)
        for (k, t) in tiles {
            switch s.mode {
            case .changing:
                t.isHidden = k == .clear
                t.selected = list.contains(k)
                t.alphaValue = list.contains(k) ? 1 : 0.45
                t.toolTip = list.contains(k) ? "\(k.blurb) — comes to the \(b.label). Click to take it out." : "\(k.blurb). Click to have it come to the \(b.label) too."
            case .always:
                t.isHidden = false
                t.selected = s.always == k
                t.alphaValue = 1
                t.toolTip = "\(k.blurb). Click to keep it that way."
            case .outside:
                t.isHidden = true
            }
        }
        let changing = s.mode == .changing
        tileGrid.isHidden = s.mode == .outside
        listNote.isHidden = s.mode == .outside
        listNote.stringValue = changing
            ? "Lit up: comes to the \(b.label) now and then, with clear skies in between. Click one to add it or take it out."
            : "Click one to keep it that way."
        resetButton.isHidden = !changing
        resetButton.isEnabled = s.isCustom(b)
        resetButton.set(title: "Back to the \(b.label)’s Own", symbol: "arrow.counterclockwise")
        paceRow.isHidden = !changing
        amountRow.isHidden = !changing
        if abs(paceSlider.doubleValue - Double(s.pace)) > 0.001 { paceSlider.doubleValue = Double(s.pace) }
        if abs(amountSlider.doubleValue - Double(s.amount)) > 0.001 { amountSlider.doubleValue = Double(s.amount) }
        let available = c.outsideAvailable()
        outsideNote.isHidden = s.mode != .outside
        outsideButton.isHidden = s.mode != .outside || available
        outsideNote.stringValue = available
            ? "The tank has the weather where you are — rain when it rains, snow when it snows. It’s looked up every twenty minutes, from Open-Meteo, going by roughly where your internet connection is. " + (c.outsideSummary() ?? "Looking it up…")
            : "To follow the weather where you are, the app looks it up every twenty minutes (from Open-Meteo, going by roughly where your internet connection is). That’s off at the moment."
        layoutSubtreeIfNeeded()
    }

    @objc private func showBringMenu() {
        guard let c = controller else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (i, k) in WeatherKind.allCases.enumerated() where k != .clear {
            let it = NSMenuItem(title: k.summon, action: #selector(HabitatController.weatherBroughtItem(_:)), keyEquivalent: "")
            it.target = c
            it.tag = i
            it.image = NSImage(systemSymbolName: k.symbol, accessibilityDescription: nil)
            menu.addItem(it)
        }
        if c.weather.settings.mode == .changing {
            menu.addItem(.separator())
            let other = NSMenuItem(title: "Something Else — Surprise Me", action: #selector(HabitatController.weatherChangeNow), keyEquivalent: "")
            other.target = c
            other.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)
            menu.addItem(other)
        }
        let below = bringButton.isFlipped ? bringButton.bounds.height + 4 : -4
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: below), in: bringButton)
    }

    @objc private func modeChanged() {
        guard let c = controller else { return }
        let m: WeatherSettings.Mode = mode.selectedSegment == 1 ? .always : (mode.selectedSegment == 2 ? .outside : .changing)
        if m == .outside {
            // (Only once it is allowed to look.)
            if c.outsideAvailable() { c.setWeatherMode(.outside) }
            else { c.weather.settings.mode = .outside; c.refreshWeatherPanel() }
        } else {
            c.setWeatherMode(m)
        }
    }

    private func tileClicked(_ k: WeatherKind) {
        guard let c = controller else { return }
        switch c.weather.settings.mode {
        case .changing: c.weather.settings.toggle(k, in: c.scene.habitat.biome)
        case .always, .outside: c.keepWeather(k)
        }
        c.refreshWeatherPanel()
    }

    @objc private func resetTapped() {
        guard let c = controller else { return }
        c.weather.settings.reset(c.scene.habitat.biome)
        c.refreshWeatherPanel()
    }

    @objc private func paceChanged() { controller?.weather.settings.pace = CGFloat(paceSlider.doubleValue) }
    @objc private func amountChanged() { controller?.weather.settings.amount = CGFloat(amountSlider.doubleValue) }
    @objc private func outsideTapped() { controller?.setWeatherMode(.outside) }
}

// MARK: - A saved habitat

/// One of My Habitats: its picture, its name and when it was saved, and a
/// ⋯ for the rest. A click puts it in the tank.
final class SavedHabitatCard: NSView {
    let saved: SavedHabitat
    var onLoad: (() -> Void)?
    var onMenu: ((NSView) -> Void)?
    /// It is what the tank has in it now.
    var current = false { didSet { needsDisplay = true; badge.isHidden = !current } }
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private let picture = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let when = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "In the tank")
    private let more = HabitatIconButton(symbol: "ellipsis", tip: "Rename, update, share or delete")
    private let thumb: CGSize

    init(_ s: SavedHabitat, width: CGFloat) {
        saved = s
        let tw = width - 12
        thumb = CGSize(width: tw, height: (tw * 0.3).rounded())
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: thumb.height + 50))
        wantsLayer = true
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.wantsLayer = true
        picture.layer?.cornerRadius = 6
        picture.layer?.masksToBounds = true
        name.stringValue = s.name
        name.font = .systemFont(ofSize: 12.5, weight: .semibold)
        name.textColor = .white
        name.lineBreakMode = .byTruncatingTail
        when.stringValue = "\(s.habitat.biome.label) · \(s.when)"
        when.font = .systemFont(ofSize: 10.5)
        when.textColor = NSColor(white: 1, alpha: 0.5)
        when.lineBreakMode = .byTruncatingTail
        badge.font = .systemFont(ofSize: 9.5, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.drawsBackground = true
        badge.backgroundColor = .controlAccentColor
        badge.layer?.cornerRadius = 4
        badge.isHidden = true
        more.target = self
        more.action = #selector(moreTapped)
        for v in [picture, name, when, badge, more] { addSubview(v) }
        more.translatesAutoresizingMaskIntoConstraints = true
        toolTip = "Put “\(s.name)” in the tank (you can undo it)"
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        let size = thumb
        let h = s.habitat
        PanelKit.paintLater({ [weak self] in self?.picture.image = $0 }) { HabitatArt.habitatThumbnail(h, size: size) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: thumb.height + 50) }

    override func layout() {
        super.layout()
        picture.frame = CGRect(x: 6, y: 6, width: thumb.width, height: thumb.height)
        let y = picture.frame.maxY + 6
        more.frame = CGRect(x: bounds.width - 6 - 28, y: y + 3, width: 28, height: 28)
        let textW = more.frame.minX - 10 - 8
        name.frame = CGRect(x: 10, y: y, width: textW, height: 17)
        when.frame = CGRect(x: 10, y: y + 18, width: textW, height: 14)
        let bw = (badge.attributedStringValue.size().width + 12).rounded()
        badge.frame = CGRect(x: picture.frame.maxX - bw - 6, y: picture.frame.minY + 6, width: bw, height: 16)
    }

    @objc private func moreTapped() { onMenu?(more) }

    // (A click anywhere but the ⋯ is on the card itself.)
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return more.frame.contains(convert(point, from: superview)) ? more : self
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onLoad?() }
    }
    override func rightMouseDown(with event: NSEvent) { onMenu?(more) }

    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        guard let l = layer else { return }
        l.cornerRadius = 10
        l.backgroundColor = NSColor(white: 1, alpha: pressed ? 0.16 : (hovering ? 0.11 : 0.05)).cgColor
        l.borderWidth = current ? 2 : 1
        l.borderColor = current ? NSColor.controlAccentColor.cgColor : NSColor(white: 1, alpha: 0.07).cgColor
    }
}
