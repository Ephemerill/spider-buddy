import AppKit
import Network

// MARK: - The browser extension's line to the app
//
// The Spider Buddy extension (Extension/ in the repo), where it is added to
// a browser, tells the app two things about the page it is climbing that a
// picture cannot: how far each part of it has scrolled, exactly and as it
// happens, and when it has changed. The pictures still say where the
// ledges are (see WebPages.swift); this says where they have got to since,
// and when to look again.
//
// The line is a WebSocket on 127.0.0.1 only — nothing outside the Mac can
// reach it — taking only browser extensions (a page cannot pose as one:
// the browser sets where a connection comes from). What comes over it is
// positions and sizes, never anything on the page.

final class PageBridge {
    /// A part of a page that scrolls (0 is the page itself), as the page
    /// last laid it out: where it shows, in the page's own pixels from the
    /// top left of the window's page area, and what it is carried by when
    /// something else scrolls (0 the page, -1 nothing).
    struct Scroller {
        var id: Int
        var carrier: Int
        var rect: CGRect
        /// How far it had scrolled when it was laid out.
        var offset: CGPoint
    }

    /// One page as the extension last described it.
    struct Page {
        var tab: Int
        /// The browser window it is in, as the browser has it (screen points,
        /// from the top left of the main display).
        var window: CGRect
        /// The page area, in the page's pixels, and how many of them to a
        /// device pixel.
        var viewport: CGSize
        var dpr: CGFloat
        var scrollers: [Int: Scroller] = [:]
        /// Parts that stay put when the page scrolls, in the page's pixels.
        var fixed: [CGRect] = []
        /// How far each part has scrolled now.
        var offsets: [Int: CGPoint] = [:]
        var laidOutAt: CFTimeInterval = 0
    }

    private(set) var pages: [Int: Page] = [:]
    /// Whether an extension is on the line at all.
    private(set) var connected = false
    /// A page scrolled: which tab.
    var onScroll: ((Int) -> Void)?
    /// A page changed, or was laid out afresh: look at it again.
    var onChange: ((Int) -> Void)?

    static let ports: [UInt16] = [47219, 47220, 47221]
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private let queue = DispatchQueue(label: "spider.bridge", qos: .userInitiated)
    /// Windows the app is climbing, as the browser would give them.
    private var wanted: [CGRect] = []
    private var portIndex = 0

    var running: Bool { listener != nil }

    func start() {
        guard listener == nil else { return }
        let ws = NWProtocolWebSocket.Options()
        ws.autoReplyPing = true
        // Browser extensions only: a page's own scripts come from its site.
        ws.setClientRequestHandler(queue) { _, headers in
            let origin = headers.first { $0.name.lowercased() == "origin" }?.value ?? ""
            let ok = ["chrome-extension://", "moz-extension://", "safari-web-extension://"].contains { origin.hasPrefix($0) }
            return NWProtocolWebSocket.Response(status: ok ? .accept : .reject, subprotocol: nil)
        }
        let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        params.defaultProtocolStack.applicationProtocols.insert(ws, at: 0)
        params.requiredInterfaceType = .loopback
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: PageBridge.ports[portIndex]),
              let l = try? NWListener(using: params, on: port) else { tryNextPort(); return }
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
        l.stateUpdateHandler = { [weak self] state in
            if case .failed = state { DispatchQueue.main.async { self?.listener = nil; self?.tryNextPort() } }
        }
        l.start(queue: queue)
        listener = l
    }

    private func tryNextPort() {
        listener?.cancel()
        listener = nil
        portIndex += 1
        guard portIndex < PageBridge.ports.count else { return }
        start()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        portIndex = 0
        queue.async { [weak self] in
            self?.connections.values.forEach { $0.cancel() }
            self?.connections = [:]
        }
        pages = [:]
        connected = false
    }

    /// The windows being climbed, in the app's own terms (AppKit screen
    /// points): the extension is told, so only their pages report.
    func want(_ frames: [CGRect]) {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let rects = frames.map { CGRect(x: $0.minX, y: top - $0.maxY, width: $0.width, height: $0.height).integral }
        guard rects != wanted else { return }
        wanted = rects
        sendWant()
    }

    private func sendWant() {
        let list = wanted.map { ["left": $0.minX, "top": $0.minY, "width": $0.width, "height": $0.height] }
        broadcast(["type": "want", "windows": list])
    }

    /// The page the extension says is showing in a window (AppKit frame).
    func page(in frame: CGRect) -> Page? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let r = CGRect(x: frame.minX, y: top - frame.maxY, width: frame.width, height: frame.height)
        return pages.values.first { p in
            abs(p.window.minX - r.minX) <= 6 && abs(p.window.minY - r.minY) <= 6
                && abs(p.window.width - r.width) <= 6 && abs(p.window.height - r.height) <= 6
        }
    }

    // MARK: The line

    private func accept(_ c: NWConnection) {
        let key = ObjectIdentifier(c)
        connections[key] = c
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self?.connected = true
                    self?.sendWant()
                }
            case .failed, .cancelled:
                self?.queue.async {
                    self?.connections[key] = nil
                    let any = !(self?.connections.isEmpty ?? true)
                    DispatchQueue.main.async {
                        self?.connected = any
                        if !any { self?.pages = [:] }
                    }
                }
            default: break
            }
        }
        c.start(queue: queue)
        receive(c)
    }

    private func receive(_ c: NWConnection) {
        c.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty,
               let m = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                DispatchQueue.main.async { self?.handle(m) }
            }
            if error == nil { self?.receive(c) } else { c.cancel() }
        }
    }

    private func broadcast(_ m: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: m) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            for c in self.connections.values {
                let meta = NWProtocolWebSocket.Metadata(opcode: .text)
                let ctx = NWConnection.ContentContext(identifier: "text", metadata: [meta])
                c.send(content: data, contentContext: ctx, isComplete: true, completion: .idempotent)
            }
        }
    }

    // MARK: What it says

    private static func num(_ v: Any?) -> CGFloat? {
        if let d = v as? Double { return CGFloat(d) }
        if let i = v as? Int { return CGFloat(i) }
        if let n = v as? NSNumber { return CGFloat(truncating: n) }
        return nil
    }

    private static func rect(_ a: [Any], from i: Int) -> CGRect? {
        guard a.count >= i + 4, let x = num(a[i]), let y = num(a[i + 1]), let w = num(a[i + 2]), let h = num(a[i + 3]) else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func handle(_ m: [String: Any]) {
        guard let type = m["type"] as? String else { return }
        let tab = (m["tab"] as? Int) ?? Int(PageBridge.num(m["tab"]) ?? -1)
        switch type {
        case "layout":
            guard tab >= 0, let w = m["window"] as? [String: Any], let v = m["view"] as? [String: Any],
                  let left = PageBridge.num(w["left"]), let top = PageBridge.num(w["top"]),
                  let width = PageBridge.num(w["width"]), let height = PageBridge.num(w["height"]),
                  let vw = PageBridge.num(v["w"]), let vh = PageBridge.num(v["h"]) else { return }
            var p = Page(tab: tab, window: CGRect(x: left, y: top, width: width, height: height),
                         viewport: CGSize(width: vw, height: vh), dpr: PageBridge.num(v["dpr"]) ?? 2)
            for case let s as [Any] in (m["scrollers"] as? [Any]) ?? [] {
                guard s.count >= 8, let id = PageBridge.num(s[0]), let carrier = PageBridge.num(s[1]),
                      let r = PageBridge.rect(s, from: 2), let ox = PageBridge.num(s[6]), let oy = PageBridge.num(s[7]) else { continue }
                let sc = Scroller(id: Int(id), carrier: Int(carrier), rect: r, offset: CGPoint(x: ox, y: oy))
                p.scrollers[sc.id] = sc
                p.offsets[sc.id] = sc.offset
            }
            for case let f as [Any] in (m["fixed"] as? [Any]) ?? [] {
                if let r = PageBridge.rect(f, from: 0) { p.fixed.append(r) }
            }
            p.laidOutAt = CACurrentMediaTime()
            pages[tab] = p
            onChange?(tab)
        case "scroll":
            guard var p = pages[tab] else { return }
            for case let s as [Any] in (m["s"] as? [Any]) ?? [] {
                guard s.count >= 3, let id = PageBridge.num(s[0]), let x = PageBridge.num(s[1]), let y = PageBridge.num(s[2]) else { continue }
                p.offsets[Int(id)] = CGPoint(x: x, y: y)
            }
            pages[tab] = p
            onScroll?(tab)
        case "changed":
            onChange?(tab)
        case "gone":
            pages[tab] = nil
        default:
            break
        }
    }
}
