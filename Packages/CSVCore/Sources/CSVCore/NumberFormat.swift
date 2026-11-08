/// セルの値が数値かどうかの判定と、小数点記号の変換。
///
/// オリジナルの正規表現 `^\s*[+-]?(\d+\.?\d*|\d*\.?\d+)([eE][+-]?\d+)?\s*$` と同じ規則。
/// オリジナルは数値を NSDecimalNumber に変換していたが、ここでは文字列のまま保持し
/// （`007` などの表記を失わないため）、判定と変換だけを行う。
public enum NumberFormat {
    public static func isNumber(_ value: String, decimalMark: Unicode.Scalar) -> Bool {
        numberBounds(value.utf8, decimalMark: decimalMark) != nil
    }

    /// 数値であれば小数点記号を置き換えた文字列を、そうでなければ元の文字列を返す。
    public static func convertDecimalMark(
        _ value: String, from source: Unicode.Scalar, to destination: Unicode.Scalar
    ) -> String {
        guard source != destination, isNumber(value, decimalMark: source) else { return value }
        return String(String.UnicodeScalarView(value.unicodeScalars.map { $0 == source ? destination : $0 }))
    }

    private static func numberBounds(_ utf8: String.UTF8View, decimalMark: Unicode.Scalar) -> Range<Int>? {
        guard decimalMark.isASCII else { return nil }
        let mark = UInt8(decimalMark.value)
        let bytes = Array(utf8)
        var i = 0
        func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
        func isSpace(_ b: UInt8) -> Bool { b == 0x20 || (b >= 0x09 && b <= 0x0D) }

        while i < bytes.count, isSpace(bytes[i]) { i += 1 }
        let start = i
        if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }

        var digits = 0
        while i < bytes.count, isDigit(bytes[i]) { i += 1; digits += 1 }
        if i < bytes.count, bytes[i] == mark {
            i += 1
            while i < bytes.count, isDigit(bytes[i]) { i += 1; digits += 1 }
        }
        guard digits > 0 else { return nil }

        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            i += 1
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") { i += 1 }
            var expDigits = 0
            while i < bytes.count, isDigit(bytes[i]) { i += 1; expDigits += 1 }
            guard expDigits > 0 else { return nil }
        }
        let end = i
        while i < bytes.count, isSpace(bytes[i]) { i += 1 }
        return i == bytes.count ? start..<end : nil
    }
}
