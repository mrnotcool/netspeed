import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // 无 Dock 图标，菜单栏可用
let delegate = AppDelegate()
app.delegate = delegate
app.run()
