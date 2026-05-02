---
name: twl:ref-architecture-spec
description: |
  Architecture Spec ディレクトリ構造仕様。
  プロジェクトレベルの設計意図を構造化するための各ファイルの役割・フォーマット・テンプレートを定義。
type: reference
disable-model-invocation: true
---

# Architecture Spec 仕様

プロジェクトレベルの設計意図（前方参照）を管理するディレクトリ構造。

## Project Type

プロジェクトの種別（`type`）に応じて、必須ファイルと Severity が異なる。`architect-completeness-check` は `--type` 引数または type 解決ロジック（`.architecture-type` ファイル → `vision.md` frontmatter → デフォルト `ddd`）で type を決定し、対応する Severity 列を動的に参照する（テーブル駆動）。

有効な type 値: `ddd` | `generic` | `lib`（`lib` は将来実装予定、定義のみ）

| type | 説明 |
|------|------|
| `ddd` | Domain-Driven Design。Bounded Context / ユビキタス言語を中心に設計（デフォルト） |
| `generic` | 汎用プロジェクト。`vision.md` + `phases/*.md` 中心の軽量設計フロー |
| `lib` | ライブラリ。将来実装予定（TBD）、現時点では未実装・予約済み |

## ディレクトリ構造

```
architecture/
├── vision.md              # プロジェクトビジョン・制約・非目標
├── domain/
│   ├── model.md           # コアドメインモデル
│   ├── glossary.md        # ユビキタス言語
│   └── contexts/          # Bounded Context 定義（1ファイル/Context）
├── decisions/             # ADR（Architecture Decision Records）
├── contracts/             # Context 間 API 境界定義
└── phases/                # Phase 計画 + スコープ定義 + 実装状態テーブル
```

## 必須ファイル

アーキテクチャ完全性チェックで検証される必須ファイル。`Severity` 列は type 別に定義し、不在時の報告レベルを決定する（`WARNING` または `RECOMMENDED`）。`RECOMMENDED` 不在は `INFO` レベルで報告する（`WARNING` より低い）。テーブル変更のみで `Severity` 値を切替可能な設計とする（テーブル駆動）。

| ファイル | 必須 | Severity (DDD) | Severity (Generic) | 説明 |
|---------|------|----------------|--------------------|------|
| vision.md | YES | WARNING | WARNING | プロジェクトの目的・制約・非目標 |
| domain/model.md | YES | WARNING | RECOMMENDED | コアドメインモデル（generic では任意） |
| domain/glossary.md | YES | WARNING | RECOMMENDED | ユビキタス言語定義（generic では任意） |
| domain/contexts/*.md | 1つ以上 | WARNING | RECOMMENDED | Bounded Context 定義（generic では任意） |
| phases/*.md | 1つ以上 | WARNING | WARNING | Phase 計画 |
| decisions/*.md | NO | RECOMMENDED | RECOMMENDED | ADR（任意） |
| contracts/*.md | NO | RECOMMENDED | RECOMMENDED | API 境界（任意） |

## ファイルフォーマット

### vision.md

```markdown
## Vision

<!-- プロジェクトの目的・提供する価値 -->

## Constraints

<!-- 技術的・ビジネス上の制約 -->

## Non-Goals

<!-- 明示的に含まないもの -->
```

### domain/model.md

```markdown
## Core Domain Model

<!-- エンティティ、値オブジェクト、集約の定義 -->
<!-- Mermaid classdiagram 推奨 -->
```

### domain/glossary.md

```markdown
## Glossary

| 用語 | 定義 | Context |
|------|------|---------|
| <!-- 用語 --> | <!-- 定義 --> | <!-- 所属 Context --> |
```

### domain/contexts/<context-name>.md

ファイル名: kebab-case（例: `user-auth.md`, `payment.md`）

```markdown
# <Context 名>

## Responsibility

<!-- この Context が担う責務 -->

## Key Entities

<!-- 主要エンティティのリスト -->

## Dependencies

<!-- 他 Context への依存 -->
- <context-name> (upstream|downstream): <依存の説明>
```

### decisions/<NNNN>-<title>.md

```markdown
## Status

<!-- proposed | accepted | deprecated | superseded -->

## Context

<!-- この決定が必要になった背景 -->

## Decision

<!-- 採用した決定内容 -->

## Consequences

<!-- この決定がもたらす結果（良い面・悪い面） -->
```

### contracts/<contract-name>.md

```markdown
## Participants

<!-- 関与する Context -->
- Provider: <context-name>
- Consumer: <context-name>

## Interface

<!-- API 境界の定義（エンドポイント、イベント、共有カーネル等） -->

## Constraints

<!-- この契約の制約条件 -->
```

### phases/<phase-number>.md

ファイル名: `01.md`, `02.md` 等（連番）

```markdown
## Scope

<!-- この Phase で達成すること -->

## Issues

| # | タイトル | スコープ (Context) | 依存 Issue |
|---|---------|-------------------|-----------|
| - | <!-- タイトル --> | <!-- 関連 Context --> | <!-- 依存する Issue --> |

## Implementation Status

| Issue | PR | Status |
|-------|-----|--------|
| - | - | planned |
```

Status 値: `planned` | `in-progress` | `done`
