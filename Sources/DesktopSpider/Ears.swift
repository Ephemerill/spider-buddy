import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Listens to what the Mac is playing, for a beat to dance to.
///
/// Every app's sound is heard as it goes out to the speakers or headphones,
/// through a Core Audio process tap (macOS 14.2 and later) — nothing is
/// recorded or kept, only the beat is taken from it (see `BeatTracker`).
/// The tap is only open while some other app is actually playing sound:
/// the rest of the time it just checks, once a second, whether one is.
/// The first time it opens, macOS asks whether it may.
final class Ears {
    enum Status: Equatable {
        case unsupported        // older than macOS 14.2
        case off
        case quiet              // nothing is playing
        case listening          // something is: no beat yet
        case hearing(Double)    // music, at this many beats a minute
        case deaf               // things are playing, but it hears nothing
    }

    /// Called on the main thread when `status` changes.
    var onChange: (() -> Void)?

    private(set) var status: Status = .off {
        didSet { if status != oldValue { onChange?() } }
    }
    /// The app (or apps) it can hear playing, by name.
    private(set) var playingApps: [String] = []

    static var supported: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }

    /// How long after the tap hears something it reaches your ears — the
    /// output's own buffering and latency — and how long after the frame
    /// is worked out it is on the screen. (Measured on a MacBook Pro's own
    /// speakers, 2026-09-27: a click came out of them 26 ms after the tap
    /// heard it, which is what the device says; a frame is on the screen
    /// about two refreshes after it is drawn. A dance a touch ahead of the
    /// sound reads better than one behind it.) Tunable with SPIDER_BEAT_LAG
    /// (ms, added on: more if it dances early, less if late).
    private var outputLatency: Double = 0.02
    private static let displayLead = 0.035
    private static let extraLag = (Double(ProcessInfo.processInfo.environment["SPIDER_BEAT_LAG"] ?? "") ?? 0) / 1000

    private let queue = DispatchQueue(label: "spider.ears", qos: .userInteractive)
    private let lock = NSLock()
    // (Behind the lock: what the queue has heard, for the main thread.)
    private var heard: (clock: BeatTracker.Clock?, playing: Bool, confidence: Double, energy: Double, bar: Int, silent: Bool)
        = (nil, false, 0, 0, 0, true)

    /// Tools only: every buffer the tap hears, mono, with the host time of
    /// its first sample (called on the audio queue).
    var debugHeard: ((UnsafeBufferPointer<Float>, Double) -> Void)?

    // Queue only.
    private var tracker: BeatTracker?
    private var mono: [Float] = []

    // Main thread only.
    private var pollTimer: Timer?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var tapOpenedAt: CFTimeInterval = 0
    private var nobodyPlayingFor: CFTimeInterval = 0
    private var silentWhilePlayingFor: CFTimeInterval = 0
    private var lastPoll: CFTimeInterval = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private let log = ProcessInfo.processInfo.environment["SPIDER_EARS_LOG"] != nil

    func start() {
        guard pollTimer == nil else { return }
        guard Ears.supported else { status = .unsupported; return }
        status = .quiet
        lastPoll = CACurrentMediaTime()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        // New headphones: the tap is opened again on the new output.
        let l: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.tapOpen else { return }
            self.closeTap()
            self.poll()
        }
        var addr = Ears.defaultOutputAddress
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, l)
        deviceListener = l
        poll()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        if let l = deviceListener {
            var addr = Ears.defaultOutputAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, l)
        }
        deviceListener = nil
        closeTap()
        playingApps = []
        status = Ears.supported ? .off : .unsupported
    }

    /// The music as it is on the screen at `now` (`CACurrentMediaTime`),
    /// or nil if there is none with a beat.
    func music(at now: CFTimeInterval) -> MusicBeat? {
        lock.lock()
        let h = heard
        lock.unlock()
        guard tapOpen, h.playing, let c = h.clock else { return nil }
        let heardAt = now + Ears.displayLead - outputLatency - Ears.extraLag
        return MusicBeat(beat: c.beat(at: heardAt), period: c.period, confidence: h.confidence, energy: h.energy, bar: h.bar)
    }

    private var tapOpen: Bool { procID != nil }

    // MARK: Who is playing

    private func poll() {
        guard #available(macOS 14.2, *) else { return }
        let now = CACurrentMediaTime()
        let dt = min(now - lastPoll, 3)
        lastPoll = now
        let apps = Ears.appsPlaying()
        playingApps = apps
        if apps.isEmpty {
            nobodyPlayingFor += dt
            // A pause between songs is not the end: the tap stays open a
            // little while.
            if tapOpen, nobodyPlayingFor > 12 { closeTap() }
        } else {
            nobodyPlayingFor = 0
            if !tapOpen { openTap() }
        }
        lock.lock()
        let h = heard
        lock.unlock()
        // Apps playing and not a sound coming through for a long while:
        // most likely it has not been allowed to listen (yet — the tap is
        // opened again now and then, so it hears once it is).
        if tapOpen, !apps.isEmpty, h.silent, now - tapOpenedAt > 3 {
            silentWhilePlayingFor += dt
            if now - tapOpenedAt > 10 {
                closeTap()
                openTap()
            }
        } else if !h.silent {
            silentWhilePlayingFor = 0
        }
        if !tapOpen {
            status = apps.isEmpty ? .quiet : .deaf
        } else if h.playing, let c = h.clock {
            status = .hearing((60 / c.period).rounded())
        } else if silentWhilePlayingFor > 20 {
            status = .deaf
        } else {
            status = apps.isEmpty ? .quiet : .listening
        }
        if log {
            fputs(String(format: "ears: %@ apps=%@ silent=%d playing=%d conf=%.2f latency=%.0fms\n", "\(status)",
                         apps.joined(separator: ","), h.silent ? 1 : 0, h.playing ? 1 : 0, h.confidence, outputLatency * 1000), stderr)
        }
    }

    /// The apps sending sound out right now, by name (not this one).
    @available(macOS 14.2, *)
    private static func appsPlaying() -> [String] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        let me = getpid()
        var names: [String] = []
        for id in ids {
            guard let running: UInt32 = read(id, kAudioProcessPropertyIsRunningOutput), running != 0,
                  let pid: pid_t = read(id, kAudioProcessPropertyPID), pid != me else { continue }
            // (A browser plays through a helper: it goes by the app's name.)
            let app = NSRunningApplication(processIdentifier: pid)
            var name = app?.localizedName ?? ""
            if name.isEmpty, let bundle = readString(id, kAudioProcessPropertyBundleID), !bundle.isEmpty {
                name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
                    .flatMap { Bundle(url: $0)?.object(forInfoDictionaryKey: "CFBundleName") as? String } ?? bundle
            }
            if name.isEmpty { name = processName(pid) }
            if !name.isEmpty, !names.contains(name) { names.append(name) }
        }
        return names
    }

    /// A command-line player has no app name: its process name, then.
    private static func processName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buf, UInt32(buf.count)) > 0 else { return "" }
        return String(cString: buf)
    }

    private static func read<T>(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> T? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        let p = UnsafeMutableRawPointer.allocate(byteCount: MemoryLayout<T>.size, alignment: MemoryLayout<T>.alignment)
        defer { p.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, p) == noErr else { return nil }
        return p.load(as: T.self)
    }

    private static func readString(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<CFString?>.size)
        var s: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &s) == noErr, let v = s else { return nil }
        return v.takeRetainedValue() as String
    }

    private static let defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    // MARK: The tap

    private func openTap() {
        guard #available(macOS 14.2, *), !tapOpen else { return }
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = Ears.defaultOutputAddress
        var output = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &output) == noErr, output != kAudioObjectUnknown,
              let outputUID = Ears.readString(output, kAudioDevicePropertyDeviceUID) else { return }
        outputLatency = Ears.latency(of: output)

        // Everything but its own bell.
        var mine = AudioObjectID(kAudioObjectUnknown)
        var pid = getpid()
        var paddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                               mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(system, &paddr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &mine)
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: mine == kAudioObjectUnknown ? [] : [mine])
        desc.uuid = UUID()
        desc.name = "\(AppInfo.name) listening for a beat"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(desc, &tap) == noErr, tap != kAudioObjectUnknown else {
            if log { fputs("ears: no tap\n", stderr) }
            return
        }
        guard let format: AudioStreamBasicDescription = Ears.read(tap, kAudioTapPropertyFormat),
              format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mBitsPerChannel == 32, format.mSampleRate > 8000 else {
            AudioHardwareDestroyProcessTap(tap)
            return
        }
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "\(AppInfo.name) Ears",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg) == noErr, agg != kAudioObjectUnknown else {
            AudioHardwareDestroyProcessTap(tap)
            return
        }
        let rate = format.mSampleRate
        queue.async { [weak self] in
            guard let self else { return }
            if self.tracker?.sampleRate != rate { self.tracker = BeatTracker(sampleRate: rate) } else { self.tracker?.reset() }
        }
        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, queue) { [weak self] _, input, inputTime, _, _ in
            self?.hear(input, at: inputTime)
        }
        guard status == noErr, let proc, AudioDeviceStart(agg, proc) == noErr else {
            if let proc { AudioDeviceDestroyIOProcID(agg, proc) }
            AudioHardwareDestroyAggregateDevice(agg)
            AudioHardwareDestroyProcessTap(tap)
            return
        }
        tapID = tap
        aggregateID = agg
        procID = proc
        tapOpenedAt = CACurrentMediaTime()
        silentWhilePlayingFor = 0
        if log { fputs(String(format: "ears: tap open at %.0f Hz on %@, latency %.0f ms\n", rate, outputUID, outputLatency * 1000), stderr) }
    }

    private func closeTap() {
        guard #available(macOS 14.2, *) else { return }
        if let proc = procID {
            AudioDeviceStop(aggregateID, proc)
            AudioDeviceDestroyIOProcID(aggregateID, proc)
        }
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        queue.async { [weak self] in self?.tracker?.reset() }
        lock.lock()
        heard = (nil, false, 0, 0, 0, true)
        lock.unlock()
        if log { fputs("ears: tap closed\n", stderr) }
    }

    /// How long sound takes from the tap to the speakers: the device's own
    /// latency, its safety offset and one buffer, plus the stream's.
    private static func latency(of device: AudioObjectID) -> Double {
        let out = kAudioObjectPropertyScopeOutput
        let rate: Double = read(device, kAudioDevicePropertyNominalSampleRate) ?? 48000
        let frames = (read(device, kAudioDevicePropertyLatency, scope: out) as UInt32? ?? 0)
            + (read(device, kAudioDevicePropertySafetyOffset, scope: out) as UInt32? ?? 0)
            + (read(device, kAudioDevicePropertyBufferFrameSize, scope: out) as UInt32? ?? 512)
        var stream: UInt32 = 0
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: out, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        if AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioObjectID>.size) {
            var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &ids) == noErr, let first = ids.first {
                stream = read(first, kAudioStreamPropertyLatency) ?? 0
            }
        }
        return Double(frames + stream) / max(rate, 1)
    }

    // MARK: On the audio queue

    private func hear(_ input: UnsafePointer<AudioBufferList>, at time: UnsafePointer<AudioTimeStamp>) {
        guard let tracker else { return }
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var channels = 0
        var frames = Int.max
        for b in list where b.mData != nil && b.mNumberChannels > 0 {
            channels += Int(b.mNumberChannels)
            frames = min(frames, Int(b.mDataByteSize) / (4 * Int(b.mNumberChannels)))
        }
        guard channels > 0, frames > 0, frames != .max else { return }
        if mono.count != frames { mono = Array(repeating: 0, count: frames) } else { for i in mono.indices { mono[i] = 0 } }
        let g = 1 / Float(channels)
        for b in list where b.mData != nil && b.mNumberChannels > 0 {
            let n = Int(b.mNumberChannels)
            let p = b.mData!.assumingMemoryBound(to: Float.self)
            for i in 0..<frames {
                var s: Float = 0
                for c in 0..<n { s += p[i * n + c] }
                mono[i] += s * g
            }
        }
        let ts = time.pointee
        let at = ts.mFlags.contains(.hostTimeValid)
            ? Double(AudioConvertHostTimeToNanos(ts.mHostTime)) / 1e9
            : CACurrentMediaTime() - Double(frames) / tracker.sampleRate
        mono.withUnsafeBufferPointer { tracker.feed($0, at: at); debugHeard?($0, at) }
        lock.lock()
        heard = (tracker.clock, tracker.playing, tracker.confidence, tracker.energy, tracker.bar, tracker.silent)
        lock.unlock()
    }
}
