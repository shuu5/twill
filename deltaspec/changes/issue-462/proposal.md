## Why

`cli/twl/src/twl/autopilot/mergegate.py` は 954 行に達し、baseline CRITICAL 閾値（500 行）を超過している。単一ファイルに責務が集中しており、保守性・テスタビリティが低下している。

## What Changes

- `_check_worktree_guard`, `_check_worker_window_guard`, `_check_running_guard`, `_check_phase_review_guard` の 4 関数（`self` 依存なし）を新規モジュール `mergegate_guards.py` へ抽出（Phase A）
- `mergegate.py` から抽出関数を削除し、`mergegate_guards` からインポートへ変更
- テストファイル `test_merge_gate_phase_review.py` のインポートパスを `mergegate_guards` に更新
- `plugins/twl/deps.yaml` に新エントリ `autopilot-mergegate-guards` を追加
- Phase A 後の行数測定で 500 行超過が残る場合のみ Phase B（`_check_base_drift`, `_check_deps_yaml_conflict_and_rebase` の mixin 化）を実施

## Capabilities

### New Capabilities

- `twl.autopilot.mergegate_guards` モジュール: guard 関数群の独立したインポートが可能になる

### Modified Capabilities

- `MergeGate` クラスの公開 API（`execute`, `reject`, `reject_final`, `from_env`）のシグネチャ・動作は不変
- guard 関数は `mergegate.py` から再エクスポートしない（直接 `mergegate_guards` からインポート）

## Impact

- **変更ファイル**: `cli/twl/src/twl/autopilot/mergegate.py`（抽出元）
- **新規ファイル**: `cli/twl/src/twl/autopilot/mergegate_guards.py`
- **テスト更新**: `cli/twl/tests/autopilot/test_merge_gate_phase_review.py`（インポートパス変更）
- **設定更新**: `plugins/twl/deps.yaml`（`autopilot-mergegate-guards` エントリ追加）
- **既存テスト影響**: `cli/twl/tests/test_autopilot_mergegate.py` はインポートパス変更なし（`MergeGate` クラス自体は移動しない）
