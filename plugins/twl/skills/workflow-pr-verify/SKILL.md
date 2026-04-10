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
tools: [Bash, Read, Skill]
maxTurns: 30
---

# PR検証ワークフロー（chain-driven）

workflow-pr-cycle を 3 分割した第1段階。TypeScript preflight、specialist レビュー、スコープ判定、テスト実行を行う。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 0.5 | prompt-compliance | atomic |
| 1 | ts-preflight | atomic |
| 2 | phase-review | composite |
| 2.5 | scope-judge | atomic |
| 3 | pr-test | atomic |
| 3.5 | ac-verify | atomic |

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Step 0.5: prompt-compliance（refined_by ハッシュ整合性）【機械的 → runner】
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" prompt-compliance
```
.md ファイル変更なし→PASS スキップ。refined_by フォーマット不正→FAIL（ブロック）。stale→WARN（非ブロック）。

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

### Step 3.5: ac-verify（AC↔diff 整合性チェック）【LLM 判断】

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" ac-verify
```

chain-runner はマーカー（current_step 記録）のみ実行する。続けて
`commands/ac-verify.md` を Read → 実行ロジックに従い AC checklist と PR diff・pr-test
checkpoint を照合し、`python3 -m twl.autopilot.checkpoint write --step ac-verify ...`
で結果を永続化すること。前提: workflow-setup の ac-extract が済んでおり
`${SNAPSHOT_DIR}/01.5-ac-checklist.md` が存在すること（不在時は WARN で抜ける）。

## 完了後の遷移（meta chain 定義から自動生成）

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
eval "$(bash "$CR" autopilot-detect)"
```

- IS_AUTOPILOT=true → `python3 -m twl.autopilot.state write --autopilot-dir "${AUTOPILOT_DIR:-}" --type issue --issue "$ISSUE_NUM" --role worker --set "workflow_done=pr-verify"` を実行して停止
- IS_AUTOPILOT=false → 「workflow-pr-verify 完了。次のステップ: /twl:workflow-pr-fix を実行してください」と案内

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。ステップリスト: `prompt-compliance ts-preflight pr-test ac-verify`

- phase-review, scope-judge, ac-verify は LLM ステップのため状態を確認してから再実行すること

## 完了後の遷移（meta chain 定義から自動生成）

```bash
eval "$(bash "$CR" autopilot-detect)"
```

- IS_AUTOPILOT=true → ユーザーへ案内して停止
- IS_AUTOPILOT=false → 「workflow-pr-verify 完了。次のステップ: /twl:workflow-pr-fix を実行してください」と案内
