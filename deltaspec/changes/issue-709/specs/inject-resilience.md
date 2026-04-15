## MODIFIED Requirements

### Requirement: input-waiting debounce
`issue-lifecycle-orchestrator.sh` の `wait_for_batch()` は、`session-state.sh` が `input-waiting` を返した直後に、5 秒の debounce を設け `session-state.sh` で再確認しなければならない（SHALL）。再確認が `input-waiting` でない場合、inject をスキップしてポーリングサイクルを継続しなければならない（MUST）。

#### Scenario: transient false positive を排除する
- **WHEN** `session-state.sh` が `input-waiting` を返し、5 秒後の再確認が `input-waiting` 以外を返す
- **THEN** inject を実行せず `all_done=false` で次のポーリングサイクルへ進む

#### Scenario: 真の input-waiting を受理する
- **WHEN** `session-state.sh` が `input-waiting` を返し、5 秒後の再確認も `input-waiting` を返す
- **THEN** inject フローを継続する

### Requirement: inject 上限緩和
inject 上限は 5 回でなければならない（MUST）。`inject_count -lt 3` の条件を `-lt 5` に変更し、ログメッセージ内の上限値も 5 に更新しなければならない（SHALL）。

#### Scenario: inject 5 回未満で継続する
- **WHEN** `inject_count` が 5 未満かつ non-terminal state で `input-waiting` が確認される
- **THEN** inject を実行し `inject_count` をインクリメントする

#### Scenario: inject 5 回到達で fallback に移行する
- **WHEN** `inject_count` が 5 以上になる
- **THEN** fallback report を生成してウィンドウを kill する

### Requirement: inject 間の progressive delay
inject 実行後に `sleep $((5 * inject_count))` を挿入しなければならない（MUST）。これにより inject 間隔が回数に応じて増加し（5秒・10秒・15秒・20秒・25秒）、Worker の処理時間を確保しなければならない（SHALL）。

#### Scenario: inject 後に progressive delay が適用される
- **WHEN** inject が実行される
- **THEN** `sleep $((5 * inject_count))` が inject の直後に実行される

### Requirement: inject 直前の状態再確認
inject 実行直前（`session-comm.sh` 呼び出し前）に `session-state.sh` で状態を再確認しなければならない（MUST）。再確認が `input-waiting` でない場合は inject をスキップしなければならない（SHALL）。

#### Scenario: inject 直前に状態が変化していれば注入しない
- **WHEN** inject 実行直前の再確認で `session-state.sh` が `input-waiting` 以外を返す
- **THEN** inject を実行せず `continue` でポーリングサイクルへ戻る

#### Scenario: inject 直前も input-waiting なら注入する
- **WHEN** inject 実行直前の再確認でも `session-state.sh` が `input-waiting` を返す
- **THEN** `session-comm.sh inject` を実行する

### Requirement: inject メッセージ簡素化
inject メッセージは `"処理を続行してください。"` に統一しなければならない（MUST）。ワークフロー分岐（`existing-issue.json` 有無による分岐）を削除しなければならない（SHALL）。

#### Scenario: inject メッセージが簡潔である
- **WHEN** inject が実行される
- **THEN** `session-comm.sh inject` に渡すメッセージが `"処理を続行してください。"` である
