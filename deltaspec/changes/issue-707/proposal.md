## Why

`autopilot-orchestrator.sh` の `inject_next_workflow()` が Worker の chain 実行中に `resolve_next_workflow` を連続呼び出しして失敗（13回）し、Worker が terminal step に到達後も tmux capture-pane による prompt 検出が脆弱で inject タイムアウトが10回連続発生する。sandbox テストで検出され、observer の手動介入なしでは自律動作が阻害される。

## What Changes

- `plugins/twl/scripts/autopilot-orchestrator.sh` の `inject_next_workflow()` (L882-991) を修正
  - `resolve_next_workflow` の exit=1 (non-terminal step) を TRACE レベル、予期せぬエラーを WARNING レベルに分離
  - tmux capture-pane + regex の prompt 検出を `session-state.sh` ベースの `input-waiting` 検出に置換
  - prompt 検出リトライに exponential backoff (2s, 4s, 8s) を適用

## Capabilities

### New Capabilities

- **ログ分離**: `RESOLVE_NOT_READY` (non-terminal) と `RESOLVE_ERROR` (unexpected) をカテゴリ別に trace ログへ記録。正常な待機と異常を明確に区別できる
- **input-waiting 確実検出**: `session-state.sh state` で `input-waiting` を判定することで、Claude Code TUI の `❯` 表示との競合を排除
- **exponential backoff**: 長時間 processing（specialist 並列実行など）に対応した 2s→4s→8s の段階的待機

### Modified Capabilities

- **inject_next_workflow ログ出力**: WARNING→TRACE 降格（non-terminal step の場合）。`INJECT_TIMEOUT` / `INJECT_SUCCESS` カテゴリも追加

## Impact

- `plugins/twl/scripts/autopilot-orchestrator.sh`: `inject_next_workflow()` (L882-991) の修正
- テスト: sandbox テストで orchestrator が Worker の terminal step 到達後に正常に inject できることを確認
- 依存: #708 (session-state.sh の false positive 解消) が前提
