import Foundation
import CoreGraphics

// Random-number fixtures: the first 1,000 values of every kind of draw the
// spider makes, for each of several seeds, written as one JSON document. The
// Windows port must reproduce these exactly (same generator, same mapping from
// bits to numbers) or its seeded runs cannot match the Mac's frame for frame.
//
// It calls the very functions the spider calls: the shadows in
// tools/legs/Seeded.swift (CGFloat/Double/Int .random(in:), Bool via
// seededBool(), shuffled(), randomElement()), all fed by SplitMix64.
//
//   ./tools/rngprobe.sh > rng.json

setvbuf(stdout, nil, _IONBF, 0)
let seeds: [UInt64] = [1, 2, 3, 42, 12345]
let n = 1000
var docs: [String] = []

for s in seeds {
    var parts: [String] = []
    func section(_ name: String, _ vals: [String]) { parts.append("\"\(name)\":[" + vals.joined(separator: ",") + "]") }

    reseed(s); section("raw", (0..<n).map { _ in "\"\(seededRNG.next())\"" })
    reseed(s); section("double_0_1", (0..<n).map { _ in "\(Double.random(in: 0.0...1.0))" })
    reseed(s); section("double_0_1_open", (0..<n).map { _ in "\(Double.random(in: 0.0..<1.0))" })
    reseed(s); section("double_m3p5_7p25", (0..<n).map { _ in "\(Double.random(in: -3.5...7.25))" })
    reseed(s); section("cgfloat_0_1", (0..<n).map { _ in "\(Double(CGFloat.random(in: CGFloat(0)...CGFloat(1))))" })
    reseed(s); section("cgfloat_open_2_9", (0..<n).map { _ in "\(Double(CGFloat.random(in: CGFloat(2)..<CGFloat(9))))" })
    reseed(s); section("int_0_9", (0..<n).map { _ in "\(Int.random(in: 0...9))" })
    reseed(s); section("int_0_7_open", (0..<n).map { _ in "\(Int.random(in: 0..<7))" })
    reseed(s); section("int_m5_5", (0..<n).map { _ in "\(Int.random(in: -5...5))" })
    reseed(s); section("int_0_1000000", (0..<n).map { _ in "\(Int.random(in: 0...1_000_000))" })
    reseed(s); section("bool", (0..<n).map { _ in seededBool() ? "true" : "false" })
    reseed(s); section("shuffled_0_7", (0..<100).map { _ in "[" + [0, 1, 2, 3, 4, 5, 6, 7].shuffled().map(String.init).joined(separator: ",") + "]" })
    reseed(s); section("random_element_10", (0..<n).map { _ in "\([10, 11, 12, 13, 14, 15, 16, 17, 18, 19].randomElement()!)" })
    reseed(s); section("random_element_range", (0..<n).map { _ in "\((0..<7).randomElement()!)" })
    // The draws interleaved, as the spider makes them (order matters).
    reseed(s)
    section("mixed", (0..<n).map { i -> String in
        switch i % 4 {
        case 0: return "\(Double(CGFloat.random(in: CGFloat(0)...CGFloat(1))))"
        case 1: return "\(Int.random(in: 0..<5))"
        case 2: return seededBool() ? "1" : "0"
        default: return "\([1, 2, 3].randomElement()!)"
        }
    })
    docs.append("{\"seed\":\(s),\"count\":\(n),\(parts.joined(separator: ","))}")
}
print("{\"generator\":\"SplitMix64\",\"note\":\"values are what Swift prints: shortest round-trip doubles; raw is decimal UInt64 as a string\",\"seeds\":[" + docs.joined(separator: ",\n") + "]}")
