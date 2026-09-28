import AVFoundation
import Foundation

// The beat tracker, offline: audio streamed through it the way the tap
// delivers it (10 ms at a time), and where it says the beats fall checked
// against where they really are.
//
//   beat loops [dir]      Apple Loops drum/percussion loops, repeated — the
//                         tempo from each loop's "beat count" and length.
//   beat mixes            several loops of one tempo played together.
//   beat synth            made-up patterns: straight, swung, sparse, busy.
//   beat change           one tempo, then another, then silence.
//   beat file <path>...   any audio: tempo and sureness over time, and the
//                         onsets lined up on the beats it hears.
//   beat speech <path>... must never be taken for music.

setvbuf(stdout, nil, _IONBF, 0)
let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "loops"
let verbose = ProcessInfo.processInfo.environment["BEAT_V"] != nil

struct Track {
    var name: String
    var samples: [Float]
    var sampleRate: Double
    /// True beat times, seconds from the start (nil: unknown).
    var beats: [Double]?
    var bpm: Double?
}

func load(_ path: String) -> (samples: [Float], sr: Double)? {
    guard let f = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: f.processingFormat.sampleRate,
                            channels: f.processingFormat.channelCount, interleaved: false)!
    guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(f.length)) else { return nil }
    do { try f.read(into: buf) } catch { return nil }
    let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
    var mono = [Float](repeating: 0, count: n)
    for c in 0..<ch {
        let p = buf.floatChannelData![c]
        for i in 0..<n { mono[i] += p[i] / Float(ch) }
    }
    return (mono, fmt.sampleRate)
}

/// An Apple Loop's beats, from the "beat count" in its metadata.
func loopBeats(_ path: String) -> Int? {
    guard let d = FileManager.default.contents(atPath: path) else { return nil }
    let key = Array("beat count".utf8) + [0]
    let bytes = [UInt8](d)
    guard bytes.count > key.count else { return nil }
    for i in 0..<(bytes.count - key.count) where bytes[i] == key[0] {
        if Array(bytes[i..<(i + key.count)]) == key {
            var j = i + key.count, s = ""
            while j < bytes.count, bytes[j] != 0, s.count < 6 { s.append(Character(UnicodeScalar(bytes[j]))); j += 1 }
            return Int(s)
        }
    }
    return nil
}

func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
    guard from != to else { return x }
    let n = Int(Double(x.count) * to / from)
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
        let s = Double(i) * from / to
        let a = Int(s), f = Float(s - Double(a))
        out[i] = a + 1 < x.count ? x[a] * (1 - f) + x[a + 1] * f : 0
    }
    return out
}

/// A loop played over and over for `seconds`.
func looped(_ path: String, seconds: Double = 40, sr: Double = 48000) -> Track? {
    guard let beats = loopBeats(path), beats > 0, let a = load(path) else { return nil }
    let x = resample(a.samples, from: a.sr, to: sr)
    let dur = Double(x.count) / sr
    let bpm = Double(beats) * 60 / dur
    var out: [Float] = []
    while Double(out.count) / sr < seconds { out += x }
    let period = 60 / bpm
    let truth = stride(from: 0.0, to: Double(out.count) / sr, by: period).map { $0 }
    return Track(name: (path as NSString).lastPathComponent, samples: out, sampleRate: sr, beats: truth, bpm: bpm)
}

// MARK: Synthesized patterns

struct Rng { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

func kick(_ out: inout [Float], at t: Double, sr: Double, gain: Float = 1) {
    let i0 = Int(t * sr)
    for k in 0..<Int(0.25 * sr) where i0 + k < out.count && i0 + k >= 0 {
        let tt = Double(k) / sr
        let f = 50 + 90 * exp(-tt * 30)
        out[i0 + k] += gain * Float(sin(2 * .pi * f * tt) * exp(-tt * 9))
    }
}
func snare(_ out: inout [Float], at t: Double, sr: Double, rng: inout Rng, gain: Float = 0.6) {
    let i0 = Int(t * sr)
    for k in 0..<Int(0.18 * sr) where i0 + k < out.count && i0 + k >= 0 {
        let tt = Double(k) / sr
        out[i0 + k] += gain * Float((rng.next() * 2 - 1) * exp(-tt * 22) + 0.4 * sin(2 * .pi * 190 * tt) * exp(-tt * 18))
    }
}
func hat(_ out: inout [Float], at t: Double, sr: Double, rng: inout Rng, gain: Float = 0.18) {
    let i0 = Int(t * sr)
    var prev = 0.0
    for k in 0..<Int(0.05 * sr) where i0 + k < out.count && i0 + k >= 0 {
        let tt = Double(k) / sr
        let w = rng.next() * 2 - 1
        out[i0 + k] += gain * Float((w - prev) * exp(-tt * 70))
        prev = w
    }
}
func tone(_ out: inout [Float], at t: Double, dur: Double, freq: Double, sr: Double, gain: Float = 0.25) {
    let i0 = Int(t * sr)
    for k in 0..<Int(dur * sr) where i0 + k < out.count && i0 + k >= 0 {
        let tt = Double(k) / sr
        let env = min(1, tt * 200) * exp(-tt * 3)
        out[i0 + k] += gain * Float(env * (sin(2 * .pi * freq * tt) + 0.3 * sin(4 * .pi * freq * tt)))
    }
}

enum Style: String, CaseIterable { case fourFloor, backbeat, swung, sparse, busy, pads, halfTime }

func synth(_ style: Style, bpm: Double, seconds: Double = 40, sr: Double = 48000, seed: UInt64 = 1) -> Track {
    var out = [Float](repeating: 0, count: Int(seconds * sr))
    var rng = Rng(s: seed)
    let p = 60 / bpm
    var truth: [Double] = []
    let start = 0.37
    var b = 0
    while start + Double(b) * p < seconds {
        let t = start + Double(b) * p
        truth.append(t)
        let jitter = { (r: inout Rng) in (r.next() - 0.5) * 0.008 }
        switch style {
        case .fourFloor:
            kick(&out, at: t + jitter(&rng), sr: sr)
            if b % 2 == 1 { snare(&out, at: t + jitter(&rng), sr: sr, rng: &rng) }
            hat(&out, at: t + p / 2, sr: sr, rng: &rng)
        case .backbeat:
            if b % 4 == 0 || b % 4 == 2 || (b % 8 == 7) { kick(&out, at: t, sr: sr) }
            if b % 4 == 2 && b % 8 == 2 { kick(&out, at: t + p * 0.5, sr: sr, gain: 0.7) }
            if b % 2 == 1 { snare(&out, at: t, sr: sr, rng: &rng) }
            hat(&out, at: t, sr: sr, rng: &rng); hat(&out, at: t + p / 2, sr: sr, rng: &rng)
        case .swung:
            if b % 2 == 0 { kick(&out, at: t, sr: sr) }
            if b % 2 == 1 { snare(&out, at: t, sr: sr, rng: &rng) }
            hat(&out, at: t, sr: sr, rng: &rng); hat(&out, at: t + p * 0.66, sr: sr, rng: &rng)
        case .sparse:
            if b % 4 == 0 { kick(&out, at: t, sr: sr) }
            if b % 4 == 2 { snare(&out, at: t, sr: sr, rng: &rng) }
            tone(&out, at: t, dur: p * 0.9, freq: [110, 110, 147, 131][b % 4], sr: sr)
        case .busy:
            kick(&out, at: t, sr: sr)
            if b % 2 == 1 { snare(&out, at: t, sr: sr, rng: &rng) }
            for s in 0..<4 { hat(&out, at: t + p * Double(s) / 4, sr: sr, rng: &rng, gain: s == 0 ? 0.2 : 0.12) }
            if rng.next() < 0.3 { kick(&out, at: t + p * 0.75, sr: sr, gain: 0.6) }
            tone(&out, at: t + p * 0.5, dur: p * 0.4, freq: 220, sr: sr, gain: 0.15)
        case .pads:
            // No drums: a bass note on every beat and chords on the bar.
            tone(&out, at: t, dur: p * 0.8, freq: [55, 55, 73, 65][b % 4], sr: sr, gain: 0.35)
            if b % 4 == 0 { for f in [261.6, 329.6, 392.0] { tone(&out, at: t, dur: p * 3.5, freq: f, sr: sr, gain: 0.08) } }
        case .halfTime:
            if b % 4 == 0 { kick(&out, at: t, sr: sr) }
            if b % 4 == 2 { snare(&out, at: t, sr: sr, rng: &rng, gain: 0.8) }
            hat(&out, at: t, sr: sr, rng: &rng); hat(&out, at: t + p / 2, sr: sr, rng: &rng, gain: 0.1)
        }
        b += 1
    }
    // A little noise under it all.
    for i in out.indices { out[i] += Float((rng.next() * 2 - 1) * 0.004) }
    return Track(name: "\(style.rawValue) \(Int(bpm))", samples: out, sampleRate: sr, beats: truth, bpm: bpm)
}

// MARK: Running it

struct Result {
    var lockAt: Double?          // seconds in, first playing
    var beats: [Double] = []     // when it said each beat fell
    var level = ""               // same / double / half / other tempo
    var within50 = 0.0           // share of its beats within 50 ms of a true one
    var meanAbs = 0.0            // ms
    var bias = 0.0               // ms, signed: + late
    var offbeat = 0.0            // share of its beats nearer a true half beat
    var playingShare = 0.0       // of the time after the lock
    var longestRun = 0.0         // longest stretch playing, seconds
    var runs = 0                 // how many separate stretches
    var bpmSeen: [Double] = []
    var log: [String] = []
}

func run(_ track: Track, chunk: Int = 480, logEvery: Double = 2) -> Result {
    let tr = BeatTracker(sampleRate: track.sampleRate)
    var r = Result()
    let base = 1000.0
    var prevBeat: Double?
    var prevT = 0.0
    var playingFrames = 0, framesAfterLock = 0
    var nextLog = 0.0
    var run = 0.0
    track.samples.withUnsafeBufferPointer { all in
        var i = 0
        while i < all.count {
            let k = min(chunk, all.count - i)
            let t0 = base + Double(i) / track.sampleRate
            tr.feed(UnsafeBufferPointer(rebasing: all[i..<(i + k)]), at: t0)
            i += k
            let now = base + Double(i) / track.sampleRate
            let s = tr.snapshot(at: now)
            let secs = now - base
            if s != nil { run += Double(k) / track.sampleRate; r.longestRun = max(r.longestRun, run) } else { if run > 0 { r.runs += 1 }; run = 0 }
            if let s {
                if r.lockAt == nil { r.lockAt = secs }
                playingFrames += 1
                r.bpmSeen.append(s.bpm)
                if let pb = prevBeat, floor(s.beat) > floor(pb), s.beat - pb < 0.9 {
                    // Crossed a whole beat between the two looks: when.
                    let f = (floor(s.beat) - pb) / (s.beat - pb)
                    r.beats.append(prevT + (secs - prevT) * f)
                }
                prevBeat = s.beat
            } else {
                prevBeat = nil
            }
            if r.lockAt != nil { framesAfterLock += 1 }
            prevT = secs
            if secs >= nextLog {
                nextLog += logEvery
                r.log.append(String(format: "%6.1fs %@ %@", secs, s.map { String(format: "b%8.2f %5.1fbpm", $0.beat, $0.bpm) } ?? "   (not playing)       ", tr.debug))
            }
        }
    }
    r.playingShare = framesAfterLock > 0 ? Double(playingFrames) / Double(framesAfterLock) : 0
    if let truth = track.beats, truth.count > 2, !r.beats.isEmpty, let bpm = track.bpm {
        let p = 60 / bpm
        let median = r.bpmSeen.sorted()[r.bpmSeen.count / 2]
        let ratio = median / bpm
        r.level = abs(ratio - 1) < 0.04 ? "same" : abs(ratio - 2) < 0.08 ? "double" : abs(ratio - 0.5) < 0.03 ? "half" : String(format: "x%.2f", ratio)
        // Only beats from 3 s after the lock: settled.
        let settled = r.beats.filter { $0 > (r.lockAt ?? 0) + 3 }
        var hits = 0, off = 0, sum = 0.0, signed = 0.0
        // At twice the tempo every other beat of its is a true half beat,
        // and on it: those count.
        let grid = r.level == "double" ? p / 2 : p
        for b in settled {
            // Nearest true beat (and half beat).
            let k = ((b - truth[0]) / grid).rounded()
            let d = b - (truth[0] + k * grid)
            let kh = ((b - truth[0] - p / 2) / p).rounded()
            let dh = b - (truth[0] + p / 2 + kh * p)
            if abs(d) < 0.05 { hits += 1 }
            if abs(dh) < abs(d), r.level != "double" { off += 1 }
            sum += abs(d)
            signed += d
        }
        if !settled.isEmpty {
            r.within50 = Double(hits) / Double(settled.count)
            r.offbeat = Double(off) / Double(settled.count)
            r.meanAbs = sum / Double(settled.count) * 1000
            r.bias = signed / Double(settled.count) * 1000
        }
    }
    return r
}

/// The tracker's onsets folded over the true beat, in sixteenths.
func fold(_ track: Track) -> String {
    guard let bpm = track.bpm else { return "" }
    let bt = BeatTracker(sampleRate: track.sampleRate)
    bt.recordOnsets = true
    track.samples.withUnsafeBufferPointer { bt.feed($0, at: 0) }
    let p = 60 / bpm
    var ff = [Double](repeating: 0, count: 16), fl = [Double](repeating: 0, count: 16)
    for o in bt.recorded {
        let ph = (o.t / p).truncatingRemainder(dividingBy: 1)
        let k = min(15, Int((ph * 16 + 0.5).truncatingRemainder(dividingBy: 16)))
        ff[k] += Double(o.full); fl[k] += Double(o.low)
    }
    let tf = ff.max() ?? 1, tl = fl.max() ?? 1
    if ProcessInfo.processInfo.environment["BEAT_FOLD"] == "bar" {
        var bf = [Double](repeating: 0, count: 64), bl = bf
        for o in bt.recorded {
            let ph = (o.t / (4 * p)).truncatingRemainder(dividingBy: 1)
            let k = Int((ph * 64 + 0.5)) % 64
            bf[k] += Double(o.full); bl[k] += Double(o.low)
        }
        let a = bf.max() ?? 1, b = bl.max() ?? 1
        return "bar full " + bf.map { String(format: "%.0f", $0 / a * 9) }.joined() + "\n      bar low  " + bl.map { String(format: "%.0f", $0 / b * 9) }.joined()
    }
    return "full " + ff.map { String(format: "%.0f", $0 / tf * 9) }.joined() + "  low " + fl.map { String(format: "%.0f", $0 / tl * 9) }.joined()
}

func report(_ track: Track, _ r: Result) {
    let lock = r.lockAt.map { String(format: "%4.1fs", $0) } ?? "never"
    let median = r.bpmSeen.isEmpty ? 0 : r.bpmSeen.sorted()[r.bpmSeen.count / 2]
    print(String(format: "%-44@ true %6.1f  heard %6.1f %-7@ lock %@  in±50ms %3.0f%%  mean %4.0fms bias %+4.0f  offbeat %3.0f%%  playing %3.0f%%",
                 String(track.name.prefix(44)) as NSString, track.bpm ?? 0, median, r.level as NSString, lock,
                 r.within50 * 100, r.meanAbs, r.bias, r.offbeat * 100, r.playingShare * 100))
    if verbose { r.log.forEach { print("   ", $0) } }
    if ProcessInfo.processInfo.environment["BEAT_FOLD"] != nil { print("      " + fold(track)) }
}

func summary(_ rows: [(Track, Result)]) {
    let scored = rows.filter { $0.0.beats != nil }
    let locked = scored.filter { $0.1.lockAt != nil }
    let good = locked.filter { $0.1.within50 > 0.8 && $0.1.offbeat < 0.2 }
    let lockTimes = locked.compactMap { $0.1.lockAt }.sorted()
    print(String(format: "\n%d tracks: locked %d, on the beat (>80%% within 50 ms) %d, same tempo %d, double %d, half %d, off-beat %d; median lock %.1fs",
                 scored.count, locked.count, good.count,
                 locked.filter { $0.1.level == "same" }.count, locked.filter { $0.1.level == "double" }.count,
                 locked.filter { $0.1.level == "half" }.count, locked.filter { $0.1.offbeat > 0.5 }.count,
                 lockTimes.isEmpty ? 0 : lockTimes[lockTimes.count / 2]))
}

let loopRoot = "/Library/Audio/Apple Loops/Apple"
func loopFiles(matching: (String) -> Bool, limit: Int) -> [String] {
    guard let e = FileManager.default.enumerator(atPath: loopRoot) else { return [] }
    var out: [String] = []
    for case let p as String in e where p.hasSuffix(".caf") && matching(p) { out.append(loopRoot + "/" + p) }
    out.sort()
    // Spread across the folders rather than the first few of one.
    if out.count > limit {
        let step = Double(out.count) / Double(limit)
        out = (0..<limit).map { out[Int(Double($0) * step)] }
    }
    return out
}

switch mode {
case "loops":
    let filter = args.count > 1 ? args[1].lowercased() : ""
    let files = loopFiles(matching: { p in
        let l = p.lowercased()
        return (l.contains("beat") || l.contains("break") || l.contains("drummer") || l.contains("groove") || l.contains("kit"))
            && (filter.isEmpty || l.contains(filter))
    }, limit: Int(ProcessInfo.processInfo.environment["BEAT_N"] ?? "40") ?? 40)
    var rows: [(Track, Result)] = []
    for f in files {
        guard let tr = looped(f, seconds: 30) else { continue }
        let r = run(tr)
        report(tr, r)
        rows.append((tr, r))
    }
    summary(rows)

case "mixes":
    // Loops from one pack at one tempo played together: a beat, and bass,
    // keys, synths or guitar over it (or, "BEAT_NODRUMS", none of the beat).
    let noDrums = ProcessInfo.processInfo.environment["BEAT_NODRUMS"] != nil
    guard let dirs = try? FileManager.default.contentsOfDirectory(atPath: loopRoot) else { break }
    var rows: [(Track, Result)] = []
    let sr = 48000.0
    for d in dirs.sorted() {
        guard let e = FileManager.default.enumerator(atPath: loopRoot + "/" + d) else { continue }
        var byTempo: [Int: [(path: String, drum: Bool)]] = [:]
        for case let p as String in e where p.hasSuffix(".caf") {
            let path = loopRoot + "/" + d + "/" + p
            guard let beats = loopBeats(path), beats > 0,
                  let f = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { continue }
            let dur = Double(f.length) / f.processingFormat.sampleRate
            let bpm = Int((Double(beats) * 60 / dur).rounded())
            let l = p.lowercased()
            let drum = l.contains("beat") || l.contains("break") || l.contains("drum") || l.contains("kit") || l.contains("perc") || l.contains("hat") || l.contains("snare") || l.contains("clap") || l.contains("shaker") || l.contains("topper") || l.contains(" - ")
            byTempo[bpm, default: []].append((path, drum))
        }
        for (bpm, loops) in byTempo.sorted(by: { $0.key < $1.key }) {
            let drums = loops.filter { $0.drum }, others = loops.filter { !$0.drum }
            guard others.count >= 2, noDrums || !drums.isEmpty else { continue }
            var rng = Rng(s: UInt64(bpm) &* 977 &+ UInt64(d.count))
            let takes = min(3, others.count)
            for mixN in 0..<min(2, max(1, others.count / 2)) {
                var parts: [String] = []
                if !noDrums { parts.append(drums[Int(rng.next() * Double(drums.count))].path) }
                var pool = others.map { $0.path }
                for _ in 0..<takes { let i = Int(rng.next() * Double(pool.count)); parts.append(pool.remove(at: i)) }
                var mix = [Float](repeating: 0, count: Int(30 * sr))
                for part in parts {
                    guard let a = load(part) else { continue }
                    let x = resample(a.samples, from: a.sr, to: sr)
                    guard !x.isEmpty else { continue }
                    let rms = (x.reduce(0) { $0 + $1 * $1 } / Float(x.count)).squareRoot()
                    let g = 0.12 / max(rms, 1e-4)
                    for i in mix.indices { mix[i] += x[i % x.count] * g }
                }
                let p = 60 / Double(bpm)
                let tr = Track(name: "\(d.prefix(14)) \(bpm) #\(mixN) " + parts.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension.prefix(10) }.joined(separator: "+"),
                               samples: mix, sampleRate: sr, beats: stride(from: 0.0, to: 30, by: p).map { $0 }, bpm: Double(bpm))
                let r = run(tr)
                report(tr, r)
                rows.append((tr, r))
            }
        }
    }
    summary(rows)

case "synth":
    var rows: [(Track, Result)] = []
    for style in Style.allCases {
        for bpm in [72.0, 96, 118, 128, 145, 172] {
            let tr = synth(style, bpm: bpm, seconds: 30, seed: UInt64(bpm) * 31 + UInt64(style.hashValue & 0xff))
            let r = run(tr)
            report(tr, r)
            rows.append((tr, r))
        }
    }
    summary(rows)

case "change":
    // 20 s at one tempo, straight into another, then silence.
    for (a, b) in [(120.0, 96.0), (96.0, 140.0), (128.0, 128.0)] {
        let sr = 48000.0
        var one = synth(.backbeat, bpm: a, seconds: 20)
        let two = synth(.fourFloor, bpm: b, seconds: 20, seed: 7)
        one.samples += two.samples + [Float](repeating: 0, count: Int(4 * sr))
        one.name = "\(Int(a)) then \(Int(b)) then silence"
        let tr = BeatTracker(sampleRate: sr)
        var line = ""
        one.samples.withUnsafeBufferPointer { all in
            var i = 0
            var next = 0.0
            while i < all.count {
                let k = min(480, all.count - i)
                tr.feed(UnsafeBufferPointer(rebasing: all[i..<(i + k)]), at: 1000 + Double(i) / sr)
                i += k
                let secs = Double(i) / sr
                if secs >= next {
                    next += 1
                    let s = tr.snapshot(at: 1000 + secs)
                    line += s.map { String(format: " %.0f", $0.bpm) } ?? " -"
                }
            }
        }
        print(one.name + ":" + line)
    }

case "file", "speech":
    for path in args.dropFirst() {
        guard let a = load(path) else { print("can't read \(path)"); continue }
        let x = resample(a.samples, from: a.sr, to: 48000)
        let maxSecs = Double(ProcessInfo.processInfo.environment["BEAT_SECS"] ?? "120") ?? 120
        let tr0 = Track(name: (path as NSString).lastPathComponent, samples: Array(x.prefix(Int(maxSecs * 48000))), sampleRate: 48000, beats: nil, bpm: nil)
        let r = run(tr0, logEvery: 3)
        let bpms = r.bpmSeen
        let median = bpms.isEmpty ? 0 : bpms.sorted()[bpms.count / 2]
        let spread = bpms.isEmpty ? 0 : (bpms.sorted()[bpms.count * 9 / 10] - bpms.sorted()[bpms.count / 10])
        print(String(format: "%@: lock %@, longest run %.1fs (%d runs), playing %.0f%% after, median %.1f bpm (10–90%% spread %.1f)", tr0.name,
                     r.lockAt.map { String(format: "%.1fs", $0) } ?? "never", r.longestRun, r.runs, r.playingShare * 100, median, spread))
        if mode == "file" || verbose { r.log.forEach { print("   ", $0) } }
        if mode == "file", r.beats.count > 8 {
            // The low end's onsets lined up on the beats it heard: a peak at
            // 0 ms is a beat on the kick.
            let tr = BeatTracker(sampleRate: 48000)
            _ = tr
            let lows = lowOnsets(tr0.samples)
            var prof = [Double](repeating: 0, count: 21)
            for b in r.beats {
                for (j, off) in stride(from: -100, through: 100, by: 10).enumerated() {
                    let i = Int(((b + Double(off) / 1000) * 100).rounded())
                    if i >= 0, i < lows.count { prof[j] += lows[i] }
                }
            }
            let top = prof.max() ?? 1
            print("    kick onsets around its beats (-100…+100 ms):", prof.map { String(format: "%.0f", $0 / max(top, 1e-9) * 9) }.joined())
        }
    }

case "grid":
    // Where the onsets fall against the true beat: folded over one beat in
    // sixteenths, low end and everything.
    for f in args.dropFirst() {
        guard let tr = looped(f, seconds: 16), let bpm = tr.bpm else { continue }
        let bt = BeatTracker(sampleRate: tr.sampleRate)
        bt.recordOnsets = true
        tr.samples.withUnsafeBufferPointer { bt.feed($0, at: 0) }
        let p = 60 / bpm
        var ff = [Double](repeating: 0, count: 16), fl = [Double](repeating: 0, count: 16)
        for o in bt.recorded {
            let ph = (o.t / p).truncatingRemainder(dividingBy: 1)
            let k = min(15, Int((ph * 16 + 0.5).truncatingRemainder(dividingBy: 16)))
            ff[k] += Double(o.full); fl[k] += Double(o.low)
        }
        let tf = ff.max() ?? 1, tl = fl.max() ?? 1
        if verbose {
            let firstBar = bt.recorded.filter { $0.t < 4 * p + 0.05 }
            let top = firstBar.map { $0.full }.max() ?? 1
            for o in firstBar where o.full > top * 0.35 {
                print(String(format: "   %.3fs (beat %.2f) full %.2f low %.2f", o.t, o.t / p, o.full / top, o.low / (firstBar.map { $0.low }.max() ?? 1)))
            }
        }
        print(String(format: "%-36@ tracker full: %@  low: %@", tr.name as NSString, ff.map { String(format: "%.0f", $0 / tf * 9) }.joined(), fl.map { String(format: "%.0f", $0 / tl * 9) }.joined()))
        let lows = lowOnsets(tr.samples)
        var fold = [Double](repeating: 0, count: 16)
        for (i, v) in lows.enumerated() {
            let ph = (Double(i) / 100 / p).truncatingRemainder(dividingBy: 1)
            fold[min(15, Int(ph * 16))] += v
        }
        let top = fold.max() ?? 1
        print(String(format: "%-36@ %5.1f bpm  low: %@", tr.name as NSString, bpm, fold.map { String(format: "%.0f", $0 / top * 9) }.joined()))
        // And by beat of the bar, the low end at each beat.
        var bars = [Double](repeating: 0, count: 4)
        for (i, v) in lows.enumerated() {
            let b = Double(i) / 100 / p
            let fr = b - b.rounded()
            if abs(fr) < 0.06 { bars[((Int(b.rounded()) % 4) + 4) % 4] += v }
        }
        print("      by beat of the bar:", bars.map { String(format: "%.0f", $0) })
    }

default:
    print("modes: loops [filter] | synth | change | file <paths> | speech <paths>")
}

/// A simple low-end onset curve at 100 a second, for lining up.
func lowOnsets(_ x: [Float]) -> [Double] {
    let hop = 480
    var out: [Double] = []
    var prev = 0.0
    var lp = 0.0
    var i = 0
    while i + hop <= x.count {
        var e = 0.0
        for k in 0..<hop {
            lp += (Double(x[i + k]) - lp) * 0.012   // ~90 Hz low-pass at 48 kHz
            e += lp * lp
        }
        let db = 10 * log10(e / Double(hop) + 1e-12)
        out.append(max(0, db - prev))
        prev = db
        i += hop
    }
    return out
}
