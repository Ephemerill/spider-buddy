import AppKit
import UniformTypeIdentifiers

// MARK: - My Habitats

/// A habitat kept to come back to: the scenery and everything in the tank,
/// under a name. The tank itself always keeps itself as it is (see
/// `Habitat.save`); these are copies put by.
struct SavedHabitat: Codable, Equatable {
    /// Its own, lasting: the name of its file.
    var id: String
    var name: String
    var saved: Date
    var habitat: Habitat

    init(name: String, habitat: Habitat) {
        id = UUID().uuidString
        self.name = name
        saved = Date()
        self.habitat = habitat
    }

    /// When it was saved, in a few words ("Today, 14:05", "3 Sep").
    var when: String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(saved) {
            f.timeStyle = .short
            return "Today, " + f.string(from: saved)
        }
        if cal.isDateInYesterday(saved) {
            f.timeStyle = .short
            return "Yesterday, " + f.string(from: saved)
        }
        f.setLocalizedDateFormatFromTemplate(cal.isDate(saved, equalTo: Date(), toGranularity: .year) ? "d MMM" : "d MMM y")
        return f.string(from: saved)
    }

    /// Its habitat, ready to go in a tank whose world is `world`: a habitat
    /// saved in a world of another size (on another display, or brought in
    /// from someone else's) is stood in the middle of this one, hanging
    /// things still hanging from the lid.
    func habitat(for world: CGSize) -> Habitat {
        var h = habitat
        _ = h.giveIdentities()
        if h.size != world {
            let dx = ((world.width - h.size.width) / 2).rounded()
            let lift = world.height - h.size.height
            for i in h.items.indices {
                h.items[i].x += dx
                if h.items[i].kind.hangs { h.items[i].y += lift; h.items[i].h += lift }
            }
            h.world = world
        }
        h.clampAll()
        h.pruneLinks()
        return h
    }
}

/// The habitats put by, one file each in the app's own folder (so they can
/// be found, backed up and shared), newest first.
enum HabitatLibrary {
    /// A file of one habitat, for passing on.
    static let fileExtension = "spiderhabitat"
    static var fileType: UTType { UTType(filenameExtension: fileExtension) ?? .json }

    /// Where they live. (SPIDER_HABITAT_LIBRARY=dir: somewhere else, for tests.)
    static var folder: URL = {
        if let dir = ProcessInfo.processInfo.environment["SPIDER_HABITAT_LIBRARY"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.gabriel.desktopspider", isDirectory: true)
            .appendingPathComponent("Habitats", isDirectory: true)
    }()

    /// Told whenever the library changes (saved, renamed, deleted).
    static let changed = Notification.Name("HabitatLibraryChanged")

    private static var cache: [SavedHabitat]?

    /// Everything saved, newest first.
    static func all() -> [SavedHabitat] {
        if let c = cache { return c }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let list = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decode(Data(contentsOf: $0)) }
            .sorted { $0.saved > $1.saved }
        cache = list
        return list
    }

    static func saved(id: String) -> SavedHabitat? { all().first { $0.id == id } }

    private static func url(_ id: String) -> URL { folder.appendingPathComponent(id + ".json") }

    private static func encode(_ s: SavedHabitat) throws -> Data {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return try e.encode(s)
    }

    private static func decode(_ data: Data) throws -> SavedHabitat {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(SavedHabitat.self, from: data)
    }

    /// Writes it (a new one, or over the one with its id).
    @discardableResult
    static func store(_ s: SavedHabitat) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try encode(s).write(to: url(s.id), options: .atomic)
        } catch {
            NSLog("habitat library: couldn't save \(s.name): \(error)")
            return false
        }
        cache = nil
        NotificationCenter.default.post(name: changed, object: nil)
        return true
    }

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: url(id))
        cache = nil
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func rename(id: String, to name: String) {
        guard var s = saved(id: id) else { return }
        s.name = name
        store(s)
    }

    /// A name no other saved habitat has: "Forest", "Forest 2", …
    static func freshName(_ base: String) -> String {
        let names = Set(all().map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// Written out as a file of its own, to pass on.
    static func export(_ s: SavedHabitat, to u: URL) throws {
        try encode(s).write(to: u, options: .atomic)
    }

    /// A habitat file read in and kept, under a new id (so bringing the
    /// same file in twice keeps both). Throws if it isn't one.
    static func importFile(_ u: URL) throws -> SavedHabitat {
        let data = try Data(contentsOf: u)
        var s: SavedHabitat
        if let whole = try? decode(data) {
            s = whole
        } else {
            // (A bare habitat will do, too.)
            let h = try JSONDecoder().decode(Habitat.self, from: data)
            s = SavedHabitat(name: u.deletingPathExtension().lastPathComponent, habitat: h)
        }
        s.id = UUID().uuidString
        s.name = freshName(s.name.isEmpty ? u.deletingPathExtension().lastPathComponent : s.name)
        s.saved = Date()
        guard store(s) else { throw CocoaError(.fileWriteUnknown) }
        return s
    }
}

// MARK: - Saving and loading, from the tank

extension HabitatController {
    /// Which of My Habitats is in the tank (the last put in, or saved), and
    /// whether the tank has been changed since.
    var currentSaved: (saved: SavedHabitat, changed: Bool)? {
        guard let id = currentSaveID, let s = HabitatLibrary.saved(id: id) else { return nil }
        return (s, s.habitat(for: scene.habitat.size) != scene.habitat)
    }

    /// ⌘S, and the Save button: the changes kept in the one it came from,
    /// or — if it came from none — kept as a new one.
    @objc func saveHabitatAction() {
        if let cur = currentSaved {
            guard cur.changed else { flash("“\(cur.saved.name)” is saved"); return }
            var s = cur.saved
            s.habitat = scene.habitat
            s.saved = Date()
            if HabitatLibrary.store(s) { flash("Saved “\(s.name)”") }
            decorPanelRefresh()
        } else {
            saveHabitatAsNewAction()
        }
    }

    /// Kept as another of My Habitats, under a name asked for.
    @objc func saveHabitatAsNewAction() {
        let suggested = HabitatLibrary.freshName("My \(scene.habitat.biome.label)")
        askName(title: "Save This Habitat", message: "It goes in My Habitats, to come back to whenever you like.",
                button: "Save", name: suggested) { [weak self] name in
            guard let self else { return }
            let s = SavedHabitat(name: name, habitat: self.scene.habitat)
            guard HabitatLibrary.store(s) else { self.failed("It couldn’t be saved."); return }
            self.currentSaveID = s.id
            self.flash("Saved “\(name)”")
            self.decorPanelRefresh()
        }
    }

    /// One of My Habitats put in the tank, as one edit (so it can be undone).
    func loadSaved(id: String) {
        guard let s = HabitatLibrary.saved(id: id) else { return }
        let h = s.habitat(for: scene.habitat.size)
        currentSaveID = s.id
        if h != scene.habitat { scene.replace(with: h, fade: true) }
        flash("“\(s.name)” is in the tank")
        decorPanelRefresh()
    }

    /// The ⋯ on one of My Habitats.
    func showSavedMenu(id: String, from view: NSView) {
        guard let s = HabitatLibrary.saved(id: id) else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, _ symbol: String, enabled: Bool = true, _ f: @escaping () -> Void) {
            let it = MenuAction.item(title, f)
            it.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            it.isEnabled = enabled
            menu.addItem(it)
        }
        add("Put in the Tank", "arrow.down.to.line") { [weak self] in self?.loadSaved(id: id) }
        let cur = currentSaved
        let same = cur?.saved.id == id && cur?.changed == false
        add("Update to the Tank as It Is Now", "arrow.triangle.2.circlepath", enabled: !same) { [weak self] in
            guard let self, var s = HabitatLibrary.saved(id: id) else { return }
            s.habitat = self.scene.habitat
            s.saved = Date()
            HabitatLibrary.store(s)
            self.currentSaveID = id
            self.flash("Updated “\(s.name)”")
            self.decorPanelRefresh()
        }
        menu.addItem(.separator())
        add("Rename…", "pencil") { [weak self] in
            self?.askName(title: "Rename “\(s.name)”", message: nil, button: "Rename", name: s.name) { name in
                HabitatLibrary.rename(id: id, to: name)
            }
        }
        add("Share a Copy…", "square.and.arrow.up") { [weak self] in self?.export(s) }
        add("Show in Finder", "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([HabitatLibrary.folder.appendingPathComponent(id + ".json")])
        }
        menu.addItem(.separator())
        add("Delete…", "trash") { [weak self] in self?.confirmDelete(s) }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: view.isFlipped ? view.bounds.height + 4 : -4), in: view)
    }

    /// A habitat file brought in, kept in My Habitats and put in the tank.
    @objc func importHabitatAction() {
        let open = NSOpenPanel()
        open.allowedContentTypes = [HabitatLibrary.fileType, .json]
        open.allowsMultipleSelection = false
        open.message = "Choose a habitat to bring in"
        open.prompt = "Bring In"
        open.beginSheetModal(for: window) { [weak self] r in
            guard let self, r == .OK, let u = open.url else { return }
            do {
                let s = try HabitatLibrary.importFile(u)
                self.loadSaved(id: s.id)
            } catch {
                self.failed("“\(u.lastPathComponent)” isn’t a habitat this app can read.")
            }
        }
    }

    /// A copy written out as a file, to pass on.
    private func export(_ s: SavedHabitat) {
        let save = NSSavePanel()
        save.allowedContentTypes = [HabitatLibrary.fileType]
        save.nameFieldStringValue = s.name
        save.message = "Anyone with the app can bring this habitat into their own tank."
        save.beginSheetModal(for: window) { [weak self] r in
            guard r == .OK, let u = save.url else { return }
            do { try HabitatLibrary.export(s, to: u) } catch { self?.failed("It couldn’t be written there.") }
        }
    }

    private func confirmDelete(_ s: SavedHabitat) {
        let a = NSAlert()
        a.messageText = "Delete “\(s.name)”?"
        a.informativeText = "It’s gone for good — the tank stays as it is."
        a.addButton(withTitle: "Delete")
        a.addButton(withTitle: "Cancel")
        a.buttons.first?.hasDestructiveAction = true
        a.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn else { return }
            HabitatLibrary.delete(id: s.id)
            if self?.currentSaveID == s.id { self?.currentSaveID = nil }
            self?.decorPanelRefresh()
        }
    }

    /// A name asked for, in a sheet on the tank.
    private func askName(title: String, message: String?, button: String, name: String, then: @escaping (String) -> Void) {
        let a = NSAlert()
        a.messageText = title
        if let message { a.informativeText = message }
        a.addButton(withTitle: button)
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(string: name)
        field.frame = CGRect(x: 0, y: 0, width: 260, height: 24)
        a.accessoryView = field
        a.window.initialFirstResponder = field
        a.beginSheetModal(for: window) { r in
            let typed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard r == .alertFirstButtonReturn, !typed.isEmpty else { return }
            then(String(typed.prefix(60)))
        }
    }

    private func failed(_ s: String) {
        let a = NSAlert()
        a.messageText = s
        a.alertStyle = .warning
        a.beginSheetModal(for: window)
    }

    /// A few words under the name for a moment.
    func flash(_ s: String) {
        setStatus(s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.titleView.status == s else { return }
            self.setStatus(nil)
        }
    }

    /// The Habitats menu in the menu bar (while the tank is open): save,
    /// bring one in, and My Habitats to put in the tank.
    func fillHabitatsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        let save = NSMenuItem(title: currentSaved?.changed == true ? "Save Changes" : "Save This Habitat…", action: #selector(saveHabitatAction), keyEquivalent: "s")
        save.target = self
        menu.addItem(save)
        let saveNew = NSMenuItem(title: "Save as New…", action: #selector(saveHabitatAsNewAction), keyEquivalent: "S")
        saveNew.target = self
        menu.addItem(saveNew)
        let imp = NSMenuItem(title: "Bring In a Habitat…", action: #selector(importHabitatAction), keyEquivalent: "o")
        imp.target = self
        menu.addItem(imp)
        menu.addItem(.separator())
        let head = NSMenuItem(title: "My Habitats", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        let all = HabitatLibrary.all()
        if all.isEmpty {
            let none = NSMenuItem(title: "None saved yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            none.indentationLevel = 1
            menu.addItem(none)
        }
        let cur = currentSaveID
        for s in all {
            let it = MenuAction.item(s.name) { [weak self] in self?.loadSaved(id: s.id) }
            it.indentationLevel = 1
            it.state = s.id == cur ? .on : .off
            menu.addItem(it)
        }
        menu.addItem(.separator())
        let tour = NSMenuItem(title: "Show Me Round the Habitat", action: #selector(showTour), keyEquivalent: "")
        tour.target = self
        menu.addItem(tour)
    }
}

/// A menu item that runs a closure.
final class MenuAction: NSObject {
    private let f: () -> Void
    private init(_ f: @escaping () -> Void) { self.f = f }
    @objc private func run() { f() }

    static func item(_ title: String, _ f: @escaping () -> Void) -> NSMenuItem {
        let a = MenuAction(f)
        let it = NSMenuItem(title: title, action: #selector(run), keyEquivalent: "")
        it.target = a
        it.representedObject = a   // (the item keeps it alive)
        return it
    }
}
