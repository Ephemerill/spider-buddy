import AppKit

// MARK: - Weather in the habitat
//
// The tank has weather of its own. Left to itself it comes and goes: a
// spell of something rolls in, stays a while and clears, then clear skies,
// then something else — drawn from what suits the scenery (snow in the
// snowfall, sandstorms in the desert, downpours in the jungle), and what
// comes can be changed for each scenery. It can also be kept to one kind
// for good, or follow the weather outside.
//
// This is the model: what the weather is doing and when. HabitatWeather.swift
// draws it, and the spider feels it (`WeatherFeel`, in Spider.swift).

enum WeatherKind: String, CaseIterable {
    case clear, sunny, cloudy, fog, drizzle, rain, storm, hail, snow, blizzard, windy, sandstorm, sunshower, starfall, aurora

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .sunny: return "Blazing Sun"
        case .cloudy: return "Overcast"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .storm: return "Thunderstorm"
        case .hail: return "Hail"
        case .snow: return "Snow"
        case .blizzard: return "Blizzard"
        case .windy: return "Gale"
        case .sandstorm: return "Sandstorm"
        case .sunshower: return "Sun Shower"
        case .starfall: return "Shooting Stars"
        case .aurora: return "Northern Lights"
        }
    }

    /// What it looks like, in a word or two, for the tiles.
    var blurb: String {
        switch self {
        case .clear: return "Just the scenery"
        case .sunny: return "Glare and heat haze"
        case .cloudy: return "Grey skies"
        case .fog: return "Thick, drifting mist"
        case .drizzle: return "A fine, light rain"
        case .rain: return "Puddles and splashes"
        case .storm: return "Lightning and thunder"
        case .hail: return "Ice, bouncing"
        case .snow: return "It settles on things"
        case .blizzard: return "Snow on a gale"
        case .windy: return "Everything blows about"
        case .sandstorm: return "A wall of dust"
        case .sunshower: return "Rain, sun and a rainbow"
        case .starfall: return "A meteor shower"
        case .aurora: return "Curtains of light"
        }
    }

    var symbol: String {
        switch self {
        case .clear: return "sun.min"
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .storm: return "cloud.bolt.rain.fill"
        case .hail: return "cloud.hail.fill"
        case .snow: return "cloud.snow.fill"
        case .blizzard: return "wind.snow"
        case .windy: return "wind"
        case .sandstorm: return "sun.dust.fill"
        case .sunshower: return "cloud.sun.rain.fill"
        case .starfall: return "moon.stars.fill"
        case .aurora: return "sparkles"
        }
    }

    /// Asking for it, in the menu.
    var summon: String {
        switch self {
        case .clear: return "Clear the Sky"
        case .sunny: return "Bring Out the Sun"
        case .cloudy: return "Cloud Over"
        case .fog: return "Roll In the Fog"
        case .drizzle: return "Make It Drizzle"
        case .rain: return "Make It Rain"
        case .storm: return "Brew a Thunderstorm"
        case .hail: return "Make It Hail"
        case .snow: return "Make It Snow"
        case .blizzard: return "Whip Up a Blizzard"
        case .windy: return "Blow a Gale"
        case .sandstorm: return "Kick Up a Sandstorm"
        case .sunshower: return "A Sun Shower"
        case .starfall: return "Shooting Stars"
        case .aurora: return "The Northern Lights"
        }
    }

    /// What it is made of, at its height.
    var recipe: WeatherRecipe {
        var r = WeatherRecipe()
        switch self {
        case .clear:
            break
        case .sunny:
            r.sun = 1; r.heat = 0.8; r.wind = 0.08; r.gust = 0.2
        case .cloudy:
            r.cloud = 0.9; r.dark = 0.22; r.wind = 0.25; r.gust = 0.3; r.cold = 0.1
        case .fog:
            r.fog = 1; r.cloud = 0.35; r.dark = 0.15; r.cold = 0.25; r.wind = 0.03
        case .drizzle:
            r.rain = 0.3; r.cloud = 0.75; r.dark = 0.25; r.wind = 0.12; r.gust = 0.2; r.cold = 0.1
        case .rain:
            r.rain = 0.75; r.cloud = 0.95; r.storm = 0.35; r.dark = 0.4; r.wind = 0.3; r.gust = 0.4; r.cold = 0.15
        case .storm:
            r.rain = 1; r.cloud = 1; r.storm = 1; r.dark = 0.62; r.wind = 0.7; r.gust = 0.9; r.lightning = 1; r.cold = 0.2
        case .hail:
            r.hail = 1; r.rain = 0.25; r.cloud = 1; r.storm = 0.8; r.dark = 0.5; r.wind = 0.45; r.gust = 0.6; r.lightning = 0.25; r.cold = 0.45
        case .snow:
            r.snow = 0.65; r.cloud = 0.85; r.dark = 0.18; r.wind = 0.12; r.gust = 0.2; r.cold = 0.8
        case .blizzard:
            r.snow = 1; r.cloud = 1; r.storm = 0.4; r.dark = 0.3; r.fog = 0.45; r.wind = 1; r.gust = 0.7; r.cold = 1
        case .windy:
            r.wind = 0.85; r.gust = 1; r.cloud = 0.3
        case .sandstorm:
            r.sand = 1; r.wind = 0.95; r.gust = 0.6; r.dark = 0.3; r.fog = 0.35; r.heat = 0.4
        case .sunshower:
            r.rain = 0.45; r.sun = 0.8; r.rainbow = 1; r.cloud = 0.2; r.wind = 0.1; r.gust = 0.2
        case .starfall:
            r.night = 1; r.stars = 1; r.dark = 0.35; r.cold = 0.1
        case .aurora:
            r.night = 1; r.aurora = 1; r.dark = 0.35; r.cold = 0.35
        }
        return r
    }

    /// Anything falling out of the sky.
    var falls: Bool { [.drizzle, .rain, .storm, .hail, .snow, .blizzard, .sandstorm, .sunshower].contains(self) }

    /// How long it takes to roll in (and to clear), in seconds.
    fileprivate var fade: ClosedRange<Double> {
        switch self {
        case .storm: return 30...50
        case .rain, .fog, .snow: return 22...40
        case .drizzle, .cloudy, .blizzard: return 16...28
        case .sunny, .aurora, .starfall: return 16...24
        case .windy, .sandstorm: return 8...16
        case .sunshower, .hail: return 8...12
        case .clear: return 8...12
        }
    }

    /// How long a spell of it lasts, compared with the usual.
    fileprivate var stay: Double {
        switch self {
        case .hail: return 0.35
        case .sunshower: return 0.5
        case .storm, .blizzard, .sandstorm: return 0.75
        case .fog, .cloudy: return 1.2
        default: return 1
        }
    }

    /// What it often turns into, rather than clearing.
    fileprivate var turnsInto: [WeatherKind] {
        switch self {
        case .cloudy: return [.drizzle, .rain]
        case .drizzle: return [.rain]
        case .rain: return [.storm, .drizzle, .sunshower]
        case .storm: return [.rain, .hail]
        case .hail: return [.rain]
        case .snow: return [.blizzard]
        case .blizzard: return [.snow]
        case .windy: return [.sandstorm, .rain]
        case .sandstorm: return [.windy]
        case .fog: return [.drizzle]
        case .starfall: return [.aurora]
        default: return []
        }
    }

    /// Rain of some sort: a rainbow may follow it.
    fileprivate var wet: Bool { [.drizzle, .rain, .storm, .sunshower].contains(self) }
}

/// Everything the weather is made of, 0…1 each: what falls, what the sky
/// and the light do, the wind, and how it feels.
struct WeatherRecipe: Equatable {
    var rain: CGFloat = 0, snow: CGFloat = 0, hail: CGFloat = 0, sand: CGFloat = 0
    /// Grey cloud over the sky, and dark storm cloud over that.
    var cloud: CGFloat = 0, storm: CGFloat = 0
    /// How much the light goes, and how thick the mist is.
    var dark: CGFloat = 0, fog: CGFloat = 0
    var sun: CGFloat = 0
    /// How hard the wind blows on average, and how much it gusts.
    var wind: CGFloat = 0, gust: CGFloat = 0
    var lightning: CGFloat = 0
    var cold: CGFloat = 0, heat: CGFloat = 0
    var rainbow: CGFloat = 0
    /// The sky gone to night, shooting stars across it, the northern lights.
    var night: CGFloat = 0, stars: CGFloat = 0, aurora: CGFloat = 0

    static func + (a: WeatherRecipe, b: WeatherRecipe) -> WeatherRecipe {
        var r = a
        r.rain += b.rain; r.snow += b.snow; r.hail += b.hail; r.sand += b.sand
        r.cloud += b.cloud; r.storm += b.storm; r.dark += b.dark; r.fog += b.fog
        r.sun += b.sun; r.wind += b.wind; r.gust += b.gust; r.lightning += b.lightning
        r.cold += b.cold; r.heat += b.heat; r.rainbow += b.rainbow
        r.night += b.night; r.stars += b.stars; r.aurora += b.aurora
        return r
    }

    static func * (a: WeatherRecipe, k: CGFloat) -> WeatherRecipe {
        var r = a
        r.rain *= k; r.snow *= k; r.hail *= k; r.sand *= k
        r.cloud *= k; r.storm *= k; r.dark *= k; r.fog *= k
        r.sun *= k; r.wind *= k; r.gust *= k; r.lightning *= k
        r.cold *= k; r.heat *= k; r.rainbow *= k
        r.night *= k; r.stars *= k; r.aurora *= k
        return r
    }

    /// Each channel held to 0…1 (two spells crossing can add up past it).
    var clamped: WeatherRecipe {
        func c(_ v: CGFloat) -> CGFloat { min(max(v, 0), 1) }
        var r = self
        r.rain = c(r.rain); r.snow = c(r.snow); r.hail = c(r.hail); r.sand = c(r.sand)
        r.cloud = c(r.cloud); r.storm = c(r.storm); r.dark = c(r.dark); r.fog = c(r.fog)
        r.sun = c(r.sun); r.wind = c(r.wind); r.gust = c(r.gust); r.lightning = c(r.lightning)
        r.cold = c(r.cold); r.heat = c(r.heat); r.rainbow = c(r.rainbow)
        r.night = c(r.night); r.stars = c(r.stars); r.aurora = c(r.aurora)
        return r
    }
}

/// The weather at a moment: every channel blended from whatever is
/// coming and going, the wind as it blows right now (signed: + blows to
/// the right, gusts and all), and the kind most in evidence.
struct WeatherConditions: Equatable {
    var mix = WeatherRecipe()
    var windNow: CGFloat = 0
    var shown: WeatherKind = .clear
    /// How far in `shown` is, 0…1.
    var strength: CGFloat = 0

    static let calm = WeatherConditions()
}

extension Biome {
    /// The weather that comes naturally to it, and how often, relative to
    /// the rest.
    var naturalWeather: [(kind: WeatherKind, weight: Double)] {
        switch self {
        case .forest: return [(.cloudy, 3), (.drizzle, 2), (.rain, 3), (.storm, 1.2), (.fog, 2), (.windy, 1.5), (.sunshower, 1), (.sunny, 1)]
        case .jungle: return [(.rain, 4), (.storm, 2), (.drizzle, 2), (.fog, 2.5), (.sunshower, 1.5), (.sunny, 1), (.cloudy, 1)]
        case .desert: return [(.sunny, 4), (.windy, 2), (.sandstorm, 2), (.cloudy, 0.6), (.storm, 0.5), (.starfall, 0.6)]
        case .meadow: return [(.sunny, 3), (.cloudy, 2), (.drizzle, 1.5), (.rain, 2), (.storm, 0.8), (.windy, 1.5), (.sunshower, 1.5), (.hail, 0.5)]
        case .cave: return [(.fog, 3), (.drizzle, 2), (.rain, 0.6)]
        case .beach: return [(.sunny, 3), (.windy, 2.5), (.cloudy, 1.5), (.rain, 1.5), (.storm, 1), (.sunshower, 1), (.fog, 1)]
        case .tundra: return [(.snow, 4), (.blizzard, 1.5), (.windy, 1.5), (.fog, 1.5), (.cloudy, 1), (.aurora, 2)]
        case .night: return [(.fog, 2), (.drizzle, 1), (.rain, 1.5), (.storm, 1), (.windy, 1), (.starfall, 2), (.aurora, 1), (.snow, 0.5)]
        }
    }

    /// Has a sky a rainbow could be seen in.
    var hasOpenSky: Bool { self != .cave }
}

// MARK: - Settings

/// How the tank's weather is run. Kept apart from the habitat's layout (and
/// its undo), under a key of its own.
struct WeatherSettings: Equatable {
    enum Mode: String, CaseIterable {
        /// Comes and goes on its own, from each scenery's list.
        case changing
        /// One kind, for good (`always`) — clear skies included.
        case always
        /// Whatever it is doing where you are.
        case outside
    }
    var mode: Mode = .changing
    var always: WeatherKind = .rain
    /// Each scenery's list, where it has been changed from its own.
    var custom: [Biome: [WeatherKind]] = [:]
    /// How often it changes, 0 (slowly) … 1 (often).
    var pace: CGFloat = 0.5
    /// How much of the time there is weather rather than clear skies, 0 … 1.
    var amount: CGFloat = 0.5

    static let key = "habitatWeather"

    /// What comes to this scenery, in the order the picker shows them.
    func rotation(_ b: Biome) -> [WeatherKind] {
        let list = custom[b] ?? b.naturalWeather.map(\.kind)
        return WeatherKind.allCases.filter { $0 != .clear && list.contains($0) }
    }

    /// The rotation with how often each comes: its own weight where it
    /// comes naturally, a fair share where it was added.
    func weights(_ b: Biome) -> [(kind: WeatherKind, weight: Double)] {
        let natural = Dictionary(b.naturalWeather.map { ($0.kind, $0.weight) }, uniquingKeysWith: { a, _ in a })
        return rotation(b).map { ($0, natural[$0] ?? 1.6) }
    }

    func isCustom(_ b: Biome) -> Bool {
        guard let c = custom[b] else { return false }
        return Set(c) != Set(b.naturalWeather.map(\.kind))
    }

    mutating func toggle(_ k: WeatherKind, in b: Biome) {
        guard k != .clear else { return }
        var list = rotation(b)
        if let i = list.firstIndex(of: k) { list.remove(at: i) } else { list.append(k) }
        custom[b] = list
        if !isCustom(b) { custom[b] = nil }
    }

    mutating func reset(_ b: Biome) { custom[b] = nil }

    static func load() -> WeatherSettings {
        var s = WeatherSettings()
        guard let d = UserDefaults.standard.dictionary(forKey: key) else { return s }
        if let m = (d["mode"] as? String).flatMap(Mode.init) { s.mode = m }
        if let k = (d["always"] as? String).flatMap(WeatherKind.init) { s.always = k }
        if let p = d["pace"] as? Double { s.pace = CGFloat(min(max(p, 0), 1)) }
        if let a = d["amount"] as? Double { s.amount = CGFloat(min(max(a, 0), 1)) }
        if let c = d["custom"] as? [String: [String]] {
            for (b, kinds) in c {
                guard let biome = Biome(rawValue: b) else { continue }
                s.custom[biome] = kinds.compactMap(WeatherKind.init)
            }
        }
        return s
    }

    func save() {
        var c: [String: [String]] = [:]
        for (b, kinds) in custom { c[b.rawValue] = kinds.map(\.rawValue) }
        UserDefaults.standard.set(["mode": mode.rawValue, "always": always.rawValue,
                                   "pace": Double(pace), "amount": Double(amount), "custom": c] as [String: Any], forKey: WeatherSettings.key)
    }
}

// MARK: - The clock

/// Runs the weather: which spells are in, how far, and what comes next.
/// It keeps wall-clock time — shut the tank for an hour and the weather
/// has moved on when it opens again — and it is saved as it goes, so it
/// carries on across launches.
final class WeatherClock {
    struct Spell: Codable, Equatable {
        var kind: String
        /// Rolling in from `start`, all in by `full`, clearing from
        /// `leave`, gone at `end` (seconds since the reference date).
        var start: Double
        var full: Double
        var leave: Double
        var end: Double
        /// Which way its wind blows, ±1.
        var dir: Double
        /// Decided what follows it.
        var planned = false

        var weather: WeatherKind { WeatherKind(rawValue: kind) ?? .clear }

        func strength(at now: Double) -> CGFloat {
            if now <= start || now >= end { return 0 }
            if now < full { return smoothstep(CGFloat((now - start) / max(full - start, 0.01))) }
            if now < leave { return 1 }
            return 1 - smoothstep(CGFloat((now - leave) / max(end - leave, 0.01)))
        }
    }

    private struct Saved: Codable {
        var spells: [Spell]
        var nextAt: Double?
        var rainbowFrom: Double
        var rainbowTo: Double
    }

    /// A spell kept for good ends here: never, in practice (and JSON has no
    /// infinity).
    static let forever: Double = 1e12
    static let saveKey = "habitatWeatherNow"

    private(set) var spells: [Spell] = []
    /// Clear skies until then, before the next spell (changing mode).
    private(set) var nextAt: Double?
    private var rainbowFrom: Double = 0
    private var rainbowTo: Double = 0

    var settings: WeatherSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save()
            settle(now: WeatherClock.now, was: oldValue)
        }
    }
    var biome: Biome = .forest {
        didSet { if biome != oldValue { settle(now: WeatherClock.now, was: settings) } }
    }
    /// The weather outside, when it is known.
    var outside: WeatherKind? {
        didSet { if outside != oldValue, settings.mode == .outside { settle(now: WeatherClock.now, was: settings) } }
    }
    /// Something changed that the tank should say or show (a new spell).
    var onChange: (() -> Void)?

    /// Tools only: nothing is written to the prefs.
    var persists = true

    static var now: Double { Date().timeIntervalSinceReferenceDate }

    init(settings: WeatherSettings = .load(), biome: Biome) {
        self.settings = settings
        self.biome = biome
        restore()
        settle(now: WeatherClock.now, was: settings, fresh: true)
    }

    // MARK: Reading it

    /// The weather now, everything blended. `clock` runs the gusts: any
    /// steady time in seconds.
    func conditions(at now: Double = WeatherClock.now, clock: CGFloat) -> WeatherConditions {
        advance(now)
        var c = WeatherConditions()
        var mix = WeatherRecipe()
        var wind: CGFloat = 0
        var best: CGFloat = 0
        var bestStart = -Double.greatestFiniteMagnitude
        for s in spells {
            let k = s.strength(at: now)
            guard k > 0 else { continue }
            let r = s.weather.recipe
            mix = mix + r * k
            wind += r.wind * k * CGFloat(s.dir)
            // (The newer of two that are as far in as each other.)
            if k > best + 0.001 || (abs(k - best) <= 0.001 && s.start > bestStart) {
                best = k
                bestStart = s.start
                c.shown = s.weather
            }
        }
        c.strength = best
        // A rainbow, after the rain.
        if now > rainbowFrom, now < rainbowTo {
            let a = CGFloat(min((now - rainbowFrom) / 12, (rainbowTo - now) / 15, 1))
            mix.rainbow = max(mix.rainbow, smoothstep(a))
        }
        c.mix = mix.clamped
        // Gusts: the wind rises and falls about its mean, now and then
        // well past it, never backing.
        let n = WeatherClock.gustiness(clock)
        c.windNow = wind * (1 + c.mix.gust * (1.6 * n - 0.5))
        return c
    }

    /// 0…1, mostly low, with bursts: how hard the wind is gusting.
    static func gustiness(_ t: CGFloat) -> CGFloat {
        let a = sin(t * 0.53) * 0.45 + sin(t * 1.37 + 1.3) * 0.3 + sin(t * 2.91 + 0.4) * 0.15 + sin(t * 5.3 + 2.2) * 0.1
        let v = min(max(0.5 + 0.5 * a, 0), 1)
        return v * v * (1.4 - 0.4 * v)
    }

    /// A few words on what it is doing, for the tank's controls.
    func summary(now: Double = WeatherClock.now) -> String {
        advance(now)
        switch settings.mode {
        case .always:
            return settings.always == .clear ? "Always clear skies" : "Always \(settings.always.label.lowercased())"
        case .outside:
            guard let o = outside else { return "Waiting to hear what it’s doing outside" }
            return o == .clear ? "Clear, like it is outside" : "\(o.label), like it is outside"
        case .changing:
            let live = spells.filter { $0.strength(at: now) > 0.02 || $0.start > now }
            guard let s = live.max(by: { $0.start < $1.start }) else {
                if let n = nextAt, n - now < 75 { return "Clear, but something’s brewing" }
                return "Clear skies, for now"
            }
            let name = s.weather.label
            if now < s.full { return "\(name), rolling in" }
            if now >= s.leave { return "\(name), clearing" }
            let left = s.leave - now
            if left > 3600 { return name }
            if left < 90 { return "\(name), clearing soon" }
            let mins = Int((left / 60).rounded())
            return "\(name), for about \(mins) more minute\(mins == 1 ? "" : "s")"
        }
    }

    /// The kind that is in, or coming in.
    var current: WeatherKind {
        let now = WeatherClock.now
        return spells.filter { $0.strength(at: now) > 0 && now < $0.leave }.max { $0.start < $1.start }?.weather ?? .clear
    }

    // MARK: Changing it

    /// Brings `kind` in now, quickly: the menu's "Make It Rain". Kept to
    /// one kind, it becomes the one; following outside, it goes back to
    /// coming and going first.
    func bring(_ kind: WeatherKind) {
        let now = WeatherClock.now
        if settings.mode == .always {
            settings.always = kind
            return
        }
        if settings.mode == .outside { settings.mode = .changing }
        clearAll(now, over: 6)
        rainbowTo = min(rainbowTo, now)
        if kind == .clear {
            nextAt = now + gap()
        } else {
            add(kind, now: now, fadeIn: 6, hold: hold(kind))
            nextAt = nil
        }
        changed()
    }

    /// Something else, now: whatever is in clears and the next comes.
    func changeNow() {
        guard settings.mode == .changing else { return }
        let now = WeatherClock.now
        let was = current
        clearAll(now, over: 10)
        if let k = draw(avoiding: was) {
            add(k, now: now, fadeIn: 10, hold: hold(k))
            nextAt = nil
        } else {
            nextAt = now + gap()
        }
        changed()
    }

    /// Tools only: `kind` fully in, at once, for good.
    func debugForce(_ kind: WeatherKind) {
        let now = WeatherClock.now
        spells = kind == .clear ? [] : [Spell(kind: kind.rawValue, start: now - 2, full: now - 1, leave: WeatherClock.forever,
                                                 end: WeatherClock.forever + 1, dir: 1, planned: true)]
        nextAt = nil
        rainbowTo = 0
    }

    // MARK: Inside

    private func clearAll(_ now: Double, over fade: Double) {
        for i in spells.indices { fadeOut(i, now: now, over: fade) }
        spells.removeAll { $0.end <= now }
    }

    /// Spell `i` clears over `fade` seconds, from however far in it is now
    /// — no jump, whether it was still rolling in or already going.
    private func fadeOut(_ i: Int, now: Double, over fade: Double) {
        let k = spells[i].strength(at: now)
        spells[i].planned = true
        guard spells[i].start < now, k > 0.001 else { spells[i].end = now; return }
        if now >= spells[i].leave, spells[i].end - now <= fade { return }
        // How far through a fade-out it would be, at this strength.
        var lo: CGFloat = 0, hi: CGFloat = 1
        for _ in 0..<16 {
            let m = (lo + hi) / 2
            if 1 - smoothstep(m) > k { lo = m } else { hi = m }
        }
        spells[i].leave = now - fade * Double(lo)
        spells[i].end = spells[i].leave + fade
        spells[i].full = min(spells[i].full, spells[i].leave)
        spells[i].start = min(spells[i].start, spells[i].full - 0.01)
    }

    private func add(_ kind: WeatherKind, now: Double, fadeIn: Double, hold: Double, already: Bool = false) {
        let fadeOut = Double.random(in: kind.fade)
        let start = already ? now - fadeIn : now
        var s = Spell(kind: kind.rawValue, start: start, full: start + fadeIn, leave: start + fadeIn + hold,
                      end: start + fadeIn + hold + fadeOut, dir: Bool.random() ? 1 : -1)
        if hold >= WeatherClock.forever / 2 {
            s.leave = WeatherClock.forever
            s.end = WeatherClock.forever + 1
            s.planned = true
        }
        // The same wind as what is clearing, mostly: it veers now and then.
        if let last = spells.last, Double.random(in: 0...1) < 0.7 { s.dir = last.dir }
        spells.append(s)
    }

    /// How long a spell of `kind` stays, in seconds.
    private func hold(_ kind: WeatherKind) -> Double {
        let minutes = Double(lerp(9, 1.5, settings.pace)) * kind.stay * Double.random(in: 0.6...1.4)
        return minutes * 60
    }

    /// Clear skies between spells, in seconds.
    private func gap() -> Double {
        let mean = Double(lerp(9, 1.5, settings.pace)) * Double(lerp(2.4, 0.12, settings.amount)) * 60
        return max(12, mean * Double.random(in: 0.5...1.5))
    }

    /// The next spell, from this scenery's list (nil: nothing on it).
    private func draw(avoiding last: WeatherKind?) -> WeatherKind? {
        let w = settings.weights(biome)
        guard !w.isEmpty else { return nil }
        let weighted = w.map { ($0.kind, $0.kind == last && w.count > 1 ? $0.weight * 0.25 : $0.weight) }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var pick = Double.random(in: 0..<max(total, 0.0001))
        for (k, wt) in weighted {
            pick -= wt
            if pick < 0 { return k }
        }
        return weighted.last?.0
    }

    /// Rolls the plan on to `now`: spells over are dropped, and whatever
    /// comes next is decided.
    private func advance(_ now: Double) {
        var dirty = false
        let before = spells.count
        spells.removeAll { $0.end <= now }
        if spells.count != before { dirty = true }
        guard settings.mode == .changing else { if dirty { save() }; return }
        // A spell starting to clear: something may follow straight on from
        // it; else clear skies for a while — with a rainbow, now and then.
        for i in spells.indices where !spells[i].planned && now >= spells[i].leave {
            spells[i].planned = true
            dirty = true
            let s = spells[i]
            let follow = s.weather.turnsInto.filter { settings.rotation(biome).contains($0) }
            if let k = follow.randomElement(), Double.random(in: 0...1) < 0.4 {
                add(k, now: now, fadeIn: Double.random(in: k.fade), hold: hold(k))
                nextAt = nil
            } else {
                nextAt = s.end + gap()
                if s.weather.wet, biome.hasOpenSky, Double.random(in: 0...1) < 0.45 {
                    rainbowFrom = s.leave + (s.end - s.leave) * 0.4
                    rainbowTo = rainbowFrom + Double.random(in: 50...90)
                }
            }
        }
        let live = spells.contains { now < $0.leave || !$0.planned }
        if !live, nextAt == nil {
            nextAt = now + gap()
            dirty = true
        }
        if !live, let n = nextAt, now >= n {
            nextAt = nil
            if let k = draw(avoiding: spells.last?.weather) {
                add(k, now: now, fadeIn: Double.random(in: k.fade), hold: hold(k))
                changed(save: false)
            } else {
                nextAt = now + gap()
            }
            dirty = true
        }
        if dirty { save() }
    }

    /// After a change of mode, list or scenery: the weather is put right.
    private func settle(now: Double, was: WeatherSettings, fresh: Bool = false) {
        spells.removeAll { $0.end <= now }
        switch settings.mode {
        case .always, .outside:
            let want = settings.mode == .always ? settings.always : (outside ?? .clear)
            let kept = spells.contains { $0.weather == want && $0.leave >= WeatherClock.forever }
            if !kept {
                clearAll(now, over: fresh ? 0.01 : 8)
                if want != .clear { add(want, now: now, fadeIn: fresh ? 3 : 8, hold: WeatherClock.forever, already: fresh) }
            }
            nextAt = nil
        case .changing:
            // Anything kept for good gets an ending; anything no longer on
            // this scenery's list goes.
            let list = settings.rotation(biome)
            for i in spells.indices {
                if spells[i].leave >= WeatherClock.forever {
                    let k = spells[i].weather
                    spells[i].leave = max(now, spells[i].full) + hold(k)
                    spells[i].end = spells[i].leave + Double.random(in: k.fade)
                    spells[i].planned = false
                }
            }
            let gone = spells.filter { !list.contains($0.weather) && now < $0.leave }
            if !gone.isEmpty {
                for i in spells.indices where !list.contains(spells[i].weather) && now < spells[i].leave {
                    fadeOut(i, now: now, over: 10)
                }
                spells.removeAll { $0.end <= now }
                nextAt = now + gap()
            }
            if fresh, spells.isEmpty, nextAt == nil {
                // The first time, often something is already on: the
                // weather is plain to see from the start.
                if Double.random(in: 0...1) < 0.5, let k = draw(avoiding: nil) {
                    add(k, now: now, fadeIn: Double.random(in: k.fade), hold: hold(k) * 0.6, already: true)
                } else {
                    nextAt = now + Double.random(in: 25...90)
                }
            }
        }
        changed()
    }

    private func changed(save doSave: Bool = true) {
        if doSave { save() }
        onChange?()
    }

    private func save() {
        guard persists else { return }
        let s = Saved(spells: spells, nextAt: nextAt, rainbowFrom: rainbowFrom, rainbowTo: rainbowTo)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: WeatherClock.saveKey) }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: WeatherClock.saveKey),
              let s = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        let now = WeatherClock.now
        spells = s.spells.filter { $0.end > now && WeatherKind(rawValue: $0.kind) != nil }
        nextAt = s.nextAt
        rainbowFrom = s.rainbowFrom
        rainbowTo = s.rainbowTo
    }
}

extension WeatherFeel {
    /// The weather as the spider feels it, out in the tank.
    init(_ c: WeatherConditions) {
        let m = c.mix
        self.init()
        wind = c.windNow
        gust = m.gust
        rain = m.rain
        snow = m.snow
        hail = m.hail
        sand = m.sand
        fog = m.fog
        sun = m.sun
        cold = m.cold
        heat = m.heat
        rainbow = m.rainbow
        storm = m.lightning
        skyShow = max(m.stars, m.aurora)
    }
}

// MARK: - The weather outside

extension WeatherKind {
    /// The nearest of ours to a WMO weather code (as Open-Meteo gives it),
    /// with the wind in km/h, whether it is day, and the temperature in °C.
    static func outside(code: Int, wind: Double, day: Bool, temperature: Double?) -> WeatherKind {
        switch code {
        case 45, 48: return .fog
        case 51...57: return .drizzle
        case 61, 63, 66, 80, 81: return wind > 45 ? .storm : .rain
        case 65, 67, 82: return .rain
        case 71, 73, 77, 85: return wind > 35 ? .blizzard : .snow
        case 75, 86: return wind > 25 ? .blizzard : .snow
        case 95: return .storm
        case 96, 99: return .hail
        case 3: return wind > 38 ? .windy : .cloudy
        default:
            if wind > 38 { return .windy }
            if day, code <= 1, (temperature ?? 0) >= 28 { return .sunny }
            return .clear
        }
    }
}
