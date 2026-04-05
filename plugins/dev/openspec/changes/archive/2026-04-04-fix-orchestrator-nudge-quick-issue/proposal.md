## Why

`autopilot-orchestrator.sh` の `_nudge_command_for_pattern` が quick ラベルを考慮せず、"setup chain 完了" パターン検出時に一律 `/dev:workflow-test-ready` を nudge として送信するため、quick Issue の Worker が不要な test-ready → pr-cycle チェーンを実行してしまう。

## What Changes

- `_nudge_command_for_pattern` の冒頭に `is_quick` 判定を追加し、quick Issue では test-ready 系 nudge を送信しない（`return 1`）
- `is_quick` は `state-read.sh --field is_quick` でキャッシュから読み取り。未永続化時は `detect_quick_label()` の fallback で対応
- `orchestrator-nudge.bats` に quick Issue シナリオのテストを追加

## Capabilities

### New Capabilities

- quick Issue 判定ロジック: `_nudge_command_for_pattern` が呼ばれた際に issue の `is_quick` フラグを確認する

### Modified Capabilities

- `_nudge_command_for_pattern`（autopilot-orchestrator.sh L365-381）: quick Issue の場合、test-ready 系パターンへの nudge をスキップ

## Impact

- `scripts/autopilot-orchestrator.sh`: `_nudge_command_for_pattern` 関数の修正
- `tests/orchestrator-nudge.bats`: quick Issue シナリオのテスト追加
- `scripts/state-read.sh`: `is_quick` フィールド読み取り（既存機能の活用）
