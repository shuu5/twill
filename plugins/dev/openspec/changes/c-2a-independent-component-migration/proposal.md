## Why

loom-plugin-dev は B-1〜B-7 + C-1 で基盤構造（chain-driven, autopilot-first, specialist few-shot, controller 4本）を構築済み。しかし既存 dev plugin（claude-plugin-dev）に存在する独立系コンポーネント48個がまだ移植されておらず、co-issue / co-project / co-architect / co-autopilot が実際にこれらを spawn できない状態。

## What Changes

- 既存 dev plugin から48個のコンポーネントを loom-plugin-dev の deps.yaml v3.0 構造に移植
- section 誤配置を修正（explore/propose/apply/archive は現行 skills/ → 正しくは commands/）
- 各コンポーネントのプロンプトファイル（COMMAND.md / SKILL.md）を新プラグイン構造に配置
- deps.yaml に全48コンポーネントを定義（type, path, spawnable_by, can_spawn, description）
- body 内参照（他コンポーネント呼び出し）を新プラグインの命名規則に合致させる

## Capabilities

### New Capabilities

- **Issue管理**: issue-dig, issue-structure, issue-create, issue-bulk-create, issue-tech-debt-absorb, project-board-sync, issue-assess（7個）
- **Project管理**: project-create, project-governance, project-migrate, container-dependency-check, setup-crg, snapshot-analyze, snapshot-classify, snapshot-generate（8個）
- **Architect**: architect-completeness-check, architect-decompose, architect-group-refine, architect-issue-create, evaluate-architecture（5個）
- **Plugin管理**: plugin-interview, plugin-research, plugin-design, plugin-generate, plugin-migrate-analyze, plugin-diagnose, plugin-fix, plugin-verify, plugin-phase-diagnose, plugin-phase-verify（10個）
- **OpenSpec/汎用**: explore, propose, apply, archive, check（5個、opsx-propose は既存）
- **Dead Component/Triage**: dead-component-detect, dead-component-execute, triage-execute, workflow-dead-cleanup, workflow-tech-debt-triage（5個）
- **Self-improve/ECC**: self-improve-collect, self-improve-propose, self-improve-close, ecc-monitor（4個）
- **その他**: loom-validate（1個、project-board-status-update は既存）

### Modified Capabilities

- deps.yaml: 48コンポーネントの定義追加
- skills/: workflow-dead-cleanup, workflow-tech-debt-triage を SKILL.md として追加
- commands/: 残り全コンポーネントを COMMAND.md として追加

## Impact

- **deps.yaml**: 大幅拡張（commands セクションに ~43 エントリ、skills セクションに ~3 エントリ追加）
- **プロンプトファイル**: 48個の COMMAND.md / SKILL.md 新規作成
- **既存コンポーネント影響なし**: 既存の chain, controller, workflow, script は変更しない
- **loom validate**: 全コンポーネント登録後に PASS が必要
