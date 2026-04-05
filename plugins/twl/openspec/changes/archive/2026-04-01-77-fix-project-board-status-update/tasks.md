## 1. project-board-status-update.md Step 2 書き換え

- [x] 1.1 `project-board-sync.md` の Step 2 ロジック（MATCHED_PROJECTS + TITLE_MATCH_PROJECT）を `project-board-status-update.md` の Step 2 に移植
- [x] 1.2 user → organization フォールバックの GraphQL クエリを記述
- [x] 1.3 複数 Project 検出時の警告メッセージを追加
- [x] 1.4 Project 未リンク時の正常終了パスを明記

## 2. バッチバックフィルスクリプト

- [x] 2.1 `scripts/project-board-backfill.sh` を新規作成（引数: 開始番号 終了番号）
- [x] 2.2 Project 検出ロジックを Step 2 と同等に実装（DRY: project-board-sync.md 参照）
- [x] 2.3 Issue ループ: `gh project item-add` + Status "In Progress" 設定
- [x] 2.4 結果を表形式で出力
- [x] 2.5 API レート制限対策（Issue 間 1 秒 wait）

## 3. 検証

- [x] 3.1 バッチスクリプトを実行し、欠落 Issue (#41-#58, #62等) を Board に追加
- [x] 3.2 `gh project item-list` で Board に追加されたことを確認
- [x] 3.3 `loom check` が PASS することを確認
