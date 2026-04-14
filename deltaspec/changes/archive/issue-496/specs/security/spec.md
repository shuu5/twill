## ADDED Requirements

### Requirement: check_and_nudge allow-list 検証

`check_and_nudge` は `_nudge_command_for_pattern` が返す `next_cmd` を `tmux send-keys` に渡す前に allow-list 正規表現 `^/twl:workflow-[a-z][a-z0-9-]*$` でバリデーションしなければならない（SHALL）。

#### Scenario: 有効な workflow コマンドは inject される
- **WHEN** `_nudge_command_for_pattern` が `/twl:workflow-test-ready` を返す
- **THEN** allow-list を通過し `tmux send-keys` に渡される

#### Scenario: 不正なコマンドは nudge をスキップする
- **WHEN** `_nudge_command_for_pattern` が allow-list 正規表現に一致しない文字列を返す
- **THEN** WARNING ログを出力し `tmux send-keys` を呼び出さずに `return 0` する

#### Scenario: バリデーション失敗時に trace ログを出力する
- **WHEN** allow-list バリデーションが失敗する
- **THEN** trace ログファイルに `result=skip reason="invalid next_cmd"` のエントリが記録されなければならない（SHALL）

#### Scenario: 既存 7 パターンは全て allow-list を通過する
- **WHEN** `_nudge_command_for_pattern` が返す 7 パターン（`/twl:workflow-test-ready`、`/twl:workflow-pr-verify` ×2、`/twl:workflow-pr-fix`、`/twl:workflow-pr-merge`、空文字列 ×2）を allow-list に通す
- **THEN** 空文字列は `[[ -n "$next_cmd" ]]` で除外、残り 5 パターンは全て `^/twl:workflow-[a-z][a-z0-9-]*$` に一致する

### Requirement: ADR-0009 tmux pane trust model

`architecture/decisions/` に ADR-0009 を新規作成し tmux pane trust model を明文化しなければならない（SHALL）。

#### Scenario: ADR が脅威モデルを定義する
- **WHEN** ADR-0009 を参照する
- **THEN** 「信頼する入力源」と「信頼しない入力源」が明記されており、最終防衛線が `tmux send-keys` 直前の allow-list バリデーションであることが読み取れる

#### Scenario: ADR が適用範囲を明示する
- **WHEN** ADR-0009 を参照する
- **THEN** 対象の脅威モデルが「同一ユーザー・同一 tmux セッション内」に限定されることが明記されており、リモート攻撃者は対象外であることが分かる

### Requirement: shunit2 テストによる検証

shunit2 テストを追加し `check_and_nudge` の allow-list 検証を自動確認しなければならない（SHALL）。

#### Scenario: 有効パターンがテストで通過する
- **WHEN** shunit2 テストで `_nudge_command_for_pattern` の既存 7 パターンを対象に allow-list 正規表現を評価する
- **THEN** 非空文字列の 5 パターン全てが `^/twl:workflow-[a-z][a-z0-9-]*$` に一致する

#### Scenario: 不正パターンがテストでブロックされる
- **WHEN** shunit2 テストで `check_and_nudge` に不正な `next_cmd` を注入する（モック）
- **THEN** `tmux send-keys` が呼ばれず WARNING 出力が発生することを確認する
