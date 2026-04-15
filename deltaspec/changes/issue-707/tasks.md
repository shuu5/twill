## 1. resolve ログレベル分離

- [x] 1.1 `inject_next_workflow()` の `resolve_next_workflow` 呼び出し後の失敗処理を修正: exit=1 は TRACE ログのみ（`category=RESOLVE_NOT_READY`）、exit≠1 は WARNING ログ + TRACE ログ（`category=RESOLVE_ERROR`）に分岐する
- [x] 1.2 TRACE ログエントリに `category` フィールドを追加し、`RESOLVE_NOT_READY` / `RESOLVE_ERROR` / `INJECT_TIMEOUT` / `INJECT_SUCCESS` を記録する

## 2. session-state.sh ベースの input-waiting 検出

- [x] 2.1 `inject_next_workflow()` の tmux capture-pane + regex ループ（L936-955）を削除し、`session-state.sh state "$window_name"` で `input-waiting` を判定するループに置換する
- [x] 2.2 SESSION_STATE_CMD 変数が設定されていない場合のフォールバック（またはエラーハンドリング）を追加する

## 3. exponential backoff 適用

- [x] 3.1 prompt 検出リトライの `sleep 2` を `sleep $(( 2 ** _i ))` に変更し（i=1,2,3 → 2s, 4s, 8s）exponential backoff を適用する

## 4. sandbox テスト追加・更新

- [x] 4.1 既存のsandbox テストまたは bats テストで、orchestrator が Worker の terminal step 到達後に正常に inject できることを確認するテストケースを追加・更新する
- [x] 4.2 resolve_not_ready (exit=1) のログが WARNING を出力しないことを検証するテストケースを追加する
