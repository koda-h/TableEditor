import Foundation
import Testing
@testable import CSVCore

/// オリジナル Table Tool の読み込みテストの移植
@Suite struct CSVReaderTests {
    private func readAll(_ path: String, _ configure: (inout CSVConfiguration) -> Void = { _ in }) throws -> [[String]] {
        var config = CSVConfiguration()
        configure(&config)
        var reader = try CSVReader(data: Fixture.data(path), configuration: config)
        return try reader.readAll()
    }

    private func readError(_ path: String, _ configure: (inout CSVConfiguration) -> Void = { _ in }) throws -> CSVError? {
        do {
            _ = try readAll(path, configure)
            return nil
        } catch let error as CSVError {
            return error
        }
    }

    @Test func commaSeparated() throws {
        let rows = try readAll("Reading/comma-separated") { $0.quote = nil }
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"], ["1.1", "1.2", "1.3"]])
        #expect(rows[2].allSatisfy { NumberFormat.isNumber($0, decimalMark: ".") })
    }

    @Test func semicolonSeparated() throws {
        let rows = try readAll("Reading/semicolon-separated") {
            $0.delimiter = ";"; $0.decimalMark = ","; $0.quote = nil
        }
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.count == 3 })
        #expect(rows[2].allSatisfy { NumberFormat.isNumber($0, decimalMark: ",") })
    }

    @Test func quotedCommaSeparated() throws {
        let rows = try readAll("Reading/comma-separated-quote") { $0.decimalMark = "," }
        #expect(rows == [["a", "b", "c"], ["1", "2", "3"], ["1,1", "1,2", "1,3"]])
    }

    @Test func quoteQuoteEscape() throws {
        let rows = try readAll("Reading/quote-quote-escape")
        #expect(rows == [["test\" test", "test"], ["1.2", "1,3"]])
    }

    @Test func quoteBackslashEscape() throws {
        let rows = try readAll("Reading/quote-backslash-escape") { $0.escape = "\\" }
        #expect(rows == [["test\" test", "test"], ["1.2", "1,3"]])
    }

    @Test func invalidEncoding() throws {
        #expect(try readError("Reading/invalid-encoding") == .decodingFailed(.utf8))
    }

    @Test(arguments: [
        ("Reading/missing-quote-atEnd", Unicode.Scalar("\"")),
        ("Reading/missing-backslash-beforeValue", "\\"),
        ("Reading/missing-backslash-afterValue", "\\"),
        ("Reading/missing-value-for-backslash-inquote", "\\"),
        ("Reading/missing-value-for-backslash", "\\"),
    ])
    func malformedQuotedValue(path: String, escape: Unicode.Scalar) throws {
        let error = try readError(path) { $0.escape = escape }
        guard case .malformedQuotedValue = error else {
            Issue.record("expected malformedQuotedValue, got \(String(describing: error))")
            return
        }
    }

    @Test func quoteInUnquotedValue() throws {
        let error = try readError("Reading/quote-in-unquoted-value")
        #expect(error == .unexpectedQuote(row: 0))
    }

    @Test func blankLines() throws {
        let rows = try readAll("Reading/blank-lines")
        #expect(rows == [["1"], ["2"], [""], [""], ["5"], ["6"]])
    }

    @Test func crlfAndUtf8BOM() throws {
        var reader = try CSVReader(string: "\u{FEFF}a,\"b\r\nc\"\r\n1,2\r\n", configuration: CSVConfiguration())
        #expect(try reader.readAll() == [["a", "b\r\nc"], ["1", "2"]])
    }

    @Test func emptyInput() throws {
        var reader = try CSVReader(string: "", configuration: CSVConfiguration())
        #expect(try reader.readAll() == [])
    }

    @Test func multibyteText() throws {
        var reader = try CSVReader(string: "名前,\"東京,大阪\"\n①,髙橋", configuration: CSVConfiguration())
        #expect(try reader.readAll() == [["名前", "東京,大阪"], ["①", "髙橋"]])
    }
}
