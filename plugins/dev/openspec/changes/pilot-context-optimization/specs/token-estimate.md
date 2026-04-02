## ADDED Requirements

### Requirement: postprocess の token_estimate を session.json に記録

`autopilot-phase-postprocess.md` は postprocess 開始・終了の経過時間をベースに `token_estimate` を計算し、session.json の retrospective エントリに記録しなければならない（MUST）。

#### Scenario: postprocess 完了時に token_estimate が記録される
- **WHEN** `autopilot-phase-postprocess.md` が全ステップ（collect → retrospective → patterns → cross-issue）を完了する
- **THEN** session.json の当該 Phase の retrospective エントリに `token_estimate: <秒数>` が追記される

#### Scenario: 経過時間ベースの推定値が記録される
- **WHEN** postprocess の開始時に `START_TIME=$(date +%s)` が記録され、完了時に `END_TIME=$(date +%s)` が記録される
- **THEN** `token_estimate = END_TIME - START_TIME`（秒）が session.json に書き込まれる

#### Scenario: 異常な長時間処理の検出に利用できる
- **WHEN** postprocess が異常に長い時間（例: 300秒以上）実行された場合
- **THEN** session.json の `token_estimate` からその異常を事後に検出できる
