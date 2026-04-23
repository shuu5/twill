---
name: twl:workflow-test-ready
description: |
  テスト生成と準備確認を実行する。workflow-setup の後に呼び出す。

  Use when user: says テスト準備/test-ready,
  or when called from workflow-setup chain.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-setup
tools: [Bash, Read, Skill]
maxTurns: 30
---

# テスト準備 Workflow

workflow-setup の後に呼び出す。`CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"` として使用。

## chain 実行指示（MUST — 全ステップ順に実行。途中停止禁止）

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

### Quick Guard
```bash
bash "$CR" quick-guard || { echo "quick Issue — test-ready スキップ"; exit 0; }
```
quick なら終了。非 quick → Step 1 へ。

### Step 1: テスト生成（LLM 判断）
実装コードが存在し、テストが未作成のとき:
- a. `/twl:test-scaffold --type=unit --coverage=edge-cases`

条件不成立 or テスト対象コードなし → スキップ理由を報告。**テスト生成の独断スキップ禁止。**

### Step 2: check 実行
`bash "$CR" check` → CRITICAL FAIL あれば報告して停止、なければ遷移へ。

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `test-scaffold check`

## 完了後の遷移（meta chain 定義から自動生成）

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
eval "$(bash "$CR" autopilot-detect)"
```

- IS_AUTOPILOT=true → context.md 書き出し（下記スニペット）→ 停止（orchestrator が `current_step=check` を terminal として検知し次 workflow を inject する）
- IS_AUTOPILOT=false → 「完了。次: /twl:workflow-pr-verify」と案内

**context.md 書き出しスニペット（停止直前）:**
```bash
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  cat > "${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md" <<EOF
# Workflow Context: Issue #${ISSUE_NUM}
workflow: test-ready

## completed_steps
- test-scaffold
- check

## pr_number


## test_results


## review_findings

EOF
fi
```
