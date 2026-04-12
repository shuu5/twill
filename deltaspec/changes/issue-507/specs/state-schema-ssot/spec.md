## MODIFIED Requirements

### Requirement: status フィールドが SSOT として機能しなければならない

autopilot の state file における進捗判定は `status` フィールドのみを参照することで完結しなければならない（SHALL）。Monitor や su-observer が `current_step` や `workflow_done` を組み合わせて判定する必要があってはならない。

#### Scenario: Monitor が単一フィールドで進捗判定できる
- **WHEN** Monitor が issue state file を読み込んだとき
- **THEN** `jq -r '.status'` 単一クエリで「進行中 / マージ可能 / 完了 / 失敗 / コンフリクト」が判定できる

#### Scenario: status=merge-ready 時に STAGNATE 警告が発生しない
- **WHEN** issue の `status` が `merge-ready` であるとき
- **THEN** Monitor は STAGNATE 警告を発してはならない（該当 issue は正常待機状態と判断する）

### Requirement: IssueState の全値が autopilot.md に明記されなければならない

`plugins/twl/architecture/domain/contexts/autopilot.md` の IssueState 表は `conflict` を含む全ての valid な status 値と遷移を明記しなければならない（SHALL）。

#### Scenario: 状態遷移グラフの完全性
- **WHEN** autopilot.md の IssueState 表を参照したとき
- **THEN** `running` / `merge-ready` / `done` / `failed` / `conflict` の5値と、それぞれの遷移先が明記されている

## REMOVED Requirements

### Requirement: workflow_done フィールドが廃止されなければならない

`workflow_done` フィールドは SSOT が不明確な原因の一つであったため廃止しなければならない（SHALL）。全ての writer/reader を削除または代替に変更する必要がある。

#### Scenario: workflow_done の writer が全て削除される
- **WHEN** `workflow-{setup,test-ready,pr-verify,pr-fix,pr-merge}/SKILL.md` を参照したとき
- **THEN** `workflow_done=<name>` を書き込む行が存在しない

#### Scenario: orchestrator が workflow_done を参照しない
- **WHEN** `autopilot-orchestrator.sh` が inject_next_workflow トリガーを判定するとき
- **THEN** `workflow_done` フィールドではなく `status` の terminal 値（例: `merge-ready`）を検知してトリガーする

#### Scenario: state.py の PILOT_ISSUE_ALLOWED_KEYS に workflow_done が含まれない
- **WHEN** Pilot が state file を更新しようとするとき
- **THEN** `workflow_done` は `_PILOT_ISSUE_ALLOWED_KEYS` に含まれておらず、書き込みが拒否される

## ADDED Requirements

### Requirement: ADR-016 が新規作成されなければならない

`plugins/twl/architecture/decisions/ADR-016-state-schema-ssot.md` を新規作成し、Option 1（status SSOT）採用の設計決定と根拠を記録しなければならない（SHALL）。

#### Scenario: ADR-016 が正典として参照できる
- **WHEN** `ADR-016-state-schema-ssot.md` を参照したとき
- **THEN** Option 1 採用の根拠、廃止フィールド一覧、代替トリガー機構の説明が含まれている

#### Scenario: ADR-003 から ADR-016 へのリンクが存在する
- **WHEN** `ADR-003-unified-state-file.md` を参照したとき
- **THEN** ADR-016 への参照リンクが存在する

### Requirement: inject_next_workflow が status ベースのトリガーで機能しなければならない

`autopilot-orchestrator.sh` の `inject_next_workflow` は `workflow_done` フィールドではなく `status` フィールドの terminal 値（`merge-ready`）遷移を検知してトリガーしなければならない（SHALL）。

#### Scenario: status=merge-ready で次 workflow が inject される
- **WHEN** issue の status が `running` から `merge-ready` に遷移したとき
- **THEN** orchestrator が次のワークフロー（例: pr-merge）を tmux inject する

#### Scenario: inject-next-workflow bats テストが更新済みで通過する
- **WHEN** `plugins/twl/tests/unit/inject-next-workflow/*.bats` を実行したとき
- **THEN** 全テストが PASS する（workflow_done ベースの旧テストは削除済みまたは更新済み）
