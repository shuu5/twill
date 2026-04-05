## 1. chain-runner.sh に board-archive 追加

- [x] 1.1 `step_board_archive()` 関数を追加（`step_board_status_update()` の Project 検出ロジックを踏襲）
- [x] 1.2 `gh project item-list` + `jq` で対象 Issue のアイテムIDを取得するロジックを実装
- [x] 1.3 `gh project item-archive` 呼び出しを実装
- [x] 1.4 エラー時は warning のみで `return 0`（`skip` パターン）
- [x] 1.5 `board-archive` サブコマンドのディスパッチ追加（`case "$1"` 分岐）

## 2. merge-gate-execute.sh に呼び出し追加

- [x] 2.1 PASS フロー末尾（worktree 削除後）に `bash scripts/chain-runner.sh board-archive "$ISSUE_NUM"` を追加
- [x] 2.2 ISSUE_NUM が空の場合はスキップするガード条件を追加

## 3. 動作確認

- [x] 3.1 `bash scripts/chain-runner.sh board-archive "<test-issue-num>"` を手動実行してアーカイブ成功を確認
- [x] 3.2 アーカイブ後に `gh project item-list` で当該 Issue が含まれないことを確認
- [x] 3.3 存在しない Issue番号でスキップ（警告のみ）になることを確認
