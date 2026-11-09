import AppKit
import CSVCore

/// 表の表示と編集操作。View ベースの NSTableView を使う。
///
/// 先頭（表示上の 0 列目）は行番号の列で、データの列はその右に並ぶ。
/// データの列の識別子にはモデル上の列番号を入れる。列をドラッグで並べ替えたら
/// モデル側も並べ替え、列を作り直して「表示上の位置 = モデルの列番号 + 1」に戻す。
///
/// View ベースの NSTableView は列選択に対応していないので、列の選択は自前で持つ。
/// - 列はヘッダーのクリックで選ぶ（⌘クリックで追加・解除、⇧クリックで範囲選択）
/// - 行の選択と列の選択はどちらか一方だけ（Excel と同じ）
/// - セルのクリックは行の選択だけ。クリックした列は `activeColumn` として覚え、
///   列の追加位置や検索の開始位置に使う
final class TableViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation,
    NSMenuDelegate, NSTextFieldDelegate {
    private weak var document: Document?
    private let tableView = NSTableView()
    private let cellIdentifier = NSUserInterfaceItemIdentifier("Cell")
    private let rowNumberIdentifier = NSUserInterfaceItemIdentifier("RowNumber")
    private var isRebuildingColumns = false

    // 列の選択（モデルの列番号）
    private var selectedColumns = IndexSet()
    /// 最後にクリックした列（セルでもヘッダーでも）
    private var activeColumn: Int?
    /// ⇧クリックの範囲選択の起点
    private var columnAnchor: Int?

    // 見出しの編集
    private var headerEditor: NSTextField?
    private var editingHeaderColumn: Int?

    // 検索
    private var searchQuery = ""
    private var searchMatches: [CellPosition] = []
    private var searchMatchSet: Set<CellPosition> = []
    private var currentMatch: CellPosition?
    /// 検索結果が変わったときに呼ぶ（ステータスバーの更新用）
    var searchStatusChanged: (() -> Void)?

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

        let header = ColumnSelectionHeaderView(frame: tableView.headerView?.frame ?? NSRect(x: 0, y: 0, width: 0, height: 28))
        header.selectedViewColumns = { [weak self] in self?.selectedViewColumns ?? [] }
        header.onDoubleClick = { [weak self] viewColumn in self?.beginEditingHeader(viewColumn: viewColumn) }
        tableView.headerView = header

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        view = scrollView

        rebuildColumns()
    }

    func apply(_ change: TableChange) {
        if !searchQuery.isEmpty { updateSearchMatches() }
        switch change {
        case .cell(let row, let column):
            let viewColumn = tableView.column(withIdentifier: identifier(for: column))
            guard row < tableView.numberOfRows, viewColumn >= 0 else { return tableView.reloadData() }
            tableView.reloadData(forRowIndexes: [row], columnIndexes: [viewColumn])
        case .rows:
            updateRowNumberWidth()
            tableView.reloadData()
        case .columns:
            // Undo などで列が作り直されるときは、編集中の見出しを確定せずに閉じる
            endEditingHeader(commit: false)
            rebuildColumns()
            tableView.reloadData()
            // Undo などで列が減ったら、なくなった列を選択から外す
            if let active = activeColumn, active >= table.columnCount { activeColumn = nil }
            selectedColumns = selectedColumns.filteredIndexSet { $0 < table.columnCount }
            redrawColumnSelection()
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

    /// モデルの列番号。行番号の列なら nil
    private func modelColumn(_ tableColumn: NSTableColumn?) -> Int? {
        tableColumn.flatMap { Int($0.identifier.rawValue) }
    }

    /// モデルの列番号 → 表示上の列番号（先頭に行番号の列があるので 1 ずれる）
    private func viewColumn(for column: Int) -> Int {
        tableView.column(withIdentifier: identifier(for: column))
    }

    private func rebuildColumns() {
        isRebuildingColumns = true
        defer { isRebuildingColumns = false }
        let widths = Dictionary(uniqueKeysWithValues: tableView.tableColumns.map { ($0.identifier, $0.width) })
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }

        let numbers = NSTableColumn(identifier: rowNumberIdentifier)
        numbers.title = ""
        numbers.resizingMask = []
        numbers.isEditable = false
        tableView.addTableColumn(numbers)
        updateRowNumberWidth()

        for index in 0..<table.columnCount {
            let id = identifier(for: index)
            let column = NSTableColumn(identifier: id)
            column.title = table.columnTitle(index)
            column.width = widths[id] ?? 120
            column.minWidth = 40
            tableView.addTableColumn(column)
        }
    }

    /// 行番号の列の幅を桁数に合わせる
    private func updateRowNumberWidth() {
        guard let column = tableView.tableColumn(withIdentifier: rowNumberIdentifier) else { return }
        let digits = String(max(table.rowCount, 1)).count
        let width = max(32, CGFloat(digits) * 8 + 16)
        column.minWidth = width
        column.maxWidth = width
        column.width = width
    }

    // MARK: - Header editing

    /// 見出しの上にテキスト欄を重ねて編集する。NSTableHeaderView 自体には編集機能がない。
    /// ヘッダー行がない（列名が A, B, C …）ときは編集できない。
    private func beginEditingHeader(viewColumn: Int) {
        guard viewColumn < tableView.numberOfColumns,
              let column = modelColumn(tableView.tableColumns[viewColumn]),
              let header = tableView.headerView
        else { return }
        guard table.header != nil else { return NSSound.beep() }
        endEditingHeader(commit: true)

        tableView.scrollColumnToVisible(viewColumn)
        header.layoutSubtreeIfNeeded()
        let field = NSTextField(frame: header.headerRect(ofColumn: viewColumn).insetBy(dx: 3, dy: 3))
        field.stringValue = table.columnTitle(column)
        field.font = tableView.tableColumns[viewColumn].headerCell.font
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.delegate = self
        header.addSubview(field)
        headerEditor = field
        editingHeaderColumn = column
        view.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    /// 見出しの編集を終える。`commit` なら入力を反映する（Undo できる）
    private func endEditingHeader(commit: Bool, focusTable shouldFocus: Bool = false) {
        guard let field = headerEditor, let column = editingHeaderColumn else { return }
        // 確定で列が作り直されて再入するので、先に状態を消す
        headerEditor = nil
        editingHeaderColumn = nil
        let title = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()
        if commit { document?.setHeaderTitle(title, column: column) }
        if shouldFocus { focusTable() }
    }

    /// Return・Tab で確定して表に戻る。ほかの場所をクリックしたときは確定だけ
    func controlTextDidEndEditing(_ obj: Notification) {
        guard (obj.object as? NSTextField) === headerEditor else { return }
        let movement = obj.userInfo?["NSTextMovement"] as? Int ?? NSTextMovement.other.rawValue
        endEditingHeader(commit: true, focusTable: movement != NSTextMovement.other.rawValue)
    }

    /// Esc で取り消して表に戻る
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === headerEditor, selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        endEditingHeader(commit: false, focusTable: true)
        return true
    }

    // MARK: - Column selection

    /// 選択中の列（表示上の列番号）。行ビューとヘッダーの描画用
    private var selectedViewColumns: IndexSet {
        IndexSet(selectedColumns.map { viewColumn(for: $0) }.filter { $0 >= 0 })
    }

    private func setSelectedColumns(_ columns: IndexSet) {
        let valid = columns.filteredIndexSet { $0 < table.columnCount }
        guard valid != selectedColumns else { return }
        selectedColumns = valid
        redrawColumnSelection()
    }

    private func redrawColumnSelection() {
        tableView.headerView?.needsDisplay = true
        tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
    }

    /// モデルの列番号で 1 列だけを選択し、見える位置までスクロールする（行の選択は外す）
    private func selectColumn(_ index: Int) {
        let view = viewColumn(for: index)
        guard view >= 0 else { return }
        tableView.deselectAll(nil)
        setSelectedColumns([index])
        activeColumn = index
        columnAnchor = index
        tableView.scrollColumnToVisible(view)
    }

    /// ヘッダーのクリックで列を選択する。⌘ で追加・解除、⇧ で起点からの範囲。
    func tableView(_ tableView: NSTableView, mouseDownInHeaderOf tableColumn: NSTableColumn) {
        guard let column = modelColumn(tableColumn) else { return }
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        var columns = selectedColumns
        if flags.contains(.command) {
            if columns.contains(column) { columns.remove(column) } else { columns.insert(column) }
            columnAnchor = column
        } else if flags.contains(.shift), let anchor = columnAnchor {
            columns = IndexSet(integersIn: min(anchor, column)...max(anchor, column))
        } else {
            columns = [column]
            columnAnchor = column
        }
        activeColumn = column
        tableView.deselectAll(nil)
        setSelectedColumns(columns)
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = ColumnTintRowView()
        rowView.tableView = tableView
        rowView.selectedViewColumns = { [weak self] in self?.selectedViewColumns ?? [] }
        return rowView
    }

    /// 行を選んだら列の選択は外す
    func tableViewSelectionDidChange(_ notification: Notification) {
        if !tableView.selectedRowIndexes.isEmpty { setSelectedColumns([]) }
    }

    /// 今のマウスイベントがヘッダー上か。NSTableView はヘッダーのクリックでも action を送ってくる
    /// （そのとき clickedRow は -1）ので、行のない所のクリックと区別するのに使う。
    private var isEventInHeader: Bool {
        guard let event = NSApp.currentEvent, let header = tableView.headerView else { return false }
        return header.bounds.contains(header.convert(event.locationInWindow, from: nil))
    }

    @objc private func tableClicked(_ sender: Any?) {
        if isEventInHeader { return } // 列の選択は mouseDownInHeaderOf で済んでいる
        // 行のない所のクリックは選択をすべて外す
        if tableView.clickedRow < 0 { setSelectedColumns([]) }
        guard tableView.clickedColumn >= 0,
              let column = modelColumn(tableView.tableColumns[tableView.clickedColumn]) // 行番号の列は除く
        else { return }
        activeColumn = column
        // クリックしたセルから次の検索を始める
        if let current = currentMatch {
            currentMatch = nil
            reloadCells([current])
            searchStatusChanged?()
        }
    }

    /// ダブルクリックしたセルを編集する。
    /// NSTableView は「選択済みの行をクリックして少し待つ」ときしか編集を始めないため、
    /// 未選択の行をダブルクリックしても編集にならない。ここで明示的に編集を始める。
    @objc private func tableDoubleClicked(_ sender: Any?) {
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard !isEventInHeader, row >= 0, column >= 0, modelColumn(tableView.tableColumns[column]) != nil else { return }
        tableView.editColumn(column, row: row, with: nil, select: true)
    }

    /// 行番号の列は動かさず、ほかの列もその左には置かせない
    func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
        columnIndex != 0 && newColumnIndex != 0
    }

    func tableViewColumnDidMove(_ notification: Notification) {
        guard !isRebuildingColumns,
              let oldView = notification.userInfo?["NSOldColumn"] as? Int,
              let newView = notification.userInfo?["NSNewColumn"] as? Int,
              oldView != newView, oldView > 0, newView > 0
        else { return }
        let old = oldView - 1
        let new = newView - 1
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
        if tableColumn?.identifier == rowNumberIdentifier {
            let cell = tableView.makeView(withIdentifier: rowNumberIdentifier, owner: self) as? NSTableCellView
                ?? makeRowNumberView()
            cell.textField?.stringValue = String(row + 1)
            return cell
        }
        guard let column = modelColumn(tableColumn), column < table.columnCount, row < table.rowCount else { return nil }
        let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView ?? makeCellView()
        let value = table[row, column]
        cell.textField?.stringValue = value
        let decimalMark = document?.tableDecimalMark ?? "."
        cell.textField?.alignment = NumberFormat.isNumber(value, decimalMark: decimalMark) ? .right : .natural
        applySearchHighlight(to: cell, at: CellPosition(row: row, column: column))
        return cell
    }

    /// 検索に一致したセルに背景色を付ける。現在の一致は濃く、ほかは薄く。
    private func applySearchHighlight(to cell: NSTableCellView, at position: CellPosition) {
        guard let field = cell.textField else { return }
        if searchMatchSet.contains(position) {
            field.drawsBackground = true
            field.backgroundColor = position == currentMatch
                ? .findHighlightColor
                : .findHighlightColor.withAlphaComponent(0.35)
            field.textColor = .black
        } else {
            field.drawsBackground = false
            field.textColor = .controlTextColor
        }
    }

    // MARK: - Search

    func focusTable() {
        view.window?.makeFirstResponder(tableView)
    }

    /// 「"東京": 3 / 12 件」のような表示用の文字列。検索していなければ nil
    var searchSummary: String? {
        guard !searchQuery.isEmpty else { return nil }
        if searchMatches.isEmpty { return String(localized: "“\(searchQuery)” not found") }
        let index = currentMatch.flatMap { searchMatches.firstIndex(of: $0) }.map { $0 + 1 }
        let total = searchMatches.count
        if let index { return String(localized: "“\(searchQuery)”: \(index) of \(total)") }
        return String(localized: "“\(searchQuery)”: \(total) found")
    }

    /// 検索文字列が変わったとき。選択中のセル以降で最初の一致に移動する（入力中に結果を追える）
    func setSearchQuery(_ query: String) {
        guard query != searchQuery else { return }
        searchQuery = query
        currentMatch = nil
        updateSearchMatches()
        if let target = CSVSearch.next(in: searchMatches, from: selectedCellPosition, inclusive: true) {
            reveal(target)
        }
        tableView.reloadData()
        searchStatusChanged?()
    }

    func findNext(backward: Bool) {
        guard !searchMatches.isEmpty else {
            NSSound.beep()
            return
        }
        let from = currentMatch ?? selectedCellPosition
        guard let target = CSVSearch.next(in: searchMatches, from: from, backward: backward) else { return }
        let previous = currentMatch
        reveal(target)
        reloadCells([previous, target].compactMap { $0 })
        searchStatusChanged?()
    }

    private func updateSearchMatches() {
        searchMatches = table.cells(matching: searchQuery)
        searchMatchSet = Set(searchMatches)
        if let current = currentMatch, !searchMatchSet.contains(current) { currentMatch = nil }
    }

    /// 選択中の行と列。行が未選択なら nil
    private var selectedCellPosition: CellPosition? {
        let row = tableView.selectedRow
        guard row >= 0 else { return nil }
        return CellPosition(row: row, column: activeColumn ?? 0)
    }

    /// 一致したセルの行を選択して見える位置までスクロールする
    private func reveal(_ position: CellPosition) {
        currentMatch = position
        activeColumn = position.column
        tableView.selectRowIndexes([position.row], byExtendingSelection: false)
        tableView.scrollRowToVisible(position.row)
        let view = viewColumn(for: position.column)
        if view >= 0 { tableView.scrollColumnToVisible(view) }
    }

    private func reloadCells(_ positions: [CellPosition]) {
        for position in positions where position.row < tableView.numberOfRows {
            let viewColumn = tableView.column(withIdentifier: identifier(for: position.column))
            guard viewColumn >= 0 else { continue }
            tableView.reloadData(forRowIndexes: [position.row], columnIndexes: [viewColumn])
        }
    }

    /// 行番号（編集不可、右寄せ、灰色の等幅数字）
    private func makeRowNumberView() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = rowNumberIdentifier
        let field = NSTextField(labelWithString: "")
        field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        field.textColor = .secondaryLabelColor
        field.alignment = .right
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
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
        insertColumn(at: selectedColumns.first ?? activeColumn ?? 0)
    }

    @objc func addColumnRight(_ sender: Any?) {
        insertColumn(at: (selectedColumns.last ?? activeColumn).map { $0 + 1 } ?? table.columnCount)
    }

    @objc func deleteSelectedRows(_ sender: Any?) {
        let rows = tableView.selectedRowIndexes
        guard !rows.isEmpty else { return NSSound.beep() }
        document?.removeRows(at: rows)
    }

    @objc func deleteSelectedColumns(_ sender: Any?) {
        let columns = selectedColumns
        guard !columns.isEmpty else { return NSSound.beep() }
        setSelectedColumns([])
        activeColumn = nil
        columnAnchor = nil
        document?.removeColumns(at: columns)
    }

    private func insertRow(at index: Int) {
        guard let document else { return }
        if table.columnCount == 0 { document.insertColumns([.init(title: nil, cells: [])], at: [0]) }
        document.insertRows([Array(repeating: "", count: table.columnCount)], at: [index])
        tableView.selectRowIndexes([index], byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        tableView.editColumn(viewColumn(for: 0), row: index, with: nil, select: true)
        flashRows([index])
    }

    private func insertColumn(at index: Int) {
        document?.insertColumns([.init(title: nil, cells: [])], at: [index])
        selectColumn(index)
    }

    /// 追加した行の背景を一瞬ハイライトしてフェードアウトさせる
    private func flashRows(_ rows: IndexSet) {
        // 行の作り直しとスクロールが終わってから行のビューを取り出す
        DispatchQueue.main.async { [weak self] in
            guard let tableView = self?.tableView else { return }
            tableView.layoutSubtreeIfNeeded()
            for row in rows where row < tableView.numberOfRows {
                guard let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) else { continue }
                rowView.wantsLayer = true
                guard let rowLayer = rowView.layer else { continue }
                let flash = CALayer()
                flash.frame = rowLayer.bounds
                flash.backgroundColor = NSColor.findHighlightColor.withAlphaComponent(0.6).cgColor
                flash.opacity = 0
                // セルの文字より下（行の背景・選択色より上）に置く
                rowLayer.insertSublayer(flash, at: 0)

                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                fade.duration = 0.9
                fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
                CATransaction.begin()
                CATransaction.setCompletionBlock { flash.removeFromSuperlayer() }
                flash.add(fade, forKey: "flash")
                CATransaction.commit()
            }
        }
    }

    // MARK: - Copy / Paste / Delete

    /// クリップボードとのやり取りはタブ区切り（Excel / Numbers と互換）
    private static let clipboardFormat = CSVConfiguration(delimiter: "\t", quotingStyle: .minimal)

    @objc func copy(_ sender: Any?) {
        let rows: [[String]]
        if !tableView.selectedRowIndexes.isEmpty {
            rows = tableView.selectedRowIndexes.map { table.rows[$0] }
        } else if !selectedColumns.isEmpty {
            // 列のコピーはセルだけ（見出しは含めない）
            rows = table.rows.map { row in selectedColumns.map { row[$0] } }
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

        if let lastColumn = selectedColumns.last {
            pasteAsColumns(rows, at: lastColumn + 1)
            return
        }

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
        flashRows(indexes)
    }

    /// 列を選択しているときの貼り付け: クリップボードの各列を、新しい列として `start` の位置に挿入する。
    /// 行が足りなければ先に空の行を足す（同じイベント内なので Undo は 1 回で戻る）。
    private func pasteAsColumns(_ rows: [[String]], at start: Int) {
        guard let document else { return }
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return }
        if rows.count > table.rowCount {
            let added = table.rowCount..<rows.count
            let empty = Array(repeating: "", count: table.columnCount)
            document.insertRows(Array(repeating: empty, count: added.count), at: IndexSet(integersIn: added))
        }
        let contents = (0..<width).map { c in
            CSVTable.ColumnContent(title: nil, cells: rows.map { c < $0.count ? $0[c] : "" })
        }
        let indexes = IndexSet(integersIn: start..<(start + width))
        document.insertColumns(contents, at: indexes)
        selectColumn(start)
        setSelectedColumns(indexes)
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
        let hasColumns = !selectedColumns.isEmpty
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
