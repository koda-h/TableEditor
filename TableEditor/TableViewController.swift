import AppKit
import CSVCore

/// 表の表示と編集操作。View ベースの NSTableView を使う。
///
/// 列の識別子にはモデル上の列番号を入れる。列をドラッグで並べ替えたら
/// モデル側も並べ替え、列を作り直して「表示上の位置 = モデルの列番号」に戻す。
///
/// View ベースの NSTableView は列選択に対応していないので、
/// 「選択中の列」は `highlightedTableColumn`（ヘッダーかセルを最後にクリックした列）で表す。
final class TableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation,
    NSMenuDelegate {
    private weak var document: Document?
    private let tableView = NSTableView()
    private let cellIdentifier = NSUserInterfaceItemIdentifier("Cell")
    private var isRebuildingColumns = false

    init(document: Document) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var table: CSVTable { document?.table ?? CSVTable() }

    override func loadView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.target = self
        tableView.action = #selector(tableClicked(_:))
        tableView.doubleAction = #selector(tableDoubleClicked(_:))
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.gridStyleMask = [.solidVerticalGridLineMask]
        tableView.style = .plain
        tableView.rowSizeStyle = .default
        tableView.menu = makeContextMenu()

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        view = scrollView

        rebuildColumns()
    }

    func apply(_ change: TableChange) {
        switch change {
        case .cell(let row, let column):
            let viewColumn = tableView.column(withIdentifier: identifier(for: column))
            guard row < tableView.numberOfRows, viewColumn >= 0 else { return tableView.reloadData() }
            tableView.reloadData(forRowIndexes: [row], columnIndexes: [viewColumn])
        case .rows:
            tableView.reloadData()
        case .columns:
            rebuildColumns()
            tableView.reloadData()
        }
    }

    // MARK: - Context menu

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        func add(_ title: String, _ action: Selector) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
            item.target = self
        }
        add(String(localized: "Add Row Above"), #selector(addRowAbove(_:)))
        add(String(localized: "Add Row Below"), #selector(addRowBelow(_:)))
        menu.addItem(.separator())
        add(String(localized: "Delete Rows"), #selector(deleteSelectedRows(_:)))
        return menu
    }

    /// 右クリックした行を操作の対象にする（Finder と同じく、選択外の行なら選択し直す）。
    /// 行のない所を右クリックしたときは選択を外し、「行を追加」で末尾に追加されるようにする。
    func menuNeedsUpdate(_ menu: NSMenu) {
        let row = tableView.clickedRow
        if row < 0 {
            tableView.deselectAll(nil)
        } else if !tableView.selectedRowIndexes.contains(row) {
            tableView.selectRowIndexes([row], byExtendingSelection: false)
        }
    }

    // MARK: - Columns

    private func identifier(for column: Int) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(String(column))
    }

    private func modelColumn(_ tableColumn: NSTableColumn?) -> Int? {
        tableColumn.flatMap { Int($0.identifier.rawValue) }
    }

    private func rebuildColumns() {
        isRebuildingColumns = true
        defer { isRebuildingColumns = false }
        let highlighted = selectedColumn
        let widths = Dictionary(uniqueKeysWithValues: tableView.tableColumns.map { ($0.identifier, $0.width) })
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        for index in 0..<table.columnCount {
            let id = identifier(for: index)
            let column = NSTableColumn(identifier: id)
            column.title = table.columnTitle(index)
            column.width = widths[id] ?? 120
            column.minWidth = 40
            tableView.addTableColumn(column)
        }
        if let highlighted, highlighted < tableView.tableColumns.count {
            tableView.highlightedTableColumn = tableView.tableColumns[highlighted]
        }
    }

    /// 選択中の列（モデルの列番号）
    private var selectedColumn: Int? {
        modelColumn(tableView.highlightedTableColumn)
    }

    @objc private func tableClicked(_ sender: Any?) {
        guard tableView.clickedColumn >= 0 else { return }
        tableView.highlightedTableColumn = tableView.tableColumns[tableView.clickedColumn]
    }

    /// ダブルクリックしたセルを編集する。
    /// NSTableView は「選択済みの行をクリックして少し待つ」ときしか編集を始めないため、
    /// 未選択の行をダブルクリックしても編集にならない。ここで明示的に編集を始める。
    @objc private func tableDoubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard row >= 0, column >= 0 else { return }
        tableView.editColumn(column, row: row, with: nil, select: true)
    }

    /// ヘッダーのクリックで列を選択する（行の選択は外して、削除・コピーの対象を列にする）
    func tableView(_ tableView: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
        tableView.highlightedTableColumn = tableColumn
        tableView.deselectAll(nil)
    }

    func tableViewColumnDidMove(_ notification: Notification) {
        guard !isRebuildingColumns,
              let old = notification.userInfo?["NSOldColumn"] as? Int,
              let new = notification.userInfo?["NSNewColumn"] as? Int,
              old != new
        else { return }
        // 通知の処理中に列を作り直さないよう、次のランループで反映する
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.document?.moveColumn(from: old, to: new)
            self.selectColumn(new)
        }
    }

    // MARK: - Data source / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        table.rowCount
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let column = modelColumn(tableColumn), column < table.columnCount, row < table.rowCount else { return nil }
        let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView ?? makeCellView()
        let value = table[row, column]
        cell.textField?.stringValue = value
        let decimalMark = document?.tableDecimalMark ?? "."
        cell.textField?.alignment = NumberFormat.isNumber(value, decimalMark: decimalMark) ? .right : .natural
        return cell
    }

    private func makeCellView() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = cellIdentifier
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = true
        field.target = self
        field.action = #selector(cellEdited(_:))
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func cellEdited(_ sender: NSTextField) {
        let row = tableView.row(for: sender)
        let viewColumn = tableView.column(for: sender)
        guard row >= 0, viewColumn >= 0, let column = modelColumn(tableView.tableColumns[viewColumn]) else { return }
        document?.setValue(sender.stringValue, row: row, column: column)
    }

    // MARK: - Row / Column actions

    @objc func addRowAbove(_ sender: Any?) {
        insertRow(at: tableView.selectedRowIndexes.first ?? 0)
    }

    @objc func addRowBelow(_ sender: Any?) {
        insertRow(at: tableView.selectedRowIndexes.last.map { $0 + 1 } ?? table.rowCount)
    }

    @objc func addColumnLeft(_ sender: Any?) {
        insertColumn(at: selectedColumn ?? 0)
    }

    @objc func addColumnRight(_ sender: Any?) {
        insertColumn(at: selectedColumn.map { $0 + 1 } ?? table.columnCount)
    }

    @objc func deleteSelectedRows(_ sender: Any?) {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return NSSound.beep() }
        document?.removeRows(at: rows)
    }

    @objc func deleteSelectedColumns(_ sender: Any?) {
        guard let column = selectedColumn else { return NSSound.beep() }
        document?.removeColumns(at: [column])
        tableView.highlightedTableColumn = nil
    }

    private func insertRow(at index: Int) {
        guard let document else { return }
        if table.columnCount == 0 { document.insertColumns([.init(title: nil, cells: [])], at: [0]) }
        document.insertRows([Array(repeating: "", count: table.columnCount)], at: [index])
        tableView.selectRowIndexes([index], byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        tableView.editColumn(0, row: index, with: nil, select: true)
    }

    private func insertColumn(at index: Int) {
        document?.insertColumns([.init(title: nil, cells: [])], at: [index])
        selectColumn(index)
    }

    private func selectColumn(_ index: Int) {
        guard index < tableView.tableColumns.count else { return }
        tableView.highlightedTableColumn = tableView.tableColumns[index]
        tableView.scrollColumnToVisible(index)
    }

    // MARK: - Copy / Paste / Delete

    /// クリップボードとのやり取りはタブ区切り（Excel / Numbers と互換）
    private static let clipboardFormat = CSVConfiguration(delimiter: "\t", quotingStyle: .minimal)

    @objc func copy(_ sender: Any?) {
        let rows: [[String]]
        if !tableView.selectedRowIndexes.isEmpty {
            rows = tableView.selectedRowIndexes.map { table.rows[$0] }
        } else if let column = selectedColumn {
            rows = table.rows.map { [$0[column]] }
        } else {
            rows = []
        }
        guard !rows.isEmpty else { return NSSound.beep() }
        let text = CSVWriter.string(for: CSVTable(rows: rows), configuration: Self.clipboardFormat)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func cut(_ sender: Any?) {
        copy(sender)
        delete(sender)
    }

    @objc func paste(_ sender: Any?) {
        guard let document, let text = NSPasteboard.general.string(forType: .string) else { return }
        var rows: [[String]]
        if var reader = try? CSVReader(string: text, configuration: Self.clipboardFormat),
           let parsed = try? reader.readAll() {
            rows = parsed
        } else {
            var reader = try? CSVReader(string: text, configuration: .tabSeparatedPlain)
            rows = (try? reader?.readAll()) ?? []
        }
        guard !rows.isEmpty else { return }

        // 列が足りなければ先に列を足す（同じイベント内なので Undo は 1 回で戻る）
        let width = rows.map(\.count).max() ?? 0
        if width > table.columnCount {
            let added = table.columnCount..<width
            document.insertColumns(added.map { _ in .init(title: nil, cells: []) }, at: IndexSet(integersIn: added))
        }
        rows = rows.map { $0 + Array(repeating: "", count: table.columnCount - $0.count) }

        let start = tableView.selectedRowIndexes.last.map { $0 + 1 } ?? table.rowCount
        let indexes = IndexSet(integersIn: start..<(start + rows.count))
        document.insertRows(rows, at: indexes)
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        tableView.scrollRowToVisible(start)
    }

    @objc func delete(_ sender: Any?) {
        if !tableView.selectedRowIndexes.isEmpty {
            deleteSelectedRows(sender)
        } else {
            deleteSelectedColumns(sender)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Delete / Forward Delete
            delete(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasRows = !tableView.selectedRowIndexes.isEmpty
        let hasColumns = selectedColumn != nil
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return hasRows || hasColumns
        case #selector(deleteSelectedRows(_:)):
            return hasRows
        case #selector(deleteSelectedColumns(_:)):
            return hasColumns
        case #selector(paste(_:)):
            return NSPasteboard.general.string(forType: .string) != nil
        default:
            return true
        }
    }
}
