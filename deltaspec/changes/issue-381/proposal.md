## Why

`chain-runner.sh` の `step_next_step()` は `QUICK_SKIP_STEPS` のみを参照し、`DIRECT_SKIP_STEPS` を参照していない。`mode=direct` が state に書き込まれても、Bash 実行経路では `change-propose`・`change-id-resolve`・`change-apply` がスキップされず、Python `chain.py` との動作不一致が発生する。

## What Changes

- `plugins/twl/scripts/chain-runner.sh`
  - `step_next_step()`: `is_quick` チェックに加え `mode=direct` かつ `DIRECT_SKIP_STEPS` に含まれるステップをスキップするロジックを追加
  - `step_chain_status()`: 表示ループに `DIRECT_SKIP_STEPS` スキップ判定を追加（`(skipped/direct)` ラベル付き）

## Capabilities

### New Capabilities

なし

### Modified Capabilities

- `mode=direct` 時、`change-propose`・`change-id-resolve`・`change-apply` ステップが `step_next_step()` でスキップされる（Python `chain.py` と同一動作）
- `chain-status` コマンドが `mode=direct` 時のスキップステップを `⊘ ... (skipped/direct)` で正しく表示する

## Impact

- `plugins/twl/scripts/chain-runner.sh`（`step_next_step` と `step_chain_status` の 2 関数のみ）
