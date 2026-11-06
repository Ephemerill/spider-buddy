import AppKit

// What the Mac's scroll events look like, so the Windows wheel can be mapped
// to the same orders: the sign, size and count of the deltas of a mouse wheel
// notch and of a trackpad swipe, with natural scrolling on and off.
//
//   ./tools/scrollprobe.sh [seconds] > scroll.txt      (default 40)
//
// Scroll anywhere on the screen while it runs. Every event is printed.
// dy is `scrollingDeltaY`, what Spider.scroll(_:precise:startsGesture:) is given.

setvbuf(stdout, nil, _IONBF, 0)
let secs = Double(CommandLine.arguments.dropFirst().first ?? "40") ?? 40
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let start = Date()
NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { e in
    print(String(format: "%.3f dy=%.3f dx=%.3f precise=%d phase=%lu momentum=%lu naturalDirection=%d",
                 Date().timeIntervalSince(start), Double(e.scrollingDeltaY), Double(e.scrollingDeltaX),
                 e.hasPreciseScrollingDeltas ? 1 : 0, e.phase.rawValue, e.momentumPhase.rawValue,
                 e.isDirectionInvertedFromDevice ? 1 : 0))
}
Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { _ in exit(0) }
FileHandle.standardError.write("Scrolling is being logged for \(Int(secs)) s: wheel notch down x3, up x3; trackpad swipe down, up; then switch natural scrolling and repeat.\n".data(using: .utf8)!)
app.run()
