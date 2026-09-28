import Accelerate
import Foundation

/// The beat of whatever is playing, as it reaches the spider: where in the
/// beat the music is right now, how fast it goes, how sure the ear is of
/// it and how hard the music is going.
struct MusicBeat {
    /// Beats counted, continuous: the whole part ticks over on each beat as
    /// it is heard.
    var beat: Double
    /// Seconds a beat.
    var period: Double
    /// How sure it is of the beat, 0…1.
    var confidence: Double = 1
    /// How loud and busy the music is against its own loudest, 0…1.
    var energy: Double = 0.7
    /// Which beat of four starts a bar: beat `b` is the one when
    /// `(floor(b) - bar) % 4 == 0`.
    var bar: Int = 0

    var bpm: Double { 60 / period }
}

/// Hears the beat in a stream of audio. Onsets come from the spectral flux
/// (how much louder each band got since a moment ago), the tempo from how
/// the onsets repeat, and the phase from where the beats of that tempo
/// line up with them best — the low end, where the kick drum is, counting
/// double. The result is a clock that is nudged into line as it goes, so
/// it never jumps: `beat(at:)` gives where in the beat any moment is.
///
/// Not thread safe: feed it and read it on one queue (see `Ears`).
final class BeatTracker {
    /// The beat clock: `anchorBeat` at `anchorTime`, going at `rate` beats a
    /// second (a touch off 1/`period` while it is being pulled into line).
    struct Clock {
        var anchorTime: Double
        var anchorBeat: Double
        var rate: Double
        var period: Double
        func beat(at time: Double) -> Double { anchorBeat + (time - anchorTime) * rate }
        /// When beat `b` comes round.
        func time(ofBeat b: Double) -> Double { anchorTime + (b - anchorBeat) / rate }
    }

    let sampleRate: Double
    /// Onset frames a second.
    let fps: Double
    private let n: Int
    private let hop: Int
    private let log2n: vDSP_Length
    private let fft: FFTSetup
    private let window: [Float]
    private var bands: [Range<Int>] = []
    private var lowBands = 0
    private var prevDb: [Float] = []
    private var peakDb: Float = -60
    private var primed = false

    /// Mono samples not yet taken into a frame; `pending[0]` was heard at
    /// `pendingTime`.
    private var pending: [Float] = []
    private var pendingTime: Double = 0
    private var framesSinceAnalysis = 0

    private var onset = History<Float>(capacity: 1100)
    private var onsetLow = History<Float>(capacity: 1100)
    private var level = History<Float>(capacity: 1100)
    private var times = History<Double>(capacity: 1100)

    private(set) var clock: Clock?
    /// Playing: locked onto a beat it is sure of, and not silent.
    private(set) var playing = false
    private(set) var confidence: Double = 0
    private(set) var energy: Double = 0.5
    private(set) var bar = 0
    /// The tempo it heard last, whatever the clock is doing.
    private(set) var heardBPM: Double = 0
    /// Nothing but silence of late.
    private(set) var silent = true
    /// Tools only: every onset frame, kept.
    var recordOnsets = false
    private(set) var recorded: [(t: Double, full: Float, low: Float)] = []
    /// The last analysis, for the tools.
    private(set) var debug = ""

    // Locking on: the tempo it has heard, and for how long it has held.
    private var candidate: Double = 0
    private var candidateFor = 0
    private var disagreeFor = 0
    private var lowConfidenceFor = 0
    private var farOffFor = 0
    /// How steadily what it hears has agreed with the clock of late, 0…1:
    /// music keeps to its beat; the rhythms in speech come and go.
    private var agreement = 0.0
    private var barAcc = [Double](repeating: 0, count: 4)
    private var lastBarBeat: Int?

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        hop = max(64, Int((sampleRate / 100).rounded()))
        fps = sampleRate / Double(hop)
        var size = 512
        while Double(size) < sampleRate * 0.042 { size *= 2 }
        n = size
        log2n = vDSP_Length(log2(Double(size)).rounded())
        fft = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        // Log-spaced bands from 40 Hz to 12 kHz, each at least one bin.
        let binHz = sampleRate / Double(size)
        let top = min(12_000, sampleRate / 2 - binHz)
        var edges: [Int] = []
        let count = 36
        for i in 0...count {
            let f = 40 * pow(top / 40, Double(i) / Double(count))
            edges.append(max(1, Int((f / binHz).rounded())))
        }
        var lo = edges[0]
        for e in edges.dropFirst() where e > lo {
            bands.append(lo..<e)
            if Double(e) * binHz <= 170 { lowBands = bands.count }
            lo = e
        }
        lowBands = max(lowBands, 1)
        prevDb = Array(repeating: -80, count: bands.count)
    }

    deinit { vDSP_destroy_fftsetup(fft) }

    /// Starts over, as if nothing had been heard. (The samples waiting to
    /// be framed are kept: it is called in the middle of framing them.)
    func reset() {
        onset.clear(); onsetLow.clear(); level.clear(); times.clear()
        clock = nil
        playing = false
        confidence = 0
        candidate = 0; candidateFor = 0; disagreeFor = 0; lowConfidenceFor = 0; farOffFor = 0
        barAcc = [0, 0, 0, 0]
        lastBarBeat = nil
        prevDb = Array(repeating: -80, count: bands.count)
        primed = false
    }

    /// Mono samples, the first of them heard at `time` (seconds, on the
    /// host clock — `CACurrentMediaTime`'s).
    func feed(_ samples: UnsafeBufferPointer<Float>, at time: Double) {
        if pending.isEmpty {
            pendingTime = time
        } else {
            // A gap or a skip in the stream: go by the new time stamp once
            // it is well off where the samples say we are.
            let expected = pendingTime + Double(pending.count) / sampleRate
            if abs(expected - time) > 0.05 {
                pending.removeAll(keepingCapacity: true)
                pendingTime = time
            }
        }
        pending.append(contentsOf: samples)
        var start = 0
        while pending.count - start >= n {
            frame(pending, from: start, at: pendingTime + Double(start + n / 2) / sampleRate)
            start += hop
        }
        if start > 0 {
            pending.removeFirst(start)
            pendingTime += Double(start) / sampleRate
        }
    }

    private var scratch: [Float] = []
    private var real: [Float] = []
    private var imag: [Float] = []
    private var power: [Float] = []

    private func frame(_ buf: [Float], from start: Int, at time: Double) {
        if scratch.count != n {
            scratch = Array(repeating: 0, count: n)
            real = Array(repeating: 0, count: n / 2)
            imag = Array(repeating: 0, count: n / 2)
            power = Array(repeating: 0, count: n / 2)
        }
        buf.withUnsafeBufferPointer { b in
            vDSP_vmul(b.baseAddress! + start, 1, window, 1, &scratch, 1, vDSP_Length(n))
        }
        // Loudness of the newest hop, in dB below full scale.
        var ms: Float = 0
        buf.withUnsafeBufferPointer { b in
            vDSP_measqv(b.baseAddress! + start + n - hop, 1, &ms, vDSP_Length(hop))
        }
        let db = 10 * log10(ms + 1e-12)

        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                scratch.withUnsafeBufferPointer { s in
                    s.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { c in
                        vDSP_ctoz(c, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fft, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }
        power[0] = 0

        // Spectral flux on log band energies, floored 80 dB under the
        // loudest band of late so hiss in silent bands does not count.
        var flux: Float = 0, fluxLow: Float = 0
        var loudest: Float = -200
        power.withUnsafeBufferPointer { p in
            for (i, r) in bands.enumerated() {
                var e: Float = 0
                vDSP_sve(p.baseAddress! + r.lowerBound, 1, &e, vDSP_Length(r.count))
                var d = 10 * log10(e / Float(r.count) + 1e-12)
                loudest = max(loudest, d)
                d = max(d, peakDb - 80)
                // (The first frame after a reset only sets the levels: out
                // of silence every band would count as a hit.)
                let rise = primed ? max(0, d - prevDb[i]) : 0
                flux += rise
                if i < lowBands { fluxLow += rise }
                prevDb[i] = d
            }
        }
        peakDb = max(loudest, peakDb - 0.05)
        primed = true
        if recordOnsets { recorded.append((time, flux / Float(bands.count), fluxLow / Float(lowBands))) }
        onset.append(flux / Float(bands.count))
        onsetLow.append(fluxLow / Float(lowBands))
        level.append(db)
        times.append(time)

        framesSinceAnalysis += 1
        if framesSinceAnalysis >= 10 {
            framesSinceAnalysis = 0
            analyze(now: time)
        }
    }

    // MARK: Analysis

    private func analyze(now: Double) {
        // Silence: nothing to dance to, and nothing heard before it counts.
        let recent = level.last(Int(fps * 0.5))
        let quiet = recent.count >= Int(fps * 0.5) && recent.allSatisfy { $0 < -58 }
        if quiet {
            if !silent { reset() }
            silent = true
            debug = "silent"
            return
        }
        silent = false
        energy = loudness()

        let w = min(onset.count, Int(fps * 10))
        guard w >= Int(fps * 2.4) else { debug = "listening"; return }
        // (One huge onset — a song starting, a door slamming — would have
        // the whole window to itself: none counts for more than a few
        // ordinary ones.)
        var o = BeatTracker.tamed(onset.last(w))
        let low = BeatTracker.tamed(onsetLow.last(w))
        let ts = times.last(w)

        // How the onsets repeat: their autocorrelation, over lags out to
        // three beats of the slowest tempo it will hear.
        let mean = vDSP.mean(o)
        vDSP.add(-mean, o, result: &o)
        let maxLag = min(w - Int(fps), Int(fps * 60 / BeatTracker.slowest * 8) + 2)
        var r = [Double](repeating: 0, count: maxLag + 1)
        o.withUnsafeBufferPointer { p in
            for lag in 0...maxLag {
                var d: Float = 0
                vDSP_dotpr(p.baseAddress!, 1, p.baseAddress! + lag, 1, &d, vDSP_Length(w - lag))
                r[lag] = Double(d) / Double(w - lag)
            }
        }
        guard r[0] > 1e-9 else { debug = "flat"; return }
        let r0 = r[0]
        for i in r.indices { r[i] /= r0 }
        func ac(_ lag: Double) -> Double {
            guard lag >= 0, lag < Double(maxLag) else { return 0 }
            let i = Int(lag), f = lag - Double(i)
            return r[i] * (1 - f) + r[i + 1] * f
        }
        // Each tempo scored by the onsets repeating at one, two and three
        // beats, and leaned toward a comfortable tempo to tap along to —
        // and toward the one it is already on.
        var best = (bpm: 0.0, score: -Double.infinity, raw: 0.0)
        var scores: [Double] = []
        let current = clock.map { 60 / $0.period }
        var bpm = BeatTracker.slowest
        while bpm <= BeatTracker.fastest + 0.001 {
            let tau = fps * 60 / bpm
            var raw = 0.0, wsum = 0.0
            for (k, wk) in BeatTracker.comb where wk > 0 && Double(k) * tau < Double(maxLag) {
                raw += wk * ac(Double(k) * tau)
                wsum += wk
            }
            raw /= max(wsum, 1e-9)
            let octaves = log2(bpm / 118)
            var s = raw * exp(-0.5 * octaves * octaves)
            if let c = current, abs(log2(bpm / c)) < 0.03 { s *= 1.2 }
            scores.append(s)
            if s > best.score { best = (bpm, s, raw) }
            bpm += 0.5
        }
        // Between the grid points.
        if let i = scores.firstIndex(of: best.score), i > 0, i < scores.count - 1 {
            let a = scores[i - 1], b = scores[i], c = scores[i + 1]
            let den = a - 2 * b + c
            if den < 0 { best.bpm += 0.5 * clamp(0.5 * (a - c) / den, -0.5, 0.5) }
        }
        heardBPM = best.bpm
        let tempoSure = clamp(ac(fps * 60 / best.bpm) / 0.35, 0, 1)

        // Where the beats fall: the phase of the clock's tempo (or the one
        // just heard) that lines up best with the onsets, the recent ones
        // counting most.
        let period = clock?.period ?? 60 / best.bpm
        let tau = period * fps
        var p = [Float](repeating: 0, count: w)
        let raw = BeatTracker.tamed(onset.last(w))
        let sdFull = max(BeatTracker.sd(raw), 1e-6)
        let sdLow = max(BeatTracker.sd(low), 1e-6)
        for i in 0..<w { p[i] = raw[i] / sdFull + low[i] / sdLow }
        p = BeatTracker.smooth(BeatTracker.smooth(p))
        func at(_ x: Double) -> Double {
            guard x >= 0, x <= Double(w - 1) else { return 0 }
            let i = min(Int(x), w - 2), f = x - Double(i)
            return Double(p[i]) * (1 - f) + Double(p[i + 1]) * f
        }
        let step = 0.25
        var phase: [Double] = []
        var bestPhase = (lag: 0.0, score: -Double.infinity)
        var lag = 0.0
        while lag < tau {
            var s = 0.0, wk = 1.0, k = 0.0
            while true {
                let x = Double(w - 1) - lag - k * tau
                if x < 0 || k > 24 { break }
                s += at(x) * wk
                wk *= 0.9
                k += 1
            }
            phase.append(s)
            if s > bestPhase.score { bestPhase = (lag, s) }
            lag += step
        }
        if let i = phase.firstIndex(of: bestPhase.score) {
            let a = phase[(i - 1 + phase.count) % phase.count], b = phase[i], c = phase[(i + 1) % phase.count]
            let den = a - 2 * b + c
            if den < 0 { bestPhase.lag += step * clamp(0.5 * (a - c) / den, -0.5, 0.5) }
        }
        let pm = phase.reduce(0, +) / Double(phase.count)
        let psd = (phase.reduce(0) { $0 + ($1 - pm) * ($1 - pm) } / Double(phase.count)).squareRoot()
        let clarity = psd > 1e-9 ? (bestPhase.score - pm) / psd : 0
        // (Two beats' worth of peak over the rest is clear; one is not.)
        let phaseSure = clamp((clarity - 1.2) / 1.2, 0, 1)
        let x = Double(w - 1) - bestPhase.lag
        let xi = min(max(Int(x), 0), w - 2)
        let beatTime = ts[xi] + (ts[xi + 1] - ts[xi]) * (x - Double(xi))

        let sure = tempoSure * (0.4 + 0.6 * phaseSure)
        confidence += (sure - confidence) * 0.25

        updateClock(heard: 60 / best.bpm, beatTime: beatTime, sure: sure, now: now)
        if clock != nil { tallyBar(now: now) }
        // Sure and steady to start; once going, only a real falling off
        // stops it — a busy bar or a break in the drums does not.
        if clock == nil {
            playing = false
        } else if playing {
            playing = confidence > 0.2 && agreement > 0.3
        } else {
            playing = confidence > BeatTracker.playSure && agreement > 0.6
        }
        debug = String(format: "heard %.1f tempo %.2f phase %.2f (%.2f) conf %.2f agree %.2f clock %@ bar %d energy %.2f",
                       best.bpm, tempoSure, phaseSure, clarity, confidence, agreement,
                       clock.map { String(format: "%.1f", 60 / $0.period) } ?? "-", bar, energy)
    }

    static let comb: [(Int, Double)] = [(1, 1), (2, 0.5), (3, 0.33), (4, 1), (8, 0.5)]
    private static let samePulse: [Double] = [0.5, 2, 1.5, 2.0 / 3, 0.75, 4.0 / 3, 3, 1.0 / 3]
    private static let lockSure = 0.35
    private static let lockAfter = 15
    private static let playSure = 0.35
    /// Slowest and fastest tempo it will hear, in beats a minute.
    static let slowest = 60.0
    static let fastest = 190.0

    private func updateClock(heard: Double, beatTime: Double, sure: Double, now: Double) {
        guard var c = clock else {
            // Locking on: the same tempo heard, surely, for a second and a
            // half. (Speech has moments of rhythm; they do not last.)
            if sure > BeatTracker.lockSure, candidate > 0, abs(heard / candidate - 1) < 0.03 {
                candidateFor += 1
            } else {
                candidateFor = sure > BeatTracker.lockSure ? 1 : 0
                candidate = heard
            }
            candidate += (heard - candidate) * 0.3
            if candidateFor >= BeatTracker.lockAfter {
                let rate = 1 / candidate
                // The beat just heard is a whole beat.
                clock = Clock(anchorTime: beatTime, anchorBeat: 0, rate: rate, period: candidate)
                clock!.anchorBeat = 0
                let b = clock!.beat(at: now)
                clock = Clock(anchorTime: now, anchorBeat: b, rate: rate, period: candidate)
                disagreeFor = 0
                lowConfidenceFor = 0
                farOffFor = 0
                agreement = 0.7
                barAcc = [0, 0, 0, 0]
                lastBarBeat = nil
            }
            return
        }
        // Lost it: a good while unsure, and it lets go.
        lowConfidenceFor = sure < 0.2 ? lowConfidenceFor + 1 : 0
        if lowConfidenceFor > 25 {
            clock = nil
            candidateFor = 0
            return
        }
        // The tempo: followed while it agrees; a different one heard
        // steadily for a few seconds is a new tempo, and the clock takes it
        // up — but not one merely a simple ratio off it (twice as fast,
        // three beats to its four): that is the same pulse counted another
        // way, which the busier parts of a song throw up.
        let ratio = heard / c.period
        let octave = BeatTracker.samePulse.contains { abs(ratio / $0 - 1) < 0.04 }
        var target = c.period
        if abs(ratio - 1) < 0.04 {
            disagreeFor = 0
            target = heard
        } else if !octave, sure > 0.3 {
            disagreeFor += 1
        } else {
            disagreeFor = max(0, disagreeFor - 1)
        }
        if disagreeFor > 30 {
            disagreeFor = 0
            let b = c.beat(at: now)
            c = Clock(anchorTime: now, anchorBeat: b, rate: 1 / heard, period: heard)
        }
        // The phase: how far off the beat just heard the clock reads.
        let bp = c.beat(at: beatTime)
        let e = bp - bp.rounded()
        farOffFor = abs(e) > 0.2 && sure > 0.25 ? farOffFor + 1 : 0
        let agrees = (abs(ratio - 1) < 0.04 || octave) && abs(e) < 0.15 && sure > 0.25
        agreement += ((agrees ? 1 : 0) - agreement) * 0.08
        let b = c.beat(at: now)
        c.anchorTime = now
        c.anchorBeat = b
        if sure > 0.15 { c.period += (target - c.period) * 0.12 }
        let base = 1 / c.period
        if sure > 0.15 {
            // Pulled into line over about a second — quicker when it is
            // well out — never faster or slower than a fifth.
            let tc = farOffFor >= 3 ? 0.45 : 1.1
            let most = base * (farOffFor >= 3 ? 0.3 : 0.12)
            c.rate = base - clamp(e / tc, -most, most)
        } else {
            c.rate = base
        }
        clock = c
    }

    /// Which beat of four is the one: where the low end hits hardest,
    /// taken beat by beat as they go by.
    private func tallyBar(now: Double) {
        guard let c = clock else { return }
        // (Beats a little while back, so their onsets are all in.)
        let upTo = Int(floor(c.beat(at: now - 0.08)))
        let from = (lastBarBeat ?? upTo - 1) + 1
        guard upTo >= from else { return }
        let low = onsetLow.last(onsetLow.count)
        let ts = times.last(times.count)
        guard let t0 = ts.first else { return }
        for b in max(from, upTo - 8)...upTo {
            let bt = c.time(ofBeat: Double(b))
            let i = Int(((bt - t0) * fps).rounded())
            guard i >= 3, i < low.count - 3 else { continue }
            let v = Double(low[(i - 3)...(i + 3)].max() ?? 0)
            for k in 0..<4 { barAcc[k] *= 0.97 }
            barAcc[((b % 4) + 4) % 4] += v
        }
        lastBarBeat = upTo
        if let best = barAcc.indices.max(by: { barAcc[$0] < barAcc[$1] }), barAcc[best] > barAcc[bar] * 1.15 {
            bar = best
        }
    }

    /// How hard the music is going just now against the loudest it has been
    /// of late, 0…1.
    private func loudness() -> Double {
        let recent = level.last(Int(fps * 0.6))
        let long = level.last(Int(fps * 8))
        guard !recent.isEmpty, let top = long.max() else { return 0.5 }
        let now = Double(recent.reduce(0, +)) / Double(recent.count)
        return clamp((now - Double(top) + 16) / 13, 0, 1)
    }

    private static func sd(_ v: [Float]) -> Float {
        guard v.count > 1 else { return 0 }
        let m = vDSP.mean(v)
        var ss: Float = 0
        for x in v { ss += (x - m) * (x - m) }
        return (ss / Float(v.count)).squareRoot()
    }

    /// Onsets with the outliers clipped to a few times the typical one.
    private static func tamed(_ v: [Float]) -> [Float] {
        guard v.count > 8 else { return v }
        let sorted = v.sorted()
        let cap = max(sorted[sorted.count * 9 / 10] * 2.5, 1e-6)
        return v.map { min($0, cap) }
    }

    private static func smooth(_ v: [Float]) -> [Float] {
        guard v.count > 2 else { return v }
        var out = v
        for i in 1..<(v.count - 1) { out[i] = 0.25 * v[i - 1] + 0.5 * v[i] + 0.25 * v[i + 1] }
        return out
    }

    /// Where the music is at `time`, if it has the beat.
    func snapshot(at time: Double) -> MusicBeat? {
        guard playing, let c = clock else { return nil }
        return MusicBeat(beat: c.beat(at: time), period: c.period, confidence: confidence, energy: energy, bar: bar)
    }
}

/// A fixed-length record of the latest values.
struct History<T> {
    private var store: [T] = []
    private var head = 0
    let capacity: Int
    init(capacity: Int) { self.capacity = capacity; store.reserveCapacity(capacity) }
    var count: Int { store.count }
    mutating func append(_ v: T) {
        if store.count < capacity { store.append(v) } else { store[head] = v; head = (head + 1) % capacity }
    }
    mutating func clear() { store.removeAll(keepingCapacity: true); head = 0 }
    /// The newest `k`, oldest first.
    func last(_ k: Int) -> [T] {
        let k = min(k, store.count)
        guard k > 0 else { return [] }
        if store.count < capacity { return Array(store[(store.count - k)...]) }
        var out: [T] = []
        out.reserveCapacity(k)
        let start = (head - k + capacity) % capacity
        for i in 0..<k { out.append(store[(start + i) % capacity]) }
        return out
    }
}
