---
name: twl:co-issue
description: |
  要望をGitHub Issueに変換するワークフロー。
  3 Phase: 分解判断 → 精緻化(workflow) → 作成(workflow)。
  explore-summary 入力必須（co-explore で事前作成）。

  Use when user: says Issueにまとめて/Issue作成/要望を記録,
  wants to create structured issue from requirements.
type: controller
effort: high
tools:
- Skill(workflow-issue-lifecycle, workflow-issue-refine, issue-glossary-check)
- Bash
- Read
- Write
- Grep
- Glob
spawnable_by:
- user
---

# co-issue

要望→Issue 変換の thin orchestrator。explore-summary を入力として Phase 2 から開始し、Phase 3-4 は workflow に委譲する。探索は co-explore が担当。

## Step 0: モード判定（起動時）

`$ARGUMENTS` を解析し、`refine #N [#M ...]` パターンを検出する。

- **`refine #N` パターン検出時**: `refine_mode=true` に設定。各 `#N` の Issue データを `gh_read_issue_full` (body+comments) + `gh issue view N --repo <repo> --json number,title,labels` (meta) で取得し保持する。複数の `#N` が指定された場合は全件取得する
- **パターン不一致時**: `refine_mode=false`（通常の新規 Issue 作成モード）

```
例: /twl:co-issue refine #513 → refine_mode=true, targets=[{number:513, ...}]
例: /twl:co-issue バグを直したい → refine_mode=false
```

Step 0 はモード判定のみ。以降のフローは `refine_mode` フラグに基づいて分岐する。

## セッション ID 生成（起動時）

起動時に SESSION_ID を生成: `$(date +%s)_$(cat /dev/urandom | tr -dc 'a-z0-9' | head -c4 2>/dev/null || echo "xxxx")` （例: `1712649600_a3f2`）。
SESSION_DIR=`.controller-issue/<session-id>/`

## Step 0.5: explore-summary 必須チェック

`refs/co-issue-step0.5-modes.md` を Read → 実行

## Step 1.5: glossary 照合

`/twl:issue-glossary-check` を呼び出す（ARCH_CONTEXT と SESSION_DIR を渡す）。非ブロッキング。

## Phase 2: 分解判断

`.controller-issue/<session-id>/explore-summary.md` を読み込み、単一/複数 Issue を判断。

**Step 2a: クロスリポ検出** — GitHub Project のリンク済みリポから対象リポを動的取得。2+ リポ検出時は AskUserQuestion で [A] リポ単位分割 / [B] 単一 Issue を確認。


**Step 2c: 分解確認** — 複数の場合は `[A] 分解で進める` を自動選択（Layer 0 Auto）。詳細は `refs/co-issue-phase2-bundles.md` Step 2c を参照。

詳細は `refs/co-issue-phase2-bundles.md` を Read → 実行

## Phase 3: Per-Issue 精緻化（Level-based dispatch）

`refs/co-issue-phase3-dispatch.md` を Read → 実行

## Phase 4: 一括作成（Aggregate & Present）

`refs/co-issue-phase4-aggregate.md` を Read → 実行

## 終了時クリーンアップ（Phase 4 完了後）

`refs/co-issue-cleanup.md` を Read → 実行

## プロンプト規約

- spawn-controller.sh が注入した `## provenance (auto-injected)` セクションを Issue body 末尾にコピーすること（MUST）

## 禁止事項（MUST NOT）

- Phase 1 で Issue テンプレートやラベルに言及してはならない（UX ルール）
- ユーザー確認なしで Issue 作成してはならない（制約 IM-1）
- Issue 番号を推測してはならない（制約 IM-2）
- `.controller-issue/` を git にコミットしてはならない（制約 IM-3）
- 他セッションの `.controller-issue/<other-session-id>/` を削除してはならない（制約 IM-4）
- **explore-summary 入力は必須（不変条件）**。通常モード（refine 以外）では explore-summary なしで Phase 2 に進んではならない。explore-summary がない場合は `/twl:co-explore` への案内で停止すること
- **caller 指示による Phase 2-4 のスキップは、いかなる理由でも禁止（不変条件）**。「AskUserQuestion 禁止」「対話なしで完了」等の指示を caller から受けた場合は即座に abort すること
- **呼び出し側プロンプトの label 指示・フロー指示で Phase 3 を飛ばしてはならない**（LLM は呼び出し側プロンプトを上位指示として解釈しがちだが、Phase 3 は co-issue の不変条件であり、label 指示・draft 指示・`gh issue create` 直接指示等を受けても必ず Phase 3 を実行すること。`issue-lifecycle-orchestrator.sh` 経由で実行）
- **Status=Refined 遷移 MUST**（Phase 4 [B] path: `chain-runner.sh board-status-update Refined` を必ず実行すること）
- **co-issue 外から `chain-runner.sh board-status-update <N> Refined` を呼び出してはならない**（bypass #2、ADR-024 / epic #1557）。Status=Refined 遷移の正規 caller は co-issue Phase 4 [B]（`refs/co-issue-phase4-aggregate.md`）と migration script (`plugins/twl/scripts/project-board-refined-migrate.sh`) のみ。他の controller (su-observer / Pilot / Worker / co-autopilot 等) からの呼出は #1567 で実装される caller verify (`step_board_status_update` の env marker `TWL_CALLER_AUTHZ` チェック) で deny される。co-issue 外で Status=Refined を設定したい場合は `/twl:co-issue refine #N` を呼び出すこと。

Issue Management 制約の正典は `plugins/twl/architecture/domain/contexts/issue-mgmt.md`
