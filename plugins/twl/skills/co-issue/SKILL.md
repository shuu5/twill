---
name: twl:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  4 Phase 構成: 問題探索 → 分解判断 → Per-Issue 精緻化 → 一括作成。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Skill(workflow-issue-refine, workflow-issue-create, issue-glossary-check)
- Agent(context-checker, template-validator)
spawnable_by:
- user
---

# co-issue

要望→Issue 変換ワークフロー（4 Phase 構成）。各 Phase の詳細ロジックはコマンドに委譲する。

## explore-summary 検出（起動時チェック）

`.controller-issue/explore-summary.md` が存在すれば「継続しますか？」と確認。[A] 継続 → Phase 2 から再開、[B] 最初から → 削除して Phase 1 から開始。

## Phase 1: 問題探索

TaskCreate 「Phase 1: 問題探索」(status: in_progress)

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。`/twl:explore` に「問題空間の理解に集中」と ARCH_CONTEXT を注入して呼び出す。探索後 `.controller-issue/explore-summary.md` に書き出す。

explore-summary から scope/* が判明した場合、`architecture/domain/context-map.md` の flowchart ノードラベルでコンポーネントパスを特定し、該当コンポーネントの architecture ファイルを ARCH_CONTEXT に追加する（複数 scope/* の場合は各コンポーネント分を追加）。

TaskUpdate Phase 1 → completed

## Step 1.5: glossary 照合

`/twl:issue-glossary-check` を呼び出す（ARCH_CONTEXT を渡す）。非ブロッキング。

## Phase 2: 分解判断

TaskCreate 「Phase 2: 分解判断」(status: in_progress)

explore-summary.md を読み込み、単一/複数 Issue を判断。

**Step 2a: クロスリポ検出** — GitHub Project のリンク済みリポから対象リポを動的取得。2+ リポ検出時は AskUserQuestion で [A] リポ単位分割 / [B] 単一 Issue を確認。[A] → `cross_repo_split = true`, `target_repos` 記録。

**Step 2b: quick 判定** — 変更ファイル 1-2 個 AND ~20行以下 AND patch レベル → `is_quick_candidate: true`。

**Step 2c: 通常の分解判断** — 複数の場合は AskUserQuestion で [A] この分解で進める / [B] 調整 / [C] 単一のまま。

TaskUpdate Phase 2 → completed

## Phase 3: Per-Issue 精緻化ループ

TaskCreate 「Phase 3: 精緻化（N件）」(status: in_progress)

`/twl:workflow-issue-refine` を呼び出す。以下を渡す:

- **unstructured_issues**: Phase 2 で分解された Issue リスト
- **ARCH_CONTEXT**: Phase 1 で収集した architecture コンテキスト
- **is_quick_candidate flags**: Phase 2 Step 2b で判定された quick 候補フラグ
- **cross_repo_split**: クロスリポ分割フラグ

返却値（`review_results`, `blocked_issues`, `split_issues`, `is_split_generated` flags, `recommended_labels`）を Phase 4 で使用する。

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

`/twl:workflow-issue-create` を呼び出す。以下を渡す:

- **refined_issues**: Phase 3 で精緻化された Issue リスト
- **is_split_generated flags**: Phase 3 で生成された split フラグ
- **is_quick_candidate flags**: Phase 2 Step 2b で判定された quick 候補フラグ
- **cross_repo_split**: クロスリポ分割フラグ
- **target_repos**: クロスリポ対象リポジトリリスト

返却値（`created_issue_urls`）で完了通知。

TaskUpdate Phase 4 → completed

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
