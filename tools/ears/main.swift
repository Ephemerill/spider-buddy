import AppKit
import AVFoundation

// The real ears, outside the app: which apps are playing sound, and — with
// `listen [seconds]` — the tap opened on them and what it hears, once a
// second. (Opening the tap is what asks macOS for permission, for whichever
// app this is run from.)

enum AppInfo { static let name = "Spider ears test" }

setvbuf(stdout, nil, _IONBF, 0)
let args = Array(CommandLine.arguments.dropFirst())
let ears = Ears()
if args.first == "latency" {
    // Clicks heard through the tap and through the microphone, both on the
    // host clock: how long after the tap hears a sound it comes out of the
    // speakers (play something with sharp clicks while this runs).
    let secs = Double(args.dropFirst().first ?? "15") ?? 15
    /// A signal folded over half a second on the host clock, in 1 ms
    /// bins: where in the half second its clicks come.
    final class Fold {
        var sum = [Double](repeating: 0, count: 500), n = [Int](repeating: 0, count: 500)
        var prev: Float = 0
        let lock = NSLock()
        func feed(_ x: UnsafeBufferPointer<Float>, at t0: Double, rate: Double) {
            lock.lock(); defer { lock.unlock() }
            for (i, v) in x.enumerated() {
                let t = t0 + Double(i) / rate
                let b = Int((t.truncatingRemainder(dividingBy: 0.5)) * 1000) % 500
                sum[b] += Double(abs(v - prev)); n[b] += 1
                prev = v
            }
        }
        /// The bin where the click starts: the first rising above a quarter
        /// of the way from the floor to the peak, before the peak.
        func onset() -> (ms: Int, contrast: Double) {
            let f = (0..<500).map { n[$0] > 0 ? sum[$0] / Double(n[$0]) : 0 }
            let base = f.sorted()[250]
            let pk = f.indices.max { f[$0] < f[$1] }!
            let th = base + 0.25 * (f[pk] - base)
            var on = pk
            while f[(on - 1 + 500) % 500] > th, pk - on < 80 { on -= 1 }
            return ((on + 500) % 500, f[pk] / max(base, 1e-12))
        }
    }
    let tap = Fold(), mic = Fold()
    var tapRate = 48000.0
    ears.debugHeard = { buf, t0 in tap.feed(buf, at: t0, rate: tapRate) }
    ears.start()
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let fmt = input.outputFormat(forBus: 0)
    input.installTap(onBus: 0, bufferSize: 512, format: fmt) { buf, when in
        guard let ch = buf.floatChannelData?[0], when.isHostTimeValid else { return }
        let t0 = Double(AudioConvertHostTimeToNanos(when.hostTime)) / 1e9
        mic.feed(UnsafeBufferPointer(start: ch, count: Int(buf.frameLength)), at: t0, rate: fmt.sampleRate)
    }
    do { try engine.start() } catch { print("mic: \(error)"); exit(1) }
    // When the app would draw each beat: the music as it has it on the
    // screen (`music(at:)`), its beat count crossing a whole number.
    var drawn: [Double] = []
    var lastWhole: Double?
    let clock = Timer(timeInterval: 1.0 / 120.0, repeats: true) { _ in
        let now = CACurrentMediaTime()
        guard let m = ears.music(at: now) else { lastWhole = nil; return }
        let whole = floor(m.beat)
        if let w = lastWhole, whole > w { drawn.append(now - (m.beat - whole) * m.period) }
        lastWhole = whole
    }
    RunLoop.main.add(clock, forMode: .common)
    print("mic at \(fmt.sampleRate) Hz; listening \(Int(secs)) s…")
    DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
        engine.stop(); ears.stop()
        let a = tap.onset(), b = mic.onset()
        let gap = ((b.ms - a.ms) % 500 + 600) % 500 - 100   // (reads -100 … 400 ms)
        print(String(format: "tap: clicks at %d ms (contrast %.1f); microphone: at %d ms (contrast %.1f)", a.ms, a.contrast, b.ms, b.contrast))
        print("microphone minus tap: \(gap) ms")
        if !drawn.isEmpty {
            // (A circular mean of where in the half second they fall.)
            let ang = drawn.map { $0.truncatingRemainder(dividingBy: 0.5) / 0.5 * 2 * Double.pi }
            let ph = atan2(ang.map(sin).reduce(0, +), ang.map(cos).reduce(0, +)) / (2 * Double.pi) * 500
            let d = (Int(ph.rounded()) + 500) % 500
            let lead = ((b.ms - d) % 500 + 750) % 500 - 250
            print("beats drawn at \(d) ms (\(drawn.count) of them): the heard click comes \(lead) ms after the beat is drawn")
        }
        exit(0)
    }
    RunLoop.main.run()
} else if args.first == "listen" {
    let secs = Double(args.dropFirst().first ?? "20") ?? 20
    ears.start()
    let began = CACurrentMediaTime()
    var lastBeat: Int?
    let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
        let now = CACurrentMediaTime()
        if let m = ears.music(at: now) {
            let b = Int(floor(m.beat))
            if b != lastBeat {
                lastBeat = b
                print(String(format: "%6.2fs  beat %d  %.1f bpm  sure %.2f  energy %.2f  bar %d", now - began, b, m.bpm, m.confidence, m.energy, m.bar))
            }
        }
    }
    RunLoop.main.add(t, forMode: .common)
    let s = Timer(timeInterval: 1, repeats: true) { _ in
        print(String(format: "%6.2fs  %@  apps: %@", CACurrentMediaTime() - began, "\(ears.status)", ears.playingApps.joined(separator: ", ")))
        if CACurrentMediaTime() - began > secs { ears.stop(); exit(0) }
    }
    RunLoop.main.add(s, forMode: .common)
    RunLoop.main.run()
} else {
    // Just who is playing, via the same poll (no tap).
    ears.start()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    print("supported: \(Ears.supported)  status: \(ears.status)  apps playing: \(ears.playingApps)")
    ears.stop()
}
