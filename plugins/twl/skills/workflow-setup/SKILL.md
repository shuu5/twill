---
name: twl:workflow-setup
description: |
  開発準備ワークフロー（worktree作成 → DeltaSpec → テスト準備）。
  setup chain のオーケストレーター。

  Use when user: says 開発準備/setup/ワークフロー開始,
  or when called from co-autopilot workflow.
type: workflow
effort: medium
spawnable_by:
- user
- co-autopilot
tools: [Bash, Read, Skill]
maxTurns: 30
---

# 開発準備 Workflow（chain-driven）

setup chain のオーケストレーター。chain 実行順序は deps.yaml に宣言。本 SKILL.md ��� chain で表現できないドメインルールのみ記載。

## ドメインルール

- **引数**: `$ARGUMENTS` の `#N` → `ISSUE_NUM`。worktree-create にそのまま渡す
- **arch-ref 取得** (Step 2.5): Issue 起点のみ。body/comments の `<!-- arch-ref-start -->` タグ間の `architecture/` パスを Read（最大5件、`..` 拒否、不在は警告のみ）
- **DeltaSpec 分岐** (Step 3): init の `recommended_action` に基づく。`propose` → change-propose 実行（ARCH_CONTEXT 注入）、`apply` → 実装案内、`direct` → 直接案内。言語: 構造キー英語、説明日本語
- **Board Status** (Step 2.3): ISSUE_NUM 存在時のみ。なければ無言スキップ
- **軽微変更**: 10行未満は直接実装可。slug 生成は `worktree-create.sh` に委譲

## chain 実行指示（MUST — 全ステップを順に実行。途中停止禁止）

`CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"` として以下を順に実行:

1. **init** [runner]: `bash "$CR" init "$ISSUE_NUM"` → JSON の `recommended_action` を記録
2. **worktree-create** [trigger]: IS_AUTOPILOT=true ならスキップ。Manual かつ `recommended_action=worktree` のみ: `bash "$CR" worktree-create "$ARGUMENTS"`
3. **board-status-update** [runner]: ISSUE_NUM ありのみ: `bash "$CR" board-status-update "$ISSUE_NUM"`
4. **crg-auto-build** [llm]: `bash "$CR" llm-delegate "crg-auto-build" "$ISSUE_NUM"` → `commands/crg-auto-build.md` Read → 実行 → `bash "$CR" llm-complete "crg-auto-build" "$ISSUE_NUM"`
5. **arch-ref** [runner]: `bash "$CR" arch-ref "$ISSUE_NUM"` → 出力パス Read → ARCH_CONTEXT 保持
6. **change-propose** [llm]: `bash "$CR" llm-delegate "change-propose" "$ISSUE_NUM"` → ドメインルールの DeltaSpec 分岐に従い `commands/change-propose.md` Read → 実行 → `bash "$CR" llm-complete "change-propose" "$ISSUE_NUM"`
7. **ac-extract** [runner]: `bash "$CR" ac-extract`
8. **workflow-test-ready 遷移**:
   ```bash
   eval "$(bash "$CR" autopilot-detect)"
   eval "$(bash "$CR" quick-detect)"
   ```
   - IS_QUICK=true かつ IS_AUTOPILOT=true → workflow-test-ready **呼び出し禁止**。直接実装 → commit → push → PR 作成（`source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/pr-create-helper.sh" && pr_create_with_closes "$ISSUE_NUM" quick`、PR 本文に必ず `Closes #${ISSUE_NUM}` を機械的に挿入）→ `bash "$CR" llm-delegate "ac-verify" "$ISSUE_NUM"` → `commands/ac-verify.md` Read → 実行（checkpoint 永続化必須）→ `bash "$CR" llm-complete "ac-verify" "$ISSUE_NUM"` → `commands/merge-gate.md` Read → merge-gate 実行（merge-gate は ac-verify checkpoint を統合する）→ `python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "workflow_done=setup"` を実行して停止
   - IS_QUICK=false かつ IS_AUTOPILOT=true → `python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "workflow_done=setup"` を実行して停止
   - IS_AUTOPILOT=false → 「setup chain 完了。次: `/twl:workflow-test-ready`」と案内

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `init board-status-update crg-auto-build arch-ref change-propose ac-extract`

compaction 復帰時: `bash "$CR" chain-status "$ISSUE_NUM"` で現在状態を確認し、`current_step` から再開する。llm-delegate 記録済みステップは llm-complete 未実行の場合は再実行する。

