import AppKit
import CSVCore

final class DocumentWindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate {
    private let tableViewController: TableViewController
    private let statusLabel = NSTextField(labelWithString: "")
    private weak var csvDocument: Document?
    private weak var searchField: NSSearchField?

    init(document: Document) {
        csvDocument = document
        tableViewController = TableViewController(document: document)

        let container = NSViewController()
        container.view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 560))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.tabbingMode = .preferred
        super.init(window: window)

        buildContent(in: container)
        window.contentViewController = container
        window.minSize = NSSize(width: 400, height: 250)
        window.toolbar = makeToolbar()
        window.toolbarStyle = .unified
        // 前回のウインドウ位置・サイズを復元（初回は中央に表示）
        if !window.setFrameUsingName("DocumentWindow") {
            window.setContentSize(NSSize(width: 900, height: 560))
            window.center()
        }
        window.setFrameAutosaveName("DocumentWindow")
        tableViewController.searchStatusChanged = { [weak self] in self?.updateStatus() }
        updateStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func documentDidChange(_ change: TableChange) {
        tableViewController.apply(change)
        updateStatus()
    }

    // MARK: - Layout

    private func buildContent(in container: NSViewController) {
        container.addChild(tableViewController)
        let tableView = tableViewController.view
        tableView.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        // ラベルの文字幅でウインドウサイズが決まらないようにする
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let root = container.view
        root.addSubview(tableView)
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: root.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 4),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -10),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5),
        ])
    }

    private func updateStatus() {
        guard let document = csvDocument else { return }
        let c = document.configuration
        let table = document.table
        statusLabel.stringValue = [
            tableViewController.searchSummary,
            String(localized: "\(table.rowCount) rows × \(table.columnCount) columns"),
            c.encoding.localizedName + (c.hasByteOrderMark ? " (BOM)" : ""),
            FormatLabels.delimiter(c.delimiter),
            FormatLabels.quote(c.quote, escape: c.escape),
            String(localized: "Decimal \(String(c.decimalMark))"),
        ].compactMap { $0 }.joined(separator: "  ·  ")
    }

    // MARK: - Search

    /// 編集 → 検索 → 検索…（⌘F）: ツールバーの検索欄にフォーカスする
    @objc func showFind(_ sender: Any?) {
        guard let searchField, let window else { return NSSound.beep() }
        window.makeFirstResponder(searchField)
        searchField.selectText(nil)
    }

    @objc func findNext(_ sender: Any?) {
        tableViewController.findNext(backward: false)
    }

    @objc func findPrevious(_ sender: Any?) {
        tableViewController.findNext(backward: true)
    }

    /// 入力のたびに一致セルを更新する（検索欄の × ボタンで消したときもここに来る）
    @objc private func searchFieldChanged(_ sender: NSSearchField) {
        tableViewController.setSearchQuery(sender.stringValue)
    }

    /// 検索欄で Return → 次を検索、Shift+Return → 前を検索
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField else { return false }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            tableViewController.setSearchQuery(control.stringValue)
            let backward = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            tableViewController.findNext(backward: backward)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            // Esc で検索を終了して表に戻る
            control.stringValue = ""
            tableViewController.setSearchQuery("")
            tableViewController.focusTable()
            return true
        default:
            return false
        }
    }

    // MARK: - Toolbar

    private enum ItemID {
        static let addRow = NSToolbarItem.Identifier("addRow")
        static let addColumn = NSToolbarItem.Identifier("addColumn")
        static let deleteRows = NSToolbarItem.Identifier("deleteRows")
        static let deleteColumns = NSToolbarItem.Identifier("deleteColumns")
        static let format = NSToolbarItem.Identifier("format")
        static let search = NSToolbarItem.Identifier("search")
    }

    private func makeToolbar() -> NSToolbar {
        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        return toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.addRow, ItemID.addColumn, .space, ItemID.deleteRows, ItemID.deleteColumns, .flexibleSpace,
         ItemID.format, ItemID.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if id == ItemID.search {
            let item = NSSearchToolbarItem(itemIdentifier: id)
            item.label = String(localized: "Search")
            let field = item.searchField
            field.placeholderString = String(localized: "Search")
            field.sendsSearchStringImmediately = true
            field.target = self
            field.action = #selector(searchFieldChanged(_:))
            field.delegate = self
            searchField = field
            return item
        }
        let item = NSToolbarItem(itemIdentifier: id)
        func configure(_ label: String, _ symbol: String, _ action: Selector) {
            item.label = label
            item.toolTip = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.action = action
            item.isBordered = true
        }
        switch id {
        case ItemID.addRow:
            configure(String(localized: "Add Row"), "plus.rectangle", #selector(TableViewController.addRowBelow(_:)))
        case ItemID.addColumn:
            configure(String(localized: "Add Column"), "rectangle.split.3x1", #selector(TableViewController.addColumnRight(_:)))
        case ItemID.deleteRows:
            configure(String(localized: "Delete Rows"), "minus.rectangle", #selector(TableViewController.deleteSelectedRows(_:)))
        case ItemID.deleteColumns:
            configure(String(localized: "Delete Columns"), "rectangle.badge.minus", #selector(TableViewController.deleteSelectedColumns(_:)))
        case ItemID.format:
            configure(String(localized: "File Format"), "doc.badge.gearshape", #selector(Document.showFormatSheet(_:)))
        default:
            return nil
        }
        return item
    }
}
