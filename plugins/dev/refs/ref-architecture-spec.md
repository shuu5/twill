---
name: dev:ref-architecture-spec
description: |
  Architecture Spec ディレクトリ構造仕様。
  プロジェクトレベルの設計意図を構造化するための各ファイルの役割・フォーマット・テンプレートを定義。
type: reference
disable-model-invocation: true
---

# Architecture Spec 仕様

プロジェクトレベルの設計意図（前方参照）を管理するディレクトリ構造。OpenSpec（後方参照）とは独立した概念。

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

アーキテクチャ完全性チェックで検証される必須ファイル:

| ファイル | 必須 | 説明 |
|---------|------|------|
| vision.md | YES | プロジェクトの目的・制約・非目標 |
| domain/model.md | YES | コアドメインモデル |
| domain/glossary.md | YES | ユビキタス言語定義 |
| domain/contexts/*.md | 1つ以上 | Bounded Context 定義 |
| phases/*.md | 1つ以上 | Phase 計画 |
| decisions/*.md | NO | ADR（任意） |
| contracts/*.md | NO | API 境界（任意） |

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
## Name

<!-- Context 名 -->

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

## OpenSpec との関係

| 側面 | Architecture Spec | OpenSpec |
|------|------------------|---------|
| 方向 | 前方参照（設計意図） | 後方参照（実装仕様） |
| 粒度 | プロジェクトレベル | 変更レベル |
| 独立性 | OpenSpec から独立 | Architecture Spec から独立 |
| 相互参照 | OpenSpec change の「根拠」として参照可能 | Architecture Spec の Context を参照可能 |
