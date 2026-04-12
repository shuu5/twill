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

### 禁止事項（不変条件 C enforcement）

Worker は `gh pr merge` を直接実行してはならない（不変条件 C）。マージは必ず `chain-runner.sh auto-merge` 経由で auto-merge.sh のガードを通すこと。`gh pr merge --squash` 等の直接呼び出しは ac-verify / merge-gate / auto-merge.sh の全ガードをバイパスするため厳禁。

### merge-gate エスカレーション条件

merge-gate が REJECT を返した場合の処理（不変条件 E: リトライ最大 1 回）:

```
IF retry_count == 0
THEN
  1. issue-{N}.json の status を failed → running に遷移
  2. fix_instructions に CRITICAL findings を記録
  3. fix-phase → pr-test → post-fix-verify → merge-gate を再実行
  4. retry_count を 1 に更新
ELIF retry_count >= 1
THEN
  1. issue-{N}.json の status を failed に確定
  2. Pilot に手動介入を要求
  3. ワークフローを停止
```

### merge 失敗時の対応（不変条件 F）

```
IF squash merge が失敗（コンフリクト等）
THEN
  停止のみ。自動 rebase は行わない。
  Pilot に手動介入を要求。
```

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

### Step 6: e2e-screening（Visual 検証）【LLM 判断】
`commands/e2e-screening.md` を Read → 実行。E2E なければスキップ。

### Step 7: pr-cycle-report（結果レポート）【機械的 → runner】
各ステップの結果を Markdown レポートとして構築し、runner に渡す:
```bash
echo "$REPORT" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-cycle-report
```

### Step 7.3: pr-cycle-analysis（パターン分析）【LLM 判断】
`commands/pr-cycle-analysis.md` を Read → 実行。

### Step 7.5: all-pass-check（全パス判定）【機械的 → runner】
全ステップの結果が PASS であれば:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" all-pass-check PASS
```
FAIL があれば:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" all-pass-check FAIL
```

### Step 8: merge-gate（マージ判定）【LLM 判断】
`commands/merge-gate.md` を Read → 実行。上記「ドメインルール」の merge-gate エスカレーション条件に従う。

### Step 8.5: auto-merge（自動マージ）【機械的 → runner】
merge-gate が PASS の場合のみ:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" auto-merge
```

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
  CHANGE_ID_VAL=$(python3 -m twl.autopilot.state read --autopilot-dir "${AUTOPILOT_DIR}" --type issue --issue "${ISSUE_NUM}" --field change_id 2>/dev/null || echo "")
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

## change_id
${CHANGE_ID_VAL}

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

- merge-gate エスカレーションは LLM ステップのため状態を確認してから再実行すること
- all-pass-check スキップ時は PR の CI 結果を直接確認すること
