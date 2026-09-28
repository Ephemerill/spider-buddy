import AppKit
import UniformTypeIdentifiers

// MARK: - What goes in a report

/// A screenshot or a video sent along with a report.
struct BugAttachment: Equatable {
    let url: URL
    let size: Int
    var name: String { url.lastPathComponent }
    private var type: UTType? { UTType(filenameExtension: url.pathExtension) }
    var isMovie: Bool { type?.conforms(to: .movie) ?? false }
    var mime: String { type?.preferredMIMEType ?? "application/octet-stream" }
}

struct BugReport {
    var name: String
    var description: String
    /// Nil when they'd rather not say.
    var system: [(String, String)]?
    var attachments: [BugAttachment]
}

enum BugReportError: LocalizedError {
    case notSetUp, offline, tooBig, rateLimited, refused(Int, String?), unreadable(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: return "Bug reports aren't set up in this copy of the app, so it couldn't be sent."
        case .offline: return "It couldn't be sent: you seem to be offline. Check your connection and try again."
        case .tooBig: return "The attachments were too big to send. Try fewer, or a shorter video."
        case .rateLimited: return "Lots of reports are coming in just now. Give it a minute and try again."
        case .unreadable(let name): return "“\(name)” couldn't be read. Was it moved or deleted? Remove it and try again."
        case .refused(let code, let why): return "It couldn't be sent (\(code)\(why.map { ": \($0)" } ?? "")). Try again in a little while."
        }
    }
}

// MARK: - Sending

/// Reports go to a Discord channel as a message with the words in an embed
/// and any files attached to it (more than fit in one message go on in
/// follow-ups).
///
/// They're sent just as Discord's webhooks take them, but to a Cloudflare
/// Worker (tools/report-worker) that holds the webhook, so its address never
/// ships in the app: the Worker checks each report over, turns away anyone
/// sending too many, and passes it on. build.sh puts the Worker's address in
/// Info.plist; `SPIDER_BUG_ENDPOINT` points it somewhere else for testing.
enum BugReporter {
    /// Discord takes 10 MB a message on a server that isn't boosted (and
    /// the Worker holds it to that).
    static let eachFileAtMost = 10_000_000
    static let mostFiles = 10

    static var endpoint: URL? {
        if let s = ProcessInfo.processInfo.environment["SPIDER_BUG_ENDPOINT"] { return URL(string: s) }
        guard let s = Bundle.main.object(forInfoDictionaryKey: "SpiderReportEndpoint") as? String else { return nil }
        return URL(string: s)
    }

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Spider Buddy"
    }

    static func send(_ report: BugReport) async throws {
        guard let base = endpoint, var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw BugReportError.notSetUp
        }
        // Wait for the message to be made, so a failure is heard about.
        parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "wait", value: "true")]
        guard let url = parts.url else { throw BugReportError.notSetUp }
        let batches = batched(report.attachments)
        for (i, files) in batches.enumerated() {
            var payload: [String: Any] = ["username": appName, "allowed_mentions": ["parse": [String]()]]
            if i == 0 {
                payload["embeds"] = [embed(report)]
            } else {
                payload["content"] = "More attachments for the report above (\(i + 1) of \(batches.count))."
            }
            try await post(payload, files: files, to: url)
        }
    }

    /// The files in as few messages as they fit in: always one, even with
    /// none.
    private static func batched(_ files: [BugAttachment]) -> [[BugAttachment]] {
        var out: [[BugAttachment]] = [[]]
        var bytes = 0
        for f in files {
            if out[out.count - 1].count == mostFiles || (!out[out.count - 1].isEmpty && bytes + f.size > eachFileAtMost) {
                out.append([])
                bytes = 0
            }
            out[out.count - 1].append(f)
            bytes += f.size
        }
        return out
    }

    private static func embed(_ r: BugReport) -> [String: Any] {
        let fields: [[String: Any]]
        if let system = r.system {
            fields = system.prefix(24).map { k, v in
                ["name": String(k.prefix(200)), "value": v.isEmpty ? "—" : String(v.prefix(1000)), "inline": true]
            }
        } else {
            fields = [["name": "System info", "value": "Not shared", "inline": false]]
        }
        let name = r.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "title": "🐞 Bug report",
            "description": String(r.description.prefix(BugReportController.mostCharacters)),
            "color": 0xD9822B,
            "author": ["name": name.isEmpty ? "Anonymous" : String(name.prefix(100))],
            "fields": fields,
            "footer": ["text": "\(appName) \(Updater.currentVersion)"],
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
    }

    private static func post(_ payload: [String: Any], files: [BugAttachment], to url: URL) async throws {
        let boundary = "spider-\(UUID().uuidString)"
        var body = Data()
        func part(_ headers: String, _ data: Data) {
            body.append(Data("--\(boundary)\r\n\(headers)\r\n\r\n".utf8))
            body.append(data)
            body.append(Data("\r\n".utf8))
        }
        part("Content-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json",
             try JSONSerialization.data(withJSONObject: payload))
        var used = Set<String>()
        for (i, f) in files.enumerated() {
            var name = safeName(f.name)
            if !used.insert(name).inserted { name = "\(i + 1)-\(name)"; used.insert(name) }
            guard let data = try? Data(contentsOf: f.url) else { throw BugReportError.unreadable(f.name) }
            part("Content-Disposition: form-data; name=\"files[\(i)]\"; filename=\"\(name)\"\r\nContent-Type: \(f.mime)", data)
        }
        body.append(Data("--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url, timeoutInterval: 180)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.upload(for: req, from: body)
        } catch let e as URLError where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                                         .cannotConnectToHost, .dnsLookupFailed, .timedOut].contains(e.code) {
            throw BugReportError.offline
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 200..<300: return
        case 413: throw BugReportError.tooBig
        case 429: throw BugReportError.rateLimited
        default:
            let said = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw BugReportError.refused(code, said?["message"] as? String)
        }
    }

    /// Plain letters for Discord, which is fussy about file names.
    private static func safeName(_ s: String) -> String {
        let ok = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let cleaned = String(s.unicodeScalars.map { ok.contains($0) && $0.isASCII ? Character($0) : "_" })
        return cleaned.isEmpty ? "file" : cleaned
    }
}

/// What it says about the Mac, when they're happy for it to.
enum SystemReport {
    static func lines(extra: [(String, String)]) -> [(String, String)] {
        let info = ProcessInfo.processInfo
        let v = info.operatingSystemVersion
        let build = sysctl("kern.osversion").map { " (\($0))" } ?? ""
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let screens = NSScreen.screens.map { s in
            "\(Int(s.frame.width))×\(Int(s.frame.height)) @\(Int(s.backingScaleFactor))x"
        }
        return [
            ("App", "\(BugReporter.appName) \(Updater.currentVersion)"),
            ("macOS", "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)\(build)"),
            ("Mac", sysctl("hw.model") ?? "Unknown"),
            ("Chip", sysctl("machdep.cpu.brand_string") ?? "Unknown"),
            ("Memory", "\(info.physicalMemory >> 30) GB"),
            ("Displays", screens.joined(separator: ", ")),
            ("Appearance", dark ? "Dark" : "Light"),
            ("Language", Locale.preferredLanguages.first ?? "Unknown"),
            ("Mac Low Power Mode", info.isLowPowerModeEnabled ? "On" : "Off"),
        ] + extra
    }

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

// MARK: - The window

/// Report a Bug, from the App page: an optional name, what went wrong, the
/// Mac's particulars (ticked, but theirs to untick, and to see before they
/// go), and any screenshots or videos. Looks like the welcome: soft cards
/// on the window's own material.
final class BugReportController: NSObject, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    static let width: CGFloat = 500
    static let mostCharacters = 4000
    private static let inset: CGFloat = 28

    let window: NSWindow
    /// Closed, however: the owner can let it go.
    var onClose: (() -> Void)?

    private let look: SpiderLook
    private let spiderName: String
    private let systemInfo: () -> [(String, String)]
    private var attachments: [BugAttachment] = []
    private var sending = false

    private let root = NSVisualEffectView()
    private let form = NSStackView()
    private let thanks = NSStackView()
    private let nameField = NSTextField()
    private let nameBox = FieldBox()
    private let textView = PlaceholderTextView()
    private let textBox = FieldBox()
    private let dropZone = DropZone()
    private let fileList = NSStackView()
    private let includeSystem = NSButton(checkboxWithTitle: "Include system info", target: nil, action: nil)
    private let peekButton = NSButton(title: "See what's sent", target: nil, action: nil)
    private let peekCard = CardView()
    private let peekText = NSTextField(wrappingLabelWithString: "")
    private let problem = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let sendButton = NSButton(title: "Send Report", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private var sitter: SittingSpiderView?
    private var focusWatch: NSKeyValueObservation?
    /// The window no shorter than the form: let go of for the thanks.
    private var formFloor: NSLayoutConstraint!

    private var inner: CGFloat { BugReportController.width - BugReportController.inset * 2 }

    init(look: SpiderLook, spiderName: String, systemInfo: @escaping () -> [(String, String)]) {
        self.look = look
        self.spiderName = spiderName
        self.systemInfo = systemInfo
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: BugReportController.width, height: 600),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Report a Bug"
        build()
        fit(animated: false)
        // The box being typed in lights up.
        focusWatch = window.observe(\.firstResponder, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async { self?.showFocus() }
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible {
            window.center()
            window.makeFirstResponder(nameField.stringValue.isEmpty ? nameField : textView)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        sitter?.stop()
        onClose?()
    }

    // MARK: Layout

    private func build() {
        root.material = .windowBackground
        root.blendingMode = .behindWindow
        root.state = .active
        window.contentView = root

        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 18
        let i = BugReportController.inset
        form.edgeInsets = NSEdgeInsets(top: 38, left: i, bottom: 22, right: i)
        form.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(form)
        // As tall as `fit` makes the window; never shorter than the form.
        let snug = root.bottomAnchor.constraint(equalTo: form.bottomAnchor)
        snug.priority = .init(1)
        formFloor = root.bottomAnchor.constraint(greaterThanOrEqualTo: form.bottomAnchor)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: root.topAnchor),
            form.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            form.widthAnchor.constraint(equalToConstant: BugReportController.width),
            formFloor,
            snug,
        ])

        form.addArrangedSubview(header())

        // Name.
        nameField.isBordered = false
        nameField.drawsBackground = false
        nameField.focusRingType = .none
        nameField.font = .systemFont(ofSize: 13)
        nameField.placeholderString = "Anonymous if left blank"
        nameField.stringValue = UserDefaults.standard.string(forKey: "bugReportName") ?? ""
        nameField.delegate = self
        nameField.cell?.isScrollable = true
        nameField.cell?.wraps = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameBox.addSubview(nameField)
        NSLayoutConstraint.activate([
            nameBox.widthAnchor.constraint(equalToConstant: inner),
            nameBox.heightAnchor.constraint(equalToConstant: 32),
            nameField.leadingAnchor.constraint(equalTo: nameBox.leadingAnchor, constant: 10),
            nameField.trailingAnchor.constraint(equalTo: nameBox.trailingAnchor, constant: -10),
            nameField.centerYAnchor.constraint(equalTo: nameBox.centerYAnchor),
        ])
        form.addArrangedSubview(field("Your name", optional: true, nameBox))

        // What happened.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.frame = NSRect(x: 0, y: 0, width: inner, height: 150)
        textView.minSize = NSSize(width: 0, height: 150)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 7, height: 8)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.placeholder = "What were you doing, what did you expect to happen, and what happened instead? The more detail, the better."
        textView.delegate = self
        textView.onSubmit = { [weak self] in self?.send() }
        scroll.documentView = textView
        textBox.addSubview(scroll)
        NSLayoutConstraint.activate([
            textBox.widthAnchor.constraint(equalToConstant: inner),
            textBox.heightAnchor.constraint(equalToConstant: 150),
            scroll.leadingAnchor.constraint(equalTo: textBox.leadingAnchor, constant: 1),
            scroll.trailingAnchor.constraint(equalTo: textBox.trailingAnchor, constant: -1),
            scroll.topAnchor.constraint(equalTo: textBox.topAnchor, constant: 1),
            scroll.bottomAnchor.constraint(equalTo: textBox.bottomAnchor, constant: -1),
        ])
        form.addArrangedSubview(field("What happened?", optional: false, textBox))

        // Screenshots and videos.
        dropZone.onChoose = { [weak self] in self?.chooseFiles() }
        dropZone.onDrop = { [weak self] urls in self?.attach(urls) }
        dropZone.widthAnchor.constraint(equalToConstant: inner).isActive = true
        fileList.orientation = .vertical
        fileList.alignment = .leading
        fileList.spacing = 6
        fileList.isHidden = true
        let files = NSStackView(views: [dropZone, fileList])
        files.orientation = .vertical
        files.alignment = .leading
        files.spacing = 8
        form.addArrangedSubview(field("Screenshots or videos", optional: true, files))

        // System info: ticked unless they'd rather not, and theirs to see.
        includeSystem.state = .on
        includeSystem.font = .systemFont(ofSize: 13)
        includeSystem.toolTip = "Your Mac's model, macOS version, displays and a few of the app's settings. Nothing personal."
        includeSystem.target = self
        includeSystem.action = #selector(systemToggled)
        peekButton.isBordered = false
        peekButton.font = .systemFont(ofSize: 12)
        peekButton.contentTintColor = .controlAccentColor
        peekButton.target = self
        peekButton.action = #selector(togglePeek)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let systemRow = NSStackView(views: [includeSystem, spacer, peekButton])
        systemRow.translatesAutoresizingMaskIntoConstraints = false
        systemRow.widthAnchor.constraint(equalToConstant: inner).isActive = true

        peekText.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        peekText.textColor = .secondaryLabelColor
        peekText.isSelectable = true
        peekText.preferredMaxLayoutWidth = inner - 24
        peekText.translatesAutoresizingMaskIntoConstraints = false
        peekCard.addSubview(peekText)
        NSLayoutConstraint.activate([
            peekCard.widthAnchor.constraint(equalToConstant: inner),
            peekText.leadingAnchor.constraint(equalTo: peekCard.leadingAnchor, constant: 12),
            peekText.trailingAnchor.constraint(equalTo: peekCard.trailingAnchor, constant: -12),
            peekText.topAnchor.constraint(equalTo: peekCard.topAnchor, constant: 10),
            peekText.bottomAnchor.constraint(equalTo: peekCard.bottomAnchor, constant: -10),
        ])
        peekCard.isHidden = true
        let system = NSStackView(views: [systemRow, peekCard])
        system.orientation = .vertical
        system.alignment = .leading
        system.spacing = 8
        form.addArrangedSubview(system)

        // Whatever went wrong sending it.
        problem.font = .systemFont(ofSize: 12)
        problem.textColor = .systemRed
        problem.preferredMaxLayoutWidth = inner
        problem.isHidden = true
        form.addArrangedSubview(problem)

        // Along the bottom.
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .large
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(send)
        sendButton.toolTip = "⌘↩ sends it from the description too"
        let hint = NSTextField(labelWithString: "Sent privately to the developer.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        let gap = NSView()
        gap.setContentHuggingPriority(.init(1), for: .horizontal)
        let buttons = NSStackView(views: [hint, gap, spinner, cancelButton, sendButton])
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.widthAnchor.constraint(equalToConstant: inner).isActive = true
        sendButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        form.setCustomSpacing(22, after: problem)
        form.setCustomSpacing(22, after: system)
        form.addArrangedSubview(buttons)

        buildThanks()
        refresh()
    }

    /// A tile with a ladybug on it, and what this is for.
    private func header() -> NSView {
        let tile = IconTile(symbol: "ladybug.fill")
        let title = NSTextField(labelWithString: "Report a Bug")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let sub = NSTextField(wrappingLabelWithString: "Something not right? Tell us what happened, and we'll squash it.")
        sub.font = .systemFont(ofSize: 13)
        sub.textColor = .secondaryLabelColor
        sub.preferredMaxLayoutWidth = inner - 58
        let words = NSStackView(views: [title, sub])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 3
        let row = NSStackView(views: [tile, words])
        row.spacing = 14
        row.alignment = .centerY
        return row
    }

    /// A little heading over a box, as the panel's sections have.
    private func field(_ title: String, optional: Bool, _ content: NSView) -> NSView {
        let heading = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.secondaryLabelColor])
        if optional {
            heading.append(NSAttributedString(string: "  Optional", attributes: [
                .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.tertiaryLabelColor]))
        }
        let l = NSTextField(labelWithAttributedString: heading)
        let row = NSStackView(views: [l])
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        let col = NSStackView(views: [row, content])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 6
        return col
    }

    private func buildThanks() {
        let spider = SittingSpiderView(look: look, scale: 1.5)
        spider.translatesAutoresizingMaskIntoConstraints = false
        spider.widthAnchor.constraint(equalToConstant: 220).isActive = true
        spider.heightAnchor.constraint(equalToConstant: 170).isActive = true
        sitter = spider
        let title = NSTextField(labelWithString: "Thanks — it's on its way.")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let body = NSTextField(wrappingLabelWithString:
            "Every report helps. \(spiderName) has been told there's a bug about, and is very keen to catch it.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.preferredMaxLayoutWidth = inner - 40
        let done = doneButton
        done.target = self
        done.action = #selector(cancel)
        done.bezelStyle = .rounded
        done.controlSize = .large
        done.keyEquivalent = "\r"
        done.widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true
        thanks.setViews([spider, title, body, done], in: .center)
        thanks.orientation = .vertical
        thanks.alignment = .centerX
        thanks.spacing = 10
        thanks.setCustomSpacing(22, after: body)
        thanks.isHidden = true
        thanks.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(thanks)
        NSLayoutConstraint.activate([
            thanks.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            thanks.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 4),
        ])
    }

    /// The window as tall as the form (or `height`), keeping its top where
    /// it is.
    private func fit(animated: Bool, height: CGFloat? = nil) {
        root.layoutSubtreeIfNeeded()
        let height = height ?? form.fittingSize.height
        let content = NSRect(x: 0, y: 0, width: BugReportController.width, height: height)
        let size = window.frameRect(forContentRect: content).size
        var f = window.frame
        guard abs(f.height - size.height) > 0.5 else { return }
        f.origin.y += f.height - size.height
        f.size = size
        window.setFrame(f, display: true, animate: animated && window.isVisible)
    }

    // MARK: Keeping it in step

    private func refresh() {
        let written = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = written && !sending
        sendButton.title = sending ? "Sending…" : "Send Report"
        nameField.isEnabled = !sending
        textView.isEditable = !sending
        dropZone.enabled = !sending && attachments.count < BugReporter.mostFiles
        includeSystem.isEnabled = !sending
        peekButton.isEnabled = includeSystem.state == .on
        peekButton.alphaValue = peekButton.isEnabled ? 1 : 0.4
        for case let row as FileRow in fileList.arrangedSubviews { row.removable = !sending }
    }

    private func showFocus() {
        let r = window.firstResponder
        nameBox.focused = (r as? NSText)?.delegate === nameField || r === nameField
        textBox.focused = r === textView
    }

    func controlTextDidChange(_ obj: Notification) {
        UserDefaults.standard.set(nameField.stringValue, forKey: "bugReportName")
    }

    func textDidChange(_ notification: Notification) { refresh() }

    /// Room for Discord's embed, and no more.
    func textView(_ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
        guard let text else { return true }
        return (textView.string as NSString).length - range.length + (text as NSString).length <= BugReportController.mostCharacters
    }

    @objc private func systemToggled() {
        if includeSystem.state == .off, !peekCard.isHidden { togglePeek() }
        refresh()
    }

    @objc private func togglePeek() {
        let showing = peekCard.isHidden
        if showing {
            let lines = systemInfo()
            let pad = (lines.map(\.0.count).max() ?? 0) + 2
            peekText.stringValue = lines.map { k, v in (k + ":").padding(toLength: pad, withPad: " ", startingAt: 0) + v }
                .joined(separator: "\n")
        }
        peekCard.isHidden = !showing
        peekButton.title = showing ? "Hide" : "See what's sent"
        fit(animated: true)
    }

    // MARK: Files

    private func chooseFiles() {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        open.allowedContentTypes = [.image, .movie]
        open.message = "Choose screenshots or videos to send with the report."
        open.prompt = "Attach"
        open.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.attach(open.urls) }
        }
    }

    private func attach(_ urls: [URL]) {
        var turnedAway: [String] = []
        for url in urls {
            guard !attachments.contains(where: { $0.url == url }) else { continue }
            let type = UTType(filenameExtension: url.pathExtension)
            guard type?.conforms(to: .image) == true || type?.conforms(to: .movie) == true else {
                turnedAway.append("“\(url.lastPathComponent)” isn't a picture or a video.")
                continue
            }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= BugReporter.eachFileAtMost else {
                let big = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                turnedAway.append("“\(url.lastPathComponent)” is \(big), too big to send (10 MB at most). A shorter clip will do.")
                continue
            }
            guard attachments.count < BugReporter.mostFiles else {
                turnedAway.append("That's the most it can send (\(BugReporter.mostFiles) files).")
                break
            }
            let a = BugAttachment(url: url, size: size)
            attachments.append(a)
            let row = FileRow(a, width: inner)
            row.onRemove = { [weak self, weak row] in
                guard let self, let row else { return }
                self.attachments.removeAll { $0 == a }
                self.fileList.removeArrangedSubview(row)
                row.removeFromSuperview()
                self.fileList.isHidden = self.attachments.isEmpty
                self.refresh()
                self.fit(animated: true)
            }
            fileList.addArrangedSubview(row)
        }
        fileList.isHidden = attachments.isEmpty
        say(turnedAway.isEmpty ? nil : turnedAway.joined(separator: " "))
        refresh()
        fit(animated: true)
    }

    private func say(_ problemText: String?) {
        problem.stringValue = problemText ?? ""
        problem.isHidden = problemText == nil
    }

    // MARK: Sending

    @objc private func send() {
        guard sendButton.isEnabled else { return }
        let report = BugReport(name: nameField.stringValue,
                               description: textView.string.trimmingCharacters(in: .whitespacesAndNewlines),
                               system: includeSystem.state == .on ? systemInfo() : nil,
                               attachments: attachments)
        sending = true
        spinner.startAnimation(nil)
        say(nil)
        refresh()
        fit(animated: true)
        Task { @MainActor [weak self] in
            do {
                try await BugReporter.send(report)
                self?.sent()
            } catch {
                self?.failed(error)
            }
        }
    }

    private func sent() {
        sending = false
        spinner.stopAnimation(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            form.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            self.form.isHidden = true
            self.formFloor.isActive = false
            self.thanks.alphaValue = 0
            self.thanks.isHidden = false
            self.sitter?.start()
            self.window.makeFirstResponder(nil)
            self.window.defaultButtonCell = self.doneButton.cell as? NSButtonCell
            self.fit(animated: true, height: self.thanks.fittingSize.height + 90)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                self.thanks.animator().alphaValue = 1
            }
        }
    }

    private func failed(_ error: Error) {
        sending = false
        spinner.stopAnimation(nil)
        say((error as? LocalizedError)?.errorDescription ?? "It couldn't be sent: \(error.localizedDescription)")
        refresh()
        fit(animated: true)
    }

    @objc private func cancel() { window.close() }

    /// Tools only.
    var debugDone: Bool { !thanks.isHidden }
    var debugProblem: String? { problem.isHidden ? nil : problem.stringValue }
    func debugFill(name: String, text: String, files: [URL]) {
        nameField.stringValue = name
        textView.string = text
        attach(files)
        refresh()
    }
    func debugSend() { send() }
    func debugPeek() { togglePeek() }
    func debugSnapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: - Pieces

/// A soft rounded box around a text field, as the panel's cards are, lit in
/// the accent colour while it's typed in.
final class FieldBox: NSView {
    var focused = false { didSet { if focused != oldValue { needsDisplay = true } } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 9, yRadius: 9)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        if focused {
            NSColor.controlAccentColor.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 3.5
            path.stroke()
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1
        } else {
            NSColor.labelColor.withAlphaComponent(0.12).setStroke()
            path.lineWidth = 1
        }
        path.stroke()
    }
}

/// A text view with grey words in it while it's empty, and ⌘↩ to send.
final class PlaceholderTextView: NSTextView {
    var placeholder = ""
    var onSubmit: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let pad = textContainer?.lineFragmentPadding ?? 5
        let origin = textContainerOrigin
        let rect = NSRect(x: origin.x + pad, y: origin.y, width: bounds.width - origin.x * 2 - pad * 2, height: bounds.height)
        (placeholder as NSString).draw(in: rect, withAttributes: [
            .font: font ?? .systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor])
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.keyCode == 36 || event.keyCode == 76 {
            onSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}

/// A rounded tile in a wash of the accent colour, with a symbol on it.
final class IconTile: NSView {
    init(symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 44).isActive = true
        heightAnchor.constraint(equalToConstant: 44).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 21, weight: .medium)) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 11, yRadius: 11)
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.3).setStroke()
        path.stroke()
    }
}

/// Where screenshots and videos go: dropped on it, or chosen by clicking it.
final class DropZone: NSView {
    var onChoose: (() -> Void)?
    var onDrop: (([URL]) -> Void)?
    var enabled = true { didSet { alphaValue = enabled ? 1 : 0.5; needsDisplay = true } }
    private var lit = false { didSet { if lit != oldValue { needsDisplay = true } } }
    private var tracking: NSTrackingArea?
    private static let accepted: [String] = [UTType.image.identifier, UTType.movie.identifier]

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 64).isActive = true
        registerForDraggedTypes([.fileURL])
        toolTip = "Drop files here, or click to choose them"

        let icon = NSImageView(image: NSImage(systemSymbolName: "photo.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 20, weight: .regular)) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        let title = NSTextField(labelWithString: "Drop them here, or click to choose")
        title.font = .systemFont(ofSize: 13, weight: .medium)
        let sub = NSTextField(labelWithString: "Up to \(BugReporter.mostFiles) files, 10 MB each")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        let words = NSStackView(views: [title, sub])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 1
        let row = NSStackView(views: [icon, words])
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: centerXAnchor),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    // Clicks on the words are the zone's.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        (lit ? NSColor.controlAccentColor.withAlphaComponent(0.12) : NSColor.labelColor.withAlphaComponent(0.03)).setFill()
        path.fill()
        path.lineWidth = 1.5
        path.setLineDash([5, 4], count: 2, phase: 0)
        (lit ? NSColor.controlAccentColor : NSColor.labelColor.withAlphaComponent(0.22)).setStroke()
        path.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }
    override func mouseEntered(with event: NSEvent) { lit = enabled }
    override func mouseExited(with event: NSEvent) { lit = false }
    override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .pointingHand) } }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { onChoose?() }
    }

    private func urls(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: DropZone.accepted,
        ]) as? [URL] ?? []
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard enabled, !urls(sender).isEmpty else { return [] }
        lit = true
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { lit = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        lit = false
        let found = urls(sender)
        guard enabled, !found.isEmpty else { return false }
        onDrop?(found)
        return true
    }
}

/// One attached file: a little picture of it, its name and size, and an ✕.
final class FileRow: NSView {
    var onRemove: (() -> Void)?
    var removable = true { didSet { remove.isHidden = !removable } }
    private let remove = NSButton()

    init(_ file: BugAttachment, width: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 42).isActive = true

        let thumb = NSImageView()
        thumb.image = file.isMovie ? NSWorkspace.shared.icon(forFile: file.url.path)
                                   : NSImage(contentsOf: file.url) ?? NSWorkspace.shared.icon(forFile: file.url.path)
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 5
        thumb.layer?.masksToBounds = true
        thumb.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: file.name)
        name.font = .systemFont(ofSize: 12.5, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let kind = file.isMovie ? "Video" : "Image"
        let size = NSTextField(labelWithString: "\(kind) · \(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))")
        size.font = .systemFont(ofSize: 11)
        size.textColor = .secondaryLabelColor
        let words = NSStackView(views: [name, size])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 1
        words.translatesAutoresizingMaskIntoConstraints = false
        remove.isBordered = false
        remove.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Remove")?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        remove.imagePosition = .imageOnly
        remove.contentTintColor = .tertiaryLabelColor
        remove.toolTip = "Remove"
        remove.target = self
        remove.action = #selector(removed)
        remove.translatesAutoresizingMaskIntoConstraints = false
        for v in [thumb, words, remove] { addSubview(v) }
        NSLayoutConstraint.activate([
            thumb.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            thumb.centerYAnchor.constraint(equalTo: centerYAnchor),
            thumb.widthAnchor.constraint(equalToConstant: 30),
            thumb.heightAnchor.constraint(equalToConstant: 30),
            words.leadingAnchor.constraint(equalTo: thumb.trailingAnchor, constant: 10),
            words.centerYAnchor.constraint(equalTo: centerYAnchor),
            words.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -8),
            remove.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            remove.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func removed() { onRemove?() }

    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 9, yRadius: 9)
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        path.fill()
        NSColor.labelColor.withAlphaComponent(0.09).setStroke()
        path.stroke()
    }
}
