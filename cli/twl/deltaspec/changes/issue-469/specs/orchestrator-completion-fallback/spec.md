## MODIFIED Requirements

### Requirement: orchestrator 実装完了パターン検知 fallback

`plugins/twl/scripts/autopilot-orchestrator.sh` の `_nudge_command_for_pattern()` は pane 出力に `>>> 実装完了: issue-<N>` パターンを検知した場合、orchestrator 自身が Pilot role で `workflow_done=test-ready` を state に書き込み、`/twl:workflow-pr-verify #<N>` コマンドを返さなければならない（SHALL）。

#### Scenario: 実装完了パターン検知時に workflow_done を書き inject する
- **WHEN** Worker pane 出力が静止し、最終出力に `>>> 実装完了: issue-469` が含まれる
- **THEN** orchestrator が `state write --role pilot --set workflow_done=test-ready` を実行し、その後 tmux に `/twl:workflow-pr-verify #469` を inject する

#### Scenario: 既存パターンへの影響なし
- **WHEN** pane 出力が `setup chain 完了` を含む（既存パターン）
- **THEN** 従来通り `/twl:workflow-test-ready #<N>` が inject され、実装完了パターン処理は行われない

### Requirement: stagnate 閾値の環境変数一元化

`autopilot-orchestrator.sh` は stagnate 判定に `AUTOPILOT_STAGNATE_SEC`（デフォルト 600）環境変数を使用しなければならない（SHALL）。inject の RESOLVE_FAILED が連続して発生した場合（`AUTOPILOT_STAGNATE_SEC / POLL_INTERVAL` 回以上）、orchestrator は WARN を stderr に出力し Supervisor への通知を行わなければならない（SHALL）。

#### Scenario: 連続 RESOLVE_FAILED で WARN を出力する
- **WHEN** `inject_next_workflow` が `AUTOPILOT_STAGNATE_SEC / POLL_INTERVAL` 回連続で RESOLVE_FAILED になる
- **THEN** orchestrator が stderr に `[orchestrator] WARN: issue=<N> stagnate detected` を出力する
