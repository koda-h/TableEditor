import Foundation

/// CSV の形式（文字コード・区切り文字・引用符・小数点・ヘッダー行）を推定する。
///
/// オリジナル Table Tool の `CSVHeuristic` の移植。候補の形式それぞれで先頭 5 行を読み、
/// 「読めた行数」「列数がそろっているか」「数値セルの数」で点数を付けて最高点を選ぶ。
/// 同点なら候補リストで先にあるものを優先する。
public struct CSVHeuristic: Sendable {
    /// 試す文字コード（先頭から順に、デコードできた最初のものを採用）
    public var encodings: [String.Encoding]
    /// 採点に使う行数
    public var sampleRowCount = 5

    public init(encodings: [String.Encoding] = CSVHeuristic.defaultEncodings()) {
        self.encodings = encodings
    }

    /// オリジナルと同じ候補順。
    public static let candidates: [CSVConfiguration] = {
        let comma = CSVConfiguration(delimiter: ",", decimalMark: ".")
        let semicolon = CSVConfiguration(delimiter: ";", decimalMark: ",")
        let tabDot = CSVConfiguration(delimiter: "\t", decimalMark: ".")
        let tabComma = CSVConfiguration(delimiter: "\t", decimalMark: ",")
        func with(_ c: CSVConfiguration, _ change: (inout CSVConfiguration) -> Void) -> CSVConfiguration {
            var copy = c
            change(&copy)
            return copy
        }
        return [
            comma,
            with(comma) { $0.escape = "\\" },
            with(comma) { $0.quote = nil },
            semicolon,
            with(semicolon) { $0.escape = "\\" },
            with(semicolon) { $0.quote = nil },
            tabDot,
            with(tabDot) { $0.quote = nil },
            tabComma,
            with(tabComma) { $0.quote = nil },
            with(comma) { $0.decimalMark = "," },
        ]
    }()

    /// オリジナルの文字コード順に、ユーザーの言語設定に応じた文字コードを差し込む。
    public static func defaultEncodings(preferredLanguages: [String] = Locale.preferredLanguages) -> [String.Encoding] {
        let language = preferredLanguages.first.map { Locale.Language(identifier: $0).languageCode?.identifier } ?? nil
        switch language {
        case "ja": return [.utf8, .shiftJIS, .windowsCP1252, .macOSRoman, .gb18030]
        case "zh": return [.utf8, .gb18030, .windowsCP1252, .macOSRoman]
        default: return [.utf8, .windowsCP1252, .macOSRoman, .gb18030]
        }
    }

    public func detect(_ data: Data) -> CSVConfiguration {
        var result: CSVConfiguration
        if let (encoding, bomLength) = Self.encodingFromByteOrderMark(data) {
            result = detect(data: data.dropFirst(bomLength), encodings: [encoding])
            result.encoding = encoding == .utf8 ? .utf8 : .utf16
            result.hasByteOrderMark = true
        } else {
            result = detect(data: data, encodings: encodings)
        }
        // 保存時に元の改行コード・末尾改行を保つ（オリジナルにはない追加分）
        if let string = String(data: data, encoding: result.encoding) {
            result.lineEnding = Self.lineEnding(of: string)
            // "\r\n" は 1 つの Character なので hasSuffix("\n") では判定できない。バイトで見る
            result.endsWithLineBreak = string.utf8.last == .lf || string.utf8.last == .cr
        }
        return result
    }

    /// 最初に現れた改行が CRLF なら CRLF とみなす（引用符内の改行は考慮しない簡易判定）
    static func lineEnding(of string: String) -> CSVConfiguration.LineEnding {
        let utf8 = string.utf8
        guard let index = utf8.firstIndex(where: { $0 == .lf || $0 == .cr }) else { return .lf }
        return utf8[index] == .cr ? .crlf : .lf
    }

    // MARK: - Private

    private func detect(data: Data, encodings: [String.Encoding]) -> CSVConfiguration {
        for encoding in encodings {
            guard let string = String(data: data, encoding: encoding) else { continue }
            var best = score(string)
            best.encoding = encoding
            return best
        }
        // どの文字コードでも読めなかった: 最後の候補で開き、エラー表示は読み込み側に任せる
        var fallback = Self.candidates[0]
        fallback.encoding = encodings.first ?? .utf8
        return fallback
    }

    private func score(_ string: String) -> CSVConfiguration {
        var bestIndex = 0
        var bestScore = Int.min
        var bestHasHeader = false

        for (i, candidate) in Self.candidates.enumerated() {
            guard var reader = try? CSVReader(string: string, configuration: candidate) else { continue }
            var rows: [[String]] = []
            do {
                while rows.count < sampleRowCount, let row = try reader.readRow() {
                    rows.append(row)
                }
            } catch {
                continue // この形式では読めない
            }

            var points = rows.count
            var hasHeader = false

            // 列数がそろっているか
            if let firstCount = rows.first?.count {
                var sameLength = true
                for row in rows.dropFirst() {
                    sameLength = sameLength && row.count == firstCount
                    if row.count <= firstCount { points += row.count }
                }
                if sameLength {
                    points += 5
                    hasHeader = true
                }
            }

            // 数値セルの数（最大 5 点）。1 行目に数値や空セルがあればヘッダーではない
            var numbers = 0
            for (r, row) in rows.enumerated() {
                for cell in row {
                    if NumberFormat.isNumber(cell, decimalMark: candidate.decimalMark) {
                        numbers += 1
                        if r == 0 { hasHeader = false }
                    } else if r == 0, cell.isEmpty {
                        hasHeader = false
                    }
                }
            }
            points += min(numbers, 5)

            if points > bestScore {
                bestScore = points
                bestIndex = i
                bestHasHeader = hasHeader
            }
        }

        var result = Self.candidates[bestIndex]
        result.hasHeaderRow = bestHasHeader
        return result
    }

    private static func encodingFromByteOrderMark(_ data: Data) -> (String.Encoding, Int)? {
        let prefix = Array(data.prefix(3))
        if prefix.starts(with: [0xEF, 0xBB, 0xBF]) { return (.utf8, 3) }
        // UTF-16 は BOM 付きのまま Foundation にデコードさせる
        if prefix.starts(with: [0xFF, 0xFE]) || prefix.starts(with: [0xFE, 0xFF]) { return (.utf16, 0) }
        return nil
    }
}
