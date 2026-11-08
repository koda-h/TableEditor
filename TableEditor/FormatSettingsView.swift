import SwiftUI
import CSVCore

enum FormatLabels {
    static func delimiter(_ scalar: Unicode.Scalar) -> String {
        switch scalar {
        case ",": String(localized: "Comma separated")
        case ";": String(localized: "Semicolon separated")
        case "\t": String(localized: "Tab separated")
        default: String(localized: "Separated by \(String(scalar))")
        }
    }

    static func quote(_ quote: Unicode.Scalar?, escape: Unicode.Scalar) -> String {
        guard let quote else { return String(localized: "No quotes") }
        return escape == quote
            ? String(localized: "Quotes \(String(quote))\(String(quote))")
            : String(localized: "Quotes \(String(escape))\(String(quote))")
    }
}

/// ファイル形式の設定シート。
/// 「この形式で読み直す」は開いたときのバイト列を再解析し、
/// 「保存形式にする」は表の内容はそのままで保存時の形式だけを変える。
struct FormatSettingsView: View {
    @State var configuration: CSVConfiguration
    let canReinterpret: Bool
    let onCancel: () -> Void
    let onReinterpret: (CSVConfiguration) -> Void
    let onApply: (CSVConfiguration) -> Void

    private enum QuoteMode: Hashable { case none, doubled, backslash }

    private var quoteMode: Binding<QuoteMode> {
        Binding {
            guard configuration.quote != nil else { return .none }
            return configuration.escape == "\\" ? .backslash : .doubled
        } set: { mode in
            switch mode {
            case .none: configuration.quote = nil; configuration.escape = "\""
            case .doubled: configuration.quote = "\""; configuration.escape = "\""
            case .backslash: configuration.quote = "\""; configuration.escape = "\\"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Picker("Encoding", selection: $configuration.encoding) {
                    ForEach(String.Encoding.csvSupported, id: \.rawValue) { encoding in
                        Text(encoding.localizedName).tag(encoding)
                    }
                }
                Toggle("Byte order mark (BOM)", isOn: $configuration.hasByteOrderMark)
                Picker("Separator", selection: $configuration.delimiter) {
                    Text(FormatLabels.delimiter(",")).tag(Unicode.Scalar(","))
                    Text(FormatLabels.delimiter(";")).tag(Unicode.Scalar(";"))
                    Text(FormatLabels.delimiter("\t")).tag(Unicode.Scalar("\t"))
                }
                Picker("Quotes", selection: quoteMode) {
                    Text(FormatLabels.quote(nil, escape: "\"")).tag(QuoteMode.none)
                    Text(FormatLabels.quote("\"", escape: "\"")).tag(QuoteMode.doubled)
                    Text(FormatLabels.quote("\"", escape: "\\")).tag(QuoteMode.backslash)
                }
                Picker("Decimal mark", selection: $configuration.decimalMark) {
                    Text(verbatim: ".").tag(Unicode.Scalar("."))
                    Text(verbatim: ",").tag(Unicode.Scalar(","))
                }
                Toggle("First row is header", isOn: $configuration.hasHeaderRow)
                Picker("Line ending", selection: $configuration.lineEnding) {
                    Text(verbatim: "LF (macOS / Unix)").tag(CSVConfiguration.LineEnding.lf)
                    Text(verbatim: "CRLF (Windows)").tag(CSVConfiguration.LineEnding.crlf)
                }
                Picker("Quote cells", selection: $configuration.quotingStyle) {
                    Text("Only when needed").tag(CSVConfiguration.QuotingStyle.minimal)
                    Text("Always").tag(CSVConfiguration.QuotingStyle.always)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Reload with This Format") { onReinterpret(configuration) }
                    .disabled(!canReinterpret)
                Button("Use for Saving") { onApply(configuration) }
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom])
        }
        .frame(width: 460)
    }
}
