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

## セッション ID 生成（起動時）

起動時に SESSION_ID を生成: `$(date +%s)_$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c4 2>/dev/null || echo "xxxx")` （例: `1712649600_a3f2`）。
SESSION_DIR=`.controller-issue/<session-id>/`

## explore-summary 検出（起動時チェック）

glob `.controller-issue/*/explore-summary.md` でセッション一覧を検出:
- **0件（存在しない場合）**: 既存動作に影響なし。通常の Phase 1 から開始（デフォルト動作）
- **1件**: 「継続しますか？」と確認。[A] 継続 → Phase 1 スキップ、SESSION_ID を既存セッションに合わせ Phase 2（分解判断）から再開、[B] 最初から → explore-summary.md を含む `.controller-issue/<session-id>/` を削除して Phase 1 から開始（新しい SESSION_ID で）
- **2件以上**: AskUserQuestion でセッション選択 UI を表示（各セッションの ID + 作成日時 + explore-summary 内の最初の問題タイトルを表示、最新を先頭に推奨）。[新規開始] オプションも提示

セッション ID ベースのディレクトリ分離により、既存の co-issue フローとの互換性を維持しながら並列実行が可能。

## Phase 1: 問題探索

`architecture/` が存在する場合、vision.md・context-map.md・glossary.md を Read して `ARCH_CONTEXT` として保持（不在はスキップ）。`/twl:explore` に「問題空間の理解に集中」と ARCH_CONTEXT を注入して呼び出す。探索後 `.controller-issue/<session-id>/explore-summary.md` に書き出す（`mkdir -p .controller-issue/<session-id>`）。

scope/* 判明時は `architecture/domain/context-map.md` のノードラベルで該当コンポーネントの architecture ファイルを ARCH_CONTEXT に追加。

## Step 1.5: glossary 照合

`/twl:issue-glossary-check` を呼び出す（ARCH_CONTEXT と SESSION_DIR を渡す）。非ブロッキング。

## Phase 2: 分解判断

`.controller-issue/<session-id>/explore-summary.md` を読み込み、単一/複数 Issue を判断。

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
- 他セッションの `.controller-issue/<other-session-id>/` を削除してはならない
