import AppKit

// MARK: - My Spiders

/// A spider kept to come back to: everything the Studio makes of it, under
/// its own name. There is still only ever one spider out (see
/// `SpiderDesign.load`); these are copies put by, so trying out another
/// look is never changing the one you have.
struct SavedSpider: Codable, Equatable {
    /// Its own, lasting: the name of its file.
    var id: String
    /// When it was first kept: they are shown in the order they were made.
    var made: Date
    var design: SpiderDesign

    init(design: SpiderDesign) {
        id = UUID().uuidString
        made = Date()
        self.design = design
    }

    var name: String { design.name.isEmpty ? "Spider" : design.name }

    /// Whether `d` is this spider as it was saved. (How its legs move is a
    /// choice of animation, not of spider, so it doesn't count.)
    func matches(_ d: SpiderDesign) -> Bool {
        var a = design, b = d
        a.gait.motion = .classic
        b.gait.motion = .classic
        return a == b
    }
}

/// The spiders put by, one file each in the app's own folder (so they can
/// be found and backed up), oldest first — the order they were made in.
enum SpiderLibrary {
    /// Where they live. (SPIDER_LIBRARY=dir: somewhere else, for tests.)
    static var folder: URL = {
        if let dir = ProcessInfo.processInfo.environment["SPIDER_LIBRARY"] {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.gabriel.desktopspider", isDirectory: true)
            .appendingPathComponent("Spiders", isDirectory: true)
    }()

    /// Which of them is the one out (the last put on, or saved).
    /// (A library somewhere else, for tests, keeps its own.)
    static let currentKey = ProcessInfo.processInfo.environment["SPIDER_LIBRARY"] == nil ? "spiderCurrentSave" : "spiderCurrentSaveTest"

    static var currentID: String? {
        get { UserDefaults.standard.string(forKey: currentKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }

    private static var cache: [SavedSpider]?

    static func all() -> [SavedSpider] {
        if let c = cache { return c }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let list = files.filter { $0.pathExtension == "json" }
            .compactMap { try? decode(Data(contentsOf: $0)) }
            .sorted { $0.made < $1.made }
        cache = list
        return list
    }

    static func saved(id: String) -> SavedSpider? { all().first { $0.id == id } }

    /// The saved spider that is out, if the one out is one of them.
    static var current: SavedSpider? { currentID.flatMap(saved(id:)) }

    /// The first time there is a library at all, the spider you already
    /// have goes in it — kept safe before anything else can change it.
    /// (Once there is a folder, even an empty one, it's left to you.)
    static func seed(with design: SpiderDesign) {
        guard !FileManager.default.fileExists(atPath: folder.path) else { return }
        let s = SavedSpider(design: design)
        if store(s) { currentID = s.id }
    }

    private static func url(_ id: String) -> URL { folder.appendingPathComponent(id + ".json") }

    private static func decode(_ data: Data) throws -> SavedSpider {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return try d.decode(SavedSpider.self, from: data)
    }

    /// Writes it (a new one, or over the one with its id).
    @discardableResult
    static func store(_ s: SavedSpider) -> Bool {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let e = JSONEncoder()
            e.dateEncodingStrategy = .iso8601
            e.outputFormatting = [.sortedKeys]
            try e.encode(s).write(to: url(s.id), options: .atomic)
        } catch {
            NSLog("spider library: couldn't save \(s.name): \(error)")
            return false
        }
        cache = nil
        return true
    }

    static func delete(id: String) {
        try? FileManager.default.removeItem(at: url(id))
        cache = nil
        if currentID == id { currentID = nil }
    }

    /// A name no other saved spider has: "Pip", "Pip 2", …
    static func freshName(_ base: String) -> String {
        let names = Set(all().map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var n = 2
        while names.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }
}
