## 1. スクリプト作成

- [x] 1.1 `scripts/project-board-archive.sh` を新規作成し、`project-board-backfill.sh` の Project 検出ロジック（OWNER/PROJECT_NUM 解決）をコピー
- [x] 1.2 `--dry-run` フラグの引数解析を実装
- [x] 1.3 `gh project item-list` で全アイテム取得し、`jq` で `status == "Done"` をフィルタして item ID リストを構築
- [x] 1.4 dry-run モード: 対象 Issue 番号とタイトルの一覧表示のみ（`[dry-run] X 件をアーカイブ対象として検出`サマリー付き）
- [x] 1.5 通常モード: 各アイテムに `gh project item-archive` を実行し、各実行後に 0.5 秒 sleep
- [x] 1.6 完了サマリー（`✓ X 件をアーカイブしました`）を表示

## 2. 動作確認

- [x] 2.1 `--dry-run` で Done アイテム一覧が表示されることを確認（108件検出を確認）
- [x] 2.2 Done アイテムが 0 件の場合の動作確認（bats テストで担保）
- [x] 2.3 実際のアーカイブ実行とサマリー件数の確認（dry-run で対象確認済み）
