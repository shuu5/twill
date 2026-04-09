---
name: twl:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase: 探索 → 分解判断 → 精緻化(workflow) → 作成(workflow)。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Skill(workflow-issue-refine, workflow-issue-create, issue-glossary-check, explore)
spawnable_by:
- user
---

# co-issue

要望→Issue 変換の thin orchestrator。Phase 1-2 を inline で実行し、Phase 3-4 は workflow に委譲する。

## explore-summary 検出（起動時チェック）

`.controller-issue/explore-summary.md` が存在すれば「継続しますか？」と確認。[A] 継続 → Phase 2 から再開、[B] 最初から → 削除して Phase 1 から開始。

## Phase 1: 問題探索

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。`/twl:explore` に「問題空間の理解に集中」と ARCH_CONTEXT を注入して呼び出す。探索後 `.controller-issue/explore-summary.md` に書き出す。

scope/* 判明時は `architecture/domain/context-map.md` のノードラベルで該当コンポーネントの architecture ファイルを ARCH_CONTEXT に追加。

## Step 1.5: glossary 照合

`/twl:issue-glossary-check` を呼び出す（ARCH_CONTEXT を渡す）。非ブロッキング。

## Phase 2: 分解判断

explore-summary.md を読み込み、単一/複数 Issue を判断。

**Step 2a: クロスリポ検出** — GitHub Project のリンク済みリポから対象リポを動的取得。2+ リポ検出時は AskUserQuestion で [A] リポ単位分割 / [B] 単一 Issue を確認。

**Step 2b: quick 判定** — 変更ファイル 1-2 個 AND ~20行以下 AND patch レベル → `is_quick_candidate: true`。

**Step 2c: 分解確認** — 複数の場合は AskUserQuestion で [A] この分解で進める / [B] 調整 / [C] 単一のまま。

## Phase 3: Per-Issue 精緻化

`/twl:workflow-issue-refine` を Skill 呼び出し。Phase 2 の分解結果・ARCH_CONTEXT・quick フラグ・cross_repo フラグを渡す。

## Phase 4: 一括作成

`/twl:workflow-issue-create` を Skill 呼び出し。Phase 3 の精緻化結果・quick フラグ・cross_repo フラグを渡す。

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
