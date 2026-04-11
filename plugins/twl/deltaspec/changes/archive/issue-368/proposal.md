## Why

su-observer SKILL.md の Step 4（Wave 管理）が NOTE プレースホルダーのみで、Wave 分割→co-autopilot spawn→observe→wave-collect→externalize-state→su-compact の完全なフローが未実装。Supervisor として Wave を自律実行するためのフローが必要。

## What Changes

- `plugins/twl/skills/su-observer/SKILL.md`: Step 4（Wave 管理）を NOTE プレースホルダーから完全な実装フロー（8ステップ）に差し替え。wave-collect と externalize-state の呼出順序・引数を明示。SU-6 制約との連携を明示。

## Capabilities

### New Capabilities

- su-observer が autopilot モードで Wave 管理を完全に実行できる（Wave 分割→spawn→observe→collect→compact の全サイクル）
- Wave 完了時に wave-collect で結果収集 → externalize-state --trigger wave_complete で状態外部化 → su-compact で compaction の順序が明示される

### Modified Capabilities

- Step 4 の Wave 管理が NOTE プレースホルダーから完全なフロー定義に昇格

## Impact

- `plugins/twl/skills/su-observer/SKILL.md`: Step 4 の書き換え（他ステップへの影響なし）
