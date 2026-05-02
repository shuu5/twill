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

phase-review と ac-verify（workflow-pr-verify で実行済み）が CRITICAL findings を返した場合の修正ループ:

```
IF phase_review_critical + ac_verify_critical > 0
   （phase-review CRITICAL または ac-verify CRITICAL のいずれかが 1 以上）
THEN
  1. fix-phase を実行（Step 4）
  2. post-fix-verify を実行（Step 4.5）
  3. pr-test を再実行（runner）
  4. テスト PASS → warning-fix へ（Step 5）
  5. テスト FAIL → fix-phase に戻る（最大 1 ループ）
ELSE （phase_review_critical + ac_verify_critical == 0 のみ）
  fix-phase をスキップし warning-fix へ
```

**ac-verify CRITICAL の例**: テストが RED のまま PR を出した（GREEN 未完了）、
AC の実装が欠落している等の TDD 違反。phase-review が PASS でも fix-phase を発動する。

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

### Step 4: fix-phase（自動修正ループ）【LLM 判断】
`phase_review_critical + ac_verify_critical > 0` の場合のみ実行。`commands/fix-phase.md` を Read → 実行。
fix 後は post-fix-verify（Step 4.5）→ pr-test 再実行のループ。

### Step 4.5: post-fix-verify（fix 後検証）【LLM 判断】
fix-phase を実行した場合のみ。`commands/post-fix-verify.md` を Read → 実行。

### Step 5: warning-fix（Warning 修正）【LLM 判断】
`commands/warning-fix.md` を Read → 実行。

### Fix サマリ PR コメント投稿

全 fix ステップ完了後、修正内容を PR コメントとして投稿する。
fix-phase を実行した場合は具体的な修正内容を、スキップした場合は「No fixes applied」を投稿。

```bash
# fix サマリを構築して投稿（LLM が修正内容を箇条書きで構築し stdin 経由で渡す）
echo "$FIX_SUMMARY" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-fix-summary
```

FIX_SUMMARY には以下の形式で修正内容を記載:
```
- [WARNING] <finding message> → <修正内容> (commit <short-sha>)
- [CRITICAL] <finding message> → <修正内容> (commit <short-sha>)
```

fix-phase をスキップした場合は stdin なし（空）で呼び出す（デフォルトメッセージが投稿される）:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-fix-summary < /dev/null
```

## 完了後の遷移（meta chain 定義から自動生成）

```bash
source "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-issue-num.sh" 2>/dev/null || true
ISSUE_NUM=$(resolve_issue_num 2>/dev/null || echo "")
eval "$(bash "$CR" autopilot-detect)"
```

- IS_AUTOPILOT=true → context.md 書き出し（下記スニペット）→ 停止（orchestrator が `current_step=warning-fix` を terminal として検知し次 workflow を inject する）
- IS_AUTOPILOT=false → 「workflow-pr-fix 完了。次のステップ: /twl:workflow-pr-merge を実行してください」と案内

**context.md 書き出しスニペット（停止直前）:**
```bash
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
if [[ -n "$ISSUE_NUM" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
  mkdir -p "${AUTOPILOT_DIR}/issues"
  PR_NUMBER=$(gh pr list --head "$(git branch --show-current)" --json number -q '.[0].number' 2>/dev/null || echo "")
  TEST_RESULTS=$(python3 -m twl.autopilot.checkpoint read --step pr-test --field status 2>/dev/null || echo "")
  REVIEW_FINDINGS=$(python3 -m twl.autopilot.checkpoint read --step phase-review --field status 2>/dev/null || echo "")
  cat > "${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md" <<EOF
# Workflow Context: Issue #${ISSUE_NUM}
workflow: pr-fix

## completed_steps
- fix-phase
- post-fix-verify
- warning-fix

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

`refs/ref-compaction-recovery.md` を Read し従うこと。fix ループは LLM ステップのため issue-{N}.json の状態を確認してから再実行。fix-phase 完了済みなら post-fix-verify → warning-fix から再開。

