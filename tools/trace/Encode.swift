import Foundation
import CoreGraphics

// JSON for any value, by reflection. The trace and image tools use it to
// write a SpiderPose (and anything in it) without naming its fields, so a
// field added to the pose later is exported without touching these tools.
// Numbers are written the shortest way that reads back as the same double.
// NaN and infinity become null. Enums become their case name ("hearts",
// "text(\"hi\")"). Fields named in `skipping` are left out.

func encodeJSON(_ v: Any, skipping skip: Set<String> = ["outfit"], depth: Int = 0) -> String {
    func num(_ x: Double) -> String { x.isFinite ? "\(x)" : "null" }
    func quote(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": o += "\\\""
            case "\\": o += "\\\\"
            case "\n": o += "\\n"
            case "\t": o += "\\t"
            default:
                if u.value < 0x20 { o += String(format: "\\u%04x", u.value) } else { o.unicodeScalars.append(u) }
            }
        }
        return o + "\""
    }
    if depth > 8 { return "null" }
    switch v {
    case let x as Bool: return x ? "true" : "false"
    case let x as Int: return "\(x)"
    case let x as Int32: return "\(x)"
    case let x as UInt32: return "\(x)"
    case let x as UInt64: return "\(x)"
    case let x as UInt8: return "\(x)"
    case let x as CGFloat: return num(Double(x))
    case let x as Double: return num(x)
    case let x as Float: return num(Double(x))
    case let x as String: return quote(x)
    default: break
    }
    let m = Mirror(reflecting: v)
    switch m.displayStyle {
    case .optional:
        guard let c = m.children.first else { return "null" }
        return encodeJSON(c.value, skipping: skip, depth: depth + 1)
    case .collection, .set:
        return "[" + m.children.map { encodeJSON($0.value, skipping: skip, depth: depth + 1) }.joined(separator: ",") + "]"
    case .struct, .class, .tuple:
        var items: [String] = []
        for (i, c) in m.children.enumerated() {
            let label = c.label ?? String(i)
            if label.hasPrefix("$") || skip.contains(label) { continue }
            items.append(quote(label) + ":" + encodeJSON(c.value, skipping: skip, depth: depth + 1))
        }
        return "{" + items.joined(separator: ",") + "}"
    default:
        return quote(String(describing: v))
    }
}
