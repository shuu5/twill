# workflow-pr-merge chain 実行指示詳細

`workflow-pr-merge/SKILL.md` から切り出した各 Step の詳細実行手順。

## Step 6: e2e-screening（Visual 検証）【LLM 判断】

`commands/e2e-screening.md` を Read → 実行。E2E なければスキップ。

## Step 7: pr-cycle-report（結果レポート）【機械的 → runner】

各ステップの結果を Markdown レポートとして構築し、runner に渡す:
```bash
echo "$REPORT" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-cycle-report
```

## Step 7.3: pr-cycle-analysis（パターン分析）【LLM 判断】

`commands/pr-cycle-analysis.md` を Read → 実行。

## Step 7.5: all-pass-check（全パス判定）【機械的 → runner】

**前提条件チェック（#668 防御）:** all-pass-check 実行前に `pr` フィールドが state に記録されているか確認する。未記録の場合は `chain-runner.sh record-pr` を先に実行して PR 番号を確保すること。

全ステップの結果が PASS であれば:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" record-pr  # pr 未記録時の防御
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" all-pass-check PASS
```
FAIL があれば:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" all-pass-check FAIL
```

## Step 8: merge-gate（マージ判定）【LLM 判断】

`commands/merge-gate.md` を Read → 実行。`refs/pr-merge-domain-rules.md` の merge-gate エスカレーション条件に従う。

## Step 8.5: auto-merge（自動マージ）【機械的 → runner】

merge-gate が PASS の場合のみ:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" auto-merge
```

## Step 8.7: pr-comment-final（最終判定 PR コメント）【機械的 → runner】

auto-merge 完了後（または merge-gate REJECT 時）に最終判定を PR コメントとして投稿:
```bash
# merge-gate PASS → auto-merge 成功時
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-final MERGED
```
merge-gate REJECT 時:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-final REJECTED
```
