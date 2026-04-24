---
name: twl:workflow-setup
description: |
  開発準備ワークフロー（worktree作成 → テスト準備）。
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
- **Board Status** (Step 2.3): ISSUE_NUM 存在時のみ。なければ無言スキップ
- **軽微変更**: 10行未満は直接実装可。slug 生成は `worktree-create.sh` に委譲

## chain 実行指示（MUST — 全ステップを順に実行。途中停止禁止）

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

`CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"` として以下を順に実行:

1. **init** [runner]: `bash "$CR" init "$ISSUE_NUM"` → JSON の `recommended_action` を記録
2. **worktree-create** [trigger]: IS_AUTOPILOT=true ならスキップ。Manual かつ `recommended_action=worktree` のみ: `bash "$CR" worktree-create "$ARGUMENTS"`
3. **board-status-update** [runner]: ISSUE_NUM ありのみ: `bash "$CR" board-status-update "$ISSUE_NUM"`
4. **crg-auto-build** [llm]: `bash "$CR" llm-delegate "crg-auto-build" "$ISSUE_NUM"` → `commands/crg-auto-build.md` Read → 実行 → `bash "$CR" llm-complete "crg-auto-build" "$ISSUE_NUM"`
5. **arch-ref** [runner]: `bash "$CR" arch-ref "$ISSUE_NUM"` → 出力パス Read → ARCH_CONTEXT 保持
6. **ac-extract** [runner]: `bash "$CR" ac-extract`
7. **workflow-test-ready 遷移**:
   ```bash
   eval "$(bash "$CR" autopilot-detect)"
   ```
   - IS_AUTOPILOT=true → context.md 書き出し（下記スニペット）→ 停止（orchestrator が `current_step=ac-extract` を terminal として検知し次 workflow を inject する）
   - IS_AUTOPILOT=false → 「setup chain 完了。次: `/twl:workflow-test-ready`」と案内

**context.md 書き出しスニペット（停止直前）:**
```bash
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  cat > "${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md" <<EOF
# Workflow Context: Issue #${ISSUE_NUM}
workflow: setup

## completed_steps
- init
- worktree-create
- board-status-update
- crg-auto-build
- arch-ref
- ac-extract

## pr_number


## test_results


## review_findings

EOF
fi
```

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `init board-status-update crg-auto-build arch-ref ac-extract`

compaction 復帰時: `bash "$CR" chain-status "$ISSUE_NUM"` で現在状態を確認し、`current_step` から再開する。llm-delegate 記録済みステップは llm-complete 未実行の場合は再実行する。

