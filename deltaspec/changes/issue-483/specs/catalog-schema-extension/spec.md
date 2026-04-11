## ADDED Requirements

### Requirement: test-scenario-catalog bug_target フィールド追加

test-scenario-catalog.md のシナリオ YAML スキーマに `bug_target` フィールドを追加しなければならない（SHALL）。`bug_target` は整数または null 許容で、bug 再現シナリオはバグ Issue 番号を、汎用シナリオは null を指定する。

#### Scenario: bug_target フィールドがスキーマに定義される
- **WHEN** test-scenario-catalog.md を読み込む
- **THEN** scenario YAML フォーマットセクションに `bug_target:` フィールドが定義されている

#### Scenario: bug 再現シナリオが bug_target を持つ
- **WHEN** bug-469-chain-stall シナリオを読み込む
- **THEN** `bug_target: 469` が設定されている

#### Scenario: combo シナリオが bug_target null を持つ
- **WHEN** bug-combo-469-472 シナリオを読み込む
- **THEN** `bug_target: null` が設定され description に #469 と #472 の両方が参照されている

### Requirement: test-scenario-catalog bug level 追加

test-scenario-catalog.md の level enum に `bug` 値を追加しなければならない（SHALL）。`bug` level は特定の chain 遷移・stall パターンの再現検証に特化し、`regression` level（並列実行 conflict 検証）と明確に区別される。

#### Scenario: level enum に bug が追加される
- **WHEN** test-scenario-catalog.md のスキーマ定義を読み込む
- **THEN** `level: smoke | regression | load | bug` として 4 値が定義されている

### Requirement: 5 バグ再現シナリオの追加

test-scenario-catalog.md に Wave 1-5 由来の 5 シナリオを追加しなければならない（SHALL）。各シナリオは必須フィールド（level/description/issues_count/expected_duration_max/expected_conflicts/bug_target）を全て含む。

#### Scenario: bug-469-chain-stall シナリオが追加される
- **WHEN** test-scenario-catalog.md を読み込む
- **THEN** `bug-469-chain-stall:` エントリが存在し `level: bug, bug_target: 469` を持つ

#### Scenario: bug-470-state-path シナリオが追加される
- **WHEN** test-scenario-catalog.md を読み込む
- **THEN** `bug-470-state-path:` エントリが存在し `level: bug, bug_target: 470` を持つ

#### Scenario: bug-471-refspec シナリオが追加される
- **WHEN** test-scenario-catalog.md を読み込む
- **THEN** `bug-471-refspec:` エントリが存在し `level: bug, bug_target: 471` を持つ

#### Scenario: bug-472-monitor-stall シナリオが追加される
- **WHEN** test-scenario-catalog.md を読み込む
- **THEN** `bug-472-monitor-stall:` エントリが存在し `level: bug, bug_target: 472` を持つ

#### Scenario: bug-combo-469-472 シナリオが追加される
- **WHEN** test-scenario-catalog.md を読み込む
- **THEN** `bug-combo-469-472:` エントリが存在し `issues_count: 3, expected_conflicts: 0, expected_duration_max: 60, bug_target: null` を持つ

## MODIFIED Requirements

### Requirement: observation-pattern-catalog bug-* パターン追加

observation-pattern-catalog.md の bug-reproduction patterns セクションに Wave 4-5 由来の bug-* パターンを追加しなければならない（SHALL）。各パターンは `regex`/`severity`/`category`/`description`/`related_issue` フィールドを全て含む。

#### Scenario: bug-469 パターンが追加される
- **WHEN** observation-pattern-catalog.md を読み込む
- **THEN** `bug-469-` プレフィックスを持つパターンが存在し `related_issue: "469"` を持つ

#### Scenario: bug-470 パターンが追加される
- **WHEN** observation-pattern-catalog.md を読み込む
- **THEN** `bug-470-` プレフィックスを持つパターンが存在し `related_issue: "470"` を持つ

#### Scenario: bug-471 パターンが追加される
- **WHEN** observation-pattern-catalog.md を読み込む
- **THEN** `bug-471-` プレフィックスを持つパターンが存在し `related_issue: "471"` を持つ

#### Scenario: bug-472 パターンが追加される
- **WHEN** observation-pattern-catalog.md を読み込む
- **THEN** `bug-472-` プレフィックスを持つパターンが存在し `related_issue: "472"` を持つ

#### Scenario: bug パターン合計数が 7 以上になる
- **WHEN** observation-pattern-catalog.md を読み込む
- **THEN** `^bug-` にマッチするエントリが 7 件以上存在する（既存 3 件 + 新規 4 件）

### Requirement: observation-references.bats 検証ケース追加

`plugins/twl/tests/bats/refs/observation-references.bats` に bug-4xx パターンの検証ケースを追加しなければならない（SHALL）。既存の `bug_count -ge 3` 閾値を `bug_count -ge 7` に引き上げる。

#### Scenario: bats に bug-469 検証ケースが追加される
- **WHEN** observation-references.bats を実行する
- **THEN** `bug-469-` パターンの存在と `related_issue: "469"` を検証するテストがパスする

#### Scenario: bats の bug_count 閾値が 7 に更新される
- **WHEN** observation-references.bats を読み込む
- **THEN** `bug_count -ge 7` 条件が記載されている
