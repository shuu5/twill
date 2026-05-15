---
name: twl:atomic-check
description: lint + type-check (linter / type-checker exit 0)。Step 0/2/3 hardcode + Step 1 LLM 自由 (lint command 実行) (atomic-verification.html §3 inline 実装 standard)。
disable-model-invocation: true
allowed-tools: [Bash, Read, Edit]
---

# atomic-check

atomic skill (4-phase lifecycle、Inv U)。
lint + type-check 実行、必要なら minor fix。
spec 参照: atomic-verification.html §3 / §4 verify rule (check: lint_clean: true)。

## `Step 0` lifecycle phase: pre-check (hardcode、deterministic)

- !`[ -n "$TWL_PHASER_NAME" ] || { echo "FATAL: TWL_PHASER_NAME unset" >&2; exit 1; }`
- !`test -f package.json -o -f pyproject.toml -o -f cli/twl/pyproject.toml -o -f Cargo.toml -o -f DESCRIPTION || { echo "FATAL: no project manifest found (package.json/pyproject.toml/Cargo.toml/DESCRIPTION)" >&2; exit 1; }`

## `Step 1` lifecycle phase: exec (LLM 自由)

- Project manifest を Read で確認 (package.json / pyproject.toml / Cargo.toml / DESCRIPTION)
- 適切な lint command を判断 (e.g., `npm run lint`、`uv --project cli/twl run ruff check .`、`cargo clippy`、`R CMD check`)
- lint command を実行、issue があれば minor fix (Edit/Write)

(機械検証は Step 2 が担う、LLM はここで lint command 実行のみ)

## `Step 2` lifecycle phase: post-verify (hardcode、deterministic、Phase 6 review W-3 fix)

- !`# 全 project manifest で lint 実行、いずれか fail なら全体 fail (&& 連結、monorepo partial pass 防止)`
- !`STATUS=0; [ -f package.json ] && { npm run lint 2>&1 || STATUS=1; }; [ -f cli/twl/pyproject.toml ] && { uv --project cli/twl run ruff check . 2>&1 || STATUS=1; }; [ -f Cargo.toml ] && { cargo clippy --no-deps 2>&1 || STATUS=1; }; [ "$STATUS" -eq 0 ] || { echo "FATAL: lint failed in one or more manifests" >&2; exit 1; }`

## `Step 3` lifecycle phase: report (hardcode、deterministic)

- !`jq -nc --arg from "atomic-check" --arg phaser "$TWL_PHASER_NAME" --arg ts "$(date -Iseconds)" '{from: $from, to: $phaser, ts: $ts, event: "step-completed", detail: {step: "check", lint_clean: true}}' >> .mailbox/$TWL_PHASER_NAME/inbox.jsonl`
- !`echo "PASS"`

## 関連 spec
- atomic-verification.html §3 (inline 実装 standard)
- atomic-verification.html §4 verify rule (check: linter / type-checker exit 0)
- Inv U (Atomic skill verification)
