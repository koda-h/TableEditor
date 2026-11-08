import Foundation

/// 編集対象の表。常に長方形（全行が `columnCount` 列）に保つ。
///
/// 編集操作はすべて逆操作に必要な情報を返すので、呼び出し側で Undo を登録できる。
public struct CSVTable: Equatable, Sendable {
    /// ヘッダー行。`nil` ならヘッダーなし（列名は A, B, C … を表示する）
    public private(set) var header: [String]?
    public private(set) var rows: [[String]]
    public private(set) var columnCount: Int

    public var rowCount: Int { rows.count }

    public init(rows: [[String]] = [], header: [String]? = nil) {
        let width = max(rows.map(\.count).max() ?? 0, header?.count ?? 0)
        self.columnCount = width
        self.rows = rows.map { Self.padded($0, to: width) }
        self.header = header.map { Self.padded($0, to: width) }
    }

    /// 空の表
    public static func empty(rows: Int, columns: Int) -> CSVTable {
        CSVTable(rows: Array(repeating: Array(repeating: "", count: columns), count: rows))
    }

    /// 読み込んだ全行から表を作る。`hasHeaderRow` なら 1 行目をヘッダーにする。
    public init(parsedRows: [[String]], hasHeaderRow: Bool) {
        if hasHeaderRow, let first = parsedRows.first {
            self.init(rows: Array(parsedRows.dropFirst()), header: first)
        } else {
            self.init(rows: parsedRows)
        }
    }

    public subscript(row: Int, column: Int) -> String {
        get { rows[row][column] }
        set { rows[row][column] = newValue }
    }

    public func columnTitle(_ column: Int) -> String {
        if let header { return header[column] }
        return Self.columnLetter(column)
    }

    /// 0 → A, 25 → Z, 26 → AA
    public static func columnLetter(_ index: Int) -> String {
        var n = index + 1
        var result = ""
        while n > 0 {
            let r = (n - 1) % 26
            result = String(UnicodeScalar(UInt8(65 + r))) + result
            n = (n - 1) / 26
        }
        return result
    }

    // MARK: - Header

    public mutating func setHeaderTitle(_ title: String, column: Int) {
        if header == nil { header = Array(repeating: "", count: columnCount) }
        header![column] = title
    }

    /// 1 行目をヘッダーにする／ヘッダーを 1 行目に戻す
    public mutating func setUsesHeaderRow(_ enabled: Bool) {
        if enabled, header == nil {
            header = rows.isEmpty ? Array(repeating: "", count: columnCount) : rows.removeFirst()
        } else if !enabled, let current = header {
            rows.insert(current, at: 0)
            header = nil
        }
    }

    // MARK: - Rows

    public mutating func insertRows(_ contents: [[String]], at indexes: IndexSet) {
        precondition(contents.count == indexes.count)
        for (content, index) in zip(contents, indexes) {
            rows.insert(Self.padded(content, to: columnCount), at: index)
            if content.count > columnCount { widen(to: content.count) }
        }
    }

    public mutating func insertEmptyRow(at index: Int) {
        insertRows([Array(repeating: "", count: columnCount)], at: IndexSet(integer: index))
    }

    /// 削除した行の内容を返す（`insertRows` で元に戻せる）
    @discardableResult
    public mutating func removeRows(at indexes: IndexSet) -> [[String]] {
        let removed = indexes.map { rows[$0] }
        for index in indexes.reversed() { rows.remove(at: index) }
        return removed
    }

    // MARK: - Columns

    public mutating func insertColumns(_ contents: [ColumnContent], at indexes: IndexSet) {
        precondition(contents.count == indexes.count)
        for (content, column) in zip(contents, indexes) {
            for r in rows.indices {
                rows[r].insert(r < content.cells.count ? content.cells[r] : "", at: column)
            }
            header?.insert(content.title ?? "", at: column)
            columnCount += 1
        }
    }

    public mutating func insertEmptyColumn(at index: Int) {
        insertColumns([ColumnContent(title: nil, cells: [])], at: IndexSet(integer: index))
    }

    @discardableResult
    public mutating func removeColumns(at indexes: IndexSet) -> [ColumnContent] {
        let removed = indexes.map { c in ColumnContent(title: header?[c], cells: rows.map { $0[c] }) }
        for c in indexes.reversed() {
            for r in rows.indices { rows[r].remove(at: c) }
            header?.remove(at: c)
            columnCount -= 1
        }
        return removed
    }

    public mutating func moveColumn(from source: Int, to destination: Int) {
        guard source != destination else { return }
        for r in rows.indices {
            rows[r].insert(rows[r].remove(at: source), at: destination)
        }
        if header != nil { header!.insert(header!.remove(at: source), at: destination) }
    }

    public struct ColumnContent: Equatable, Sendable {
        public var title: String?
        public var cells: [String]
        public init(title: String?, cells: [String]) {
            self.title = title
            self.cells = cells
        }
    }

    // MARK: - Private

    private mutating func widen(to width: Int) {
        guard width > columnCount else { return }
        rows = rows.map { Self.padded($0, to: width) }
        header = header.map { Self.padded($0, to: width) }
        columnCount = width
    }

    private static func padded(_ row: [String], to width: Int) -> [String] {
        row.count >= width ? row : row + Array(repeating: "", count: width - row.count)
    }
}
