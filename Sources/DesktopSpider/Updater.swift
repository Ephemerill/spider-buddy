import AppKit

/// Checks GitHub Releases for a newer build and swaps it in.
///
/// The app is ad-hoc signed, so the first install means clicking through
/// Gatekeeper. That only happens because the browser tags the download with
/// a quarantine attribute; a file this app downloads itself never gets one,
/// and the copy it installs has the attribute stripped anyway. So after the
/// first install, updates just land — no "unidentified developer" dance.
///
/// Flow: GET /releases/latest → compare tags → download the .dmg → mount it
/// → copy the .app next to the running bundle → rename it into place →
/// relaunch.
final class Updater {
    static let repo = "Ephemerill/spider-buddy"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Release {
        let version: String
        let notes: String
        let page: URL
        let dmg: URL
    }

    enum Failure: LocalizedError {
        case http(Int)
        case noRelease
        case noDMG
        case badArchive
        case notInstalled
        case tool(String, String)

        var errorDescription: String? {
            switch self {
            case .http(let code): return "GitHub answered with HTTP \(code)."
            case .noRelease: return "GitHub returned no releases."
            case .noDMG: return "The latest release has no .dmg attached."
            case .badArchive: return "The downloaded disk image has no app inside."
            case .notInstalled:
                return "The spider is running straight from the disk image. Drag it to Applications first, then update from there."
            case .tool(let name, let output):
                return "\(name) failed: \(output.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }

    /// Set while a check or install is in flight so the menu can say so.
    private(set) var busy = false
    private var progress: ProgressPanel?
    private let session = URLSession(configuration: .ephemeral)

    /// Called back on the main thread when the state changes (for the menu).
    var onChange: (() -> Void)?

    // MARK: Entry point

    /// Looks for a newer release and, if the user agrees, installs it.
    func checkAndInstall() {
        guard !busy else { return }
        busy = true
        onChange?()
        fetchLatest { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.finish()
                self.alert("Couldn't check for updates", error.localizedDescription)
            case .success(let release):
                guard Updater.isNewer(release.version, than: Updater.currentVersion) else {
                    self.finish()
                    self.alert("You're up to date",
                               "\(AppInfo.name) \(Updater.currentVersion) is the latest version.")
                    return
                }
                if self.offer(release) {
                    self.install(release)
                } else {
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        busy = false
        progress?.close()
        progress = nil
        onChange?()
    }

    // MARK: GitHub

    private func fetchLatest(_ done: @escaping (Result<Release, Error>) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Updater.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DesktopSpider/\(Updater.currentVersion)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        session.dataTask(with: req) { data, resp, error in
            let result: Result<Release, Error>
            if let error {
                result = .failure(error)
            } else if let code = (resp as? HTTPURLResponse)?.statusCode, code != 200 {
                result = .failure(code == 404 ? Failure.noRelease : Failure.http(code))
            } else {
                result = Updater.parse(data ?? Data())
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    private static func parse(_ data: Data) -> Result<Release, Error> {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let pageString = json["html_url"] as? String,
              let page = URL(string: pageString) else {
            return .failure(Failure.noRelease)
        }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let dmgString = assets.compactMap({ asset -> String? in
            guard let name = asset["name"] as? String, name.hasSuffix(".dmg") else { return nil }
            return asset["browser_download_url"] as? String
        }).first, let dmg = URL(string: dmgString) else {
            return .failure(Failure.noDMG)
        }
        let notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(Release(version: tag, notes: notes, page: page, dmg: dmg))
    }

    /// "v1.2.3" > "1.2"? Compared number by number; a missing part is 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
            return t.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0
            let q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: Asking

    private func offer(_ release: Release) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) \(release.version) is available"
        var text = "You have \(Updater.currentVersion). The update downloads, installs over this copy and relaunches the spider. Its settings and design stay put."
        if !release.notes.isEmpty {
            text += "\n\n" + String(release.notes.prefix(600))
        }
        alert.informativeText = text
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "View on GitHub")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.page); return false
        default: return false
        }
    }

    private func alert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Installing

    private func install(_ release: Release) {
        let panel = ProgressPanel(title: "Downloading \(AppInfo.name) \(release.version)…")
        progress = panel
        panel.show()

        let task = session.downloadTask(with: release.dmg) { [weak self] tmp, resp, error in
            guard let self else { return }
            let staged: URL?
            if let tmp, error == nil, ((resp as? HTTPURLResponse)?.statusCode ?? 200) == 200 {
                // The temp file is deleted when this closure returns; keep it.
                let keep = FileManager.default.temporaryDirectory
                    .appendingPathComponent("DesktopSpider-\(release.version).dmg")
                try? FileManager.default.removeItem(at: keep)
                staged = (try? FileManager.default.moveItem(at: tmp, to: keep)) != nil ? keep : nil
            } else {
                staged = nil
            }
            DispatchQueue.main.async {
                guard let staged else {
                    self.finish()
                    let why = error?.localizedDescription
                        ?? "HTTP \((resp as? HTTPURLResponse)?.statusCode ?? 0)"
                    self.alert("Download failed", why)
                    return
                }
                panel.set(title: "Installing…", fraction: nil)
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Result { try self.swapIn(dmg: staged) }
                    try? FileManager.default.removeItem(at: staged)
                    DispatchQueue.main.async {
                        self.finish()
                        switch result {
                        case .failure(let error):
                            self.alert("Update failed", error.localizedDescription)
                        case .success(let app):
                            self.relaunch(app)
                        }
                    }
                }
            }
        }
        panel.observe(task.progress)
        task.resume()
    }

    /// Mounts the image, copies the app next to the running bundle, and
    /// renames it into place. Returns where the new app now lives.
    private func swapIn(dmg: URL) throws -> URL {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("DesktopSpiderUpdate-\(getpid())")
        try? fm.removeItem(at: mount)
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                     "-mountpoint", mount.path, dmg.path])
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            try? fm.removeItem(at: mount)
        }

        guard let fresh = (try? fm.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) else {
            throw Failure.badArchive
        }

        // Installed under the new app's own name (a rename between releases
        // carries through), and the old bundle taken away if it was
        // called something else.
        let old = try installTarget()
        let dir = old.deletingLastPathComponent()
        let target = dir.appendingPathComponent(fresh.lastPathComponent)
        let staging = dir.appendingPathComponent(".\(target.lastPathComponent).update")
        let retired = dir.appendingPathComponent(".\(target.lastPathComponent).old")
        try? fm.removeItem(at: staging)
        try? fm.removeItem(at: retired)

        // ditto keeps the code signature and bundle structure intact.
        try run("/usr/bin/ditto", [fresh.path, staging.path])
        // Nothing we download should carry quarantine, but make sure: this
        // is what keeps Gatekeeper from asking again.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])

        // Two renames on the same volume: the old app is out of the way
        // for a few microseconds, and the running process keeps its
        // already-open binary either way.
        if fm.fileExists(atPath: target.path) {
            try fm.moveItem(at: target, to: retired)
        }
        do {
            try fm.moveItem(at: staging, to: target)
        } catch {
            try? fm.moveItem(at: retired, to: target)   // put the old one back
            throw error
        }
        try? fm.removeItem(at: retired)
        if old != target, fm.fileExists(atPath: old.path) { try? fm.removeItem(at: old) }
        return target
    }

    /// Where the new app goes: over the running bundle, unless we are
    /// running from a mounted disk image or somewhere read-only.
    private func installTarget() throws -> URL {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        guard current.pathExtension == "app" else { throw Failure.notInstalled }
        if current.path.hasPrefix("/Volumes/") { throw Failure.notInstalled }
        let dir = current.deletingLastPathComponent()
        if fm.isWritableFile(atPath: dir.path) { return current }
        // Read-only home for the bundle; fall back to the user's Applications.
        let apps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        return apps.appendingPathComponent(current.lastPathComponent)
    }

    private func relaunch(_ app: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to be gone so LaunchServices starts the new
        // binary rather than focusing the old one.
        task.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.1; done; open -n \"\(app.path)\""]
        try? task.run()
        NSApp.terminate(nil)
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            throw Failure.tool((tool as NSString).lastPathComponent, text)
        }
        return text
    }
}

// MARK: - Progress panel

/// A small floating window with a progress bar, for the download.
final class ProgressPanel {
    private let window: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private var observation: NSKeyValueObservation?

    init(title: String) {
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 84),
                         styleMask: [.titled, .utilityWindow, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.title = AppInfo.name
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false

        label.stringValue = title
        label.frame = NSRect(x: 20, y: 46, width: 320, height: 20)
        bar.frame = NSRect(x: 20, y: 20, width: 320, height: 20)
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        window.contentView?.addSubview(label)
        window.contentView?.addSubview(bar)
    }

    func show() {
        window.center()
        window.orderFrontRegardless()
    }

    func observe(_ progress: Progress) {
        observation = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] p, _ in
            DispatchQueue.main.async {
                self?.set(title: nil, fraction: p.totalUnitCount > 0 ? p.fractionCompleted : nil)
            }
        }
    }

    func set(title: String?, fraction: Double?) {
        if let title { label.stringValue = title }
        if let fraction {
            bar.isIndeterminate = false
            bar.doubleValue = fraction
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func close() {
        observation = nil
        window.close()
    }
}

/// The app's own name: "Spider Buddy" for a release, "spiders" for the
/// testing build (see build.sh).
enum AppInfo {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Spider Buddy"
    }

    /// An update from 1.1.0 lands as "Spider.app" (that version's updater
    /// kept the old bundle's name). A release that finds itself so named
    /// takes its own name, once, where it can.
    static func takeOwnNameIfNeeded() {
        let fm = FileManager.default
        let here = Bundle.main.bundleURL
        guard here.lastPathComponent == "Spider.app", name == "Spider Buddy",
              !here.path.hasPrefix("/Volumes/") else { return }
        let dir = here.deletingLastPathComponent()
        let there = dir.appendingPathComponent("Spider Buddy.app")
        guard fm.isWritableFile(atPath: dir.path), !fm.fileExists(atPath: there.path) else { return }
        try? fm.moveItem(at: here, to: there)
    }
}
