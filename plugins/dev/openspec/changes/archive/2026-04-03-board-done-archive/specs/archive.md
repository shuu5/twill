## ADDED Requirements

### Requirement: Done アイテム一括アーカイブ

`scripts/project-board-archive.sh` を実行すると、Project Board の Done ステータスのアイテムを全件アーカイブしなければならない（SHALL）。

#### Scenario: 通常実行
- **WHEN** `bash scripts/project-board-archive.sh` を引数なしで実行する
- **THEN** Done ステータスの全アイテムが `gh project item-archive` でアーカイブされ、アーカイブ件数を含むサマリーが表示される

#### Scenario: Done アイテムが 0 件
- **WHEN** Project Board に Done アイテムが存在しない状態で実行する
- **THEN** 「Done アイテムはありません」と表示し、正常終了する

### Requirement: dry-run モード

`--dry-run` フラグ指定時は実際のアーカイブを行わず、対象一覧のみを表示しなければならない（SHALL）。

#### Scenario: dry-run 実行
- **WHEN** `bash scripts/project-board-archive.sh --dry-run` を実行する
- **THEN** Done アイテムの Issue 番号とタイトルの一覧が表示され、`gh project item-archive` は実行されない

#### Scenario: dry-run でアーカイブ件数確認
- **WHEN** `--dry-run` モードで実行する
- **THEN** 「[dry-run] X 件をアーカイブ対象として検出」というサマリーが表示される

### Requirement: rate limit 対策

各アイテムのアーカイブ処理間に 0.5 秒の sleep を挟まなければならない（MUST）。

#### Scenario: 連続アーカイブ
- **WHEN** 複数の Done アイテムを順次アーカイブする
- **THEN** 各 `gh project item-archive` 実行後に 0.5 秒待機してから次のアーカイブを実行する

### Requirement: 実行サマリー表示

スクリプト完了時にアーカイブ件数を標準出力に表示しなければならない（SHALL）。

#### Scenario: 実行完了サマリー
- **WHEN** アーカイブ処理が完了する
- **THEN** 「✓ X 件をアーカイブしました」形式のサマリーが表示される
