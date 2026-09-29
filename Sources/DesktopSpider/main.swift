import AppKit

let app = NSApplication.shared
// (Its ways about its tank are worked out off the main thread here: see
// "Its ways about the tank" in Spider.swift.)
Spider.waysOffMain = true
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
