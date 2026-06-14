import AppKit

// Menu-bar (accessory) app: no Dock icon, lives in the status bar.
let appDelegate = AppDelegate()
let app = NSApplication.shared
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
