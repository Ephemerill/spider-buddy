// Windows replacement for the Mac's SystemSense.swift: same names and callbacks. Stub for now: Battery Saver, charger,
// weather, volume and brightness are filled in with the sensors phase (plan Part 9).
import Foundation
import CoreGraphics

enum Commotion {
    case louder, quieter, brighter, dimmer
}

final class SystemSense {
    var raining = false
    var lowPower = false
    var onLowPower: ((Bool) -> Void)?
    var onPluggedIn: (() -> Void)?
    var onRain: ((Bool) -> Void)?
    var onOutside: ((Int, Double, Bool, Double?) -> Void)?
    var onCommotion: ((Commotion) -> Void)?
    func startPower() {}
    func stopPower() {}
    func startCommotion() {}
    func stopCommotion() {}
    func startWeather() {}
    func stopWeather() {}
}
