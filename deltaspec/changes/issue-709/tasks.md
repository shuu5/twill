## 1. issue-lifecycle-orchestrator.sh inject ロジック修正

- [x] 1.1 L380 の `input-waiting` 検出直後に `sleep 5` + `session-state.sh` 再確認ロジックを追加し、再確認が `input-waiting` 以外なら `all_done=false; continue` でスキップする
- [x] 1.2 inject 上限を 3 → 5 に変更（`-lt 3` → `-lt 5`）
- [x] 1.3 inject ログメッセージ内の上限値 `3` を `5` に更新
- [x] 1.4 inject 実行直前（`session-comm.sh` 前）に `session-state.sh` 再確認を追加し、`input-waiting` でなければ `continue`
- [x] 1.5 inject 実行後に `sleep $((5 * inject_count))` の progressive delay を追加
- [x] 1.6 inject メッセージを `"処理を続行してください。"` に簡素化（`existing-issue.json` 分岐を削除）

## 2. 検証

- [x] 2.1 `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` の変更箇所を手動レビューし、Issue #709 の受け入れ基準を全て満たすことを確認する
- [x] 2.2 `twl --check` でバリデーション通過を確認する
