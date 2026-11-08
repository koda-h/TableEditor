import Foundation
import Testing
@testable import CSVCore

@Suite struct CSVWriterTests {
    let table = CSVTable(rows: [["1.5", "a,b", "say \"hi\""], ["007", "", "x"]], header: ["n", "s", "q"])

    @Test func minimalQuoting() {
        let config = CSVConfiguration(hasHeaderRow: true)
        #expect(CSVWriter.string(for: table, configuration: config) ==
            "n,s,q\n1.5,\"a,b\",\"say \"\"hi\"\"\"\n007,,x\n")
    }

    @Test func alwaysQuotingWithBackslashAndCRLF() {
        let config = CSVConfiguration(escape: "\\", hasHeaderRow: false, lineEnding: .crlf, quotingStyle: .always, endsWithLineBreak: false)
        #expect(CSVWriter.string(for: CSVTable(rows: [["a\\b", "\"x\""]]), configuration: config) ==
            "\"a\\\\b\",\"\\\"x\\\"\"")
    }

    @Test func convertsDecimalMarkOnlyForNumbers() {
        let config = CSVConfiguration(delimiter: ";", decimalMark: ",", hasHeaderRow: true)
        #expect(CSVWriter.string(for: table, configuration: config, sourceDecimalMark: ".") ==
            "n;s;q\n1,5;a,b;\"say \"\"hi\"\"\"\n007;;x\n")
    }

    @Test func roundTrip() throws {
        for quoting in CSVConfiguration.QuotingStyle.allCases {
            for escape: Unicode.Scalar in ["\"", "\\"] {
                let config = CSVConfiguration(escape: escape, hasHeaderRow: true, quotingStyle: quoting)
                let data = try CSVWriter.data(for: table, configuration: config)
                #expect(try CSVFile.read(data, configuration: config) == table)
            }
        }
    }

    @Test func utf8BOMAndEncodingFailure() throws {
        let bom = try CSVWriter.data(for: CSVTable(rows: [["a"]]), configuration: CSVConfiguration(hasByteOrderMark: true))
        #expect(Array(bom) == [0xEF, 0xBB, 0xBF, 0x61, 0x0A])
        #expect(throws: CSVError.encodingFailed(.shiftJIS)) {
            try CSVWriter.data(for: CSVTable(rows: [["😀"]]), configuration: CSVConfiguration(encoding: .shiftJIS))
        }
    }
}

@Suite struct CSVTableTests {
    @Test func ragged_rows_are_padded() {
        let table = CSVTable(rows: [["a"], ["b", "c", "d"]])
        #expect(table.columnCount == 3)
        #expect(table.rows == [["a", "", ""], ["b", "c", "d"]])
    }

    @Test func columnLetters() {
        #expect(CSVTable.columnLetter(0) == "A")
        #expect(CSVTable.columnLetter(25) == "Z")
        #expect(CSVTable.columnLetter(26) == "AA")
        #expect(CSVTable.columnLetter(701) == "ZZ")
    }

    @Test func removeAndRestoreColumns() {
        let original = CSVTable(rows: [["1", "2", "3"], ["4", "5", "6"]], header: ["a", "b", "c"])
        var table = original
        let indexes = IndexSet([0, 2])
        let removed = table.removeColumns(at: indexes)
        #expect(table.rows == [["2"], ["5"]])
        #expect(table.header == ["b"])
        table.insertColumns(removed, at: indexes)
        #expect(table == original)
    }

    @Test func removeAndRestoreRows() {
        let original = CSVTable(rows: [["1"], ["2"], ["3"], ["4"]])
        var table = original
        let indexes = IndexSet([1, 3])
        let removed = table.removeRows(at: indexes)
        #expect(table.rows == [["1"], ["3"]])
        table.insertRows(removed, at: indexes)
        #expect(table == original)
    }

    @Test func moveColumnAndHeaderToggle() {
        var table = CSVTable(rows: [["a", "b", "c"], ["1", "2", "3"]])
        table.moveColumn(from: 0, to: 2)
        #expect(table.rows == [["b", "c", "a"], ["2", "3", "1"]])
        table.setUsesHeaderRow(true)
        #expect(table.header == ["b", "c", "a"])
        #expect(table.columnTitle(2) == "a")
        table.setUsesHeaderRow(false)
        #expect(table.rows.count == 2)
        #expect(table.columnTitle(2) == "C")
    }
}
