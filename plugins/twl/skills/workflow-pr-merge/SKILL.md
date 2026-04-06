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

## compaction 復帰プロトコル

compaction 後に workflow-pr-merge chain を再開する場合、完了済みステップをスキップすること。

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num)
for step in all-pass-check pr-cycle-report; do
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/compaction-resume.sh" "$ISSUE_NUM" "$step" || { echo "⏭ $step スキップ"; continue; }
  # 通常手順で実行（chain-runner または LLM 実行）
done
```

- `compaction-resume.sh <ISSUE_NUM> <step>` が exit 0 → 実行、exit 1 → スキップ
- merge-gate エスカレーションは LLM ステップのため状態を確認してから再実行すること
- all-pass-check がスキップされた場合は PR の CI 結果を直接確認すること
