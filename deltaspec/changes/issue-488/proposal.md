## Why

`plugins/twl/deps.yaml` の co-autopilot エントリ `spawnable_by` が `[user]` のみとなっており、`plugins/twl/skills/co-autopilot/SKILL.md` frontmatter の `spawnable_by: [user, su-observer]` と不一致。ADR-014 Decision 2 で su-observer が co-autopilot を `session:spawn` 経由で起動することが正規フローとして定義されているため、deps.yaml が SSOT 原則に違反している。

## What Changes

- `plugins/twl/deps.yaml` の co-autopilot エントリ（L141 付近）の `spawnable_by` を `[user]` → `[user, su-observer]` に更新する

## Capabilities

### New Capabilities

なし（機能追加なし）

### Modified Capabilities

- **co-autopilot の spawnable_by**: `su-observer` が deps.yaml にも正式に登録され、ADR-014 準拠の spawn フローが deps.yaml レベルで明示される

## Impact

- `plugins/twl/deps.yaml`: co-autopilot エントリの `spawnable_by` フィールド（1行変更）
- `twl check` の整合性チェックが PASS することを確認
- `twl update-readme` で README への反映が必要な場合は実行
