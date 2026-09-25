import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import IOKit.ps
import QuartzCore

/// The volume or the brightness going up or down: something the spider
/// looks up at.
enum Commotion {
    case louder, quieter, brighter, dimmer
}

/// Keeps an eye on the Mac the spider lives on: Low Power Mode, the charger
/// going in, whether it is raining outside, and the volume and brightness
/// being turned up or down. Everything is reported on the main thread, and
/// only when it changes.
final class SystemSense {
    /// Low Power Mode went on or off.
    var onLowPower: ((Bool) -> Void)?
    /// The charger went in (not at launch, only the moment it happens).
    var onPluggedIn: (() -> Void)?
    /// It started or stopped raining.
    var onRain: ((Bool) -> Void)?

    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var onAC = SystemSense.readOnAC()
    private(set) var raining = false

    private var powerSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var weatherTimer: Timer?
    private var place: (lat: Double, lon: Double, at: Date)?

    /// SPIDER_RAIN=1 pretends it is raining, without asking anyone.
    private let fakeRain = ProcessInfo.processInfo.environment["SPIDER_RAIN"] == "1"

    // MARK: Power

    func startPower() {
        guard powerSource == nil else { return }
        lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        onAC = SystemSense.readOnAC()
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let now = ProcessInfo.processInfo.isLowPowerModeEnabled
            if now != self.lowPower {
                self.lowPower = now
                self.onLowPower?(now)
            }
        }
        let me = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<SystemSense>.fromOpaque(ctx).takeUnretainedValue().powerChanged()
        }, me)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            powerSource = src
        }
    }

    func stopPower() {
        if let src = powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .defaultMode) }
        powerSource = nil
        if let o = lowPowerObserver { NotificationCenter.default.removeObserver(o) }
        lowPowerObserver = nil
    }

    private func powerChanged() {
        let now = SystemSense.readOnAC()
        guard now != onAC else { return }
        onAC = now
        if now { onPluggedIn?() }
    }

    private static func readOnAC() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() else { return true }
        return (type as String) == kIOPMACPowerKey
    }

    // MARK: Volume and brightness

    /// The volume or the brightness was changed (by a key, a slider, or
    /// the mute button) — once per step.
    var onCommotion: ((Commotion) -> Void)?

    private var outputDevice = AudioObjectID(kAudioObjectUnknown)
    private var volume: Float32?
    private var muted: Bool?
    private var volumeListener: AudioObjectPropertyListenerBlock?
    private var deviceListener: AudioObjectPropertyListenerBlock?

    private var brightnessTimer: Timer?
    private var brightness: Float?
    /// When the Mac was last left untouched long enough to dim its display.
    private var awayAt: CFTimeInterval = -99
    private static let anyInput = CGEventType(rawValue: ~0)!

    private static let defaultOutput = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    private static let volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static let muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    func startCommotion() {
        guard deviceListener == nil else { return }
        let onDevice: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.bindOutput() }
        var addr = SystemSense.defaultOutput
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, onDevice)
        deviceListener = onDevice
        bindOutput()

        brightness = nil
        if SystemSense.getBrightness != nil {
            let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.pollBrightness() }
            t.tolerance = 0.05
            RunLoop.main.add(t, forMode: .common)
            brightnessTimer = t
            pollBrightness()
        }
    }

    func stopCommotion() {
        if let l = deviceListener {
            var addr = SystemSense.defaultOutput
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, l)
        }
        deviceListener = nil
        unbindOutput()
        brightnessTimer?.invalidate()
        brightnessTimer = nil
    }

    /// Listens to whichever output is the default now. Changing output (in
    /// go the headphones) is not a change of volume: the levels are only
    /// taken, not reported.
    private func bindOutput() {
        unbindOutput()
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = SystemSense.defaultOutput
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != kAudioObjectUnknown else { return }
        outputDevice = id
        let l: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.volumeChanged() }
        for var a in [SystemSense.volumeAddress, SystemSense.muteAddress] where AudioObjectHasProperty(id, &a) {
            AudioObjectAddPropertyListenerBlock(id, &a, .main, l)
        }
        volumeListener = l
        volume = readVolume()
        muted = readMuted()
    }

    private func unbindOutput() {
        if let l = volumeListener, outputDevice != kAudioObjectUnknown {
            for var a in [SystemSense.volumeAddress, SystemSense.muteAddress] where AudioObjectHasProperty(outputDevice, &a) {
                AudioObjectRemovePropertyListenerBlock(outputDevice, &a, .main, l)
            }
        }
        volumeListener = nil
        outputDevice = AudioObjectID(kAudioObjectUnknown)
    }

    private func volumeChanged() {
        let v = readVolume(), m = readMuted()
        defer { volume = v; muted = m }
        if let m, let was = muted, m != was {
            onCommotion?(m ? .quieter : .louder)
        } else if let v, let was = volume, abs(v - was) > 0.01 {
            onCommotion?(v > was ? .louder : .quieter)
        }
    }

    private func readVolume() -> Float32? {
        var a = SystemSense.volumeAddress
        var v: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectHasProperty(outputDevice, &a),
              AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &v) == noErr else { return nil }
        return v
    }

    private func readMuted() -> Bool? {
        var a = SystemSense.muteAddress
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(outputDevice, &a),
              AudioObjectGetPropertyData(outputDevice, &a, 0, nil, &size, &v) == noErr else { return nil }
        return v != 0
    }

    /// The built-in display's brightness, from DisplayServices — private,
    /// but the only way to read it on Apple silicon. Nil where it is missing.
    private typealias BrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private static let getBrightness: BrightnessFn? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let f = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(f, to: BrightnessFn.self)
    }()

    private static func builtInDisplay() -> CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        guard CGGetOnlineDisplayList(8, &ids, &n) == .success else { return nil }
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    /// A step of the brightness keys is a sixteenth, and lands at once;
    /// automatic brightness drifts a little at a time and is let be.
    private func pollBrightness() {
        guard let get = SystemSense.getBrightness, let display = SystemSense.builtInDisplay() else { return }
        var b: Float = 0
        guard get(display, &b) == 0 else { return }
        defer { brightness = b }
        let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: SystemSense.anyInput)
        let now = CACurrentMediaTime()
        if idle > 15 { awayAt = now }
        let awayJustNow = now - awayAt < 3
        guard let was = brightness, abs(b - was) > 0.04 else { return }
        // The display dimming after a while untouched, and brightening
        // again the moment you are back, are not anything happening.
        if awayJustNow { return }
        onCommotion?(b > was ? .brighter : .dimmer)
    }

    // MARK: Weather

    /// Looks outside now and then — every twenty minutes or so. The place is
    /// only roughly known, from the internet connection (the nearest city),
    /// and is asked for again every few hours.
    func startWeather() {
        guard weatherTimer == nil else { return }
        checkWeather()
        let t = Timer(timeInterval: 20 * 60, repeats: true) { [weak self] _ in self?.checkWeather() }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        weatherTimer = t
    }

    func stopWeather() {
        weatherTimer?.invalidate()
        weatherTimer = nil
        setRaining(false)
    }

    private func setRaining(_ r: Bool) {
        guard r != raining else { return }
        raining = r
        onRain?(r)
    }

    private func checkWeather() {
        if fakeRain { setRaining(true); return }
        if let p = place, Date().timeIntervalSince(p.at) < 6 * 3600 {
            fetchRain(lat: p.lat, lon: p.lon)
            return
        }
        locate(from: SystemSense.locators) { [weak self] lat, lon in
            guard let self else { return }
            self.place = (lat, lon, Date())
            self.fetchRain(lat: lat, lon: lon)
        }
    }

    /// Keyless look-ups of roughly where an internet connection is, tried in turn.
    private static let locators = ["https://get.geojs.io/v1/ip/geo.json", "https://ipwho.is/"]

    private func locate(from urls: [String], then done: @escaping (Double, Double) -> Void) {
        guard let first = urls.first, let url = URL(string: first) else { return }
        fetchJSON(url) { [weak self] json in
            if let json, let lat = SystemSense.number(json["latitude"]), let lon = SystemSense.number(json["longitude"]) {
                done(lat, lon)
            } else {
                self?.locate(from: Array(urls.dropFirst()), then: done)
            }
        }
    }

    private func fetchRain(lat: Double, lon: Double) {
        // A tenth of a degree (a few miles) is plenty for rain.
        let q = String(format: "latitude=%.1f&longitude=%.1f", lat, lon)
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?\(q)&current=precipitation,weather_code") else { return }
        fetchJSON(url) { [weak self] json in
            guard let cur = json?["current"] as? [String: Any] else { return }
            let code = Int(SystemSense.number(cur["weather_code"]) ?? 0)
            let mm = SystemSense.number(cur["precipitation"]) ?? 0
            // Drizzle, rain, freezing rain, showers and thunderstorms.
            let wet = (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code)
            self?.setRaining(wet || (mm > 0.05 && !(71...77).contains(code) && !(85...86).contains(code)))
        }
    }

    private func fetchJSON(_ url: URL, then done: @escaping ([String: Any]?) -> Void) {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.setValue(AppInfo.name, forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { done(json) }
        }.resume()
    }

    private static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }
}
