## Why

Claude Code セッションが長期化すると compaction が自動発火し、作業中の知識・状態が失われるリスクがある。ユーザーが明示的に知識外部化と compaction を制御できる `su-compact` コマンドが必要。

## What Changes

- `plugins/twl/commands/su-compact.md` (新規): 知識外部化 + compaction を実行する atomic/workflow コマンド
- `plugins/twl/deps.yaml`: su-compact エントリ追加

## Capabilities

### New Capabilities

- `/su-compact`: 状況自動判定で Long-term Memory 外部化 + compaction 実行
- `/su-compact --wave`: Wave 完了サマリ保存 + compaction
- `/su-compact --task`: タスク状態退避 + compaction
- `/su-compact --full`: 全知識外部化 + compaction

### Modified Capabilities

なし（新規追加のみ）

## Impact

- `plugins/twl/commands/su-compact.md`: 新規作成
- `plugins/twl/deps.yaml`: su-compact コンポーネント追加
- Memory MCP（doobidoo）: Long-term Memory 保存に使用
- `.supervisor/working-memory.md`: Working Memory 退避先
- 依存: externalize-state（SupervisorSession 状態書出）
