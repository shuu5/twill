---
name: twl:atomic-test-scaffold
description: AC → RED test 生成。Step 0/2/3 hardcode + Step 1 LLM 自由生成 (atomic-verification.html §3 inline 実装 standard)。
disable-model-invocation: true
allowed-tools: [Bash, Read, Edit, Agent]
---

# atomic-test-scaffold

atomic skill (4-phase lifecycle、Inv U)。
spec 参照: atomic-verification.html §3 / §4 verify rule。

## `Step 0` lifecycle phase: pre-check (hardcode、deterministic)

- !`[ -n "$TWL_PHASER_NAME" ] || { echo "FATAL: TWL_PHASER_NAME unset (atomic-verification.html §3.1)" >&2; exit 1; }`
- !`bats --list tests/ 2>/dev/null | wc -l > /tmp/pre_test_count_${TWL_PHASER_NAME}`
- !`git diff --name-only HEAD | grep '^src/' | wc -l > /tmp/pre_src_diff_${TWL_PHASER_NAME}`
- !`mkdir -p ".mailbox/$TWL_PHASER_NAME"`

## `Step 1` lifecycle phase: exec (LLM 自由生成)

- Read `$ARGUMENTS[0]` (AC file path、e.g., `.autopilot/issues/issue-<N>/ac-test-mapping.yaml`)
- AC 内容に従い、RED test を `tests/unit/` 配下に Write/Edit で生成
- **src/ 配下の編集禁止** (Step 2 post-verify で src diff = 0 を check)

(機械検証は Step 2 が担う、LLM はここで判断/作業のみ)

## `Step 2` lifecycle phase: post-verify (hardcode、deterministic)

- !`POST=$(bats --list tests/ 2>/dev/null | wc -l); PRE=$(cat /tmp/pre_test_count_${TWL_PHASER_NAME}); [ "$POST" -gt "$PRE" ] || { echo "FATAL: test count not increased ($PRE → $POST)" >&2; exit 1; }`
- !`bats tests/unit/ 2>&1 | grep -q "^not ok " || { echo "FATAL: no RED test (all PASS、RED-only PR ADR-039 違反)" >&2; exit 1; }`
- !`SRC_DIFF=$(git diff --name-only HEAD | grep '^src/' | wc -l); [ "$SRC_DIFF" -eq 0 ] || { echo "FATAL: src/ modified ($SRC_DIFF files)、test-scaffold scope 違反" >&2; exit 1; }`

## `Step 3` lifecycle phase: report (hardcode、deterministic)

- !`RED_COUNT=$(($(bats --list tests/ | wc -l) - $(cat /tmp/pre_test_count_${TWL_PHASER_NAME})))`
- !`jq -nc --arg from "atomic-test-scaffold" --arg phaser "$TWL_PHASER_NAME" --arg ts "$(date -Iseconds)" --argjson red "$RED_COUNT" '{from: $from, to: $phaser, ts: $ts, event: "step-completed", detail: {step: "test-scaffold", red_count: $red}}' >> .mailbox/$TWL_PHASER_NAME/inbox.jsonl`
- !`echo "PASS"`

## 関連 spec
- atomic-verification.html §3 (inline 実装 standard、Step 0/2/3 hardcode + Step 1 LLM 自由)
- atomic-verification.html §3.1 (TWL_PHASER_NAME env 経由 mailbox identifier)
- atomic-verification.html §3.2 ("PASS" 以外 exit 1 厳格 binary)
- atomic-verification.html §4 verify rule (test-scaffold: test count 増加 + bats fail + src diff = 0)
- Inv U (Atomic skill verification、invariant-fate-table.html)
- ADR-039 (RED-only PR 禁止、test-scaffold 直後 PR 禁止)
