## ADDED Requirements

### Requirement: Phase 3 (CO_ISSUE_V2=1) で Level-based dispatch を実行する

CO_ISSUE_V2=1 の場合、Phase 3 は level 順に `bash scripts/issue-lifecycle-dispatch.sh <sid> <level> --max-parallel 3` を呼び出し、`Bash(run_in_background=true)` で `scripts/issue-lifecycle-wait.sh <sid> <level> --timeout 3600` を起動しなければならない（SHALL）。最後に BashOutput で level_report を取得する。

#### Scenario: Level 0 が dispatch される

- **WHEN** CO_ISSUE_V2=1 で Phase 3 が L0 を処理する
- **THEN** `issue-lifecycle-dispatch.sh <sid> 0 --max-parallel 3` が実行され、`issue-lifecycle-wait.sh <sid> 0` が Bash-bg で起動される

#### Scenario: 全 level が順次 dispatch される

- **WHEN** DAG に L0, L1 の 2 level がある
- **THEN** L0 の wait 完了後に L1 が dispatch され、全 level 完了後に Phase 4 へ進む

### Requirement: Level 間で parent URL を注入する

CO_ISSUE_V2=1 の場合、Phase 3 は prev level の `OUT/report.json` から parent issue URL を読み出し、current level の各 `policies.json` の `parent_refs_resolved` に注入しなければならない（SHALL）。

#### Scenario: L1 に L0 の URL が注入される

- **WHEN** L0 の dispatch が完了して `OUT/report.json` に issue URL が含まれる
- **THEN** L1 の `policies.json.parent_refs_resolved` に L0 の issue URL が注入された状態で L1 が dispatch される

### Requirement: failure 検知で circuit_broken する

CO_ISSUE_V2=1 の場合、Phase 3 は failed issue が次 level の DAG 依存対象である場合に `circuit_broken` として break しなければならない（SHALL）。依存対象でない場合は warning のみ記録して継続する。

#### Scenario: 依存する issue が失敗したら break する

- **WHEN** L0 の issue A が失敗し、L1 の issue B が issue A に依存している
- **THEN** circuit_broken フラグが立ち、L1 以降の dispatch は実行されない

#### Scenario: 依存しない issue の失敗は継続する

- **WHEN** L0 の issue A が失敗し、L1 の全 issue が issue A に依存していない
- **THEN** warning を記録して L1 が dispatch される
