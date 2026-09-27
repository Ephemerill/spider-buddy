import Foundation
import CoreGraphics

// Test builds only: every random draw the spider makes comes from one
// seeded generator (LC_SEED), so two builds can be run through exactly the
// same life and compared frame by frame.
struct SplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
var seededRNG = SplitMix(s: UInt64(ProcessInfo.processInfo.environment["LC_SEED"] ?? "1") ?? 1)
func reseed(_ n: UInt64) { seededRNG = SplitMix(s: n) }

extension CGFloat {
    static func random(in r: ClosedRange<CGFloat>) -> CGFloat { CGFloat(Double.random(in: Double(r.lowerBound)...Double(r.upperBound), using: &seededRNG)) }
    static func random(in r: Range<CGFloat>) -> CGFloat { CGFloat(Double.random(in: Double(r.lowerBound)..<Double(r.upperBound), using: &seededRNG)) }
}
extension Double {
    static func random(in r: ClosedRange<Double>) -> Double { Double.random(in: r, using: &seededRNG) }
    static func random(in r: Range<Double>) -> Double { Double.random(in: r, using: &seededRNG) }
}
extension Int {
    static func random(in r: ClosedRange<Int>) -> Int { Int.random(in: r, using: &seededRNG) }
    static func random(in r: Range<Int>) -> Int { Int.random(in: r, using: &seededRNG) }
}
func seededBool() -> Bool { Bool.random(using: &seededRNG) }
extension Array {
    func randomElement() -> Element? { randomElement(using: &seededRNG) }
    func shuffled() -> [Element] { shuffled(using: &seededRNG) }
}
extension Collection {
    func randomElement() -> Element? { randomElement(using: &seededRNG) }
}
