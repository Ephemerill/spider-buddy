import CoreGraphics
import Foundation

// MARK: - What it knows of the things in its tank
//
// Each thing in the tank is, to the spider, one of four: something it has
// not noticed yet; something it has noticed and not made its mind up about;
// something it is looking into; or a familiar part of its world, no more a
// mystery than the ground. None of that is ever shown as a number or a
// label — it shows only in what it does (see "Things in the tank" in
// Spider.swift).
//
// It comes to know a thing two ways: by time spent near it with nothing
// going wrong, and by looking into it — watching it, feeling it, climbing
// it. Both build its `exposure`, and at 1 it is familiar. Something that
// moves, or gives it a fright, unsettles it for a while (`unease`). And
// knowing one toadstool, the next is less of a mystery: what it knows of a
// kind of thing speeds up getting to know another of it.
//
// It is its own knowledge, kept apart from the tank: the tank can be
// rearranged, and it is the spider that finds the new things new.
//
// It knows its places too (see HabitatPlaces.swift): where it has been and
// how often, what it has liked each for — sleeping, a drink, the view —
// and anything that happened there, a fright or a catch; which thing is its
// favourite of a kind; and the ways between its places that have got it
// there before. That too is never shown: you find out which is its
// favourite branch by watching where it goes.

/// How well it knows one thing.
struct Acquaintance: Codable {
    enum Stage: String, Codable {
        /// Not noticed yet.
        case unknown
        /// Noticed; not made its mind up about it.
        case noticed
        /// Looking into it.
        case investigating
        /// Part of its world.
        case familiar
    }
    var stage: Stage = .unknown
    /// 0…1: safe time near it and looking into it; familiar at 1.
    var exposure: CGFloat = 0
    /// 0…1: how uneasy it is about it just now.
    var unease: CGFloat = 0
    /// What kind of thing it is (by name).
    var kind = ""
    /// How much it likes it, -1…1: time on it in peace, a good sleep on it.
    var fond: CGFloat = 0
    /// When it was last at it, on purpose (its knowledge's clock; -1 never).
    var lastVisit: Double = -1

    init(stage: Stage = .unknown, exposure: CGFloat = 0, unease: CGFloat = 0, kind: String = "") {
        self.stage = stage
        self.exposure = exposure
        self.unease = unease
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stage = try c.decodeIfPresent(Stage.self, forKey: .stage) ?? .unknown
        exposure = try c.decodeIfPresent(CGFloat.self, forKey: .exposure) ?? 0
        unease = try c.decodeIfPresent(CGFloat.self, forKey: .unease) ?? 0
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        fond = try c.decodeIfPresent(CGFloat.self, forKey: .fond) ?? 0
        lastVisit = try c.decodeIfPresent(Double.self, forKey: .lastVisit) ?? -1
    }
}

/// What it has made of one place in its tank (see `HabitatPlace`).
struct PlaceRecord: Codable {
    /// Where it is in the world, and what it is on (nil: the tank itself).
    var x: CGFloat = 0, y: CGFloat = 0
    var uid: String?
    /// How much it likes it for each thing it has used it for (by
    /// `PlaceUse`), -1…1.
    var fond: [String: CGFloat] = [:]
    /// Times it has stopped there.
    var visits: CGFloat = 0
    /// When last (its knowledge's clock).
    var last: Double = -1
    /// Frights it has had there, catches it has made there, prey it has
    /// seen about there — each wearing off in time.
    var frights: CGFloat = 0
    var catches: CGFloat = 0
    var sightings: CGFloat = 0

    init(x: CGFloat, y: CGFloat, uid: String?) {
        self.x = x
        self.y = y
        self.uid = uid
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decodeIfPresent(CGFloat.self, forKey: .x) ?? 0
        y = try c.decodeIfPresent(CGFloat.self, forKey: .y) ?? 0
        uid = try c.decodeIfPresent(String.self, forKey: .uid)
        fond = try c.decodeIfPresent([String: CGFloat].self, forKey: .fond) ?? [:]
        visits = try c.decodeIfPresent(CGFloat.self, forKey: .visits) ?? 0
        last = try c.decodeIfPresent(Double.self, forKey: .last) ?? -1
        frights = try c.decodeIfPresent(CGFloat.self, forKey: .frights) ?? 0
        catches = try c.decodeIfPresent(CGFloat.self, forKey: .catches) ?? 0
        sightings = try c.decodeIfPresent(CGFloat.self, forKey: .sightings) ?? 0
    }

    /// How much it likes it for `use`.
    func fond(_ use: PlaceUse) -> CGFloat { fond[use.rawValue] ?? 0 }
    var p: V2 { V2(x, y) }
}

final class HabitatKnowledge {
    struct State: Codable {
        var version = 1
        /// By the thing's `uid`.
        var things: [String: Acquaintance] = [:]
        /// How used it is to each kind of thing, 0…1.
        var kinds: [String: CGFloat] = [:]
        /// It has had a tank to know: from then on whatever is put in it is
        /// new to it. (Everything there when it first had one, it has lived
        /// with already.)
        var seeded = false
        /// Seconds it has lived in its tank with this knowledge.
        var clock: Double = 0
        /// Its places, by `HabitatPlace.key`.
        var places: [String: PlaceRecord] = [:]
        /// The ways over from one surface onto the next it has taken to get
        /// somewhere, and got there (by `routeKey`), 0…1.
        var routes: [String: CGFloat] = [:]

        init(seeded: Bool = false) {
            self.seeded = seeded
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            things = try c.decodeIfPresent([String: Acquaintance].self, forKey: .things) ?? [:]
            kinds = try c.decodeIfPresent([String: CGFloat].self, forKey: .kinds) ?? [:]
            seeded = try c.decodeIfPresent(Bool.self, forKey: .seeded) ?? false
            clock = try c.decodeIfPresent(Double.self, forKey: .clock) ?? 0
            places = try c.decodeIfPresent([String: PlaceRecord].self, forKey: .places) ?? [:]
            routes = try c.decodeIfPresent([String: CGFloat].self, forKey: .routes) ?? [:]
        }
    }

    private(set) var state: State
    /// Changed since it was last saved.
    private(set) var dirty = false

    static let key = "habitatKnowledge"

    init(state: State = State()) {
        self.state = state
    }

    static func load(from defaults: UserDefaults = .standard) -> HabitatKnowledge {
        guard let data = defaults.data(forKey: key), let s = try? JSONDecoder().decode(State.self, from: data) else { return HabitatKnowledge() }
        return HabitatKnowledge(state: s)
    }

    /// Kept — only what is about things still in `tank`, if given (a thing
    /// taken out and put back is new again).
    func save(to defaults: UserDefaults = .standard, keeping tank: Habitat? = nil) {
        if let tank {
            let uids = Set(tank.items.map(\.uid))
            state.things = state.things.filter { uids.contains($0.key) }
            state.places = state.places.filter { $0.value.uid.map { uids.contains($0) } ?? true }
        }
        tidyPlaces()
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: HabitatKnowledge.key) }
        dirty = false
    }

    /// Forgets it all: everything in the tank is new to it again.
    func forget() {
        state = State(seeded: true)
        dirty = true
    }

    // MARK: Things

    /// Brought up to date with the tank as it is: anything in it it has no
    /// word of is new to it — unless this is the first tank it has had at
    /// all, when it knows it all already.
    func meet(_ tank: Habitat) {
        let first = !state.seeded
        for it in tank.items where state.things[it.uid] == nil {
            state.things[it.uid] = Acquaintance(stage: first ? .familiar : .unknown, exposure: first ? 1 : 0, kind: it.kind.rawValue)
            dirty = true
        }
        if first {
            state.seeded = true
            dirty = true
        }
    }

    func acquaintance(_ uid: String) -> Acquaintance? { state.things[uid] }

    func stage(of uid: String) -> Acquaintance.Stage { state.things[uid]?.stage ?? .unknown }

    func isFamiliar(_ uid: String) -> Bool { stage(of: uid) == .familiar }

    /// How used it is to things of this kind, 0…1.
    func kindFamiliarity(_ k: HabitatItemKind) -> CGFloat { state.kinds[k.rawValue] ?? 0 }

    private func edit(_ it: HabitatItem, _ f: (inout Acquaintance) -> Void) {
        var a = state.things[it.uid] ?? Acquaintance(kind: it.kind.rawValue)
        f(&a)
        a.exposure = clamp(a.exposure, 0, 1)
        a.unease = clamp(a.unease, 0, 1)
        state.things[it.uid] = a
        dirty = true
    }

    /// It has seen it: it knows it is there now, and how it feels about it
    /// to begin with (`unease`, 0…1).
    func notice(_ it: HabitatItem, unease: CGFloat) {
        edit(it) { a in
            guard a.stage == .unknown else { return }
            a.stage = .noticed
            a.unease = max(a.unease, unease)
        }
    }

    /// Looking into it now — or not any more (`false`), for now.
    func investigating(_ it: HabitatItem, _ on: Bool) {
        edit(it) { a in
            guard a.stage != .familiar else { return }
            a.stage = on ? .investigating : .noticed
        }
    }

    /// Time near it, or something learned of it: `amount` of the way to
    /// knowing it (sped up by knowing its kind). True if that has made it
    /// familiar.
    @discardableResult
    func expose(_ it: HabitatItem, by amount: CGFloat) -> Bool {
        guard amount > 0, state.things[it.uid]?.stage != .familiar else { return false }
        let kind = kindFamiliarity(it.kind)
        var became = false
        edit(it) { a in
            if a.stage == .unknown { a.stage = .noticed }
            a.exposure += amount * (1 + 1.2 * kind)
            // (It settles as it gets to know it.)
            a.unease -= amount * 0.6
            if a.exposure >= 1 {
                a.stage = .familiar
                a.unease = 0
                became = true
            }
        }
        if became { state.kinds[it.kind.rawValue] = min(1, kind + 0.35) }
        return became
    }

    /// Something about it has unsettled it: it moved, or it gave it a start.
    /// A familiar thing stays familiar, but is looked at again.
    func unsettle(_ it: HabitatItem, by amount: CGFloat) {
        edit(it) { a in
            a.unease += amount
            if a.stage != .familiar { a.exposure -= amount * 0.25 }
        }
    }

    /// Unease wears off with time.
    func calm(for dt: CGFloat) {
        for (k, a) in state.things where a.unease > 0 {
            state.things[k]!.unease = max(0, a.unease - dt / 40)
        }
    }

    /// Likes it a little more (or, negative, less).
    func warm(to it: HabitatItem, by amount: CGFloat) {
        guard amount != 0 else { return }
        edit(it) { a in
            let toward: CGFloat = amount > 0 ? 1 : -1
            a.fond = clamp(a.fond + amount * (toward - a.fond) * toward, -1, 1)
        }
    }

    /// It went to it on purpose, just now.
    func visited(_ it: HabitatItem) {
        edit(it) { $0.lastVisit = state.clock }
    }

    /// How long ago it last went to it on purpose (nil: never).
    func sinceVisit(_ uid: String) -> Double? {
        guard let v = state.things[uid]?.lastVisit, v >= 0 else { return nil }
        return state.clock - v
    }

    /// Its favourite of the things `among` (by uid): the one it likes
    /// best, if it likes any of them at all.
    func favouriteThing(among uids: [String]) -> String? {
        uids.compactMap { u in state.things[u].map { (u, $0.fond) } }.filter { $0.1 > 0.08 }.max { $0.1 < $1.1 }?.0
    }

    // MARK: Places

    /// Seconds it has lived in its tank with this knowledge.
    var clock: Double { state.clock }
    private var fadeDue: Double = 0

    /// Time goes by: frights wear off, and seeing prey about; catches and
    /// fondness much more slowly.
    func tick(_ dt: CGFloat) {
        state.clock += Double(dt)
        fadeDue += Double(dt)
        guard fadeDue >= 30 else { return }
        let d = fadeDue
        fadeDue = 0
        func half(_ h: Double) -> CGFloat { CGFloat(pow(0.5, d / h)) }
        let fright = half(2 * 3600), seen = half(3600), caught = half(24 * 3600), fond = half(4 * 86_400), way = half(3 * 86_400)
        for (k, var r) in state.places {
            r.frights *= fright
            r.sightings *= seen
            r.catches *= caught
            for (u, f) in r.fond { r.fond[u] = f * fond }
            state.places[k] = r
        }
        for (k, v) in state.routes { state.routes[k] = v * way }
        for (k, a) in state.things where a.fond != 0 { state.things[k]!.fond = a.fond * fond }
        dirty = true
    }

    func record(_ key: String) -> PlaceRecord? { state.places[key] }
    var places: [String: PlaceRecord] { state.places }

    private func editPlace(_ key: String, at p: V2, uid: String?, _ f: (inout PlaceRecord) -> Void) {
        var r = state.places[key] ?? PlaceRecord(x: p.x, y: p.y, uid: uid)
        r.x = p.x
        r.y = p.y
        f(&r)
        state.places[key] = r
        dirty = true
    }

    /// It has stopped at a place (not just gone by).
    func stopped(at key: String, _ p: V2, uid: String?) {
        editPlace(key, at: p, uid: uid) { r in
            r.visits += 1
            r.last = state.clock
        }
    }

    /// It went there for `use`, and how that went: 1 just right, 0 nothing
    /// to it, -1 badly (woken, frightened, couldn't get there).
    func used(_ key: String, _ p: V2, uid: String?, for use: PlaceUse, how: CGFloat) {
        editPlace(key, at: p, uid: uid) { r in
            let f = r.fond[use.rawValue] ?? 0
            let a = clamp(how, -1, 1) * (how >= 0 ? 0.28 : 0.4)
            let toward: CGFloat = a >= 0 ? 1 : -1
            r.fond[use.rawValue] = clamp(f + a * (toward - f) * toward, -1, 1)
            r.last = state.clock
        }
    }

    /// Settled there a while, calm: it grows on it, a little.
    func settled(at key: String, _ p: V2, uid: String?, for use: PlaceUse, secs: CGFloat) {
        editPlace(key, at: p, uid: uid) { r in
            let f = r.fond[use.rawValue] ?? 0
            r.fond[use.rawValue] = min(1, f + secs / 60 * 0.05 * (1 - f))
        }
    }

    func fright(at key: String, _ p: V2, uid: String?) {
        editPlace(key, at: p, uid: uid) { r in
            r.frights = min(3, r.frights + 1)
            for (u, f) in r.fond { r.fond[u] = f - 0.15 * (1 + f) }
        }
    }

    func caught(at key: String, _ p: V2, uid: String?) {
        editPlace(key, at: p, uid: uid) { r in
            r.catches = min(5, r.catches + 1)
            r.last = state.clock
        }
    }

    func sawPrey(at key: String, _ p: V2, uid: String?) {
        editPlace(key, at: p, uid: uid) { $0.sightings = min(3, $0.sightings + 0.25) }
    }

    /// Its favourite place for `use` of those that are still there
    /// (`exists`), if it has one.
    func favourite(for use: PlaceUse, where exists: (String) -> Bool) -> (key: String, record: PlaceRecord)? {
        var best: (key: String, record: PlaceRecord, f: CGFloat)?
        for (k, r) in state.places {
            let f = r.fond(use)
            guard f > 0.15, f > best?.f ?? 0, exists(k) else { continue }
            best = (k, r, f)
        }
        return best.map { ($0.key, $0.record) }
    }

    // MARK: Ways

    /// How well it knows a way over from one surface onto the next, 0…1.
    func route(_ key: String) -> CGFloat { state.routes[key] ?? 0 }

    /// It went over these on its way somewhere: `ok`, and it got there.
    func travelled(_ keys: [String], ok: Bool) {
        guard !keys.isEmpty else { return }
        for k in Set(keys) {
            let v = state.routes[k] ?? 0
            state.routes[k] = ok ? v + 0.3 * (1 - v) : v * 0.6
        }
        dirty = true
    }

    /// Keeps the places it has any feeling about, and the most visited of
    /// the rest: a few hundred at most.
    private func tidyPlaces() {
        guard state.places.count > 600 else { return }
        func worth(_ r: PlaceRecord) -> CGFloat { r.visits + r.fond.values.reduce(0) { $0 + abs($1) } * 8 + r.catches * 3 + r.frights * 2 }
        let keep = state.places.sorted { worth($0.value) > worth($1.value) }.prefix(450)
        state.places = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        if state.routes.count > 400 {
            state.routes = Dictionary(uniqueKeysWithValues: state.routes.sorted { $0.value > $1.value }.prefix(300).map { ($0.key, $0.value) })
        }
    }

    // MARK: Noticing

    /// How readily it notices a thing it doesn't know, as a chance a second:
    /// the nearer and bigger it is the likelier, far likelier if it moves
    /// (put in with a drop, carried about) — and only if it could see it at
    /// all. `size` is the thing's size for its own (1: about its own length
    /// across), `alert` how much it has its wits about it (asleep hardly at
    /// all; watching about, the most), `kind` how used it is to such things.
    static func noticeRate(distance d: CGFloat, sight: CGFloat, size: CGFloat, inView: Bool, motion: CGFloat,
                           alert: CGFloat, curiosity: CGFloat, kind: CGFloat) -> CGFloat {
        guard d < sight else { return 0 }
        // Close by it can hardly miss it; toward the edge of sight, only
        // now and then.
        let f = 1 - clamp(d / sight, 0, 1)
        let near = 0.1 + 2.3 * f * f
        let big = clamp(size, 0.35, 2.2)
        let seen: CGFloat = inView ? 1 : 0.2
        // Movement catches its eye — the more the nearer it is.
        let stir = 1 + clamp(motion, 0, 1) * (1 + 5 * f)
        return 0.12 * near * big * seen * stir * alert * lerp(0.45, 1.7, curiosity) * lerp(1, 0.6, kind)
    }
}
