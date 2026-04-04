## ADDED Requirements

### Requirement: autopilot Phase 完了時は当該 Phase の Done アイテムのみをアーカイブしなければならない（SHALL）

`autopilot-orchestrator.sh` の Phase 完了処理は、`plan.yaml` の当該 Phase に含まれる Issue 番号の Done アイテムのみを `board-archive` でアーカイブしなければならない（SHALL）。他の Phase の Issue、手動追加 Issue、および Done でないアイテムはアーカイブ対象としてはならない（MUST NOT）。

#### Scenario: Phase 完了時の選択的 Archive

- **WHEN** `autopilot-orchestrator.sh` が特定 Phase の完了を処理する
- **THEN** 当該 Phase の plan.yaml に含まれる Issue 番号の Done アイテムのみが Archive に移行する

#### Scenario: 他 Phase の Issue は対象外

- **WHEN** `autopilot-orchestrator.sh` が Phase 完了を処理する
- **THEN** 他 Phase の Issue はアーカイブされない

## MODIFIED Requirements

### Requirement: board-archive コマンドは Phase 完了処理から呼び出せるよう維持しなければならない（SHALL）

`chain-runner.sh` の `board-archive` コマンドは削除せずに維持しなければならない（SHALL）。merge-gate-execute.sh からの呼び出しは削除されるが、autopilot Phase 完了処理からの呼び出し用途として残す。

#### Scenario: board-archive コマンドの利用可否

- **WHEN** `chain-runner.sh board-archive` が呼び出される
- **THEN** 指定 Issue を Archive に移行する（コマンド自体は動作する）
