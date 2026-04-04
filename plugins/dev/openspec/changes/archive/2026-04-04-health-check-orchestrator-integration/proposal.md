## Why

`health-check.sh`（Worker 論理的異常検知）は実装済み・テスト済みであるにもかかわらず、`autopilot-orchestrator.sh` から一度も呼び出されておらず孤立している。既存の `check_and_nudge()` は5パターンの固定マッチングに頼るため、パターン外の stall（例: pr-cycle の specialist output パース後の停止）を検知できず、autopilot が最大60分間気づかないという問題が発生している。

## What Changes

- `autopilot-orchestrator.sh` の `poll_single()` に health-check 呼び出しを追加（60秒間隔）
- `poll_phase()` にも同様の health-check 統合を追加
- health-check 検知時の汎用 Enter nudge エスカレーション実装（`NUDGE_COUNTS` 共有）
- nudge 上限到達時の `status=failed` 遷移実装
- `HEALTH_CHECK_COUNTER` 連想配列の追加
- `openspec/changes/autopilot-proactive-monitoring/specs/health-check.md` L55 の仕様更新
- `tests/bats/scripts/autopilot-orchestrator.bats` に統合テスト追加

## Capabilities

### New Capabilities

- **汎用 stall 検知**: `check_and_nudge()` パターン外の stall を health-check.sh（時間ベース）で検知可能になる
- **自動エスカレーション**: health-check 検知時に汎用 Enter nudge を送信し、nudge 上限到達時に `status=failed` へ遷移する

### Modified Capabilities

- **orchestrator ポーリング**: `running` 分岐に health-check が組み込まれ、60秒ごとに Worker の論理的異常を検知する
- **openspec 仕様**: health-check.sh の `status=failed` 遷移禁止（MUST NOT）が条件付き許可（MAY）に変更される

## Impact

- `scripts/autopilot-orchestrator.sh`: `poll_single()`・`poll_phase()` に変更
- `openspec/changes/autopilot-proactive-monitoring/specs/health-check.md`: L55 の仕様記述変更
- `tests/bats/scripts/autopilot-orchestrator.bats`: 統合テスト追加
- `scripts/health-check.sh`: 変更なし（既に完成済み）
- `scripts/state-write.sh`: 変更なし（#184 前提済み）
