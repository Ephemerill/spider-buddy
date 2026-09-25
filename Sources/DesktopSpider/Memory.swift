import CoreGraphics
import Foundation

// MARK: - Memory
//
// What it has been through, and what that has made of it. The Studio's
// personality is who it is and stays that way; on top of it, what happens
// to it leaves small, fading marks — a shy spider stroked every day grows a
// little easier about the pointer, one given a fright is warier for a
// while, one that keeps catching things goes after the next with more
// conviction. Nothing here decides what it does: the marks nudge the same
// personality sliders (and two it can only learn) that every weighted
// choice it makes already reads, so the change shows up everywhere at once
// and nowhere as a rule.
//
// Every memory has two parts: how it feels about it now (quick to come,
// gone within the hour) and what it learned from it (slow to build, fading
// over days). Doing the same thing again reinforces both, with diminishing
// returns. Nothing is ever needed of you: left be, it just grows more
// independent, and whatever it learned fades back toward who it was.

/// Something that happened to it worth remembering.
enum Experience: String, Codable, CaseIterable {
    case petted       // stroked with the pointer
    case greeted      // clicked on to say hello; you came back to it
    case company      // you about, the pointer near and unhurried (by the minute)
    case carried      // picked up and set down, or dropped gently
    case thrown       // flung hard, or shaken off the pointer
    case startled     // a fright: a pop-up, woken by the pointer
    case chased       // the pointer dashing right over it, again and again
    case played       // the laser dot, catching the pointer, peek-a-boo, tag
    case fed          // a meal
    case huntWon      // a hunt that ended with it catching something
    case huntMissed   // a pounce at something that came up empty
    case alone        // nobody about for a good while (by the minute)

    /// How it is remembered: how long the feeling and the lesson last, how
    /// much one of these teaches it, and how it likes the place it happened.
    fileprivate var imprint: Imprint {
        let min: TimeInterval = 60, day: TimeInterval = 86_400
        switch self {
        case .petted:     return Imprint(mood: 15 * min, lasting: 10 * day, rate: 0.05, comfort: 0.6)
        case .greeted:    return Imprint(mood: 10 * min, lasting: 7 * day, rate: 0.03, comfort: 0.3)
        case .company:    return Imprint(mood: 20 * min, lasting: 7 * day, rate: 0.04, comfort: 0.3)
        case .carried:    return Imprint(mood: 10 * min, lasting: 5 * day, rate: 0.03, comfort: 0)
        case .thrown:     return Imprint(mood: 15 * min, lasting: 4 * day, rate: 0.04, comfort: -0.3)
        case .startled:   return Imprint(mood: 12 * min, lasting: 3 * day, rate: 0.03, comfort: -1)
        case .chased:     return Imprint(mood: 10 * min, lasting: 3 * day, rate: 0.03, comfort: -0.4)
        case .played:     return Imprint(mood: 20 * min, lasting: 7 * day, rate: 0.04, comfort: 0.4)
        case .fed:        return Imprint(mood: 30 * min, lasting: 5 * day, rate: 0.03, comfort: 0.8)
        case .huntWon:    return Imprint(mood: 20 * min, lasting: 10 * day, rate: 0.05, comfort: 0.4)
        case .huntMissed: return Imprint(mood: 10 * min, lasting: 4 * day, rate: 0.03, comfort: 0)
        case .alone:      return Imprint(mood: 30 * min, lasting: 5 * day, rate: 0.03, comfort: 0)
        }
    }

    /// What one full measure of this does to its character, as felt by who
    /// it is: the same fling is a thrill to a bold, playful spider and a
    /// fright to a timid one.
    func feels(_ p: Personality) -> TraitShift {
        var s = TraitShift()
        switch self {
        case .petted:
            s.affection = 1; s.bravery = 0.6; s.curiosity = 0.3; s.laziness = 0.15; s.roaming = -0.3
        case .greeted:
            s.affection = 0.8; s.curiosity = 0.5; s.bravery = 0.4; s.roaming = -0.2
        case .company:
            s.affection = 0.5; s.bravery = 0.5; s.curiosity = 0.3; s.roaming = -0.4
        case .carried:
            s.bravery = 0.4; s.affection = 0.3; s.curiosity = 0.1
        case .thrown:
            let joy = (p.bravery + p.playfulness) - 1          // -1 … 1
            s.playfulness = 0.1 + 0.6 * max(joy, 0); s.energy = 0.3 * max(joy, 0)
            s.bravery = -0.1 - 0.7 * max(-joy, 0); s.affection = -0.4 * max(-joy, 0); s.roaming = 0.2 * max(-joy, 0)
        case .startled:
            s.bravery = -1; s.curiosity = -0.3; s.laziness = -0.2; s.energy = 0.1
        case .chased:
            let joy = p.playfulness * 2 - 1
            s.playfulness = 0.4 * max(joy, 0); s.energy = 0.3 * max(joy, 0)
            s.bravery = -0.2 - 0.8 * max(-joy, 0); s.curiosity = -0.3 * max(-joy, 0); s.roaming = 0.3 * max(-joy, 0)
        case .played:
            s.playfulness = 1; s.energy = 0.5; s.affection = 0.3; s.laziness = -0.4; s.bravery = 0.2
        case .fed:
            s.laziness = 0.3; s.prowess = 0.2; s.affection = 0.2; s.energy = -0.1
        case .huntWon:
            s.prowess = 1; s.bravery = 0.3; s.energy = 0.2
        case .huntMissed:
            s.prowess = -0.6; s.bravery = -0.1
        case .alone:
            s.roaming = 1; s.curiosity = 0.4; s.energy = 0.2
        }
        return s
    }
}

fileprivate struct Imprint {
    /// Half-lives, in seconds of its life: of the feeling, and of the lesson.
    let mood: TimeInterval
    let lasting: TimeInterval
    /// How much of the way to a settled lesson one full measure takes it.
    let rate: CGFloat
    /// How it comes to feel about the place this happened: good things
    /// make a favourite spot, frights somewhere it would rather not be.
    let comfort: CGFloat
}

// MARK: - Learned traits

/// A nudge to each side of its character, in slider units: the six
/// personality sliders, plus two it only ever learns — how sure of itself
/// it is on a hunt, and how much it goes off exploring on its own.
struct TraitShift: Codable, Equatable {
    var energy: CGFloat = 0
    var curiosity: CGFloat = 0
    var bravery: CGFloat = 0
    var playfulness: CGFloat = 0
    var affection: CGFloat = 0
    var laziness: CGFloat = 0
    var prowess: CGFloat = 0
    var roaming: CGFloat = 0

    static let zero = TraitShift()
    static let traits: [WritableKeyPath<TraitShift, CGFloat>] =
        [\.energy, \.curiosity, \.bravery, \.playfulness, \.affection, \.laziness, \.prowess, \.roaming]

    func map(_ f: (CGFloat) -> CGFloat) -> TraitShift {
        var s = self
        for k in TraitShift.traits { s[keyPath: k] = f(s[keyPath: k]) }
        return s
    }
    static func + (a: TraitShift, b: TraitShift) -> TraitShift {
        var s = a
        for k in traits { s[keyPath: k] += b[keyPath: k] }
        return s
    }
    static func * (a: TraitShift, k: CGFloat) -> TraitShift { a.map { $0 * k } }
    static func += (a: inout TraitShift, b: TraitShift) { a = a + b }

    /// Toward `target` by `k` (0…1) of the way.
    func approaching(_ target: TraitShift, _ k: CGFloat) -> TraitShift { self + (target + self * -1) * k }

    /// The most any one trait moves from what the Studio says, lessons and
    /// feelings together: enough to see, never enough to make a shy spider
    /// a bold one.
    static let most: CGFloat = 0.2

    /// How much more (or less) often it does a habit this shift leans
    /// toward: a spider that has learned to roam leaps, drops and swings
    /// off more; a homebody less. A habit dialled to never stays never.
    func lean(_ habit: KeyPath<Habits, CGFloat>) -> CGFloat {
        switch habit {
        case \Habits.wander, \Habits.leap, \Habits.rappel, \Habits.swing: return 1 + roaming * 2.5
        default: return 1
        }
    }
}

extension Personality {
    /// This personality as shifted by what it has learned.
    func shifted(by s: TraitShift) -> Personality {
        var p = self
        p.energy = clamp(energy + s.energy, 0, 1)
        p.curiosity = clamp(curiosity + s.curiosity, 0, 1)
        p.bravery = clamp(bravery + s.bravery, 0, 1)
        p.playfulness = clamp(playfulness + s.playfulness, 0, 1)
        p.affection = clamp(affection + s.affection, 0, 1)
        p.laziness = clamp(laziness + s.laziness, 0, 1)
        return p
    }
}

extension PreyKind {
    /// What its memory calls this kind of prey.
    var memoryName: String { "prey.\(self)" }
}

// MARK: - Places

/// Where something happened, as it thinks of it: a patch of the screen (the
/// windows move about; the top left of the screen does not), and the kind
/// of thing it was standing on. Inside the habitat it is a different world
/// and its places are kept apart.
struct Place: Equatable {
    var cell: String
    var surface: String

    static let columns = 6, rows = 4

    init(at p: V2, in frame: CGRect, on kind: SurfaceKind, habitat: Bool) {
        let fx = clamp((p.x - frame.minX) / max(frame.width, 1), 0, 0.999)
        let fy = clamp((p.y - frame.minY) / max(frame.height, 1), 0, 0.999)
        let world = habitat ? "tank" : "desk"
        cell = "place.\(world).\(Int(fx * CGFloat(Place.columns))).\(Int(fy * CGFloat(Place.rows)))"
        surface = "surface.\(world).\(kind)"
    }
}

// MARK: - The memory itself

/// One thing remembered: how it feels about it now, what it has learned
/// from it, how many times, and when last.
struct Trace: Codable {
    var mood: CGFloat = 0
    var lasting: CGFloat = 0
    var times: CGFloat = 0
    var last: TimeInterval = -1
}

/// How it feels about some particular thing — a kind of prey, a place,
/// and in time friends, toys, corners of its habitat — from -1 (would
/// rather not) to 1 (a favourite). Anything can be remembered by name;
/// the name's first part says how long the feeling lasts.
struct Fondness: Codable {
    var value: CGFloat = 0
    var times: CGFloat = 0
    var last: TimeInterval = -1
}

/// What is going on around it right now, told to its memory every second
/// or so.
struct Moment {
    /// You are about, with the pointer close by and not dashing about.
    var company = false
    /// Nothing from you for a good while.
    var alone = false
    /// Settled — resting, asleep, grooming, eating — somewhere.
    var calm = false
    /// Where it is, if it is standing on something.
    var place: Place?
}

final class SpiderMemory {
    struct State: Codable {
        var version = 1
        /// Seconds of its life it has lived with this memory.
        var clock: TimeInterval = 0
        var savedAt = Date()
        var traces: [String: Trace] = [:]
        var fondness: [String: Fondness] = [:]
    }

    private(set) var state: State
    /// Changed since it was last saved.
    private(set) var dirty = false
    /// The shift it is showing now: eased toward what its memories add up
    /// to, so nothing about it changes from one moment to the next.
    private(set) var shift = TraitShift.zero

    static let key = "memory"
    /// Time away (the app closed, the Mac off) counts toward forgetting, but
    /// only up to a few days: a fortnight's holiday doesn't wipe it clean.
    static let mostAway: TimeInterval = 3 * 86_400

    init(state: State = State()) {
        self.state = state
    }

    // MARK: Keeping it

    static func load(from defaults: UserDefaults = .standard) -> SpiderMemory {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(State.self, from: data) else { return SpiderMemory() }
        let m = SpiderMemory(state: s)
        m.fade(for: min(max(0, Date().timeIntervalSince(s.savedAt)), mostAway))
        return m
    }

    func save(to defaults: UserDefaults = .standard) {
        state.savedAt = Date()
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: SpiderMemory.key) }
        dirty = false
    }

    /// Forgets everything: back to just who the Studio says it is.
    func forget() {
        state = State()
        shift = .zero
        dirty = true
    }

    // MARK: Living

    /// Something happened. `amount` is how much of one: a quick stroke is
    /// less than a long one; the by-the-minute experiences come in slivers.
    func record(_ e: Experience, _ amount: CGFloat = 1, at place: Place? = nil) {
        let a = clamp(amount, 0, 3)
        guard a > 0 else { return }
        let im = e.imprint
        var tr = state.traces[e.rawValue] ?? Trace()
        tr.mood += a * 0.5 * (1 - tr.mood)
        tr.lasting += a * im.rate * (1 - tr.lasting)
        tr.mood = min(tr.mood, 1)
        tr.lasting = min(tr.lasting, 1)
        tr.times += a
        tr.last = state.clock
        state.traces[e.rawValue] = tr
        if let place, im.comfort != 0 {
            warm(to: place.cell, by: a * im.comfort * 0.15)
            warm(to: place.surface, by: a * im.comfort * 0.06)
        }
        dirty = true
    }

    /// Feels a little more (or, negative, less) fond of something.
    func warm(to subject: String, by amount: CGFloat) {
        guard amount != 0 else { return }
        var f = state.fondness[subject] ?? Fondness()
        let toward: CGFloat = amount > 0 ? 1 : -1
        f.value += amount * (toward - f.value) * toward
        f.value = clamp(f.value, -1, 1)
        f.times += abs(amount)
        f.last = state.clock
        state.fondness[subject] = f
        dirty = true
    }

    /// Comes across something, without feeling any particular way about it
    /// (yet): it only counts as met.
    func meet(_ subject: String) {
        var f = state.fondness[subject] ?? Fondness()
        f.times += 1
        f.last = state.clock
        state.fondness[subject] = f
        dirty = true
    }

    /// How many times it has come across something, and how long ago.
    func familiarity(with subject: String) -> (times: CGFloat, ago: TimeInterval?) {
        guard let f = state.fondness[subject] else { return (0, nil) }
        return (f.times, f.last < 0 ? nil : state.clock - f.last)
    }

    /// How it feels about something, -1…1; 0 for anything it doesn't know.
    func fondness(of subject: String) -> CGFloat { state.fondness[subject]?.value ?? 0 }

    /// How much it likes the look of a place, as a multiplier on how it
    /// would otherwise rate it: its favourite haunts pull it back, the
    /// spot where it got a fright less so.
    func appeal(of place: Place) -> CGFloat {
        clamp(1 + fondness(of: place.cell) * 0.6 + fondness(of: place.surface) * 0.4, 0.55, 1.7)
    }

    /// Another `dt` seconds of its life, and what is going on in it. The
    /// shift it shows eases toward what everything it remembers adds up to
    /// for a spider like `base`.
    func live(for dt: TimeInterval, _ now: Moment, base: Personality) {
        guard dt > 0 else { return }
        state.clock += dt
        fade(for: dt)
        let minutes = CGFloat(dt / 60)
        if now.company { record(.company, minutes / 10, at: now.place) }
        if now.alone { record(.alone, minutes / 10) }
        if now.calm, let p = now.place {
            // Somewhere it can settle is somewhere it comes to like.
            warm(to: p.cell, by: minutes / 15 * 0.12)
            warm(to: p.surface, by: minutes / 15 * 0.05)
        }
        shift = shift.approaching(target(for: base), CGFloat(1 - exp(-dt / 15)))
    }

    /// Straight to what it adds up to, with no easing: for when it is
    /// first given its memory.
    func settle(base: Personality) {
        shift = target(for: base)
    }

    /// The feelings wear off and the lessons fade, each at its own pace.
    private func fade(for dt: TimeInterval) {
        guard dt > 0 else { return }
        for (k, var tr) in state.traces {
            guard let e = Experience(rawValue: k) else { state.traces[k] = nil; continue }
            let im = e.imprint
            tr.mood *= CGFloat(pow(0.5, dt / im.mood))
            tr.lasting *= CGFloat(pow(0.5, dt / im.lasting))
            state.traces[k] = tr
        }
        for (k, var f) in state.fondness {
            f.value *= CGFloat(pow(0.5, dt / SpiderMemory.fondnessHalfLife(k)))
            // Long faded and long ago: let it go altogether.
            if abs(f.value) < 0.004, state.clock - f.last > 30 * 86_400 {
                state.fondness[k] = nil
            } else {
                state.fondness[k] = f
            }
        }
        dirty = true
    }

    private static func fondnessHalfLife(_ subject: String) -> TimeInterval {
        let day: TimeInterval = 86_400
        switch subject.prefix(while: { $0 != "." }) {
        case "prey": return 21 * day
        case "toy": return 21 * day
        case "place": return 10 * day
        case "surface": return 14 * day
        default: return 10 * day
        }
    }

    /// Everything it remembers, added up into a nudge to each trait: the
    /// lessons to a little, the feelings of the moment to a little more,
    /// and the two together never past `TraitShift.most`.
    func target(for base: Personality) -> TraitShift {
        var lasting = TraitShift.zero, mood = TraitShift.zero
        for (k, tr) in state.traces {
            guard let e = Experience(rawValue: k) else { continue }
            let f = e.feels(base)
            lasting += f * tr.lasting
            mood += f * tr.mood
        }
        let learned = lasting.map { 0.14 * tanh($0) }
        let felt = mood.map { 0.15 * tanh($0 / 0.8) }
        return (learned + felt).map { clamp($0, -TraitShift.most, TraitShift.most) }
    }

    /// The lessons alone, without the mood of the moment.
    func learned(for base: Personality) -> TraitShift {
        var lasting = TraitShift.zero
        for (k, tr) in state.traces {
            guard let e = Experience(rawValue: k) else { continue }
            lasting += e.feels(base) * tr.lasting
        }
        return lasting.map { 0.14 * tanh($0) }
    }

    func trace(_ e: Experience) -> Trace { state.traces[e.rawValue] ?? Trace() }

    // MARK: Telling you about it

    /// A line or two on how it has been shaped lately, for the panel.
    func summary(name: String, base: Personality) -> String {
        let l = learned(for: base)
        let words: [(CGFloat, String, String)] = [
            (l.bravery, "bolder", "warier"),
            (l.affection, "more affectionate", "more aloof"),
            (l.curiosity, "more curious", "less nosy"),
            (l.playfulness, "more playful", "quieter"),
            (l.energy, "livelier", "calmer"),
            (l.laziness, "more laid-back", "more restless"),
            (l.prowess, "a surer hunter", "a less sure hunter"),
            (l.roaming, "more independent", "more of a homebody"),
        ]
        let said = words.filter { abs($0.0) >= 0.025 }.sorted { abs($0.0) > abs($1.0) }.prefix(3)
            .map { $0.0 > 0 ? $0.1 : $0.2 }
        var out: String
        if said.isEmpty {
            out = state.clock < 3600 ? "\(name) is just getting to know you." : "\(name) is much as the Studio made it."
        } else {
            let list = said.count == 1 ? said[0]
                : said.dropLast().joined(separator: ", ") + " and " + said.last!
            out = "Lately \(name) has grown a little \(list)."
        }
        let s = shift
        if s.bravery - l.bravery < -0.04 { out += " A bit jumpy just now." }
        else if s.playfulness - l.playfulness > 0.04 { out += " Full of beans just now." }
        else if s.affection - l.affection > 0.04 { out += " Feeling fond of you just now." }
        if let fav = favourite(prefix: "prey."), let kind = PreyKind.allCases.first(where: { "\($0)" == fav }) {
            out += " Favourite snack: \(kind.label.lowercased())s."
        }
        if let fav = favourite(prefix: "toy."), let kind = ToyKind.allCases.first(where: { "\($0)" == fav }) {
            out += " Favourite toy: the \(kind.label.lowercased())."
        }
        return out
    }

    /// The best-liked thing of a family ("prey.", "place.desk."), by name.
    func favourite(prefix: String) -> String? {
        let best = state.fondness.filter { $0.key.hasPrefix(prefix) && $0.value.value > 0.1 }
            .max { $0.value.value < $1.value.value }
        return best.map { String($0.key.dropFirst(prefix.count)) }
    }
}
