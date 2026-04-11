## MODIFIED Requirements

### Requirement: Pilot PHASE_COMPLETE Polling with ScheduleWakeup

Pilot は orchestrator 起動後、PHASE_COMPLETE を `grep` で一括待機する bash while ループの代わりに ScheduleWakeup ベースの能動確認サイクルを使用しなければならない（SHALL）。wake-up 間隔は 300 秒（5 分）とする。

#### Scenario: PHASE_COMPLETE 検知
- **WHEN** ScheduleWakeup wake-up 時に `orchestrator-phase-N.log` に `PHASE_COMPLETE` が含まれる
- **THEN** Pilot は PHASE_COMPLETE 受信として Step 4.5 に進む

#### Scenario: wake-up 時に PHASE_COMPLETE 未検知
- **WHEN** ScheduleWakeup wake-up 時に PHASE_COMPLETE が未検知
- **THEN** Pilot は全 Worker の state file を読んで状態と `updated_at` を確認し、stagnation チェックを行った上で次の ScheduleWakeup(300) をスケジュールする

#### Scenario: polling タイムアウト
- **WHEN** ScheduleWakeup サイクルが `MAX_WAIT_MINUTES`（デフォルト: 30 分）を超過
- **THEN** Pilot は単純再スケジュールせず状況精査モードに入る（下記 Requirement 参照）

## ADDED Requirements

### Requirement: Worker State Stagnation Detection in Pilot

Pilot は wake-up 時に、`updated_at` が `STAGNATION_THRESHOLD`（デフォルト: 15 分）以上古い Worker を stall とみなして報告しなければならない（MUST）。

#### Scenario: stagnation 検知
- **WHEN** Worker の state file `updated_at` が現在時刻から 15 分以上前の値
- **THEN** Pilot は対象 Worker を stall としてログ出力し、orchestrator の nudge channel（`session-comm.sh inject-file`）経由で回復信号を送信する

#### Scenario: stagnation なし
- **WHEN** 全 Worker の `updated_at` が STAGNATION_THRESHOLD 以内
- **THEN** Pilot は通常通り次の ScheduleWakeup をスケジュールする

### Requirement: Pilot Post-Timeout Diagnosis Mode

Pilot は PHASE_COMPLETE 待機タイムアウト後に、状況を精査して自律的にフェーズを進行または失敗確定しなければならない（MUST）。

#### Scenario: 全 Worker が terminal 状態
- **WHEN** タイムアウト時に全 Worker が merge-ready / done / failed のいずれか
- **THEN** Pilot は PHASE_COMPLETE 相当として Step 4.5 に進む（orchestrator からの signal を待たない）

#### Scenario: stalled Worker が存在
- **WHEN** タイムアウト時に `status=stalled` または `updated_at` が STAGNATION_THRESHOLD 超過の Worker が存在
- **THEN** Pilot は stalled Worker に回復信号を送信し、追加 10 分の猶予後に再評価する

#### Scenario: 猶予後も stall 継続
- **WHEN** 追加猶予後も Worker が stall 状態
- **THEN** Pilot は当該 Worker を failed として記録し、Phase を次に進める

### Requirement: orchestrator.py Worker Stagnation Detection

`orchestrator.py` の `_poll_single` および `_poll_phase` は、Worker の `updated_at` が `STAGNATION_THRESHOLD` を超えた場合に stall 判定を行わなければならない（SHALL）。

#### Scenario: stagnation 検知（_poll_single）
- **WHEN** _poll_single の running ループ中に Worker の `updated_at` が STAGNATION_THRESHOLD 以上古い
- **THEN** orchestrator は stall nudge を送信し、`stagnation_nudge_count` を incrementする。`MAX_STAGNATION_NUDGE`（デフォルト: 3）を超えた場合は `status=failed` に遷移する

#### Scenario: stagnation 検知（_poll_phase）
- **WHEN** _poll_phase の running ループ中に任意 Worker の `updated_at` が STAGNATION_THRESHOLD 以上古い
- **THEN** orchestrator は当該 Worker に対して stall nudge を送信し、カウント管理する

#### Scenario: stagnation なし
- **WHEN** Worker の `updated_at` が STAGNATION_THRESHOLD 以内
- **THEN** stagnation チェックはスキップし、既存の _check_and_nudge に処理を委譲する

### Requirement: STAGNATION_THRESHOLD 環境変数オーバーライド

`orchestrator.py` の `STAGNATION_THRESHOLD` は環境変数 `DEV_AUTOPILOT_STAGNATION_THRESHOLD` でオーバーライドできなければならない（SHALL）。デフォルト値は 900（秒）とする。

#### Scenario: 環境変数設定あり
- **WHEN** `DEV_AUTOPILOT_STAGNATION_THRESHOLD=300` が設定された状態で orchestrator が起動
- **THEN** stagnation 判定閾値が 300 秒になる

#### Scenario: 環境変数設定なし
- **WHEN** `DEV_AUTOPILOT_STAGNATION_THRESHOLD` が未設定
- **THEN** STAGNATION_THRESHOLD = 900 秒（デフォルト）が使用される
