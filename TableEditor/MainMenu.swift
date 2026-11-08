import AppKit

/// メインメニュー。アクションは First Responder（nil ターゲット）経由で Document / TableViewController に届く。
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let mainMenu = NSMenu()

        // App
        mainMenu.addSubmenu(appName) { menu in
            menu.addItem(String(localized: "About \(appName)"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
            menu.addItem(.separator())
            menu.addItem(String(localized: "Hide \(appName)"), #selector(NSApplication.hide(_:)), "h")
            menu.addItem(String(localized: "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
            menu.addItem(String(localized: "Show All"), #selector(NSApplication.unhideAllApplications(_:)))
            menu.addItem(.separator())
            menu.addItem(String(localized: "Quit \(appName)"), #selector(NSApplication.terminate(_:)), "q")
        }

        // File
        mainMenu.addSubmenu(String(localized: "File")) { menu in
            menu.addItem(String(localized: "New"), #selector(NSDocumentController.newDocument(_:)), "n")
            menu.addItem(String(localized: "Open…"), #selector(NSDocumentController.openDocument(_:)), "o")
            menu.addItem(.separator())
            menu.addItem(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w")
            menu.addItem(String(localized: "Save…"), #selector(NSDocument.save(_:)), "s")
            menu.addItem(String(localized: "Duplicate"), #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
            menu.addItem(String(localized: "Rename…"), #selector(NSDocument.rename(_:)))
            menu.addItem(String(localized: "Revert to Saved"), #selector(NSDocument.revertToSaved(_:)))
            menu.addItem(.separator())
            menu.addItem(String(localized: "File Format…"), #selector(Document.showFormatSheet(_:)), "f", [.command, .option])
        }

        // Edit
        mainMenu.addSubmenu(String(localized: "Edit")) { menu in
            menu.addItem(String(localized: "Undo"), Selector(("undo:")), "z")
            menu.addItem(String(localized: "Redo"), Selector(("redo:")), "z", [.command, .shift])
            menu.addItem(.separator())
            menu.addItem(String(localized: "Cut"), #selector(NSText.cut(_:)), "x")
            menu.addItem(String(localized: "Copy"), #selector(NSText.copy(_:)), "c")
            menu.addItem(String(localized: "Paste"), #selector(NSText.paste(_:)), "v")
            menu.addItem(String(localized: "Delete"), #selector(NSText.delete(_:)))
            menu.addItem(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a")
            menu.addItem(.separator())
            menu.addSubmenu(String(localized: "Find")) { find in
                find.addItem(String(localized: "Find…"), #selector(DocumentWindowController.showFind(_:)), "f")
                find.addItem(String(localized: "Find Next"), #selector(DocumentWindowController.findNext(_:)), "g")
                find.addItem(String(localized: "Find Previous"), #selector(DocumentWindowController.findPrevious(_:)), "g", [.command, .shift])
            }
        }

        // Table
        mainMenu.addSubmenu(String(localized: "Table")) { menu in
            menu.addItem(String(localized: "Add Row Above"), #selector(TableViewController.addRowAbove(_:)), "\r", [.command, .shift])
            menu.addItem(String(localized: "Add Row Below"), #selector(TableViewController.addRowBelow(_:)), "\r")
            menu.addItem(String(localized: "Add Column Left"), #selector(TableViewController.addColumnLeft(_:)))
            menu.addItem(String(localized: "Add Column Right"), #selector(TableViewController.addColumnRight(_:)))
            menu.addItem(.separator())
            menu.addItem(String(localized: "Delete Rows"), #selector(TableViewController.deleteSelectedRows(_:)), "\u{8}", [.command])
            menu.addItem(String(localized: "Delete Columns"), #selector(TableViewController.deleteSelectedColumns(_:)), "\u{8}", [.command, .option])
            menu.addItem(.separator())
            menu.addItem(String(localized: "Use First Row as Header"), #selector(Document.toggleHeaderRow(_:)))
        }

        // Window
        let windowMenu = mainMenu.addSubmenu(String(localized: "Window")) { menu in
            menu.addItem(String(localized: "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
            menu.addItem(String(localized: "Zoom"), #selector(NSWindow.performZoom(_:)))
            menu.addItem(.separator())
            menu.addItem(String(localized: "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)))
        }
        NSApp.windowsMenu = windowMenu

        let helpMenu = mainMenu.addSubmenu(String(localized: "Help")) { _ in }
        NSApp.helpMenu = helpMenu

        return mainMenu
    }
}

private extension NSMenu {
    @discardableResult
    func addSubmenu(_ title: String, _ build: (NSMenu) -> Void) -> NSMenu {
        let submenu = NSMenu(title: title)
        build(submenu)
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
        return submenu
    }

    func addItem(
        _ title: String, _ action: Selector, _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = [.command]
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        addItem(item)
    }
}
