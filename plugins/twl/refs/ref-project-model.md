---
name: twl:ref-project-model
description: |
  Issue 管理データモデル。5軸ラベル体系（What/Where/Maturity/When/Progress）、
  ctx/* 導出ルール、Producer/Consumer 表を定義。
type: reference
disable-model-invocation: true
---

# Issue 管理データモデル

## 概要

Issue のメタデータを5軸で管理する。各軸は GitHub の異なる機能にマッピングされる。

| 軸 | 表現 | 用途 |
|----|------|------|
| What（タイプ+起源） | ラベル | 要望の種類を分類 |
| Where（領域） | ラベル（ctx/*） | 変更対象の Bounded Context を特定 |
| Maturity（成熟度） | ラベル（arch/*） | Issue の設計精緻化段階を追跡 |
| When（Phase） | Milestone | 実装時期を管理 |
| Progress（進捗） | Project Board | 作業状態を可視化 |

---

## 1. What 軸 — タイプラベル

### ラベル判定テーブル

| 要望の種類 | ラベル |
|-----------|--------|
| 新機能、改善 | `enhancement` |
| バグ修正 | `bug` |
| ドキュメント | `documentation` |
| tech-debt（Warning由来） | `tech-debt/warning` |
| tech-debt（High/Critical由来） | `tech-debt/deferred-high` |
| リファクタリング | `refactor` |
| 不明 | ユーザーに確認 |

### tech-debt ラベル運用ルール

- **`tech-debt/warning`**: lint 警告、非推奨 API 使用、軽微なコード品質問題など Warning レベルの技術的負債
- **`tech-debt/deferred-high`**: セキュリティ懸念、パフォーマンス問題、アーキテクチャ課題など High/Critical レベルだが即時対応を見送った技術的負債
- tech-debt 性質の Issue 作成時、上記いずれかのラベルを付与する
- 既存の `enhancement` / `bug` ラベルとの併用可

---

## 2. Where 軸 — ctx/* ラベル

### 適用条件

architecture/ ディレクトリを持つプロジェクトでのみ使用する。architecture/ がないプロジェクトでは What 軸のみで管理する。

### 導出ルール

| architecture/ パス | ctx/ ラベル | 種別 |
|-------------------|------------|------|
| domain/contexts/\<name\>.md | ctx/\<name\> | Bounded Context |
| contracts/\<name\>.md | ctx/\<name\> | Cross-cutting |
| domain/model.md 内 Shared Kernel セクション | ctx/shared-kernel | Cross-cutting |

### description 規約

ラベルの description は以下の形式に統一する:

```
Context: <Name> (<type>)
```

type は以下のいずれか:
- **Core**: ビジネスの差別化要因となるドメイン
- **Supporting**: Core を支えるが差別化要因ではないドメイン
- **Generic**: 汎用的なドメイン（認証、通知等）
- **Cross-cutting**: 横断的関心事（contracts/, Shared Kernel）

---

## 3. Maturity 軸 — arch/* ラベル

Issue の設計精緻化段階を示す。controller-architect ワークフローで使用。

| ラベル | 意味 | 遷移条件 |
|--------|------|----------|
| `arch/skeleton` | 初期スケルトン。タイトルと概要のみ | Issue 作成時（architect-decompose） |
| `arch/refined` | explore 済み。AC・技術詳細が確定 | architect-group-refine 完了時 |

---

## 4. When 軸 — Milestone

Milestone で実装時期（Phase）を管理する。

| 運用ルール | 説明 |
|-----------|------|
| Milestone 名 | `Phase N: <目的>` 形式（例: `Phase 1: 基盤構築`） |
| 割り当て | architect-decompose で Issue 作成時に Phase を Milestone として設定 |
| クローズ条件 | Phase 内の全 Issue が Done になった時点 |

---

## 5. Progress 軸 — Project Board

Project Board のカラムで作業進捗を管理する。

| カラム | 意味 |
|--------|------|
| Todo | 未着手 |
| In Progress | 作業中（worktree/ブランチ作成済み） |
| Done | 完了（PR マージ済み） |

---

## Producer/Consumer 表

各軸のメタデータを作成・参照するコンポーネントを明示する。

### What 軸ラベル

| 操作 | コンポーネント | 説明 |
|------|---------------|------|
| Producer | controller-issue / issue-create | Issue 作成時にラベルを判定・付与 |
| Consumer | branch-create.sh | ラベルからブランチプレフィックス（feat/fix/docs/refactor）を決定 |
| Consumer | controller-issue-triage | tech-debt ラベルで棚卸し対象をフィルタ |

### Where 軸ラベル（ctx/*）

| 操作 | コンポーネント | 説明 |
|------|---------------|------|
| Producer | architect-decompose / architect-issue-create | architecture/ から導出し Issue に付与 |
| Consumer | architect-group-refine | ctx/* でグループ化し一括精緻化 |
| Consumer | controller-issue | Issue 構造化時に ctx/* を参照 |

### Maturity 軸ラベル（arch/*）

| 操作 | コンポーネント | 説明 |
|------|---------------|------|
| Producer | architect-decompose / architect-issue-create | arch/skeleton を付与 |
| Producer | architect-group-refine | arch/skeleton → arch/refined に更新 |
| Consumer | controller-autopilot | arch/refined の Issue のみを実装対象として選択 |

### When 軸（Milestone）

| 操作 | コンポーネント | 説明 |
|------|---------------|------|
| Producer | architect-decompose / architect-issue-create | Phase を Milestone として設定 |
| Consumer | controller-autopilot | Milestone（Phase）単位で実装順序を決定 |

### Progress 軸（Project Board）

| 操作 | コンポーネント | 説明 |
|------|---------------|------|
| Producer | workflow-setup | In Progress に移動 |
| Producer | workflow-pr-cycle | Done に移動（PR マージ後） |
| Consumer | controller-autopilot | Todo の Issue を次の実装対象として選択 |

---

## 廃止ラベル

以下のラベルは廃止し、新体系に移行する。

| 廃止ラベル | 移行先 | 理由 |
|-----------|--------|------|
| arch/group:* | ctx/\<name\> | Where 軸の ctx/* ラベルに統合 |
| arch/phase-* | Milestone | When 軸の Milestone に統合 |

既存 Issue で上記ラベルを使用している場合は、新ラベルへの付け替えを推奨する（遡及修正は任意）。
