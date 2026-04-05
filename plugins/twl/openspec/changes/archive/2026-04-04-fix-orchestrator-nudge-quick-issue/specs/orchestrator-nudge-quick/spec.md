## MODIFIED Requirements

### Requirement: quick Issue での test-ready nudge スキップ

`_nudge_command_for_pattern` は、Issue が quick（`is_quick=true`）の場合、test-ready 系パターン（"setup chain 完了"、"workflow-test-ready で次に進めます"）への nudge をスキップしなければならない（SHALL）。スキップ時は `return 1` を返し、nudge を送信しない。

#### Scenario: quick Issue で "setup chain 完了" パターン検出
- **WHEN** `is_quick=true` の Issue で pane_output が "setup chain 完了" を含む
- **THEN** `_nudge_command_for_pattern` は `return 1` を返し、`/twl:workflow-test-ready` を送信しない

#### Scenario: quick Issue で "workflow-test-ready で次に進めます" パターン検出
- **WHEN** `is_quick=true` の Issue で pane_output が "workflow-test-ready で次に進めます" を含む
- **THEN** `_nudge_command_for_pattern` は `return 1` を返し、`/twl:workflow-test-ready` を送信しない

#### Scenario: 通常 Issue は従来通り動作する
- **WHEN** `is_quick=false` の Issue で pane_output が "setup chain 完了" を含む
- **THEN** `_nudge_command_for_pattern` は `/twl:workflow-test-ready #N` を返す

### Requirement: is_quick フィールドのキャッシュ優先取得

`_nudge_command_for_pattern` は `is_quick` を `state-read.sh --field is_quick` から一次取得しなければならない（SHALL）。state ファイルに `is_quick` が未記録の場合、gh API を用いた fallback で quick ラベルの有無を確認する。

#### Scenario: state ファイルに is_quick が記録済み
- **WHEN** `state-read.sh --type issue --issue N --field is_quick` が "true" または "false" を返す
- **THEN** その値を使用し、gh API を呼び出さない

#### Scenario: state ファイルに is_quick が未記録
- **WHEN** `state-read.sh` が空文字を返す
- **THEN** `gh issue view N --json labels` で quick ラベルの存在を確認し、結果を is_quick として使用する

## ADDED Requirements

### Requirement: orchestrator-nudge.bats に quick Issue シナリオを追加

`orchestrator-nudge.bats` の test double（nudge-dispatch.sh）は quick Issue 判定ロジックを含まなければならない（SHALL）。quick Issue シナリオのテストを追加する。

#### Scenario: quick Issue で setup chain 完了 → nudge しない
- **WHEN** test double が `is_quick=true` の state ファイルを参照し、pane_output が "setup chain 完了" を含む
- **THEN** test double は空文字（nudge なし）を出力し、exit code 1 を返す

#### Scenario: quick Issue で通常パターンは影響を受けない
- **WHEN** `is_quick=true` の Issue で pane_output が "テスト準備が完了しました" を含む
- **THEN** test double は `/twl:workflow-pr-cycle #N` を返す（test-ready 以外のパターンは従来通り）
