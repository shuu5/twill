## ADDED Requirements

### Requirement: setup chain 定義

deps.yaml の chains セクションに setup chain を定義しなければならない（SHALL）。chain は type A（workflow + atomic）とし、steps にワークフローの全参加コンポーネントを順序付きで列挙する（MUST）。

#### Scenario: chains セクションが存在する
- **WHEN** deps.yaml を確認する
- **THEN** `chains:` セクションに `setup:` エントリが存在し、`type: "A"` と `description` が設定されている

#### Scenario: steps が正しい順序で定義されている
- **WHEN** setup chain の steps を確認する
- **THEN** init → worktree-create → project-board-status-update → crg-auto-build → opsx-propose → ac-extract → workflow-test-ready の順序で列挙されている

#### Scenario: loom chain validate が pass する
- **WHEN** `loom chain validate` を実行する
- **THEN** setup chain に関する CRITICAL エラーが 0 件である

### Requirement: chain 参加コンポーネントの双方向参照

setup chain に参加する各コンポーネントは、deps.yaml で `chain` フィールドと `step_in` フィールドを持たなければならない（SHALL）。親コンポーネント（workflow-setup）は `calls` フィールドで各ステップを参照する（MUST）。

#### Scenario: コンポーネント側の chain フィールド
- **WHEN** init, worktree-create, project-board-status-update, crg-auto-build, opsx-propose, ac-extract, workflow-test-ready の deps.yaml エントリを確認する
- **THEN** 全コンポーネントに `chain: "setup"` が設定されている

#### Scenario: step_in の双方向整合性
- **WHEN** workflow-setup の `calls` と各コンポーネントの `step_in` を確認する
- **THEN** `calls[i].step` と対応コンポーネントの `step_in.step` が一致する

#### Scenario: loom check での双方向検証
- **WHEN** `loom check` を実行する
- **THEN** `[chain-bidir]` および `[step-bidir]` エラーが 0 件である
