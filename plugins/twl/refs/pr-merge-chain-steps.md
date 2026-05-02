# workflow-pr-merge chain 実行指示詳細

`workflow-pr-merge/SKILL.md` から切り出した各 Step の詳細実行手順。

## Step 4: fix-phase（自動修正ループ）— 判定条件リファレンス

fix-phase（`workflow-pr-fix` で実行）の発動条件は以下の通り:

```
IF phase_review_critical + ac_verify_critical == 0
THEN skip（修正不要）
ELSE fix-phase を実行
```

**ac-verify CRITICAL も判定対象**（#1263 追加）。
phase-review が PASS（critical_count=0）でも、ac-verify CRITICAL が 1 以上の場合は fix-phase を実行する。

- **ac-verify CRITICAL の例**: テスト RED のまま PR を出した（GREEN 未完了）、AC 実装が欠落している等の TDD 違反
- checkpoint: `python3 -m twl.autopilot.checkpoint read --step ac-verify --field critical_count`

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
