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

## Worker TDD mental model（MUST READ）

この workflow は TDD の RED フェーズを確立する。Worker はこのモデルを理解した上で実装に進むこと。

- **RED**: AC から生成したテストが fail する状態は **正常**。これが実装の起点。
- **GREEN**: Worker が実装し、全テストを PASS させる。
- **REFACTOR**: PASS 維持のまま品質を向上させる（optional）。

**禁止事項（MUST NOT）**:
- テストの削除
- assertion を弱める（pass しやすいよう条件を緩める）
- 全テストが PASS している状態で実装を飛ばして進む

## chain 実行指示（MUST — 全ステップ順に実行。途中停止禁止）

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

### Step 1: test-scaffold（AC-based）

`bash "$CR" llm-delegate "test-scaffold" "$ISSUE_NUM"` を実行し、`commands/test-scaffold.md` を Read → 実行。

AC-based test scaffold の入力:
- `${SNAPSHOT_DIR:-${CLAUDE_PLUGIN_ROOT:-.}/.dev-session/issue-${ISSUE_NUM:-unknown}}/01.5-ac-checklist.md`（不在は WARN のみ）
- Issue body の `## AC` / `## Acceptance Criteria` 節

出力: test ファイル（pytest/vitest/testthat）+ `ac-test-mapping.yaml`（AC 項目 → test path マッピング）

test-scaffold 完了後、test-first guard を実行:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/tdd-red-guard.sh"
```
guard 失敗（テスト未生成 or 全 PASS）の場合は停止して報告。re-scaffold または実装のやり直しが必要。

`bash "$CR" llm-complete "test-scaffold" "$ISSUE_NUM"` を呼ぶ。

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
