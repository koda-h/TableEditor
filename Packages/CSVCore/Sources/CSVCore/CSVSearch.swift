import Foundation

/// 表の中のセルの位置
public struct CellPosition: Hashable, Comparable, Sendable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    /// 行優先（左上から右へ、次の行へ）の順
    public static func < (a: CellPosition, b: CellPosition) -> Bool {
        (a.row, a.column) < (b.row, b.column)
    }
}

/// セルの文字列検索
public enum CSVSearch {
    /// 大文字・小文字と全角・半角を区別しない（濁点の有無は区別する）
    public static func matches(_ value: String, query: String) -> Bool {
        !query.isEmpty && value.range(of: query, options: [.caseInsensitive, .widthInsensitive]) != nil
    }

    /// `position` の次（`backward` なら前）の一致。端まで行ったら反対側に戻る。
    ///
    /// - Parameters:
    ///   - matches: 行優先順に並んだ一致位置
    ///   - position: 現在位置。`nil` なら先頭（`backward` なら末尾）の一致を返す
    ///   - inclusive: `true` なら `position` 自体が一致していればそれを返す
    public static func next(
        in matches: [CellPosition], from position: CellPosition?,
        backward: Bool = false, inclusive: Bool = false
    ) -> CellPosition? {
        guard let position else { return backward ? matches.last : matches.first }
        if backward {
            let found = matches.last { inclusive ? $0 <= position : $0 < position }
            return found ?? matches.last
        } else {
            let found = matches.first { inclusive ? $0 >= position : $0 > position }
            return found ?? matches.first
        }
    }
}

extension CSVTable {
    /// `query` を含むセルの位置（行優先順）。ヘッダーは対象外。
    public func cells(matching query: String) -> [CellPosition] {
        guard !query.isEmpty else { return [] }
        var result: [CellPosition] = []
        for (r, row) in rows.enumerated() {
            for (c, value) in row.enumerated() where CSVSearch.matches(value, query: query) {
                result.append(CellPosition(row: r, column: c))
            }
        }
        return result
    }
}
