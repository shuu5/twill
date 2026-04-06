## MODIFIED Requirements

### Requirement: merge 成功時は Done 遷移を経由しなければならない（SHALL）

`merge-gate-execute.sh` は merge 成功後に `chain-runner.sh board-archive` を呼んではならない（MUST NOT）。代わりに `chain-runner.sh board-status-update <issue> "Done"` を呼び出し、Done 遷移を行わなければならない（SHALL）。

#### Scenario: PR merge 成功後の Status 遷移

- **WHEN** `merge-gate-execute.sh` が PR merge 成功を検出する
- **THEN** 当該 Issue の Project Board Status が Done に更新される

#### Scenario: Done を経由せず Archive されない

- **WHEN** `merge-gate-execute.sh` が実行される
- **THEN** `board-archive` コマンドは呼び出されない
