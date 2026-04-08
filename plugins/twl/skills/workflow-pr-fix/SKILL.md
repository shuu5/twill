---
name: twl:workflow-pr-fix
description: |
  PR修正ワークフロー（fix → post-fix-verify → warning-fix）。
  workflow-pr-cycle 分割の第2段階。

  Use when user: says PR修正/pr-fix,
  or when called from workflow-pr-verify.
type: workflow
effort: medium
spawnable_by:
- user
- workflow-pr-verify
tools: [Bash, Read, Skill]
maxTurns: 30
---

# PR修正ワークフロー（chain-driven）

workflow-pr-cycle を 3 分割した第2段階。fix ループと warning 修正を行う。

## chain ライフサイクル

| Step | コンポーネント | 型 |
|------|--------------|------|
| 4 | fix-phase | composite |
| 4.5 | post-fix-verify | atomic |
| 5 | warning-fix | atomic |

## ドメインルール

### fix ループ条件

phase-review（workflow-pr-verify で実行済み）が CRITICAL findings を返した場合の修正ループ:

```
IF phase-review に CRITICAL findings (confidence >= 80) が存在
THEN
  1. fix-phase を実行（Step 4）
  2. post-fix-verify を実行（Step 4.5）
  3. pr-test を再実行（runner）
  4. テスト PASS → warning-fix へ（Step 5）
  5. テスト FAIL → fix-phase に戻る（最大 1 ループ）
ELSE
  fix-phase をスキップし warning-fix へ
```

## chain 実行指示（MUST — 全ステップを順に実行せよ。途中で停止するな）

**重要**: 以下の全ステップを上から順に実行すること。各ステップ完了後、**即座に**次のステップに進むこと。プロンプトで停止してはならない。

### Step 4: fix-phase（自動修正ループ）【LLM 判断】
review に CRITICAL findings がある場合のみ。`commands/fix-phase.md` を Read → 実行。
fix 後は post-fix-verify（Step 4.5）→ pr-test 再実行のループ。

### Step 4.5: post-fix-verify（fix 後検証）【LLM 判断】
fix-phase を実行した場合のみ。`commands/post-fix-verify.md` を Read → 実行。

### Step 5: warning-fix（Warning 修正）【LLM 判断】
`commands/warning-fix.md` を Read → 実行。

### 完了後の遷移

```bash
eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" autopilot-detect)"
# IS_AUTOPILOT が設定される
```

- IS_AUTOPILOT=true → 即座に `/twl:workflow-pr-merge` を Skill tool で実行せよ。プロンプトで停止するな。
- IS_AUTOPILOT=false → 「workflow-pr-fix 完了。次のステップ: `/twl:workflow-pr-merge` を実行してください」と案内。

## compaction 復帰プロトコル

`refs/ref-compaction-recovery.md` を Read し従うこと。fix ループは LLM ステップのため issue-{N}.json の状態を確認してから再実行。fix-phase 完了済みなら post-fix-verify → warning-fix から再開。
