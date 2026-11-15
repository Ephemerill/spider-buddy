// Windows replacement for the Mac's Updater.swift. Sparkle does not exist here: the signed Windows updater fills this in
// with the installer work. Same names, so the panel's update rows work.
import AppKit

final class Updater: NSObject {
    static var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.1" }
    override init() { super.init() }
    var onChange: (() -> Void)?
    var canCheck: Bool { false }
    var checksAutomatically: Bool { get { false } set {} }
    var installsAutomatically: Bool { get { false } set {} }
    var busy: Bool { false }
    /// A newer version found on the daily check, not yet looked at.
    private(set) var waiting: String?
    /// Why the updater would not start; nil when it did.
    private(set) var startError: Error?
    func check() {}
}

enum AppInfo {
    static var name: String { "Spider Buddy" }
    static func takeOwnNameIfNeeded() {}
}
