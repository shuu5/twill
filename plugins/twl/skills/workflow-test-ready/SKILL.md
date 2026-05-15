---
name: twl:workflow-test-ready
description: |
  workflow-test-ready: RED test 生成 → GREEN 実装 → check の 3 atomic 順次実行 launcher。
  phaser-impl から Skill() で呼ばれる disable-model-invocation workflow。
  TDD mental model: RED → GREEN を本 workflow 内で完了 (ADR-039 + Inv U)。

  Use when phaser-impl: needs to run TDD RED → GREEN → CHECK cycle.
type: workflow
effort: medium
disable-model-invocation: true
allowed-tools: [Bash, Read, Skill]
spawnable_by:
  - phaser-impl
---

# workflow-test-ready (Phase 1 PoC 新 architecture rewrite 2026-05-15)

3 atomic 順次実行 launcher (atomic-test-scaffold → atomic-green-impl → atomic-check)。
旧 chain-runner.sh 依存を廃止、atomic SKILL.md 本文 inline 実装に migrate (Inv U 新 text)。

## TDD mental model (MUST READ)

本 workflow は TDD の **RED → GREEN を完了** させる (ADR-039 + Inv U):

- **RED**: atomic-test-scaffold が AC から生成した test が fail する状態 = 正常 (実装の起点)
- **GREEN**: atomic-green-impl で実装、RED test を GREEN にする
- **CHECK**: atomic-check で lint + type-check 確認

**禁止 (MUST NOT)**:
- test 削除
- assertion 弱める (pass しやすいよう条件を緩める)
- 全 PASS 状態で実装飛ばし
- **test-scaffold 直後 (RED 状態) で PR 作成** (`pre-bash-pre-pr-gate.sh` で機械 block、ADR-039)

## 前提 (phaser-impl から Skill 呼び出し時)

- `TWL_PHASER_NAME` env 注入済 (atomic-verification.html §3.1)
- AC file path が `$ARGUMENTS[0]` で渡される (e.g., `.autopilot/issues/issue-<N>/ac-test-mapping.yaml`)

## Step 0: argument resolve (hardcode、Phase 6 review C-3 fix)

```bash
# $ARGUMENTS[0] → $AC_FILE_PATH 代入 (disable-model-invocation: true なので明示 hardcode 必須)
AC_FILE_PATH="${1:-}"
[ -n "$AC_FILE_PATH" ] || { echo "FATAL: AC_FILE_PATH not provided (\$ARGUMENTS[0])" >&2; exit 1; }
[ -n "$TWL_PHASER_NAME" ] || { echo "FATAL: TWL_PHASER_NAME unset" >&2; exit 1; }
```

## Step 1: atomic-test-scaffold (RED test 生成)

`Skill(twl:atomic-test-scaffold, "$AC_FILE_PATH")` を呼ぶ。

atomic-test-scaffold の 4-phase:
- Step 0: test count + src diff snapshot
- Step 1 (LLM 自由): AC を Read、RED test を tests/unit/ に生成
- Step 2: test count 増加 + RED 確認 + src diff = 0 検証
- Step 3: mailbox に step-completed event emit (`TWL_PHASER_NAME` 経由)

return verdict "PASS" 以外 → 本 workflow も exit 1 (atomic-verification.html §3.2 厳格 binary)。

## Step 2: atomic-green-impl (実装、RED → GREEN)

`Skill(twl:atomic-green-impl)` を呼ぶ。

atomic-green-impl の 4-phase:
- Step 0: src files + RED count baseline
- Step 1 (LLM 自由): src/ に実装 Write/Edit、RED test を GREEN にする (tests/ 編集禁止)
- Step 2: src diff > 0 + RED 数減少 + 全 PASS 検証
- Step 3: mailbox に step-completed event emit

return verdict "PASS" 以外 → 本 workflow も exit 1。

## Step 3: atomic-check (lint + type-check)

`Skill(twl:atomic-check)` を呼ぶ。

atomic-check の 4-phase:
- Step 0: project manifest verify
- Step 1 (LLM 自由): lint command 実行 + minor fix
- Step 2: lint exit 0 検証
- Step 3: mailbox に step-completed event emit

return verdict "PASS" 以外 → 本 workflow も exit 1。

## 完了

3 atomic 全 PASS で本 workflow 完了。phaser-impl が次 step (specialist code review + PR 作成) に進む。

## 関連 spec
- atomic-verification.html §3 / §4 (atomic 3 件 inline 実装 standard、verify rule)
- Inv U (Atomic skill verification、invariant-fate-table.html)
- ADR-039 (RED-only PR 禁止、test-scaffold 直後 PR 禁止)
- boundary-matrix.html (workflow scope、phaser-impl から spawn)
