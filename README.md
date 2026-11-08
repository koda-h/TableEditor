# Table Editor

macOS 用のシンプルな CSV エディタ。[Table Tool](https://github.com/jakob/TableTool)（MIT、2017 年で更新停止）の代わりとして、
Swift / AppKit で作り直したもの。

> 「Table Editor」とバンドル ID `dev.koda-h.TableEditor` は仮の名前です。

## 方針

- Table Tool と同じく「CSV を開く・編集する・別形式で保存する」ことに絞る（書式や数式は扱わない）
- 形式（文字コード・区切り文字・引用符・小数点・ヘッダー行）を自動判定する。判定方法は Table Tool から移植した
- Apple Silicon ネイティブ、macOS 14 以降

## 構成

```
TableEditor.xcodeproj      Xcode プロジェクト（フォルダ同期型。ファイル追加でプロジェクト編集は不要）
TableEditor/               アプリ本体（AppKit、XIB なし）
  main.swift               起動処理
  MainMenu.swift           メインメニュー
  Document.swift           NSDocument。表データ・形式・Undo を管理
  DocumentWindowController.swift  ウインドウ、ツールバー、ステータスバー
  TableViewController.swift       View ベースの NSTableView、行列操作、コピー＆ペースト
  ColumnSelectionViews.swift      列選択の色付け（行ビューとヘッダー）
  FormatSettingsView.swift        ファイル形式シート（SwiftUI）
  Info.plist               書類タイプ（CSV / TSV / テキスト）
Packages/CSVCore/          UI に依存しない CSV 処理（Swift Package）
  CSVReader                解析（UTF-8 バイト単位で走査）
  CSVHeuristic             形式の自動判定（Table Tool の移植＋日本語環境では Shift_JIS、BOM、改行コード）
  CSVWriter                書き出し（引用符の付け方、改行コード、BOM、小数点記号の変換）
  CSVTable                 編集対象の表モデル（行列の追加・削除・移動。逆操作用の情報を返す）
  Tests/                   Swift Testing。Fixtures は Table Tool から取り込んだもの（MIT）
```

## ビルドとテスト

Xcode で `TableEditor.xcodeproj` を開いて Run。コマンドラインでは次のとおり。

```bash
xcodebuild -project TableEditor.xcodeproj -scheme TableEditor -derivedDataPath build/DerivedData build
```

```bash
swift test --package-path Packages/CSVCore
```

## Table Tool から変えた点

- 数値を `NSDecimalNumber` に変換せず、文字列のまま持つ（`007` などの表記が消えない）。
  数値の判定は右寄せ表示と、保存時の小数点記号の変換にだけ使う
- 日本語環境では文字コードの候補に Shift_JIS（CP932）を加える（UTF-8 → Shift_JIS → CP1252 → MacRoman → GB18030 の順）
- UTF-8 / UTF-16 の BOM を判定し、保存時も保つ
- 改行コード（LF / CRLF）と末尾改行の有無を判定し、保存時も保つ
- 引用符は「必要なときだけ」がデフォルト（「常に付ける」も選べる）
- 列の並べ替えは表示だけでなくデータも並べ替える

## 既知の課題・TODO

- [ ] Shift_JIS の一部の文字（例: 髙）は、macOS の変換で別の符号（NEC 選定 IBM 拡張）になるため、保存するとバイト列が変わる。どちらも正しい CP932 だが、気になる場合は独自の変換表が必要
- [ ] 複数の列をまとめてドラッグで並べ替える（NSTableView の制約で 1 列ずつ）
- [ ] ヘッダー（列名）をその場で編集する UI（`Document.setHeaderTitle` は実装済み）
- [ ] 行の並べ替え（ドラッグ＆ドロップ）
- [ ] 「最近使った書類」メニュー
- [ ] 日本語化（String Catalog。コードは `String(localized:)` で書いてあるので、Xcode でカタログを追加すれば文字列が抽出される）
- [ ] アプリアイコン
- [ ] 大きなファイルの非同期読み込み（`canConcurrentlyReadDocuments`）
- [ ] 配布（Developer ID 署名と公証）

## ライセンス

`Packages/CSVCore/Tests/CSVCoreTests/Fixtures/` は Table Tool のテストデータで、MIT ライセンスです（同じフォルダの `LICENSE-TableTool.txt` 参照）。
