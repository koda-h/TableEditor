import Foundation

/// ファイルのバイト列と表の相互変換（アプリから使う入口）
public enum CSVFile {
    /// 形式を自動判定して読み込む
    public static func read(_ data: Data, heuristic: CSVHeuristic = CSVHeuristic()) throws(CSVError) -> (CSVTable, CSVConfiguration) {
        let configuration = heuristic.detect(data)
        return (try read(data, configuration: configuration), configuration)
    }

    /// 指定した形式で読み込む
    public static func read(_ data: Data, configuration: CSVConfiguration) throws(CSVError) -> CSVTable {
        var reader = try CSVReader(data: data, configuration: configuration)
        return CSVTable(parsedRows: try reader.readAll(), hasHeaderRow: configuration.hasHeaderRow)
    }
}
