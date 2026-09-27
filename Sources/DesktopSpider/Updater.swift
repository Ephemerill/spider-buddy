import AppKit
import Sparkle

/// Updates, through Sparkle.
///
/// Each GitHub release carries the .dmg and an appcast.xml describing it
/// (tools/release.sh makes both); the app reads the newest release's
/// appcast, `SUFeedURL` in Info.plist. The feed and the .dmg are both signed
/// with an EdDSA key and checked against `SUPublicEDKey` before anything is
/// installed, so an ad-hoc signed app can still trust what it downloads.
/// Sparkle takes the downloaded app out of quarantine, so after the first
/// install Gatekeeper does not ask again.
///
/// It looks once a day by itself. The spider lives in the menu bar with no
/// Dock icon, so an update found in the background is not thrown in front of
/// whatever the user is doing: it waits (`waiting`) for them to open the
/// panel and ask for it — a "gentle reminder", in Sparkle's words.
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []

    /// A newer version found on the daily check, not yet looked at.
    private(set) var waiting: String?

    /// Why Sparkle would not start (a broken bundle, say); nil when it did.
    private(set) var startError: Error?

    /// Called back on the main thread when the state changes (for the menu).
    var onChange: (() -> Void)?

    override init() {
        super.init()
        // Started here rather than by the controller, which would put up an
        // alert at launch if it can't; a menu bar pet says so in its panel.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self,
                                                  userDriverDelegate: self)
        let updater = controller.updater
        do {
            try updater.start()
        } catch {
            startError = error
            NSLog("Updates are off: %@", String(describing: error))
        }
        observations = [
            updater.observe(\.canCheckForUpdates) { [weak self] _, _ in self?.changed() },
            updater.observe(\.automaticallyChecksForUpdates) { [weak self] _, _ in self?.changed() },
            updater.observe(\.automaticallyDownloadsUpdates) { [weak self] _, _ in self?.changed() },
        ]
        // SPIDER_UPDATE_TEST=1 (tools): look straight away, in the
        // background, as the daily check would.
        if ProcessInfo.processInfo.environment["SPIDER_UPDATE_TEST"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.controller.updater.checkForUpdatesInBackground()
            }
        }
    }

    /// False while a check or an update is already under way.
    var canCheck: Bool { controller.updater.canCheckForUpdates }

    var checksAutomatically: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Downloads updates in the background and installs them when the app
    /// next quits, without asking.
    var installsAutomatically: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    /// Looks now, and shows what it finds (or the one it was holding).
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    private func changed() {
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows an update found right after launch itself (the user has
    /// just opened the app, so it is not an interruption); later ones wait.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if handleShowingUpdate {
            NSApp.activate(ignoringOtherApps: true)
        } else if !state.userInitiated {
            waiting = update.displayVersionString
            changed()
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        waiting = nil
        changed()
    }

    func standardUserDriverWillFinishUpdateSession() {
        waiting = nil
        changed()
    }
}

// MARK: - App identity

/// The app's own name: "Spider Buddy" for a release, "spiders" for the
/// testing build (see build.sh).
enum AppInfo {
    static var name: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "Spider Buddy"
    }

    /// An update from 1.1.0 lands as "Spider.app" (that version's updater
    /// kept the old bundle's name). A release that finds itself so named
    /// takes its own name, once, where it can.
    static func takeOwnNameIfNeeded() {
        let fm = FileManager.default
        let here = Bundle.main.bundleURL
        guard here.lastPathComponent == "Spider.app", name == "Spider Buddy",
              !here.path.hasPrefix("/Volumes/") else { return }
        let dir = here.deletingLastPathComponent()
        let there = dir.appendingPathComponent("Spider Buddy.app")
        guard fm.isWritableFile(atPath: dir.path), !fm.fileExists(atPath: there.path) else { return }
        try? fm.moveItem(at: here, to: there)
    }
}
