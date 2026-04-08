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
- Skill(issue-spec-review, issue-review-aggregate, issue-glossary-check, issue-arch-drift, issue-cross-repo-create)
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

**Step 3a**: 各 Issue に `/twl:issue-structure` でテンプレート適用。推奨ラベル抽出。tech-debt 棚卸し（該当時）。クロスリポ分割時は parent + 子 Issue の構造化ルールに従う。

**Step 3b: specialist レビュー（MUST — spawn 粒度・同期バリア厳守）**

`/twl:issue-spec-review` を **1 Issue につき 1 回** 呼び出す。複数 Issue をまとめて 1 回の呼び出しに渡してはならない（MUST NOT）。

- **spawn 数の公式**: N Issues → N 回の `/twl:issue-spec-review` 呼び出し → 各呼び出しが内部で 3 specialist を spawn → 合計 3N specialist
- **具体例**: 5 Issues なら `/twl:issue-spec-review` を 5 回呼び出し、15 specialist が起動される。3 回の呼び出しで済ませてはならない
- **並列実行可**: N 回の Skill 呼び出しは並列で発行してよい
- **quick 候補もスキップ禁止**: `is_quick_candidate: true` の Issue も必ずレビューする

**同期バリア（MUST）**: Step 3b の全 `/twl:issue-spec-review` 呼び出しが **完了を返すまで** Step 3c に進んではならない。specialist がまだ実行中の状態で aggregate や修正に着手することは禁止（MUST NOT）。全結果が揃ってから次に進む。

**Step 3c（全 Step 3b 完了後にのみ実行）**: `/twl:issue-review-aggregate` を呼び出す。CRITICAL なし → Step 3.5 へ。CRITICAL あり → ユーザー通知・修正後 Step 3b 再実行可。split 承認 → `is_split_generated: true` フラグ設定（Phase 4 まで保持）。

**Step 3.5**: `/twl:issue-arch-drift` を呼び出す（CRITICAL ブロック中はスキップ）。非ブロッキング。

TaskUpdate Phase 3 → completed

## Phase 4: 一括作成

TaskCreate 「Phase 4: Issue 作成」(status: in_progress)

**refined ラベル事前作成**: `gh label create refined` → `REFINED_LABEL_OK` フラグ追跡。失敗時はラベル非付与でワークフロー続行。`is_split_generated: true` の Issue には refined 非付与（MUST NOT）。

1. **ユーザー確認（MUST）**: 全候補提示、quick 候補に `[quick]` マーク
2. **作成**:
   - 通常: 単一→`/twl:issue-create`、複数→`/twl:issue-bulk-create`。`REFINED_LABEL_OK=true` かつ `is_split_generated != true` → `--label refined`。quick 条件充足 → `--label quick`
   - クロスリポ: `/twl:issue-cross-repo-create` を呼び出す
3. **Project Board 同期**: 各 Issue 後 `/twl:project-board-sync N`（失敗は警告のみ）。**MUST**: `chain-runner.sh board-status-update` を直接呼ばないこと（デフォルトが In Progress のため新規 Issue が誤って In Progress になる）
4. **クリーンアップ**: `.controller-issue/` を削除（中止時も同様）
5. **完了通知**: Issue URL 表示、`/twl:workflow-setup #N` で開発開始を案内

TaskUpdate Phase 4 → completed

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない
- ユーザー確認なしで Issue 作成してはならない
- Issue 番号を推測してはならない（gh 出力から取得）
- `.controller-issue/` を git にコミットしてはならない
- **複数 Issue を 1 回の `/twl:issue-spec-review` に渡してはならない**（1 Issue = 1 呼び出し。5 Issues なら 5 回呼び出す）
- **specialist が実行中のまま Step 3c 以降に進んではならない**（全 specialist の結果が揃うまで待機必須）
