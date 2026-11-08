import Foundation
import Testing
@testable import CSVCore

@Suite struct CSVSearchTests {
    let table = CSVTable(
        rows: [["Tokyo", "東京", "１２３"], ["osaka", "大阪", "tokyo tower"], ["バス", "パス", ""]],
        header: ["city", "tokyo", "n"]
    )

    private func pos(_ r: Int, _ c: Int) -> CellPosition { CellPosition(row: r, column: c) }

    @Test func findsCellsInRowOrderIgnoringCase() {
        #expect(table.cells(matching: "TOKYO") == [pos(0, 0), pos(1, 2)]) // ヘッダーは対象外
        #expect(table.cells(matching: "東") == [pos(0, 1)])
        #expect(table.cells(matching: "") == [])
    }

    @Test func ignoresWidthButNotDakuten() {
        #expect(table.cells(matching: "23") == [pos(0, 2)])
        #expect(table.cells(matching: "ﾊﾞｽ") == [pos(2, 0)])
        #expect(table.cells(matching: "ハス") == [])
    }

    @Test func nextAndPreviousWrapAround() {
        let matches = [pos(0, 1), pos(1, 0), pos(2, 2)]
        #expect(CSVSearch.next(in: matches, from: nil) == pos(0, 1))
        #expect(CSVSearch.next(in: matches, from: nil, backward: true) == pos(2, 2))
        #expect(CSVSearch.next(in: matches, from: pos(0, 1)) == pos(1, 0))
        #expect(CSVSearch.next(in: matches, from: pos(0, 1), inclusive: true) == pos(0, 1))
        #expect(CSVSearch.next(in: matches, from: pos(1, 1)) == pos(2, 2))
        #expect(CSVSearch.next(in: matches, from: pos(2, 2)) == pos(0, 1))
        #expect(CSVSearch.next(in: matches, from: pos(1, 0), backward: true) == pos(0, 1))
        #expect(CSVSearch.next(in: matches, from: pos(0, 0), backward: true) == pos(2, 2))
        #expect(CSVSearch.next(in: [], from: pos(0, 0)) == nil)
    }
}
