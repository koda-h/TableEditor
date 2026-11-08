import AppKit

// XIB / Storyboard を使わずコードだけで構成する
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.mainMenu = MainMenu.make()
app.run()
