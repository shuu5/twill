## ADDED Requirements

### Requirement: regression-003 full-chain シナリオ

test-scenario-catalog.md に regression-003 シナリオを追加しなければならない（SHALL）。このシナリオは DeltaSpec を伴う medium complexity Issue を使い、autopilot の full-chain 遷移（setup → test-ready → pr-verify → pr-merge）をすべて通すことを目的とする。

#### Scenario: regression-003 フォーマット準拠

- **WHEN** test-scenario-catalog.md を参照する
- **THEN** regression-003 エントリが存在し、level=regression、issues_count=1、complexity=medium、expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている

#### Scenario: regression-003 issue_template

- **WHEN** regression-003 の issue_templates を展開する
- **THEN** DeltaSpec を要求する Issue body が含まれており、setup → test-ready → pr-verify → pr-merge の全遷移を誘発できる

### Requirement: regression-004 Bug #436 再現シナリオ

test-scenario-catalog.md に regression-004 シナリオを追加しなければならない（SHALL）。このシナリオは `twl spec new` が `.deltaspec.yaml` に `issue:` フィールドを生成しない Bug #436 を再現するための条件を issue_templates に含む。

#### Scenario: regression-004 フォーマット準拠

- **WHEN** test-scenario-catalog.md を参照する
- **THEN** regression-004 エントリが存在し、level=regression、issues_count=1、expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている

#### Scenario: regression-004 Bug 再現条件

- **WHEN** regression-004 の issue_templates を展開する
- **THEN** Issue body に DeltaSpec（twl spec new）を使う指示が含まれており、orchestrator の `issue:` フィールド grep が 0 件ヒットして archive 失敗を誘発できる条件が記述されている

### Requirement: regression-005 Bug #438 再現シナリオ

test-scenario-catalog.md に regression-005 シナリオを追加しなければならない（SHALL）。このシナリオは orchestrator polling loop が Bash timeout（120 秒）で停止し `inject_next_workflow()` が呼ばれなくなる Bug #438 を再現するための条件を issue_templates に含む。

#### Scenario: regression-005 フォーマット準拠

- **WHEN** test-scenario-catalog.md を参照する
- **THEN** regression-005 エントリが存在し、level=regression、issues_count=1、expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている

#### Scenario: regression-005 Bug 再現条件

- **WHEN** regression-005 の issue_templates を展開する
- **THEN** Issue body に長時間実行（120 秒超）を要する処理を含む指示が記述されており、Orchestrator polling loop の timeout を誘発できる条件が明示されている

### Requirement: regression-006 Bug #439 再現シナリオ

test-scenario-catalog.md に regression-006 シナリオを追加しなければならない（SHALL）。このシナリオは merge-gate が `phase-review.json` の存在を検査しないため review なしでマージ PASS してしまう Bug #439 を再現するための条件を issue_templates に含む。

#### Scenario: regression-006 フォーマット準拠

- **WHEN** test-scenario-catalog.md を参照する
- **THEN** regression-006 エントリが存在し、level=regression、issues_count=1、expected_duration_min/max・expected_conflicts・expected_pr_count が記載されている

#### Scenario: regression-006 Bug 再現条件

- **WHEN** regression-006 の issue_templates を展開する
- **THEN** Issue body に pr-verify の review フェーズをスキップさせる条件が含まれており、`phase-review.json` が生成されないまま merge-gate に到達できる状況が記述されている
