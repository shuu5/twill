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

## ディレクトリ構造

```
architecture/
├── vision.md              # プロジェクトビジョン・制約・非目標
├── domain/
│   ├── model.md           # コアドメインモデル
│   ├── glossary.md        # ユビキタス言語
│   └── contexts/          # Bounded Context 定義（1ファイル/Context）
├── decisions/             # ADR（Architecture Decision Records）
├── contracts/             # Context 間 API 境界定義（同一リポジトリ内の静的型制約）
├── protocols/             # クロスリポジトリ知識転送プロトコル（SHA ピン必須）
└── phases/                # Phase 計画 + スコープ定義 + 実装状態テーブル
```

## Project Type

`architect-completeness-check` の `--type` パラメータで指定するプロジェクト分類。**デフォルトは `ddd`**（後方互換）。

| type | 説明 |
|------|------|
| `ddd` | DDD-first 設計（Bounded Context / ユビキタス言語）。`domain/` 必須。**ddd がデフォルト**（--type 未指定時）。 |
| `generic` | 汎用プロジェクト設計。`vision.md` + `phases/*.md` 中心。`domain/` は optional（不在でも WARNING にならない）。 |
| `lib` | 予約済み（lib type は将来実装予定。reserved, not impl yet）。定義のみ。 |

**型検証（許容 type 値域）**: `ddd`, `generic`（`lib` は予約済み）。未知の type（例: `--type=foo`）は `architect-completeness-check` が invalid type エラーで停止する。

### contracts/ と protocols/ の棲み分け

| | contracts/ | protocols/ |
|--|------------|------------|
| 対象 | 同一リポジトリ内 Context 間 | クロスリポジトリ依存 |
| 参照形式 | ファイルパス・型定義 | **40-char commit SHA**（tag/branch 禁止） |
| 変更頻度 | コード変更と同期 | 明示的な migration で変更 |
| drift 検出 | コンパイラ・型チェッカー | `Drift Detection` セクションの運用手順 |

## 必須ファイル

アーキテクチャ完全性チェックで検証される必須ファイル。`Severity` 列は不在時の報告レベルを定義する（`WARNING` または `RECOMMENDED`）。`RECOMMENDED` 不在は `INFO` レベルで報告する（`WARNING` より低い）。テーブル変更のみで `Severity` 値を切替可能な設計とする（テーブル駆動）。

### Project Type 別必須テーブル

`architect-completeness-check` が `--type` に応じて参照する type 別 Severity テーブル（ADR-032 テーブル駆動拡張）。`Severity` 列はデフォルト（ddd）の値。`DDD` 列・`Generic` 列は type 別オーバーライド値。

| ファイル | 必須 | Severity | DDD | Generic | 説明 |
|---------|------|----------|-----|---------|------|
| vision.md | YES | WARNING | WARNING | WARNING | プロジェクトの目的・制約・非目標 |
| domain/model.md | YES(DDD) | WARNING | WARNING | - | コアドメインモデル（generic type では optional / INFO 降格） |
| domain/glossary.md | YES(DDD) | WARNING | WARNING | - | ユビキタス言語定義（generic type では optional / INFO 降格） |
| domain/contexts/*.md | 1つ以上(DDD) | WARNING | WARNING | - | Bounded Context 定義（generic type では optional / INFO 降格） |
| phases/*.md | 1つ以上 | WARNING | WARNING | WARNING | Phase 計画 |
| decisions/*.md | NO | RECOMMENDED | RECOMMENDED | RECOMMENDED | ADR（任意） |
| contracts/*.md | NO | RECOMMENDED | RECOMMENDED | RECOMMENDED | API 境界（任意） |
| protocols/*.md | NO | RECOMMENDED | RECOMMENDED | RECOMMENDED | クロスリポジトリ知識転送プロトコル（任意） |

**DDD** type の domain/* ファイル（domain/model.md, domain/glossary.md, domain/contexts/*.md）は Severity=WARNING で YES 必須。

**Generic** type では domain/ ディレクトリは optional（不在時に INFO 降格、WARNING にならない）。

## skip リスト

`architect-completeness-check` の `skip:` パラメータに渡すことで、
必須ファイルの FAIL/WARNING 判定を INFO に降格（demote）できる。

**用途**: `co-explore` の explore-summary `## Recommended Structure` の `skip:` フィールドから
自動的に渡される。DDD 不要なプロジェクトで `domain/model.md` 等をスキップしたい場合に使用。

```
# 例: Recommended Structure → architect-completeness-check 連携
skip: [domain/model.md, domain/glossary.md, domain/contexts/]
→ これらのパスが不在でも [INFO] で報告し、[FAIL] / [WARNING] には昇格しない
```

**skip リスト適用ルール**:
- skip リスト内のパスは完全性チェックで `[INFO]` として降格報告される（FAIL → INFO 降格）
- skip リストに含まれないパスは通常の Severity テーブルに従い判定される
- skip リストは HUMAN GATE でユーザーが承認した場合にのみ有効となる（ADR-030 準拠）

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

### protocols/<protocol-name>.md

ファイル名: kebab-case（例: `cli-integration.md`, `plugin-api.md`）

**必須セクション（5つ）:**

```markdown
## Participants

<!-- 関与するリポジトリ・システム -->
- Provider: <repo-name>
- Consumer: <repo-name>

## Pinned Reference

<!-- クロスリポジトリ参照の固定点 -->
<!-- MUST: 40-char commit SHA のみ使用（tag/branch 禁止 — drift リスク） -->
<!-- 禁止例: main, v1.0.0, HEAD -->
<!-- 正しい例: a3f8c2d1e4b5f6a7b8c9d0e1f2a3b4c5d6e7f8a9 -->

repo: <repo-name>
sha: <40-char commit SHA>  # ^[a-f0-9]{40}$ で検証

## Interface Contract

<!-- このプロトコルで共有するインターフェース定義 -->
<!-- エンドポイント、イベント、スキーマ等 -->

## Drift Detection

<!-- SHA ピンのドリフト検出方法 -->
<!-- 運用例: -->
<!-- - cron: 定期的に sha と現在の main を比較 -->
<!-- - GitHub Actions: PR で sha を検証する CI ステップ -->
<!-- - 手動レビュー: ADR レビュー時に sha を確認 -->

## Migration Path

<!-- SHA ピンを更新する手順 -->
<!-- 1. Provider 側で変更を commit する -->
<!-- 2. 新しい SHA を本ファイルの Pinned Reference セクションに記録する -->
<!-- 3. Consumer 側で差分を確認し、Interface Contract を更新する -->
```

**tag/branch 参照の禁止理由**: tag/branch は可変参照であり、後から指し示す commit が変わる（drift）可能性がある。
`Pinned Reference` セクションには 40-char commit SHA のみ使用すること。

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
