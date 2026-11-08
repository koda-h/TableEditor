import Foundation

public enum CSVWriter {
    /// 表を CSV 文字列にする。
    /// - Parameter sourceDecimalMark: 表の数値が使っている小数点記号。
    ///   `configuration.decimalMark` と異なれば数値セルを変換して書き出す。
    public static func string(
        for table: CSVTable,
        configuration: CSVConfiguration,
        sourceDecimalMark: Unicode.Scalar? = nil
    ) -> String {
        let delimiter = String(configuration.delimiter)
        let lineEnding = configuration.lineEnding.rawValue

        func encode(_ row: [String], convertNumbers: Bool) -> String {
            row.map { cell in
                var value = cell
                if convertNumbers, let sourceDecimalMark {
                    value = NumberFormat.convertDecimalMark(value, from: sourceDecimalMark, to: configuration.decimalMark)
                }
                return quoted(value, configuration: configuration)
            }
            .joined(separator: delimiter)
        }

        var lines: [String] = []
        lines.reserveCapacity(table.rowCount + 1)
        if configuration.hasHeaderRow, let header = table.header {
            lines.append(encode(header, convertNumbers: false))
        }
        for row in table.rows {
            lines.append(encode(row, convertNumbers: true))
        }
        var output = lines.joined(separator: lineEnding)
        if configuration.endsWithLineBreak, !lines.isEmpty { output += lineEnding }
        return output
    }

    public static func data(
        for table: CSVTable,
        configuration: CSVConfiguration,
        sourceDecimalMark: Unicode.Scalar? = nil
    ) throws(CSVError) -> Data {
        let string = string(for: table, configuration: configuration, sourceDecimalMark: sourceDecimalMark)
        guard var data = string.data(using: configuration.encoding, allowLossyConversion: false) else {
            throw .encodingFailed(configuration.encoding)
        }
        if configuration.encoding == .utf8, configuration.hasByteOrderMark {
            data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
        }
        return data
    }

    static func quoted(_ value: String, configuration: CSVConfiguration) -> String {
        guard let quote = configuration.quote else { return value }
        let escape = configuration.escape

        if configuration.quotingStyle == .minimal {
            let needsQuoting = value.unicodeScalars.contains {
                $0 == configuration.delimiter || $0 == quote || $0 == escape || $0 == "\n" || $0 == "\r"
            }
            if !needsQuoting { return value }
        }

        var result = String.UnicodeScalarView()
        result.append(quote)
        for scalar in value.unicodeScalars {
            if scalar == quote || (escape != quote && scalar == escape) {
                result.append(escape)
            }
            result.append(scalar)
        }
        result.append(quote)
        return String(result)
    }
}
