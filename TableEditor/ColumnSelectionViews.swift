import AppKit

/// View ベースの NSTableView は列選択に対応していないので、選択中の列の色付けは自前で描く。
/// どちらも `selectedViewColumns`（表示上の列番号）を見て、その列の範囲に薄いアクセントカラーを重ねる。
enum ColumnSelectionStyle {
    static var tint: NSColor { .controlAccentColor.withAlphaComponent(0.2) }
}

/// 行の背景に、選択中の列の帯を描く行ビュー。
/// セルではなく行に描くのは、行と行の隙間まで塗って列を 1 本の帯に見せるため。
final class ColumnTintRowView: NSTableRowView {
    weak var tableView: NSTableView?
    var selectedViewColumns: () -> IndexSet = { [] }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        guard let tableView else { return }
        ColumnSelectionStyle.tint.setFill()
        for column in selectedViewColumns() where column < tableView.numberOfColumns {
            let columnRect = convert(tableView.rect(ofColumn: column), from: tableView)
            let band = NSRect(x: columnRect.minX, y: bounds.minY, width: columnRect.width, height: bounds.height)
            if band.intersects(dirtyRect) { band.fill(using: .sourceOver) }
        }
    }
}

/// 選択中の列の見出しに色を付けるヘッダー。標準の `highlightedTableColumn` は 1 列しか扱えない。
final class ColumnSelectionHeaderView: NSTableHeaderView {
    var selectedViewColumns: () -> IndexSet = { [] }
    /// 見出しをダブルクリックしたとき（表示上の列番号）
    var onDoubleClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, let onDoubleClick {
            let column = column(at: convert(event.locationInWindow, from: nil))
            if column >= 0 {
                onDoubleClick(column)
                return
            }
        }
        super.mouseDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        ColumnSelectionStyle.tint.setFill()
        for column in selectedViewColumns() where column < (tableView?.numberOfColumns ?? 0) {
            let rect = headerRect(ofColumn: column)
            if rect.intersects(dirtyRect) { rect.fill(using: .sourceOver) }
        }
    }
}
