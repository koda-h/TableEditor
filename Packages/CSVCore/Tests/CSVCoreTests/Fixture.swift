import Foundation
import Testing

/// 元リポジトリから取り込んだテスト用 CSV（Fixtures/LICENSE-TableTool.txt 参照）
enum Fixture {
    static func data(_ path: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(path)", withExtension: "csv"))
        return try Data(contentsOf: url)
    }
}
