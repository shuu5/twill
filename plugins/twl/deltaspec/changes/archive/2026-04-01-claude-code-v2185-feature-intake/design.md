## Context

Claude Code v2.1.85+ で hook `if` 条件フィルタリングが導入され、v2.1.78 で `${CLAUDE_PLUGIN_DATA}` 永続ディレクトリ、v2.1.72+ でエージェント frontmatter に `effort`, `skills`, `isolation`, `tools` フィールドが追加された。

現状:
- hooks/hooks.json: 2 hook（PostToolUse Edit|Write, PostToolUseFailure Bash）。`if` 条件なし
- skills/ (9): effort フィールド未設定
- agents/ (28): 全て maxTurns 設定済み。skills フィールド未設定
- deps.yaml v3.0: effort/skills/isolation/tools フィールド未定義
- 環境: Claude Code v2.1.87（全機能利用可能）

## Goals / Non-Goals

**Goals:**

- hook `if` 条件で不要発火を抑止（PostToolUse を deps.yaml 変更時のみに絞るなど）
- Controller に effort 宣言（Claude Code のリソース配分最適化）
- specialist に skills フィールドで ref-* リファレンスを事前注入
- deps.yaml に新フィールドを反映し loom check PASS を維持
- Controller tools フィールドに Agent(type) スポーン制限を宣言

**Non-Goals:**

- `${CLAUDE_PLUGIN_DATA}` への .autopilot/ 移行（影響範囲大、別 Issue で対応）
- `isolation: "worktree"` の co-autopilot Worker 適用（Worker は独自 worktree 管理済み、二重化のリスク）
- agent model フィールド追加（既に全 28 agent に設定済み）
- maxTurns 追加（既に全 28 agent に設定済み）

## Decisions

### D1: hook `if` 条件のマッピング

| hook | matcher | if 条件 |
|------|---------|--------|
| PostToolUse | `Edit\|Write` | なし（全 Edit/Write に対して実行） |
| PostToolUseFailure | `Bash` | なし（全 Bash 失敗に対して実行） |

現在の 2 hook はいずれも汎用的な検証・記録用途で、特定ファイルへの絞り込みは不適切。ただし Issue のスコープでは `if` 条件追加が求められているため、plugin-deps-validator パターン（`Write(deps.yaml) || Edit(deps.yaml)` のような特定ファイル対象 hook）を追加する方向で対応。

既存の 2 hook は現状維持（全発火が正当）。新規 hook として deps.yaml 変更検知用の `if` 条件付き hook を追加検討。

### D2: Controller effort 値の決定

| Controller | effort | 根拠 |
|------------|--------|------|
| co-autopilot | high | 複数 Issue の実装オーケストレーション |
| co-issue | high | Issue 分解・精緻化・4 Phase 実行 |
| co-project | medium | プロジェクト管理（create/migrate/snapshot） |
| co-architect | high | 対話的アーキテクチャ構築 |
| workflow-setup | medium | chain-driven セットアップ（定型） |
| workflow-test-ready | medium | テスト準備（定型） |
| workflow-pr-cycle | medium | PR サイクル（定型） |
| workflow-dead-cleanup | low | 不要リソースクリーンアップ |
| workflow-tech-debt-triage | medium | 技術的負債トリアージ |

### D3: specialist skills フィールドのマッピング

specialist が body 内で参照している ref-* をそのまま skills フィールドに昇格。対象は specialist（type: specialist）のみ。

共通パターン:
- reviewer 系: `ref-specialist-output-schema`, `ref-specialist-few-shot`
- 構造検証系: `ref-practices`, `ref-types`

### D4: Controller tools フィールドの Agent スポーン制限

| Controller | tools (Agent制限) |
|------------|------------------|
| co-autopilot | `Agent(worker-*, e2e-*, autofix-loop, spec-scaffold-tests)` |
| co-issue | `Agent(issue-critic, issue-feasibility, context-checker, template-validator)` |
| co-architect | `Agent(worker-architecture, worker-structure)` |
| co-project | `Agent(worker-structure)` |

### D5: CLAUDE_PLUGIN_DATA は見送り

.autopilot/ の移行は影響範囲が大きく（scripts/state-read.sh, state-write.sh, co-autopilot の全状態管理）、本 Issue のスコープ外。別 Issue で段階的に対応。

### D6: isolation: worktree は見送り

co-autopilot は ADR-008 に従い Pilot が事前作成した worktree ディレクトリで Worker を起動する。Claude Code の `isolation: "worktree"` を併用すると二重 worktree になり、パスの不整合が発生するリスクがある。

## Risks / Trade-offs

- **effort 値の妥当性**: 実行時のリソース消費に影響。初回は保守的に設定し、運用後に調整
- **skills フィールド注入**: Claude Code が skills を正しく事前ロードするか実機確認が必要
- **loom check 互換性**: deps.yaml に新フィールドを追加した場合、loom CLI が unknown field としてエラーにならないか確認が必要
- **hook if 条件の構文**: `if` フィールドの正確な構文を Claude Code ドキュメントで確認する必要あり
