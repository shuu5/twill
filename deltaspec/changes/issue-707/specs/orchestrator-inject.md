## MODIFIED Requirements

### Requirement: resolve ログレベル分離

`inject_next_workflow()` の `resolve_next_workflow` 呼び出し結果は、exit=1（non-terminal step）と予期せぬエラーを区別しなければならない（SHALL）。

#### Scenario: non-terminal step での resolve 失敗
- **WHEN** `resolve_next_workflow` が exit=1 で終了する（Worker がまだ processing 中）
- **THEN** TRACE ログに `category=RESOLVE_NOT_READY` として記録され、WARNING は出力されない

#### Scenario: 予期せぬ resolve エラー
- **WHEN** `resolve_next_workflow` が exit=1 以外（例: exit=2, exit=127）で終了する
- **THEN** WARNING ログに `resolve_next_workflow 予期せぬエラー` が出力され、TRACE ログに `category=RESOLVE_ERROR` として記録される

### Requirement: session-state.sh ベースの input-waiting 検出

`inject_next_workflow()` は tmux capture-pane + regex に依存してはならず、`session-state.sh state` の `input-waiting` 判定を使用しなければならない（SHALL）。

#### Scenario: Worker が terminal step で input-waiting 状態
- **WHEN** Worker が terminal step を完了し、`session-state.sh state <window>` が `input-waiting` を返す
- **THEN** inject が実行され、trace ログに `category=INJECT_SUCCESS` が記録される

#### Scenario: Worker がまだ processing 中
- **WHEN** `session-state.sh state <window>` が `processing` を返す（input-waiting ではない）
- **THEN** exponential backoff で最大3回リトライし、全失敗時に trace ログに `category=INJECT_TIMEOUT` が記録される

### Requirement: prompt 検出 exponential backoff

prompt 検出リトライは exponential backoff（2s, 4s, 8s）を適用しなければならない（SHALL）。

#### Scenario: 1回目のリトライで input-waiting 検出
- **WHEN** 1回目の `session-state.sh state` チェック（2秒待機後）で `input-waiting` が返る
- **THEN** inject が実行される（合計待機: 2秒）

#### Scenario: 3回全てのリトライで input-waiting が検出されない
- **WHEN** 3回全ての session-state チェックで `input-waiting` が返らない
- **THEN** `inject_next_workflow` は 1 を返し、次のポーリングサイクルで再試行される（合計待機: 2+4+8=14秒）

## ADDED Requirements

### Requirement: trace ログカテゴリ記録

`inject_next_workflow()` は全ての処理結果を `category` フィールド付きで trace ログに記録しなければならない（SHALL）。

#### Scenario: trace ログに RESOLVE_NOT_READY カテゴリが記録される
- **WHEN** `resolve_next_workflow` が exit=1 で終了する
- **THEN** trace ログに `category=RESOLVE_NOT_READY` を含むエントリが追記される

#### Scenario: trace ログに INJECT_SUCCESS カテゴリが記録される
- **WHEN** inject が成功する（tmux send-keys が正常終了）
- **THEN** trace ログに `category=INJECT_SUCCESS` を含むエントリが追記される

#### Scenario: trace ログに INJECT_TIMEOUT カテゴリが記録される
- **WHEN** 3回全ての input-waiting チェックが失敗する
- **THEN** trace ログに `category=INJECT_TIMEOUT` を含むエントリが追記される
