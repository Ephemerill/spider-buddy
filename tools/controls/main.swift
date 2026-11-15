// Control gallery: every kind of control the app uses, in light and dark, drawn to PNGs. Built against real AppKit on
// the Mac and against the AppKit stand-in on Windows, so the two can be compared picture for picture:
//   Mac:      tools/controls/run.sh <dir>
//   Windows:  tools/windows/swift/controls <dir>
// Frames are set from each control's own intrinsic size, so sizes are compared too.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "controls"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
NSApp.finishLaunching()

#if os(macOS)
/// Drawn as the key window, which the app's windows are when seen. (A background process cannot take focus on newer
/// macOS, and AppKit draws a window that is not key with grey controls.)
final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
}
#else
typealias KeyWindow = NSWindow
#endif

final class Back: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ r: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

func button(_ t: String, _ size: NSControl.ControlSize, `default`: Bool = false, style: NSButton.BezelStyle = .rounded) -> NSButton {
    let b = NSButton(title: t, target: nil, action: nil)
    b.bezelStyle = style
    b.controlSize = size
    if `default` { b.keyEquivalent = "\r" }
    return b
}
func rows() -> [(String, [NSView])] {
    var r: [(String, [NSView])] = []
    r.append(("push", [button("Show Me", .regular), button("Next", .large, default: true), button("Small", .small), button("Large", .large), button("Mini", .mini)]))
    let borderless = NSButton(title: "Skip", target: nil, action: nil); borderless.isBordered = false; borderless.contentTintColor = .secondaryLabelColor
    let inline = NSButton(title: "Inline", target: nil, action: nil); inline.bezelStyle = .inline
    let disabled = button("Disabled", .regular); disabled.isEnabled = false
    r.append(("other buttons", [borderless, inline, disabled]))
    let on = NSSwitch(); on.state = .on
    let off = NSSwitch(); off.state = .off
    let smallOn = NSSwitch(); smallOn.controlSize = .small; smallOn.state = .on
    let smallOff = NSSwitch(); smallOff.controlSize = .small; smallOff.state = .off
    let miniOn = NSSwitch(); miniOn.controlSize = .mini; miniOn.state = .on
    r.append(("switches", [on, off, smallOn, smallOff, miniOn]))
    let check = NSButton(checkboxWithTitle: "Checked", target: nil, action: nil); check.state = .on
    let uncheck = NSButton(checkboxWithTitle: "Unchecked", target: nil, action: nil)
    let radio = NSButton(radioButtonWithTitle: "Radio on", target: nil, action: nil); radio.state = .on
    let radioOff = NSButton(radioButtonWithTitle: "Radio off", target: nil, action: nil)
    r.append(("check and radio", [check, uncheck, radio, radioOff]))
    let seg = NSSegmentedControl(labels: ["Tiny", "Small", "Medium", "Large"], trackingMode: .selectOne, target: nil, action: nil); seg.selectedSegment = 2
    let segSmall = NSSegmentedControl(labels: ["Sleepy", "Calm", "Normal"], trackingMode: .selectOne, target: nil, action: nil); segSmall.controlSize = .small; segSmall.selectedSegment = 1
    r.append(("segmented", [seg, segSmall]))
    let field = NSTextField(string: "Mocha"); field.frame.size.width = 160
    let placeholder = NSTextField(string: ""); placeholder.placeholderString = "Name"; placeholder.frame.size.width = 160
    let pop = NSPopUpButton(frame: .zero, pullsDown: false); pop.addItems(withTitles: ["Everything", "Plants"])
    r.append(("fields", [field, placeholder, pop]))
    let slider = NSSlider(value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil); slider.frame.size.width = 160
    let ticks = NSSlider(value: 2, minValue: 0, maxValue: 4, target: nil, action: nil); ticks.numberOfTickMarks = 5; ticks.allowsTickMarkValuesOnly = true; ticks.frame.size.width = 160
    let bar = NSProgressIndicator(); bar.isIndeterminate = false; bar.doubleValue = 60; bar.frame.size.width = 160
    r.append(("sliders", [slider, ticks, bar]))
    let label = NSTextField(labelWithString: "Label"); let sec = NSTextField(labelWithString: "Secondary"); sec.textColor = .secondaryLabelColor
    let small = NSTextField(labelWithString: "Small 11"); small.font = .systemFont(ofSize: 11)
    let bold = NSTextField(labelWithString: "Bold 15"); bold.font = .systemFont(ofSize: 15, weight: .bold)
    r.append(("labels", [label, sec, small, bold]))
    let syms = ["house", "sparkles", "fork.knife", "person.2", "slider.horizontal.3", "laptopcomputer", "gearshape", "ladybug", "cloud.rain", "power", "eye", "scribble.variable", "magnifyingglass", "wifi", "battery.75percent"]
    r.append(("symbols", syms.map { n in
        let v = NSImageView(image: NSImage(systemSymbolName: n, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 17, weight: .regular)) ?? NSImage(size: NSSize(width: 17, height: 17)))
        v.contentTintColor = .labelColor
        return v
    }))
    return r
}

for (name, ap) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    let W: CGFloat = 640, rowH: CGFloat = 44
    let rs = rows()
    let H = CGFloat(rs.count) * rowH + 10
    let win = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: W, height: H), styleMask: [.titled], backing: .buffered, defer: false)
    win.appearance = NSAppearance(named: ap)
    let root = Back(frame: NSRect(x: 0, y: 0, width: W, height: H))
    win.contentView = root
    var report = ""
    for (i, (title, views)) in rs.enumerated() {
        let y = 10 + CGFloat(i) * rowH
        let l = NSTextField(labelWithString: title); l.font = .systemFont(ofSize: 10); l.textColor = .tertiaryLabelColor
        l.frame = NSRect(x: 8, y: y + 12, width: 92, height: 14); root.addSubview(l)
        var x: CGFloat = 104
        for v in views {
            let n = v.fittingSize
            let w = n.width > 0 ? n.width : max(v.frame.width, 60), h = n.height > 0 ? n.height : 20
            let w2 = v.frame.width > w ? v.frame.width : w
            v.frame = NSRect(x: x, y: y + (30 - h) / 2, width: w2, height: h)
            root.addSubview(v)
            report += String(format: "%@ %@ %.1fx%.1f\n", title, String(describing: type(of: v)), w2, h)
            x += w2 + 12
        }
    }
    // On screen and key for a moment, as the app's windows are when seen: AppKit draws a window that is not key with
    // grey controls.
    win.setFrameOrigin(NSPoint(x: 40, y: 40))
    NSApp.activate(ignoringOtherApps: true)
    win.makeKeyAndOrderFront(nil)
    win.makeFirstResponder(nil)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
    root.layoutSubtreeIfNeeded()
    root.display()
    guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { continue }
    root.cacheDisplay(in: root.bounds, to: rep)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(out)/controls-\(name).png"))
    try? report.write(toFile: "\(out)/controls-\(name).txt", atomically: true, encoding: .utf8)
    win.orderOut(nil)
}
print("wrote \(out)")
