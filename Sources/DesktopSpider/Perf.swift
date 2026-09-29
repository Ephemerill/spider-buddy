import Foundation
import QuartzCore

// MARK: - Where the main thread's time goes (developer only)
//
// Everything the spider does happens on the main thread, once a frame: a
// stretch of work there that runs long is a frame the spider misses — a
// stutter. None of this runs unless asked for:
//
//   SPIDER_TIMING=1   how long each named stretch of work took (opening the
//                     habitat, building the panel…), as it happens
//   SPIDER_FRAMES=1   once a second: frames, how long the main thread was
//                     busy for each (mean, worst), how many ran over, the
//                     longest gap between frames; and any stretch of
//                     main-thread work over 12 ms, whatever it was

enum Perf {
    static let timing = ProcessInfo.processInfo.environment["SPIDER_TIMING"] == "1"
    static let frames = ProcessInfo.processInfo.environment["SPIDER_FRAMES"] == "1"

    /// Times `f` (with SPIDER_TIMING=1), printing it under `label`.
    @inline(__always)
    static func measure<T>(_ label: @autoclosure () -> String, _ f: () throws -> T) rethrows -> T {
        guard timing else { return try f() }
        let t0 = CACurrentMediaTime()
        let r = try f()
        note(label(), ms: (CACurrentMediaTime() - t0) * 1000)
        return r
    }

    static func note(_ label: String, ms: Double) {
        print(String(format: "timing: %7.1f ms  %@", ms, label))
        fflush(stdout)
    }

    /// The frame meter, if SPIDER_FRAMES=1.
    static let meter: FrameMeter? = frames ? FrameMeter() : nil
}

/// Counts what each frame costs the main thread: from the frame clock
/// firing to the run loop going back to sleep (the spider's update, and
/// Core Animation drawing and committing what changed), printed once a
/// second — and any stretch of main-thread work, frame or not, that runs
/// over 12 ms.
final class FrameMeter {
    private var tickAt: CFTimeInterval = 0
    private var inFrame = false
    private var wokeAt: CFTimeInterval = 0
    private var lastTick: CFTimeInterval = 0
    private var n = 0, over = 0, redraws = 0
    private var busy: Double = 0, worst: Double = 0, gap: Double = 0, tickSum: Double = 0
    private var since: CFTimeInterval = 0
    private var observer: CFRunLoopObserver?
    /// What the frame did that is worth knowing when it runs long.
    var context = ""

    init() {
        let obs = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
                                                     true, Int.max) { [weak self] _, activity in
            self?.ran(activity)
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), obs, .commonModes)
        observer = obs
    }

    private func ran(_ activity: CFRunLoopActivity) {
        let now = CACurrentMediaTime()
        if activity == .afterWaiting {
            wokeAt = now
            return
        }
        // About to sleep: the stretch since waking is done.
        let stretch = (now - wokeAt) * 1000
        if inFrame {
            inFrame = false
            let b = (now - tickAt) * 1000
            busy += b
            worst = max(worst, b)
            if b > 12 { over += 1 }
        }
        if stretch > 12, wokeAt > 0 {
            print(String(format: "frames: main thread busy %.1f ms in one go%@", stretch, context.isEmpty ? "" : " (\(context))"))
            fflush(stdout)
        }
        wokeAt = now
    }

    /// The frame clock has fired.
    func tickBegan() {
        let now = CACurrentMediaTime()
        if lastTick > 0 { gap = max(gap, (now - lastTick) * 1000) }
        lastTick = now
        tickAt = now
        inFrame = true
        n += 1
        if since == 0 { since = now }
    }

    /// The spider's own work for the frame is done (Core Animation's is next).
    func tickEnded(redrew: Bool) {
        tickSum += (CACurrentMediaTime() - tickAt) * 1000
        if redrew { redraws += 1 }
        let now = CACurrentMediaTime()
        guard now - since >= 1 else { return }
        let f = Double(max(n, 1))
        print(String(format: "frames: %3d/s  busy %5.2f ms mean %5.1f worst  update %5.2f ms  over 12 ms: %d  longest gap %5.1f ms  redraws %d%@",
                     n, busy / f, worst, tickSum / f, over, gap, redraws, context.isEmpty ? "" : "  [\(context)]"))
        fflush(stdout)
        n = 0; over = 0; redraws = 0; busy = 0; worst = 0; gap = 0; tickSum = 0
        since = now
    }
}
