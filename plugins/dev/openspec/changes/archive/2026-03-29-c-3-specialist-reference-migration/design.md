## Context

loom-plugin-dev は chain-driven + autopilot-first アーキテクチャで旧 dev plugin を再構築中。phase-review / merge-gate が tech-stack-detect.sh の結果に基づき specialist を動的 spawn する設計だが、agents セクションが空のため PR サイクルが機能しない。

旧プラグインには 27 specialists（agents/）と 11 references（refs/ + refs/baseline/）が存在し、プロンプト内容はほぼそのまま移植可能。ただし出力形式の統一と model 宣言の追加が必要。

## Goals / Non-Goals

**Goals:**

- 27 specialists を agents/ に移植し deps.yaml agents セクションに登録
- 11 references を refs/ に移植し deps.yaml refs セクションに登録
- 全 specialist の出力を ADR-004 共通出力スキーマに適合させる
- severity を CRITICAL/WARNING/INFO に統一（旧 High/Medium/Suggestion を変換）
- model 宣言を設計判断 #11 に従い割り当て
- loom sync-docs 対象 4 ファイルの同期マーカー付与

**Non-Goals:**

- specialist のレビューロジック自体の改善（移植のみ）
- 新規 specialist の追加
- specialist の統合・分割
- テストの作成（別 Issue で対応）

## Decisions

### D-1: specialist ファイル構造

旧フォーマットを踏襲しつつ、以下を必須化:

```yaml
---
name: dev:<specialist-name>
description: "<1行説明>（specialist）"
type: specialist
model: haiku | sonnet  # D-2 で決定
effort: low | medium
maxTurns: 15 | 20
tools: [Read, Grep, Glob]  # specialist ごとに異なる
---
```

本文末尾に共通出力スキーマ準拠セクションを追加:

```markdown
## 出力形式（MUST）

ref-specialist-output-schema に従い、以下の JSON 構造で出力すること:
...
```

### D-2: model 割り当て基準

| カテゴリ | model | 根拠 |
|----------|-------|------|
| 構造チェック系（machine-verifiable） | haiku | パターンマッチ・ルール照合が主 |
| 品質判断系（requires-judgment） | sonnet | コード品質・セキュリティ・設計判断 |

具体的な割り当て:

**haiku**: worker-structure, worker-principles, worker-env-validator, worker-rls-reviewer, worker-supabase-migration-checker, worker-data-validator, template-validator, context-checker, worker-e2e-reviewer, worker-spec-reviewer

**sonnet**: worker-code-reviewer, worker-security-reviewer, worker-nextjs-reviewer, worker-fastapi-reviewer, worker-hono-reviewer, worker-r-reviewer, worker-llm-output-reviewer, worker-llm-eval-runner, worker-architecture, docs-researcher, pr-test, e2e-quality, autofix-loop, spec-scaffold-tests, e2e-generate, e2e-heal, e2e-visual-heal

### D-3: reference 分類と配置

| 分類 | ファイル | 同期マーカー |
|------|---------|-------------|
| loom sync 対象 (4) | ref-types, ref-practices, ref-deps-format, ref-architecture | `<!-- Synced from loom docs/ — do not edit directly -->` |
| プラグイン固有 (4) | ref-architecture-spec, ref-project-model, ref-dci, self-improve-format | なし |
| baseline (3) | baseline-coding-style, baseline-security-checklist, baseline-input-validation | なし |

baseline は `refs/baseline/` サブディレクトリではなく `refs/baseline-*.md` としてフラット配置（deps.yaml の path 規約に準拠）。

### D-4: deps.yaml 登録規約

```yaml
agents:
  worker-code-reviewer:
    type: specialist
    path: agents/worker-code-reviewer.md
    model: sonnet
    spawnable_by: [workflow, composite, controller]
    can_spawn: []
    description: "コード品質レビュー"
```

- `spawnable_by` は ref-types の specialist 行に従う
- `can_spawn` は常に空配列
- `model` フィールドを必ず宣言

### D-5: severity マッピング

| 旧表記 | 新表記 |
|--------|--------|
| High / Critical / Error | CRITICAL |
| Medium / Warning | WARNING |
| Low / Suggestion / Info | INFO |

## Risks / Trade-offs

- **リスク: 27 ファイルの一括移植で差分が大きい** → タスクを specialist カテゴリ別に分割し、段階的にコミット
- **リスク: loom sync 対象ファイルが loom リポジトリと乖離** → 移植時に loom の最新 docs/ から内容を取得
- **トレードオフ: baseline をフラット化** → サブディレクトリ構造のほうが直感的だが、deps.yaml の path 規約と loom validate の整合性を優先
