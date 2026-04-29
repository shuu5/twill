---
name: twl:workflow-pr-merge
description: |
  PRマージワークフロー（e2e → report → analysis → check → merge）。
  workflow-pr-cycle 分割の第3段階。

  Use when user: says PRマージ/pr-merge,
  or when called from workflow-pr-fix.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-pr-fix
---

# PRマージワークフロー（chain-driven）

workflow-pr-cycle を 3 分割した第3段階。E2E 検証、レポート、マージ判定を行う。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 6 | e2e-screening | composite |
| 7 | pr-cycle-report | atomic |
| 7.3 | pr-cycle-analysis | atomic |
| 7.5 | all-pass-check | atomic |
| 8 | merge-gate | composite |
| 8.5 | auto-merge | atomic |

## ドメインルール

`refs/pr-merge-domain-rules.md` を Read して実行前に参照すること（禁止事項・merge-gate エスカレーション条件・stagnation 防止ルールを含む）。

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

各 Step の詳細実行手順は `refs/pr-merge-chain-steps.md` を Read して参照すること（Step 6〜Step 8.7）。

## 完了後の遷移

auto-merge 完了後:
```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" autopilot-detect)"
```

- IS_AUTOPILOT=true → context.md 書き出し（下記スニペット）→ `python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "status=merge-ready"` を実行して停止
- IS_AUTOPILOT=false → 「workflow-pr-merge 完了」と報告して停止

**context.md 書き出しスニペット（status=merge-ready 直前）:**
```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  PR_NUMBER=$(gh pr list --head "$(git branch --show-current)" --json number -q '.[0].number' 2>/dev/null || echo "")
  TEST_RESULTS=$(python3 -m twl.autopilot.checkpoint read --step pr-test --field status 2>/dev/null || echo "")
  REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field status 2>/dev/null || echo "")
  cat > "${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md" <<EOF
# Workflow Context: Issue #${ISSUE_NUM}
workflow: pr-merge

## completed_steps
- e2e-screening
- pr-cycle-report
- pr-cycle-analysis
- all-pass-check
- merge-gate
- auto-merge

## pr_number
${PR_NUMBER}

## test_results
${TEST_RESULTS}

## review_findings
${REVIEW_FINDINGS}
EOF
fi
```

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `all-pass-check pr-cycle-report`

★HUMAN GATE — merge-gate REJECT エスカレーション時はユーザーの明示的承認が必要（自動マージ禁止）
- merge-gate エスカレーションは LLM ステップのため状態を確認してから再実行すること
- all-pass-check スキップ時は PR の CI 結果を直接確認すること
