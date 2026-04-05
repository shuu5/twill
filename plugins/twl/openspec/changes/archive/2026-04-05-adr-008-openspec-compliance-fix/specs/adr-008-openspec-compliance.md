## MODIFIED Requirements

### Requirement: openspec の Worker 起動記述を ADR-008 に準拠させる

openspec 内の Worker 起動場所の記述は、ADR-008 の決定（Worker は Pilot が事前作成した worktree ディレクトリで起動する）に準拠しなければならない（SHALL）。

対象ファイル:
- `openspec/specs/autopilot-lifecycle.md`
- `openspec/changes/cross-repo-autopilot/specs/worker-launch/spec.md`
- `openspec/changes/cross-repo-autopilot/design.md`
- `openspec/changes/cross-repo-autopilot/01.5-ac-checklist.md`
- `openspec/changes/cross-repo-autopilot/proposal.md`

#### Scenario: Worker 起動場所の記述が ADR-008 準拠であること

- **WHEN** `rg "main worktree で.*起動" openspec/` を実行する
- **THEN** 0 件ヒットすること

### Requirement: openspec の worktree 作成主体を Pilot に修正する

openspec 内の worktree 作成主体の記述は、Pilot が worktree を作成するという ADR-008 の不変条件 B 拡張に準拠しなければならない（SHALL）。

対象ファイル:
- `openspec/specs/autopilot-lifecycle.md`
- `openspec/changes/b-3-autopilot-state-management/test-mapping.yaml`

#### Scenario: worktree 作成主体の記述が ADR-008 準拠であること

- **WHEN** `rg "Worker.*worktree を作成" openspec/` を実行する
- **THEN** 0 件ヒットすること

### Requirement: b-2 の hooks-and-rules シナリオを Pilot/Worker 区別記述に修正する

`openspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/hooks-and-rules.md` L38-40 の旧セッション起動ルールシナリオは、Pilot と Worker の役割を区別した ADR-008 準拠の記述に修正されなければならない（SHALL）。

#### Scenario: hooks-and-rules の Worker シナリオが ADR-008 準拠であること

- **WHEN** `cat openspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/hooks-and-rules.md` でシナリオを確認する
- **THEN** Worker 起動場所として「Pilot が作成した worktree ディレクトリ」または ADR-008 準拠の記述が含まれること
