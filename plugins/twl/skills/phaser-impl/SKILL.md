---
name: twl:phaser-impl
description: |
  phaser-impl: status-transition Refined → Implementing 専任の L1 phaser。
  administrator が Project Board Status=Refined Issue を polling で検知して spawn、
  本 phaser が workflow-test-ready を呼んで atomic 3 件 (test-scaffold/green-impl/check) を順次実行、
  specialist code review を経て PR 作成 + Status 遷移を行う。
  1 phaser = 1 Issue rule (boundary-matrix.html I-1)。

  Use when administrator: spawns phaser-impl for status-transition Refined → Implementing.
type: phaser
effort: medium
allowed-tools: [Bash, Read, Edit, Skill, Agent]
spawnable_by:
  - administrator
---

# phaser-impl

status-transition: **Refined → Implementing** 専任の L1 phaser (boundary-matrix.html I-1)。

## 前提 (administrator spawn 時)

- `TWL_PHASER_NAME=phaser-impl-<ISSUE>` env 注入 (spawn-protocol.html §3、atomic-verification.html §3.1)
- mailbox path: `.mailbox/$TWL_PHASER_NAME/inbox.jsonl`
- Project Board Status == "Refined" (gate-hook.html §1 tier 1+2 で機械 verify、Inv W)

## Step 0: pre-check (hardcode、deterministic)

```bash
[ -n "$TWL_PHASER_NAME" ] || { echo "FATAL: TWL_PHASER_NAME unset" >&2; exit 1; }
ISSUE_NUM=$(echo "$TWL_PHASER_NAME" | grep -oP '\d+$')
[ -n "$ISSUE_NUM" ] || { echo "FATAL: Issue number not in $TWL_PHASER_NAME" >&2; exit 1; }
mkdir -p ".mailbox/$TWL_PHASER_NAME" ".mailbox/administrator"

# AC file path を Phase J/Phase 1 PoC 規約で resolve
AC_FILE_PATH=".autopilot/issues/issue-${ISSUE_NUM}/ac-test-mapping.yaml"

# Cluster 2 helper を source (mailbox_emit を flock atomic で使用、Inv T)
source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/mailbox.sh"
```

## Step 1: workflow-test-ready 呼び出し (LLM 自由判断)

`Skill(twl:workflow-test-ready, "$AC_FILE_PATH")` を呼び、RED test 生成 + GREEN 実装 + check の 3 atomic を順次実行:

- atomic-test-scaffold が mailbox に `step-completed` event emit
- atomic-green-impl が mailbox に `step-completed` event emit
- atomic-check が mailbox に `step-completed` event emit

3 step 全て PASS で次へ。1 件でも step-postverify-failed なら本 phaser fail (exit 1)。

## Step 2: specialist code review (LLM 自由判断)

`Agent(specialist-code-reviewer)` を呼び、coverage / bug / convention review。

verdict 判定 (atomic-verification.html §3.2 厳格 binary):
- "PASS" のみ通過
- "PASS" 以外 (FAIL/WARNING/unknown/空) → 全て fail、本 phaser exit 1

## Step 3: PR 作成 (hardcode + LLM 自由文、Refined → Implementing 専任、boundary-matrix.html I-1)

```bash
# branch push (worktree 前提、main 直接 push 禁止)
git push -u origin "$(git branch --show-current)"

# PR 作成 (LLM が title/body を AC + commit log から生成)
gh pr create --title "feat(...): ..." --body "..." --base main
PR_NUM=$(gh pr view --json number -q .number)
[ -n "$PR_NUM" ] || { echo "FATAL: PR_NUM empty (gh pr create/view failed)" >&2; exit 1; }
```

## Step 4: status 遷移 Refined → Implementing (hardcode、boundary-matrix.html I-1)

```bash
# Cluster 5 wire 予定: ITEM_ID / STATUS_FIELD_ID / IMPLEMENTING_OPTION_ID resolve
# TODO(Cluster 5): 以下を gh CLI で resolve:
#   ITEM_ID = gh project item-list で Issue から item ID 取得
#   STATUS_FIELD_ID = gh project field-list で Status field ID 取得
#   IMPLEMENTING_OPTION_ID = field option list で "Implementing" の option ID 取得
# 現状 Phase 1 PoC C4 では configuration として placeholder、本格 wire は C5 で実装

PROJECT_NUM=$(yq '.["project-board"].number' plugins/twl/refs/project-links.yaml)
# Cluster 5 で展開: gh project item-edit --project-id "$PROJECT_NUM" --owner shuu5 --id "$ITEM_ID" --field-id "$STATUS_FIELD_ID" --single-select-option-id "$IMPLEMENTING_OPTION_ID"
```

## Step 5: phase-completed mail emit (hardcode、flock atomic、Inv T)

```bash
# mailbox_emit (Cluster 2 lib/mailbox.sh、flock -x atomic write、Inv T 準拠)
mailbox_emit "$TWL_PHASER_NAME" "administrator" "phase-completed" \
  "$(jq -nc --argjson issue "$ISSUE_NUM" --argjson pr "$PR_NUM" \
     '{issue: $issue, status: "Implementing", pr_number: $pr, phase: "phaser-impl"}')"
echo "PASS"
```

## 失敗時 escalate (hardcode、flock atomic)

```bash
# Step 1/2/3/4 で fail 時、escalate mail を administrator に emit
# FAIL_REASON は呼び出し step が "step1-workflow-fail" / "step2-specialist-fail" / "step3-pr-fail" / "step4-status-fail" 等を明示
FAIL_REASON="${FAIL_REASON:-unspecified}"
mailbox_emit "$TWL_PHASER_NAME" "administrator" "phase-failed" \
  "$(jq -nc --argjson issue "$ISSUE_NUM" --arg reason "$FAIL_REASON" \
     '{issue: $issue, phase: "phaser-impl", reason: $reason}')"
exit 1
```

## 関連 spec
- boundary-matrix.html (10 role boundary、phaser scope)
- spawn-protocol.html §3 (TWL_PHASER_NAME env 注入)
- gate-hook.html §1 (PreToolUse gate tier 1+2 で前提 status verify、Inv W)
- atomic-verification.html §3.1-§3.2 (mailbox identifier + "PASS" 厳格 binary)
- admin-cycle.html §3 (administrator polling cycle、本 phaser spawn 元)
- hooks-mcp-policy.html §5 (PostToolUseFailure auto-learn 連携)
