## Why

ADR-008（Worktree Lifecycle Pilot Ownership）で Worker の起動スタイルが「worktree ディレクトリで起動」「Pilot が worktree を事前作成」に変更済みだが、openspec の複数仕様ファイルが旧スタイルのまま残存しており、実装と仕様の乖離が生じている。

## What Changes

- `openspec/specs/autopilot-lifecycle.md`: worktree 作成主体を Worker → Pilot に修正
- `openspec/changes/cross-repo-autopilot/` 配下（design.md, proposal.md, specs/worker-launch/spec.md, 01.5-ac-checklist.md）: Worker 起動場所を「main worktree」→「Pilot が作成した worktree ディレクトリ」に修正
- `openspec/changes/b-3-autopilot-state-management/test-mapping.yaml` L523: Worker は worktree を作成するという記述を ADR-008 準拠に修正
- `openspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/hooks-and-rules.md` L38-40: Pilot/Worker を区別するシナリオ記述に修正

## Capabilities

### Modified Capabilities

- openspec の Worker 起動仕様: ADR-008 準拠の記述（Pilot が事前作成した worktree ディレクトリで起動）に統一
- openspec の worktree 作成主体: Worker → Pilot に修正

## Impact

- **変更ファイル**: 上記 7+ ファイル（openspec 内のみ）
- **影響範囲**: 実装コードへの影響なし（openspec ドキュメントのみ）
- **依存**: ADR-008（`architecture/decisions/ADR-008-worktree-lifecycle-pilot-ownership.md`）
- **検証**: `rg "Worker.*worktree を作成" openspec/` および `rg "main worktree で.*起動" openspec/` が 0 件になること
