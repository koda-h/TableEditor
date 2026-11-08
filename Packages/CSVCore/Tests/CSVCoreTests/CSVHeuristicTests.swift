import Foundation
import Testing
@testable import CSVCore

/// オリジナル Table Tool のヒューリスティックテストの移植
@Suite struct CSVHeuristicTests {
    /// オリジナルと同じ文字コード順
    private let original = CSVHeuristic(encodings: [.utf8, .windowsCP1252, .macOSRoman, .gb18030])

    private func detect(_ path: String) throws -> CSVConfiguration {
        try original.detect(Fixture.data("Heuristic/\(path)"))
    }

    struct Expected: Sendable, CustomTestStringConvertible {
        var file: String
        var delimiter: Unicode.Scalar
        var decimalMark: Unicode.Scalar
        var quote: Unicode.Scalar? = "\""
        var escape: Unicode.Scalar = "\""
        var testDescription: String { file }
    }

    @Test(arguments: [
        Expected(file: "heuristic-comma-separated-people-1", delimiter: ",", decimalMark: "."),
        Expected(file: "heuristic-comma-separated-people-2", delimiter: ",", decimalMark: "."),
        Expected(file: "heuristic-comma-separated-places", delimiter: ",", decimalMark: "."),
        Expected(file: "heuristic-config1", delimiter: ",", decimalMark: "."),
        Expected(file: "heuristic-config2", delimiter: ";", decimalMark: ","),
        Expected(file: "heuristic-config3", delimiter: "\t", decimalMark: "."),
        Expected(file: "heuristic-config4", delimiter: "\t", decimalMark: ","),
        Expected(file: "heuristic-config5", delimiter: ";", decimalMark: ",", escape: "\\"),
        Expected(file: "heuristic-config6", delimiter: ",", decimalMark: ".", quote: nil),
        Expected(file: "heuristic-config7", delimiter: ";", decimalMark: ",", quote: nil),
        Expected(file: "heuristic-config8", delimiter: "\t", decimalMark: ".", quote: nil),
        Expected(file: "heuristic-config9", delimiter: "\t", decimalMark: ",", quote: nil),
        Expected(file: "heuristic-config10", delimiter: ",", decimalMark: ".", escape: "\\"),
        Expected(file: "heuristic-config11", delimiter: ",", decimalMark: ","),
    ])
    func detectsFormat(_ expected: Expected) throws {
        let config = try detect(expected.file)
        #expect(config.delimiter == expected.delimiter)
        #expect(config.decimalMark == expected.decimalMark)
        #expect(config.quote == expected.quote)
        if expected.quote != nil {
            #expect(config.escape == expected.escape)
        }
        #expect(config.hasHeaderRow)
    }

    @Test(arguments: [
        "heuristic-first-row-with-number",
        "heuristic-first-row-one-row-shorter",
        "heuristic-first-row-longer",
    ])
    func noHeader(_ file: String) throws {
        #expect(try detect(file).hasHeaderRow == false)
    }

    @Test func westernEncoding() throws {
        #expect(try detect("heuristic-no-utf-encoding").encoding == .windowsCP1252)
    }

    @Test func gbkEncoding() throws {
        let heuristic = CSVHeuristic(encodings: [.utf8, .gb18030, .windowsCP1252, .macOSRoman])
        let config = heuristic.detect(try Fixture.data("Heuristic/heuristic-gbk"))
        #expect(config.encoding == .gb18030)
    }

    @Test func issue4Sample() throws {
        let config = try detect("issue-4-sample")
        #expect(config.encoding == .macOSRoman)
        #expect(config.delimiter == "\t")
        #expect(config.hasHeaderRow)
    }

    @Test func largeQuotedDocument() throws {
        let config = try original.detect(Fixture.data("test-doc-quoted"))
        #expect(config.delimiter == ",")
        #expect(config.decimalMark == ",")
        #expect(config.quote == "\"")
        #expect(config.hasHeaderRow)
    }

    // MARK: - 追加分

    @Test func shiftJISForJapaneseUsers() throws {
        let text = "名前,金額\n髙橋①,1200\n山田,300\n"
        let data = try #require(text.data(using: .shiftJIS))
        let heuristic = CSVHeuristic(encodings: CSVHeuristic.defaultEncodings(preferredLanguages: ["ja-JP"]))
        let (table, config) = try CSVFile.read(data, heuristic: heuristic)
        #expect(config.encoding == .shiftJIS)
        #expect(config.hasHeaderRow)
        #expect(table.header == ["名前", "金額"])
        #expect(table[0, 0] == "髙橋①")
    }

    /// 読み込んでそのまま保存したら元のバイト列に戻ること
    @Test(arguments: [
        "名前,部署,金額\r\n髙橋①,\"営業,東京\",1200.5\r\n山田,開発,300\r\n",
        "a;b\n1,5;2",
    ])
    func preservesBytesOnRoundTrip(_ text: String) throws {
        let data = try #require(text.data(using: .shiftJIS))
        let heuristic = CSVHeuristic(encodings: CSVHeuristic.defaultEncodings(preferredLanguages: ["ja"]))
        let (table, config) = try CSVFile.read(data, heuristic: heuristic)
        #expect(try CSVWriter.data(for: table, configuration: config, sourceDecimalMark: config.decimalMark) == data)
    }

    @Test func utf8ByteOrderMark() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a;b\n1,5;2\n".utf8)
        let (table, config) = try CSVFile.read(data)
        #expect(config.encoding == .utf8)
        #expect(config.hasByteOrderMark)
        #expect(config.delimiter == ";")
        #expect(table.header == ["a", "b"])
    }
}
