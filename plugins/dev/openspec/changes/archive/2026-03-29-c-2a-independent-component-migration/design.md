## Context

loom-plugin-dev は deps.yaml v3.0 + chain-driven 構造で構築済み。既存 dev plugin（claude-plugin-dev `~/.claude/plugins/dev/`）から独立系コンポーネント48個を移植する。

移植元の構造:
- `skills/<name>/SKILL.md`（controller / workflow）
- `commands/<name>.md`（atomic / composite、フラットファイル）

移植先の構造（loom-plugin-dev）:
- `skills/<name>/SKILL.md`（controller / workflow）
- `commands/<name>.md`（atomic / composite、ディレクトリ構造）

既存で移植済みのコンポーネント（B-1〜B-7, C-1）:
- commands: init, worktree-create, worktree-list, project-board-status-update, crg-auto-build, opsx-propose, opsx-apply, opsx-archive, ac-extract, ts-preflight, scope-judge, pr-test, post-fix-verify, warning-fix, pr-cycle-report, all-pass-check, ac-verify, self-improve-review
- composites: phase-review, fix-phase, e2e-screening, merge-gate
- skills: co-autopilot, co-issue, co-project, co-architect, workflow-setup, workflow-test-ready, workflow-pr-cycle
- scripts: state-read, state-write, autopilot-init, session-create, session-archive, session-add-warning, worktree-delete, crash-detect, tech-stack-detect, specialist-output-parse

## Goals / Non-Goals

**Goals:**

- 48コンポーネント全てを deps.yaml v3.0 に定義し、COMMAND.md / SKILL.md を配置
- section 誤配置を修正（explore/propose/apply/archive → commands/）
- body 内の他コンポーネント参照を新命名規則に合致させる
- `loom validate` PASS

**Non-Goals:**

- コンポーネントのロジック改善やリファクタリング（移植のみ）
- chain への組み込み（B-4/B-5 の範囲）
- specialist / agent の移植（C-3 の範囲）
- autopilot 系コンポーネントの移植（C-2b #15 の範囲）

## Decisions

### D1: ディレクトリ構造

移植元はフラットファイル（`commands/name.md`）だが、loom-plugin-dev はディレクトリ構造（`commands/name.md`）を採用。全コンポーネントをディレクトリ構造に変換する。

### D2: section 分類ルール

| type | section | ファイル名 |
|------|---------|-----------|
| atomic | commands/ | COMMAND.md |
| composite | commands/ | COMMAND.md |
| workflow | skills/ | SKILL.md |
| controller | skills/ | SKILL.md |

explore, propose, apply, archive は既存 plugin では skills/ に配置されているが、type=atomic のため commands/ に配置する。

### D3: spawnable_by / can_spawn の決定方針

各コンポーネントの呼び出し関係を既存 plugin の deps.yaml + プロンプト内容から導出:
- controller から直接呼ばれる → `spawnable_by: [controller]`
- workflow から呼ばれる → `spawnable_by: [workflow]`
- 両方 → `spawnable_by: [controller, workflow]`
- 他コンポーネントを spawn する → `can_spawn` に記載

### D4: 移植単位

48コンポーネントを8グループに分け、グループ単位で deps.yaml 追加 + ファイル配置を行う:
1. Issue管理系（7個）
2. Project管理系（8個）
3. Architect系（5個）
4. Plugin管理系（10個）
5. OpenSpec/汎用系（5個）
6. Dead Component/Triage系（5個）
7. Self-improve/ECC系（4個）
8. その他（1個: loom-validate）

ただし workflow 3個（workflow-dead-cleanup, workflow-tech-debt-triage + controller-plugin からの分離分）は skills/ に配置。

### D5: body 内参照の変換ルール

| 旧形式 | 新形式 |
|--------|--------|
| `/dev:command-name` | `/dev:command-name`（変更なし） |
| Skill tool で `dev:old-name` | Skill tool で `dev:new-name` |
| `controller-*` 参照 | `co-*` 参照に変換 |

## Risks / Trade-offs

- **量が多い（48個）**: 機械的な移植だが、個々のプロンプト内容の body 参照更新漏れのリスク。`loom validate` で検出可能
- **既存 plugin との共存期間**: 移植中は両方のプラグインが存在する。命名衝突は loom-plugin-dev が別ディレクトリのため問題なし
- **controller-plugin の扱い**: 既存 plugin では独立 controller だが、loom-plugin-dev では co-project に統合予定（C-1 設計）。plugin 系 atomic は co-project の can_spawn に含める
