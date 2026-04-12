## MODIFIED Requirements

### Requirement: Phase 4 (CO_ISSUE_V2=1) で全 report.json を aggregate して提示する

CO_ISSUE_V2=1 の場合、Phase 4 は全 `per-issue/*/OUT/report.json` を Read し、done / warned / failed / circuit_broken に分類してユーザーに summary table を提示しなければならない（SHALL）。

#### Scenario: 全成功時に summary table が表示される

- **WHEN** CO_ISSUE_V2=1 で全 issue が done の状態で Phase 4 が実行される
- **THEN** done=N / warned=0 / failed=0 / circuit_broken=0 の summary table が表示される

#### Scenario: 一部失敗時に対話が起動する

- **WHEN** CO_ISSUE_V2=1 で一部 issue が failed の状態で Phase 4 が実行される
- **THEN** summary table 提示後に `[retry subset | manual fix | accept partial]` で AskUserQuestion が呼ばれる

### Requirement: retry 選択時に orchestrator の resume を呼び出す

CO_ISSUE_V2=1 かつ failure 時にユーザーが `retry` を選択した場合、`scripts/issue-lifecycle-orchestrator.sh --per-issue-dir ... --resume` を呼び出し、`STATE != done` の issue のみを再実行しなければならない（SHALL）。

#### Scenario: retry で非 done issue のみが再実行される

- **WHEN** ユーザーが `retry subset` を選択する
- **THEN** `issue-lifecycle-orchestrator.sh --resume` が呼ばれ、done 済みの issue はスキップされる

### Requirement: deps.yaml の co-issue controller に workflow-issue-lifecycle を追加する

`deps.yaml` の co-issue controller の `calls` フィールドに `workflow-issue-lifecycle` を追加し、`twl check` を PASS しなければならない（SHALL）。

#### Scenario: twl check が PASS する

- **WHEN** deps.yaml を更新して `twl check` を実行する
- **THEN** エラーなしで PASS する
