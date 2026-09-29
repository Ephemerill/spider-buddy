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
        }
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
