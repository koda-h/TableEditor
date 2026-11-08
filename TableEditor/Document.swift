import AppKit
import SwiftUI
import CSVCore

/// 表の変更内容。ビューの再描画範囲を決めるのに使う。
enum TableChange {
    case cell(row: Int, column: Int)
    case rows
    case columns
}

/// CSV 書類。表データ・ファイル形式・Undo を管理する。
final class Document: NSDocument {
    private(set) var table = CSVTable.empty(rows: 3, columns: 3)
    private(set) var configuration = CSVConfiguration()
    /// 表に入っている数値の小数点記号（保存時に `configuration.decimalMark` へ変換する）
    private(set) var tableDecimalMark: Unicode.Scalar = "."
    /// 開いたときのバイト列。形式を変えて読み直すときに使う
    private var originalData: Data?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    // MARK: - Reading / Writing

    /// NSDocument の読み込みは nonisolated として宣言されている。
    /// 解析はどのスレッドでもよいが、状態の更新はメインスレッドで行う
    /// （`canConcurrentlyReadDocuments` を有効にしていないので、ここはメインスレッドで呼ばれる）。
    nonisolated override func read(from data: Data, ofType typeName: String) throws {
        let (table, configuration) = try CSVFile.read(data)
        MainActor.assumeIsolated {
            self.table = table
            self.configuration = configuration
            tableDecimalMark = configuration.decimalMark
            originalData = data
            undoManager?.removeAllActions()
            notify(.columns)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        try CSVWriter.data(for: table, configuration: configuration, sourceDecimalMark: tableDecimalMark)
    }

    // MARK: - Editing (すべて Undo 可能)

    func setValue(_ value: String, row: Int, column: Int) {
        let old = table[row, column]
        guard old != value else { return }
        table[row, column] = value
        registerUndo(String(localized: "Edit Cell")) { $0.setValue(old, row: row, column: column) }
        notify(.cell(row: row, column: column))
    }

    func setHeaderTitle(_ title: String, column: Int) {
        let old = table.columnTitle(column)
        guard old != title else { return }
        table.setHeaderTitle(title, column: column)
        registerUndo(String(localized: "Rename Column")) { $0.setHeaderTitle(old, column: column) }
        notify(.columns)
    }

    func insertRows(_ contents: [[String]], at indexes: IndexSet) {
        table.insertRows(contents, at: indexes)
        registerUndo(String(localized: "Add Row")) { $0.removeRows(at: indexes) }
        notify(.rows)
    }

    func removeRows(at indexes: IndexSet) {
        let removed = table.removeRows(at: indexes)
        registerUndo(String(localized: "Delete Row")) { $0.insertRows(removed, at: indexes) }
        notify(.rows)
    }

    func insertColumns(_ contents: [CSVTable.ColumnContent], at indexes: IndexSet) {
        table.insertColumns(contents, at: indexes)
        registerUndo(String(localized: "Add Column")) { $0.removeColumns(at: indexes) }
        notify(.columns)
    }

    func removeColumns(at indexes: IndexSet) {
        let removed = table.removeColumns(at: indexes)
        registerUndo(String(localized: "Delete Column")) { $0.insertColumns(removed, at: indexes) }
        notify(.columns)
    }

    func moveColumn(from source: Int, to destination: Int) {
        guard source != destination else { return }
        table.moveColumn(from: source, to: destination)
        registerUndo(String(localized: "Move Column")) { $0.moveColumn(from: destination, to: source) }
        notify(.columns)
    }

    func setUsesHeaderRow(_ enabled: Bool) {
        guard enabled != (table.header != nil) else { return }
        table.setUsesHeaderRow(enabled)
        configuration.hasHeaderRow = enabled
        registerUndo(String(localized: "Header Row")) { $0.setUsesHeaderRow(!enabled) }
        notify(.columns)
    }

    /// 保存時の形式を変える（表の内容はそのまま）
    func setConfiguration(_ newValue: CSVConfiguration) {
        let old = configuration
        guard old != newValue else { return }
        configuration = newValue
        if old.hasHeaderRow != newValue.hasHeaderRow {
            table.setUsesHeaderRow(newValue.hasHeaderRow)
        }
        registerUndo(String(localized: "Change File Format")) { $0.setConfiguration(old) }
        notify(.columns)
    }

    /// 開いたときのバイト列を、指定した形式で読み直す
    func reinterpret(with newConfiguration: CSVConfiguration) throws {
        guard let originalData else { return }
        table = try CSVFile.read(originalData, configuration: newConfiguration)
        configuration = newConfiguration
        tableDecimalMark = newConfiguration.decimalMark
        undoManager?.removeAllActions()
        notify(.columns)
    }

    var canReinterpret: Bool { originalData != nil }

    // MARK: - Actions

    @objc func toggleHeaderRow(_ sender: Any?) {
        setUsesHeaderRow(table.header == nil)
    }

    @objc func showFormatSheet(_ sender: Any?) {
        guard let window = windowForSheet else { return }
        let sheet = NSWindow(contentViewController: NSHostingController(rootView: EmptyView()))
        let view = FormatSettingsView(
            configuration: configuration,
            canReinterpret: canReinterpret,
            onCancel: { [weak window, weak sheet] in
                if let sheet { window?.endSheet(sheet) }
            },
            onReinterpret: { [weak self, weak window, weak sheet] newValue in
                guard let self else { return }
                if let sheet { window?.endSheet(sheet) }
                do {
                    try self.reinterpret(with: newValue)
                } catch {
                    self.presentError(error)
                }
            },
            onApply: { [weak self, weak window, weak sheet] newValue in
                if let sheet { window?.endSheet(sheet) }
                self?.setConfiguration(newValue)
            }
        )
        sheet.contentViewController = NSHostingController(rootView: view)
        window.beginSheet(sheet)
    }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(toggleHeaderRow(_:)) {
            (item as? NSMenuItem)?.state = table.header != nil ? .on : .off
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Private

    private func registerUndo(_ name: String, _ handler: @escaping @MainActor (Document) -> Void) {
        undoManager?.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { handler(target) }
        }
        undoManager?.setActionName(name)
    }

    private func notify(_ change: TableChange) {
        for controller in windowControllers {
            (controller as? DocumentWindowController)?.documentDidChange(change)
        }
    }
}
