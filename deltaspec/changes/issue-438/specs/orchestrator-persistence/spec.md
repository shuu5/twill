## ADDED Requirements

### Requirement: orchestrator nohup 実行
orchestrator polling loop は Pilot の Bash context 外で持続的に実行されなければならない（SHALL）。Pilot が新しいメッセージを受信しても orchestrator プロセスは停止してはならない。

#### Scenario: Pilot がメッセージを受信しても orchestrator が継続する
- **WHEN** Pilot が orchestrator 起動後に新しいユーザーメッセージを受信する
- **THEN** orchestrator プロセスは停止せず polling loop を継続し、`inject_next_workflow()` が正常に呼ばれる

#### Scenario: orchestrator PID がトレースログに記録される
- **WHEN** Pilot が orchestrator を nohup/disown で起動する
- **THEN** orchestrator の PID と起動時刻が `.autopilot/trace/orchestrator-phase-{N}.log` に記録される

## MODIFIED Requirements

### Requirement: inject_next_workflow 実行結果のトレース記録
`inject_next_workflow()` の実行結果（成功/失敗/理由）は `.autopilot/trace/inject-{YYYYMMDD}.log` に記録されなければならない（MUST）。silent fail を排除する。

#### Scenario: inject 成功時にトレースが記録される
- **WHEN** `inject_next_workflow()` が `/twl:workflow-test-ready` を Worker に inject する
- **THEN** `.autopilot/trace/inject-{YYYYMMDD}.log` に `result=success` エントリが追記される

#### Scenario: inject 失敗時（resolve 失敗）にトレースが記録される
- **WHEN** `resolve_next_workflow` が exit code 1 で失敗する
- **THEN** `.autopilot/trace/inject-{YYYYMMDD}.log` に `result=skip reason="resolve_next_workflow exit=1"` エントリが追記される

#### Scenario: inject 失敗時（prompt 未検出）にトレースが記録される
- **WHEN** tmux pane の prompt 検出が3回リトライ後タイムアウトする
- **THEN** `.autopilot/trace/inject-{YYYYMMDD}.log` に `result=timeout reason="prompt not found"` エントリが追記される
