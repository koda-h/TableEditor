import Foundation

/// CSV を 1 行ずつ読む。
///
/// デコード済みの文字列を UTF-8 バイト列として走査する。区切り文字・引用符は ASCII に
/// 限定しているので、マルチバイト文字の途中で誤検出することはない。
/// 解析規則はオリジナル Table Tool の `CSVReader` に合わせている。
public struct CSVReader: Sendable {
    private let bytes: [UInt8]
    private var index = 0
    private var rowIndex = 0
    private let delimiter: UInt8
    private let quote: UInt8?
    private let escape: UInt8

    public private(set) var isAtEnd: Bool

    public init(string: String, configuration: CSVConfiguration) throws(CSVError) {
        guard configuration.delimiter.isASCII,
              configuration.escape.isASCII,
              configuration.quote?.isASCII ?? true
        else { throw .unsupportedConfiguration }

        var string = string
        if string.unicodeScalars.first == "\u{FEFF}" {
            string.unicodeScalars.removeFirst()
        }
        bytes = Array(string.utf8)
        delimiter = UInt8(configuration.delimiter.value)
        quote = configuration.quote.map { UInt8($0.value) }
        escape = UInt8(configuration.escape.value)
        isAtEnd = bytes.isEmpty
    }

    public init(data: Data, configuration: CSVConfiguration) throws(CSVError) {
        guard let string = String(data: data, encoding: configuration.encoding) else {
            throw .decodingFailed(configuration.encoding)
        }
        try self.init(string: string, configuration: configuration)
    }

    /// 次の行を返す。末尾に達したら `nil`。
    public mutating func readRow() throws(CSVError) -> [String]? {
        guard !isAtEnd else { return nil }
        var row: [String] = []
        while true {
            if let quote, index < bytes.count, bytes[index] == quote {
                row.append(try scanQuotedValue())
            } else {
                row.append(try scanUnquotedValue())
            }

            if index >= bytes.count {
                isAtEnd = true
                break
            }
            let byte = bytes[index]
            if byte == .lf || byte == .cr {
                index += (byte == .cr && index + 1 < bytes.count && bytes[index + 1] == .lf) ? 2 : 1
                if index >= bytes.count { isAtEnd = true }
                break
            }
            index += 1 // 区切り文字
        }
        rowIndex += 1
        return row
    }

    public mutating func readAll() throws(CSVError) -> [[String]] {
        var rows: [[String]] = []
        while let row = try readRow() {
            rows.append(row)
        }
        return rows
    }

    // MARK: - Scanning

    private func isTerminator(_ byte: UInt8) -> Bool {
        byte == delimiter || byte == .lf || byte == .cr
    }

    private mutating func scanUnquotedValue() throws(CSVError) -> String {
        let start = index
        while index < bytes.count, !isTerminator(bytes[index]) {
            if let quote, bytes[index] == quote {
                throw .unexpectedQuote(row: rowIndex)
            }
            index += 1
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func scanQuotedValue() throws(CSVError) -> String {
        guard let quote else { preconditionFailure() }
        index += 1 // 開き引用符
        var buffer: [UInt8] = []

        while true {
            let start = index
            while index < bytes.count, bytes[index] != quote, bytes[index] != escape {
                index += 1
            }
            buffer.append(contentsOf: bytes[start..<index])
            guard index < bytes.count else { throw .malformedQuotedValue(row: rowIndex) }

            if bytes[index] == escape {
                // `""` 形式: 引用符の直後が区切り・改行・末尾なら値の終わり
                if escape == quote,
                   index + 1 == bytes.count || isTerminator(bytes[index + 1]) {
                    index += 1
                    return String(decoding: buffer, as: UTF8.self)
                }
                index += 1
                guard index < bytes.count else { throw .malformedQuotedValue(row: rowIndex) }
                buffer.append(bytes[index])
                index += 1
                continue
            }

            // escape != quote で引用符に当たった
            index += 1
            if index == bytes.count || isTerminator(bytes[index]) {
                return String(decoding: buffer, as: UTF8.self)
            }
            throw .malformedQuotedValue(row: rowIndex)
        }
    }
}

extension UInt8 {
    static let lf = UInt8(ascii: "\n")
    static let cr = UInt8(ascii: "\r")
}
