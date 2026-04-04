## 1. orchestrator.sh の準備

- [x] 1.1 `declare -A HEALTH_CHECK_COUNTER=()` を NUDGE_COUNTS と同行に追加（L382 付近）

## 2. poll_single() への health-check 統合

- [x] 2.1 `poll_single()` の `running` 分岐（L275-286）に health-check カウンタ処理を追加
- [x] 2.2 crash-detect exit 2 後は health-check をスキップするよう分岐を修正
- [x] 2.3 check_and_nudge の後に health-check 呼び出しブロックを追加（HEALTH_CHECK_INTERVAL=6 間隔）
- [x] 2.4 health-check 検知（exit 1 + stderr なし）時の汎用 Enter nudge 送信実装
- [x] 2.5 NUDGE_COUNTS が MAX_NUDGE 以上の場合の status=failed 遷移実装

## 3. poll_phase() への health-check 統合

- [x] 3.1 `poll_phase()` の `running` 分岐（L322-330）に HEALTH_CHECK_COUNTER 処理を追加
- [x] 3.2 crash-detect exit 2 後は health-check をスキップするよう修正
- [x] 3.3 check_and_nudge の後に health-check 呼び出しブロックを追加（poll_single と同一ロジック）
- [x] 3.4 health-check 検知時の nudge・failed 遷移を poll_single と同一ロジックで実装

## 4. openspec 仕様の更新

- [x] 4.1 `openspec/changes/autopilot-proactive-monitoring/specs/health-check.md` L55 の MUST NOT 記述を MAY（orchestrator 経由条件付き）に変更

## 5. テスト追加

- [x] 5.1 `tests/bats/scripts/autopilot-orchestrator.bats` に health-check 統合テストを追加
  - health-check 検知（exit 1 + stderr なし）時に nudge が送信されること
  - NUDGE_COUNTS が MAX_NUDGE 以上で status=failed に遷移すること
  - crash-detect（exit 2）後は health-check をスキップすること
  - health-check 引数エラー（exit 1 + stderr あり）時はスキップされること
  - check_and_nudge のパターン nudge が health-check より優先されること
