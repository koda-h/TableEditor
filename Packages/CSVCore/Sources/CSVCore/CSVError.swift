import Foundation

public enum CSVError: Error, Equatable, Sendable {
    /// 指定した文字コードでデコードできない（オリジナルの error code 1）
    case decodingFailed(String.Encoding)
    /// 引用符が閉じていない、または閉じ引用符の直後に不正な文字がある（code 2）
    case malformedQuotedValue(row: Int)
    /// 引用符で囲まれていない値の途中に引用符がある（code 3）
    case unexpectedQuote(row: Int)
    /// 指定した文字コードで表現できない文字がある（code 4）
    case encodingFailed(String.Encoding)
    /// 区切り文字などに ASCII 以外が指定された
    case unsupportedConfiguration
}

extension CSVError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .decodingFailed(let encoding):
            String(localized: "The file could not be read as \(encoding.localizedName).")
        case .malformedQuotedValue(let row):
            String(localized: "A quoted value in row \(row + 1) is not closed correctly.")
        case .unexpectedQuote(let row):
            String(localized: "Row \(row + 1) contains a quote inside an unquoted value.")
        case .encodingFailed(let encoding):
            String(localized: "Some characters cannot be saved as \(encoding.localizedName).")
        case .unsupportedConfiguration:
            String(localized: "Separators and quotes must be ASCII characters.")
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .decodingFailed: String(localized: "Try specifying a different encoding.")
        case .malformedQuotedValue, .unexpectedQuote: String(localized: "Try specifying a different separator or quote.")
        case .encodingFailed: String(localized: "Try a different encoding such as UTF-8.")
        case .unsupportedConfiguration: nil
        }
    }
}
