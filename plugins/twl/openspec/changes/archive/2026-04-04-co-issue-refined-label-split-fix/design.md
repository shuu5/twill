## Context

co-issue の Phase 3c Step 5 で split 承認後に生成される新 Issue は specialist 再レビューを受けない（最大1ラウンド制約）。しかし Phase 4 の `REFINED_LABEL_OK` チェックは `--quick` フラグの有無しか見ておらず、split 生成 Issue に対しても `refined` ラベルを付与してしまう。

また `openspec/changes/co-issue-refined-label/design.md` の Decisions セクション「付与タイミング」では「recommended_labels に refined を追加して既存ロジックに乗せる」と記述されているが、実際の SKILL.md 実装は `REFINED_LABEL_OK` フラグ + 各作成経路（単一/複数/クロスリポ）への個別テキスト変更で対応しており、設計書と実装が乖離している。

## Goals / Non-Goals

**Goals:**

- split 承認後に生成された Issue を `is_split_generated` コンテキストフラグで識別する
- Phase 4 の `refined` ラベル付与を `is_split_generated` な Issue でスキップする
- split 後 Issue には親 Issue の `recommended_labels` を引き継ぐ
- `openspec/changes/co-issue-refined-label/design.md` の「付与タイミング」Decisions を実装パターンに合わせて更新する

**Non-Goals:**

- `refined` ラベル定義（"specialist review completed"）の変更
- 既存 Issue への遡及修正
- Phase 3b specialist レビューロジックの変更
- クロスリポ子 Issue（`cross_repo_split = true`）への refined 付与変更（既に specialist レビュー済み body から生成されるため妥当）

## Decisions

### `is_split_generated` フラグの実装方法

LLM コンテキスト内で管理する判断フラグ（`REFINED_LABEL_OK` と同じ扱い）。Phase 3c Step 5 の split 承認処理で生成された Issue candidate に `is_split_generated: true` を設定し、Phase 4 の `refined` 付与判定で `is_split_generated == true` なら `refined` を付与しない。

シェル変数ではなく LLM のコンテキスト内フラグとして管理する理由: split 承認からPhase 4 作成まで LLM コンテキストが連続しており、Issue candidate 単位でフラグを保持できるため。

### Phase 4 の `refined` 判定ロジック変更

既存の `REFINED_LABEL_OK=true` チェックに加え `is_split_generated != true` の条件を追加する。判定式:

```
refined を付与する = REFINED_LABEL_OK=true AND is_split_generated != true
```

3つの作成経路（単一 `/twl:issue-create`、複数 `/twl:issue-bulk-create`、クロスリポ Step 4-CR）すべてに同じ条件を適用する。

### split 後 Issue の `recommended_labels` 引き継ぎ

split 生成 Issue は親 Issue の `recommended_labels`（ctx/* 等）を引き継ぐ。specialist レビューは未実施だがコンテキスト分類は変わらないため。`refined` のみスキップ対象。

### `openspec/changes/co-issue-refined-label/design.md` の更新方針

Decisions セクション「付与タイミング」を以下に差し替える:
- 「recommended_labels に refined を追加」の記述を削除
- `REFINED_LABEL_OK` フラグ + 各経路個別対応のパターンを正確に記述

## Risks / Trade-offs

- split 後 Issue は specialist 未レビューだが `ctx/*` 等のラベルは付与される。これはコンテキスト分類と品質保証ラベルを分けるという意図的な設計選択
- `is_split_generated` フラグは LLM コンテキスト依存のため、コンテキスト枯渇時に失われる可能性がある（既存の `REFINED_LABEL_OK` と同じリスク）
