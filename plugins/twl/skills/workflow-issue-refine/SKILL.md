---
name: twl:workflow-issue-refine
description: |
  Per-Issue 精緻化ワークフロー（co-issue Phase 3 を分離）。
  issue-structure → issue-spec-review(並列) → issue-review-aggregate → issue-arch-drift。

  Use when user: says Issue精緻化/issue-refine,
  or when called from co-issue workflow.
type: workflow
effort: medium
spawnable_by:
- controller
can_spawn:
- composite
- atomic
---

# workflow-issue-refine

co-issue Phase 3（Per-Issue 精緻化ループ）のロジックを担当するワークフロー。

## Input

呼び出し元（co-issue）から以下を受け取る:

- **unstructured_issues**: Phase 2 で分解された Issue リスト（各 Issue の概要・scope）
- **ARCH_CONTEXT**: architecture ファイルから収集したコンテキスト（vision.md, context-map.md, glossary.md 等）
- **is_quick_candidate flags**: Phase 2 Step 2b で判定された quick 候補フラグ（Issue ごと）
- **cross_repo_split**: クロスリポ分割フラグ（true の場合、parent + 子 Issue 構造化ルールに従う）

## Step 3a: Issue 構造化

各 Issue に `/twl:issue-structure` を呼び出してテンプレート適用。

- 推奨ラベル抽出
- tech-debt 棚卸し（該当時は `/twl:issue-tech-debt-absorb` も呼び出す）
- クロスリポ分割時は parent + 子 Issue の構造化ルールに従う

## Step 3b: specialist レビュー（MUST -- spawn 粒度・同期バリア厳守）

`/twl:issue-spec-review` を **1 Issue につき 1 回** 呼び出す。複数 Issue をまとめて 1 回の呼び出しに渡してはならない（MUST NOT）。

- **spawn 数の公式**: N Issues -> N 回の `/twl:issue-spec-review` 呼び出し -> 各呼び出しが内部で 3 specialist を spawn -> 合計 3N specialist
- **具体例**: 5 Issues なら `/twl:issue-spec-review` を 5 回呼び出し、15 specialist が起動される。3 回の呼び出しで済ませてはならない
- **並列実行可**: N 回の Skill 呼び出しは並列で発行してよい
- **quick 候補もスキップ禁止**: `is_quick_candidate: true` の Issue も必ずレビューする

**同期バリア（MUST）**: Step 3b の全 `/twl:issue-spec-review` 呼び出しが **完了を返すまで** Step 3c に進んではならない。specialist がまだ実行中の状態で aggregate や修正に着手することは禁止（MUST NOT）。全結果が揃ってから次に進む。

## Step 3c: レビュー結果集約（全 Step 3b 完了後にのみ実行）

`/twl:issue-review-aggregate` を呼び出す。

- CRITICAL なし -> Step 3.5 へ
- CRITICAL あり -> ユーザー通知・修正後 Step 3b 再実行可
- split 承認 -> `is_split_generated: true` フラグ設定（Phase 4 まで保持）

## Step 3.5: Architecture Drift Detection（条件付き WARNING）

`/twl:issue-arch-drift` を呼び出す（CRITICAL ブロック中はスキップ）。

- **明示的/構造的シグナル検出時**: WARNING レベルで出力し、AskUserQuestion で co-architect delegation を確認する。ユーザーが「後で更新する」または「スキップ」を選択した場合は Phase 4 に進む（非ブロッキング）。
- **ヒューリスティックシグナルのみの場合**: INFO レベルで出力し、ユーザー入力なしで Phase 4 に進む（非ブロッキング）。

重大度レベルの設計根拠は **ADR-012** を参照。

## Output

呼び出し元（co-issue Phase 4）へ以下を返す:

- **review_results**: 各 Issue の specialist レビュー結果
- **blocked_issues**: CRITICAL で blocked された Issue リスト
- **split_issues**: split が承認された Issue リスト
- **is_split_generated flags**: Issue ごとの split 生成フラグ（Phase 4 で refined ラベル非付与判定に使用）
- **recommended_labels**: 各 Issue の推奨ラベル

## 禁止事項（MUST NOT）

- **複数 Issue を 1 回の `/twl:issue-spec-review` に渡してはならない**（UX ルール。1 Issue = 1 呼び出し。5 Issues なら 5 回呼び出す）
- **specialist が実行中のまま Step 3c 以降に進んではならない**（制約 IM-5。全 specialist の結果が揃うまで待機必須）

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
