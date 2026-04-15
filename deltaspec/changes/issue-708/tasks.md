## 1. session-state.sh 修正

- [x] 1.1 `plugins/session/scripts/session-state.sh` L158-166 の OR 条件ロジックを読む（現状把握）
- [x] 1.2 `"bypass permissions"` 分岐を先行チェックに分離（`input-waiting` 返却）
- [x] 1.3 `"esc to interrupt"` 分岐を独立チェックに分離（`processing` 返却）
- [x] 1.4 processing indicator 否定チェック（L162）を削除

## 2. テスト追加

- [x] 2.1 `plugins/session/tests/session-state-input-waiting.bats` の既存テスト 12 件を確認
- [x] 2.2 新規テスト追加: `"esc to interrupt"` のみ → `processing`（false positive 再現テスト）
- [x] 2.3 新規テスト追加: `"bypass permissions"` のみ → `input-waiting`
- [x] 2.4 新規テスト追加: `"esc to interrupt"` + `"Thinking"` → `processing`
- [x] 2.5 新規テスト追加: `"bypass permissions"` + `"esc to interrupt"` 同時 → `input-waiting`（bypass 優先）

## 3. 検証

- [x] 3.1 `bats plugins/session/tests/session-state-input-waiting.bats` を実行し 16 件 PASS を確認
