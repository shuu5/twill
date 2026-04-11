## Why

Worker が実装完了後に `workflow_done=<stage>` を state ファイルへ書き込まずにテキスト出力のみで終了するため、orchestrator の `inject_next_workflow` が `workflow_done` を読めず next skill を resolve できない。Wave 1-5 を通じて毎回 1-2 件の Issue で 30-90 分の手動介入が必要となっている。

## What Changes

- `plugins/twl/scripts/chain-runner.sh`: chain 終端ステップで `state write --set workflow_done=<stage>` を必ず実行し、書き込み失敗時は exit 非ゼロで終了するよう修正する
- `plugins/twl/scripts/autopilot-orchestrator.sh`: `check_and_nudge` 関数（または新規 `detect_completion_marker`）に `>>> 実装完了: issue-<N>` パターン検知 fallback を追加し、検知時に orchestrator 自身が `workflow_done` を書き込んで `inject_next_workflow` を呼ぶ
- stagnate 閾値を `AUTOPILOT_STAGNATE_SEC`（デフォルト 600s）環境変数に一元化し、#472 / #475 と共有

## Capabilities

### New Capabilities

- orchestrator が pane 出力の `>>> 実装完了: issue-<N>` を検知して `workflow_done` を強制書き込みする fallback 機能
- inject skip イベントが連続 3 回（`AUTOPILOT_STAGNATE_SEC` 超過）で orchestrator が WARN を出力し Supervisor に stagnate を通知する機能
- E2E テスト: Worker が `workflow_done` を書かずに終了した場合の orchestrator recovery シナリオ

### Modified Capabilities

- chain-runner.sh の chain 終端: `workflow_done` 書き込みが保証されるよう必須化

## Impact

- `plugins/twl/scripts/autopilot-orchestrator.sh`（`check_and_nudge` / `inject_next_workflow` 周辺）
- `plugins/twl/scripts/chain-runner.sh`（chain step 終端 workflow_done 書き込み）
- `cli/twl/src/twl/autopilot/resolve_next_workflow.py`（影響範囲確認のみ、変更なし想定）
- `tests/scenarios/` または pytest integration（新規 E2E シナリオ追加）
