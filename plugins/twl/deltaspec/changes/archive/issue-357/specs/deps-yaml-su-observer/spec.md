## MODIFIED Requirements

### Requirement: su-observer コンポーネントエントリ

deps.yaml の components セクションに `su-observer` エントリが存在しなければならない（SHALL）。`co-observer` エントリは削除されなければならない（SHALL）。`type` は `supervisor` に設定されなければならない（SHALL）。

#### Scenario: su-observer エントリ存在確認
- **WHEN** `plugins/twl/deps.yaml` を参照する
- **THEN** `su-observer:` キーのエントリが存在し、`type: supervisor` が設定されている

#### Scenario: co-observer エントリ不存在確認
- **WHEN** `plugins/twl/deps.yaml` を参照する
- **THEN** `co-observer:` キーのエントリが存在しない

### Requirement: entry_points パス更新

deps.yaml の entry_points セクションで参照する su-observer のスキルパスは `skills/su-observer/SKILL.md` でなければならない（SHALL）。

#### Scenario: entry_points パス確認
- **WHEN** deps.yaml の entry_points セクションを参照する
- **THEN** `skills/su-observer/SKILL.md` が参照され、`skills/co-observer/SKILL.md` への参照が存在しない

### Requirement: co-autopilot calls 参照更新

co-autopilot セクションの `calls` 内の controller 参照は `su-observer` でなければならない（SHALL）。

#### Scenario: co-autopilot calls 参照確認
- **WHEN** deps.yaml の co-autopilot コンポーネントの calls セクションを参照する
- **THEN** `controller: su-observer`（または相当する参照）が存在し、`co-observer` への参照が存在しない

### Requirement: twl check PASS

deps.yaml の変更後、`twl check` がエラーなく完了しなければならない（SHALL）。

#### Scenario: twl check 正常完了
- **WHEN** deps.yaml 更新後に `twl check` を実行する
- **THEN** exit code 0 で完了し、エラーメッセージが出力されない

### Requirement: twl update-readme 正常完了

`twl update-readme` が正常に完了しなければならない（SHALL）。

#### Scenario: twl update-readme 正常完了
- **WHEN** deps.yaml 更新後に `twl update-readme` を実行する
- **THEN** exit code 0 で完了する
