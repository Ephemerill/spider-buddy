// Total width of the strings in corpus.txt in the system font at each size and weight, one line per weight. Run on the
// Mac (SF Pro) and on Windows (the stand-in's system font, before its width scaling: SPIDER_FONT_RAW=1) to make the
// width table in src/SwiftShims/AppKit/Text.swift.
import AppKit
let corpus = ((try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
let sizes: [CGFloat] = [8, 9, 10, 11, 12, 13, 14, 15, 17, 20, 24, 30, 34, 40]
for (name, w) in [("regular", NSFont.Weight.regular), ("medium", .medium), ("semibold", .semibold), ("bold", .bold)] {
    var row: [String] = []
    for s in sizes {
        let f = NSFont.systemFont(ofSize: s, weight: w)
        let t = corpus.reduce(0.0) { $0 + Double(($1 as NSString).size(withAttributes: [.font: f]).width) }
        row.append(String(format: "%.1f", t))
    }
    print(name, row.joined(separator: " "))
}
