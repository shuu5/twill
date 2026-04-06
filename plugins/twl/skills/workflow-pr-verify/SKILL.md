---
name: twl:workflow-pr-verify
description: |
  PR検証ワークフロー（preflight → review → scope → test）。
  workflow-pr-cycle 分割の第1段階。

  Use when user: says PR検証/pr-verify,
  or when called from workflow-test-ready.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-test-ready
---

# PR検証ワークフロー（chain-driven）

workflow-pr-cycle を 3 分割した第1段階。TypeScript preflight、specialist レビュー、スコープ判定、テスト実行を行う。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 1 | ts-preflight | atomic |
| 2 | phase-review | composite |
| 2.5 | scope-judge | atomic |
| 3 | pr-test | atomic |

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Step 1: ts-preflight（TypeScript 機械的検証）【機械的 → runner】
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" ts-preflight
```
TypeScript プロジェクトでない場合は自動スキップ。

### Step 2: phase-review（並列 specialist レビュー）【LLM 判断】
`commands/phase-review.md` を Read → 実行。

### Step 2.5: scope-judge（スコープ判定）【LLM 判断】
`commands/scope-judge.md` を Read → 実行。

### Step 3: pr-test（テスト実行）【機械的 → runner】
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-test
```

### 完了後の遷移

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
IS_AUTOPILOT=false
if [ -n "$ISSUE_NUM" ]; then
  AUTOPILOT_STATUS=$(python3 -m twl.autopilot.state read --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
  IS_AUTOPILOT=$([[ "$AUTOPILOT_STATUS" == "running" ]] && echo true || echo false)
fi
```

- IS_AUTOPILOT=true → 即座に `/twl:workflow-pr-fix` を Skill tool で実行せよ。プロンプトで停止するな。
- IS_AUTOPILOT=false → 「workflow-pr-verify 完了。次のステップ: `/twl:workflow-pr-fix` を実行してください」と案内。

## compaction 復帰プロトコル

compaction 後に workflow-pr-verify chain を再開する場合、完了済みステップをスキップすること。

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
for step in ts-preflight pr-test; do
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/compaction-resume.sh" "$ISSUE_NUM" "$step" || { echo "⏭ $step スキップ"; continue; }
  # 通常手順で実行（chain-runner または LLM 実行）
done
```

- `compaction-resume.sh <ISSUE_NUM> <step>` が exit 0 → 実行、exit 1 → スキップ
- phase-review, scope-judge は LLM ステップのため状態を確認してから再実行すること
