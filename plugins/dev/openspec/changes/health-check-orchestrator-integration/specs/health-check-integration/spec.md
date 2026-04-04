## ADDED Requirements

### Requirement: health-check 定期呼び出し
orchestrator の `poll_single()` と `poll_phase()` は、`running` 状態の Issue に対して HEALTH_CHECK_INTERVAL（デフォルト 6）回のポーリングに 1 回、`health-check.sh` を呼び出さなければならない（SHALL）。

#### Scenario: health-check が定期実行される
- **WHEN** poll カウンタが HEALTH_CHECK_INTERVAL の倍数に達した
- **THEN** `health-check.sh --issue <issue> --window <window>` が実行される

#### Scenario: crash-detect 後は health-check をスキップする
- **WHEN** `crash-detect.sh` が exit 2 を返した
- **THEN** 同じポーリングサイクルで health-check を実行してはならない（MUST NOT）

### Requirement: health-check 検知時の汎用 nudge
health-check が異常を検知した（exit 1 かつ stderr なし）場合、orchestrator は汎用 Enter nudge を送信しなければならない（SHALL）。ただし `NUDGE_COUNTS` が `MAX_NUDGE` 以上の場合を除く。

#### Scenario: stall 検知時に nudge が送信される
- **WHEN** health-check が exit 1 を返し、かつ stderr が空であり、かつ `NUDGE_COUNTS[$issue]` が `MAX_NUDGE` 未満である
- **THEN** `tmux send-keys` で空の Enter nudge が送信され、`NUDGE_COUNTS[$issue]` がインクリメントされる

#### Scenario: health-check 引数エラーはスキップされる
- **WHEN** health-check が exit 1 を返し、かつ stderr に出力がある
- **THEN** nudge を送信せず処理をスキップする（MUST）

#### Scenario: check_and_nudge が優先される
- **WHEN** check_and_nudge がパターンマッチに成功した
- **THEN** health-check による追加の nudge を送信してはならない（MUST NOT）

### Requirement: nudge 上限到達時の failed 遷移
`NUDGE_COUNTS[$issue]` が `MAX_NUDGE` に達した状態で health-check が異常を検知した場合、orchestrator は `status=failed` に遷移しなければならない（SHALL）。

#### Scenario: nudge 上限到達で failed に遷移する
- **WHEN** health-check が異常を検知し、かつ `NUDGE_COUNTS[$issue]` が `MAX_NUDGE` 以上である
- **THEN** `state-write.sh` で `status=failed`、`failure.message=health_check_stall` が書き込まれる

## MODIFIED Requirements

### Requirement: health-check.sh の status 遷移制限の緩和
`openspec/changes/autopilot-proactive-monitoring/specs/health-check.md` の仕様を更新しなければならない（SHALL）。

#### Scenario: orchestrator 経由での failed 遷移が許可される
- **WHEN** orchestrator が health-check 検知 + nudge 上限到達を判定した
- **THEN** orchestrator は `status=failed` に遷移してよい（MAY）（「health-check.sh 自身が遷移してはならない（MUST NOT）」という制約は維持される）
