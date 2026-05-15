---
name: twl:atomic-green-impl
description: GREEN 実装 (RED test を PASS させる)。Step 0/2/3 hardcode + Step 1 LLM 自由生成 (atomic-verification.html §3 inline 実装 standard)。
disable-model-invocation: true
allowed-tools: [Bash, Read, Edit, Agent]
---

# atomic-green-impl

atomic skill (4-phase lifecycle、Inv U)。
atomic-test-scaffold が生成した RED test を GREEN にする (TDD GREEN phase)。
spec 参照: atomic-verification.html §3 / §4 verify rule。

## `Step 0` lifecycle phase: pre-check (hardcode、deterministic)

- !`[ -n "$TWL_PHASER_NAME" ] || { echo "FATAL: TWL_PHASER_NAME unset" >&2; exit 1; }`
- !`git ls-files src/ 2>/dev/null | wc -l > /tmp/pre_src_files_${TWL_PHASER_NAME}`
- !`bats tests/unit/ 2>&1 | grep -c "^not ok " > /tmp/pre_red_count_${TWL_PHASER_NAME} || echo 0 > /tmp/pre_red_count_${TWL_PHASER_NAME}`

## `Step 1` lifecycle phase: exec (LLM 自由生成)

- atomic-test-scaffold が生成した RED test を Read で確認
- `src/` 配下に実装を Write/Edit、RED test を GREEN にする
- **tests/ の編集禁止** (Step 2 で test 数不変 check、assertion 弱化禁止)

(機械検証は Step 2 が担う、LLM はここで判断/作業のみ)

## `Step 2` lifecycle phase: post-verify (hardcode、deterministic)

- !`SRC_DIFF=$(git diff --name-only HEAD | grep '^src/' | wc -l); [ "$SRC_DIFF" -gt 0 ] || { echo "FATAL: src/ not modified (green-impl で実装書いていない)" >&2; exit 1; }`
- !`PRE_RED=$(cat /tmp/pre_red_count_${TWL_PHASER_NAME}); POST_RED=$(bats tests/unit/ 2>&1 | grep -c "^not ok " || echo 0); [ "$POST_RED" -lt "$PRE_RED" ] || { echo "FATAL: RED test not reduced (PRE=$PRE_RED, POST=$POST_RED)" >&2; exit 1; }`
- !`POST_RED=$(bats tests/unit/ 2>&1 | grep -c "^not ok " || echo 0); [ "$POST_RED" -eq 0 ] || { echo "FATAL: RED test still exists ($POST_RED tests fail after GREEN)" >&2; exit 1; }`

## `Step 3` lifecycle phase: report (hardcode、deterministic)

- !`SRC_FILES=$(git diff --name-only HEAD | grep '^src/' | wc -l)`
- !`jq -nc --arg from "atomic-green-impl" --arg phaser "$TWL_PHASER_NAME" --arg ts "$(date -Iseconds)" --argjson src_changed "$SRC_FILES" '{from: $from, to: $phaser, ts: $ts, event: "step-completed", detail: {step: "green-impl", green: true, src_files_changed: $src_changed}}' >> .mailbox/$TWL_PHASER_NAME/inbox.jsonl`
- !`echo "PASS"`

## 関連 spec
- atomic-verification.html §3 (inline 実装 standard)
- atomic-verification.html §4 verify rule (green-impl: git diff src/ > 0 + bats 全 PASS)
- Inv U (Atomic skill verification)
- ADR-039 (RED → GREEN cycle 完了)
