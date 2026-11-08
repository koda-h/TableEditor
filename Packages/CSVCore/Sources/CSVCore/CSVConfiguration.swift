import Foundation

/// CSV ファイルの形式。読み込み・書き出しの両方で使う。
///
/// 区切り文字・引用符・エスケープ文字・小数点記号は ASCII 文字のみ対応する。
public struct CSVConfiguration: Hashable, Sendable {
    public enum LineEnding: String, CaseIterable, Sendable {
        case lf = "\n"
        case crlf = "\r\n"
    }

    public enum QuotingStyle: String, CaseIterable, Sendable {
        /// すべてのセルを引用符で囲む（オリジナル Table Tool と同じ挙動）
        case always
        /// 区切り文字・引用符・改行を含むセルだけ囲む
        case minimal
    }

    public var encoding: String.Encoding
    public var delimiter: Unicode.Scalar
    /// `nil` のとき引用符なし（値をそのまま読み書きする）
    public var quote: Unicode.Scalar?
    /// 引用符と同じ文字なら `""` 形式、`\` なら `\"` 形式のエスケープになる
    public var escape: Unicode.Scalar
    public var decimalMark: Unicode.Scalar
    public var hasHeaderRow: Bool
    /// 先頭に BOM があった／書き出すか（UTF-8 / UTF-16 のみ意味を持つ）
    public var hasByteOrderMark: Bool
    public var lineEnding: LineEnding
    public var quotingStyle: QuotingStyle
    public var endsWithLineBreak: Bool

    public init(
        encoding: String.Encoding = .utf8,
        delimiter: Unicode.Scalar = ",",
        quote: Unicode.Scalar? = "\"",
        escape: Unicode.Scalar = "\"",
        decimalMark: Unicode.Scalar = ".",
        hasHeaderRow: Bool = false,
        hasByteOrderMark: Bool = false,
        lineEnding: LineEnding = .lf,
        quotingStyle: QuotingStyle = .minimal,
        endsWithLineBreak: Bool = true
    ) {
        self.encoding = encoding
        self.delimiter = delimiter
        self.quote = quote
        self.escape = escape
        self.decimalMark = decimalMark
        self.hasHeaderRow = hasHeaderRow
        self.hasByteOrderMark = hasByteOrderMark
        self.lineEnding = lineEnding
        self.quotingStyle = quotingStyle
        self.endsWithLineBreak = endsWithLineBreak
    }

    /// タブ区切り・引用符なし。クリップボードとのやり取りに使う。
    public static let tabSeparatedPlain = CSVConfiguration(delimiter: "\t", quote: nil)
}

extension String.Encoding {
    /// GB 18030（GBK 上位互換）
    public static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )

    /// UI で選べる文字コードの一覧
    public static let csvSupported: [String.Encoding] = [
        .utf8, .shiftJIS, .japaneseEUC, .iso2022JP,
        .macOSRoman, .windowsCP1252, .gb18030,
        .isoLatin2, .windowsCP1250, .windowsCP1251, .windowsCP1253, .windowsCP1254,
        .utf16, .utf16BigEndian, .utf16LittleEndian,
        .utf32, .utf32BigEndian, .utf32LittleEndian,
    ]

    public var localizedName: String {
        String.localizedName(of: self)
    }
}
