## Why

`issue-lifecycle-orchestrator.sh` のポーリングループで、`session-state.sh` の false positive（#708）による `input-waiting` 誤検出を即座に inject してしまい、debounce がないため transient な誤検出を全て消費して `inject_exhausted` に到達する。inject 上限が 3 回と低く、false positive 消費後に本来必要な inject が送れなくなる。

## What Changes

- `input-waiting` 検出後に 5 秒の debounce（再確認待ち）を追加し、transient false positive を排除する
- inject 上限を 3 → 5 に緩和する
- inject 間に progressive delay（`sleep $((5 * inject_count))`）を適用する
- inject 実行直前に session-state.sh で再確認し、`input-waiting` でなければスキップする
- inject メッセージを簡潔化（「処理を続行してください。」）

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- **issue-lifecycle-orchestrator.sh inject ロジック**: debounce・上限緩和・progressive delay・pre-inject 再確認・メッセージ簡素化による inject_exhausted 発生防止

## Impact

- `plugins/twl/scripts/issue-lifecycle-orchestrator.sh` L370-L419（inject ロジック）のみ変更
- `autopilot-orchestrator.sh` および `session-state.sh` は変更しない（各自 #707/#708 で対応済み）
