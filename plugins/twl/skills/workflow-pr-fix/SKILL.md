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

### 前提: 前 workflow コンテキスト復元

```bash
CR="${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh"
ISSUE_NUM=$(bash "$CR" resolve-issue-num 2>/dev/null || echo "")
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"
CONTEXT_FILE="${AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}-context.md"
[[ -n "$ISSUE_NUM" && -f "$CONTEXT_FILE" ]] && echo "=== 前 workflow コンテキスト ===" && cat "$CONTEXT_FILE"
```

### Step 4: fix-phase（自動修正ループ）【LLM 判断】
review に CRITICAL findings がある場合のみ。`commands/fix-phase.md` を Read → 実行。
fix 後は post-fix-verify（Step 4.5）→ pr-test 再実行のループ。

### Step 4.5: post-fix-verify（fix 後検証）【LLM 判断】
fix-phase を実行した場合のみ。`commands/post-fix-verify.md` を Read → 実行。

### Step 5: warning-fix（Warning 修正）【LLM 判断】
`commands/warning-fix.md` を Read → 実行。

### Tech-debt Issue 自動起票

全 fix ステップ完了後、WARNING findings を tech-debt Issue として自動起票する（Issue #655）。

```bash
TECH_DEBT_JSON=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" tech-debt-issues)
```

`TECH_DEBT_JSON` は JSON 配列 `[{"index": N, "message": "...", "issue_num": NNN}, ...]` として返る。
起票された Issue 番号は次の Fix Report の Deferred セクションで使用する。

### Fix Report PR コメント投稿

tech-debt 起票後、Fix Report を以下の標準テンプレートで構築し PR コメントとして投稿する（Issue #655）:

```bash
echo "$FIX_REPORT" | bash "${CLAUDE_PLUGIN_ROOT}/scripts/chain-runner.sh" pr-comment-fix-summary
```

`FIX_REPORT` は以下の標準テンプレートで構築する:

```markdown
### Fixed (CRITICAL)
| # | Finding | Fix Commit | Verification |
|---|---------|------------|-------------|
| 1 | <finding message> | <short-sha> | テスト PASS |

### Deferred (WARNING → tech-debt)
| # | Finding | Reason | Issue |
|---|---------|--------|-------|
| 1 | <finding message> | <延期理由> | #NNN |

### Acknowledged (INFO)
| # | Finding | Note |
|---|---------|------|
| 1 | <finding message> | <メモ> |
```

- **Fixed**: fix-phase で修正した CRITICAL findings。Fix Commit には `git rev-parse --short HEAD` を記録
- **Deferred**: 修正しなかった WARNING findings。Reason には延期理由、Issue には `TECH_DEBT_JSON` の issue_num を記録
- **Acknowledged**: INFO findings への対応メモ

fix-phase をスキップした場合は stdin なし（空）で呼び出す（デフォルトテンプレートが投稿される）:
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
  CHANGE_ID_VAL=$(python3 -m twl.autopilot.state read --autopilot-dir "${AUTOPILOT_DIR}" --type issue --issue "${ISSUE_NUM}" --field change_id 2>/dev/null || echo "")
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

`refs/ref-compaction-recovery.md` を Read し従うこと。fix ループは LLM ステップのため issue-{N}.json の状態を確認してから再実行。fix-phase 完了済みなら post-fix-verify → warning-fix から再開。

