// TEMPORARY, while the launch crash is found: the Mac's main.swift with a crash reporter installed first and
// marks of how far start-up got. Delete this file once the app starts, so the Mac's own main.swift is used again.
import AppKit

CrashStack.install()
CrashStack.mark("main")
let app = NSApplication.shared
CrashStack.mark("app")
// (Its ways about its tank are worked out off the main thread here: see
// "Its ways about the tank" in Spider.swift.)
Spider.waysOffMain = true
let delegate = AppDelegate()
CrashStack.mark("delegate")
app.delegate = delegate
app.setActivationPolicy(.accessory)
CrashStack.mark("run")
app.run()
