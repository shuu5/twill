## Context

`plugins/twl/deps.yaml` は deps.yaml SSOT 原則によりコンポーネントのメタデータ（spawnable_by など）の単一信頼源として機能する。`co-autopilot` の `spawnable_by` が SKILL.md frontmatter（`[user, su-observer]`）と乖離している。修正は deps.yaml の 1 行変更のみで完結する。

## Goals / Non-Goals

**Goals:**
- deps.yaml の co-autopilot エントリ `spawnable_by` を `[user, su-observer]` に修正し、SKILL.md frontmatter と一致させる
- `twl check` PASS を確認する

**Non-Goals:**
- `su-observer` の `can_spawn` フィールドへの `controller` 追加（別 Issue 対応）
- `ref-types.md` の supervisor 型未記載問題（別途検討）

## Decisions

**D1: deps.yaml のみ修正、SKILL.md は変更しない**
- SKILL.md の `spawnable_by: [user, su-observer]` は ADR-014 準拠の正典
- deps.yaml を正典に合わせることで SSOT 原則を維持

**D2: 変更は 1 行のみ**
- `plugins/twl/deps.yaml` L141 付近の `spawnable_by: [user]` を `spawnable_by: [user, su-observer]` に変更

## Risks / Trade-offs

- リスクなし（1 行変更、既存動作に影響しない）
- `twl check` が PASS することを確認することで回帰を防止
