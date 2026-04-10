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

### Step 1: change-id 解決
`CHANGE_ID=$(bash "$CR" change-id-resolve)` → change-id を記録。

### Step 2: テスト生成（LLM 判断）
deltaspec/changes/\<change-id>/specs/ に Scenario が存在 AND test-mapping.yaml 未存在 のとき:
- a. `/twl:test-scaffold <change-id> --type=unit --coverage=edge-cases`
- b. E2E テスト（デフォルト yes）

条件不成立 or テスト対象コードなし → スキップ理由を報告。**テスト生成の独断スキップ禁止。**

### Step 3: check 実行
`bash "$CR" check` → CRITICAL FAIL あれば報告して停止、なければ Step 4 へ。

### Step 4: change-apply + autopilot 遷移

state 記録 → change-apply → state 記録 → autopilot 判定:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
[[ -n "$ISSUE_NUM" ]] && python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "current_step=change-apply" 2>/dev/null || true
```
`/twl:change-apply <change-id>` を Skill 実行。完了後:
```bash
[[ -n "$ISSUE_NUM" ]] && python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "current_step=post-change-apply" 2>/dev/null || true
eval "$(bash "$CR" autopilot-detect)"
```
- IS_AUTOPILOT=true → 即座に `/twl:workflow-pr-verify --spec <change-id>` を Skill 実行（停止禁止）
- IS_AUTOPILOT=false → 「完了。次: `/twl:workflow-pr-verify --spec <change-id>`」と案内

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `change-id-resolve test-scaffold check change-apply post-change-apply`

- `change-apply` 復帰: Step 4 の手順を再実行（state 記録 → `/twl:change-apply` → state 記録）
- `post-change-apply` 復帰: IS_AUTOPILOT 判定スニペット（Step 4 後半）を実行し、`IS_AUTOPILOT=true` なら即座に `/twl:workflow-pr-verify --spec <change-id>` を Skill tool で実行

## 完了後の遷移（meta chain 定義から自動生成）

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
eval "$(bash "$CR" autopilot-detect)"
```

- IS_AUTOPILOT=true → context.md 書き出し（下記スニペット）→ `python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "workflow_done=test-ready"` を実行して停止
- IS_AUTOPILOT=false → 「完了。次: /twl:workflow-pr-verify」と案内

**context.md 書き出しスニペット（workflow_done=test-ready 直前）:**
```bash
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  CHANGE_ID_VAL=$(python3 -m twl.autopilot.state read --autopilot-dir "${AUTOPILOT_DIR}" --type issue --issue "${ISSUE_NUM}" --field change_id 2>/dev/null || echo "")
  cat > "${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md" <<EOF
# Workflow Context: Issue #${ISSUE_NUM}
workflow: test-ready

## completed_steps
- change-id-resolve
- test-scaffold
- check
- change-apply

## change_id
${CHANGE_ID_VAL}

## pr_number


## test_results


## review_findings

EOF
fi
```

