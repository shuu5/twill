## Why

`cli/twl/tests/autopilot/test_merge_gate_phase_review.py` は 644 行で CRITICAL 閾値（500 行）を超過しており、可読性と保守性が低下している。クラス単位でファイルを分割することで、各テストの責務を明確化する。

## What Changes

- `test_merge_gate_phase_review.py`（644 行）を 3 ファイルに分割する
  - `test_phase_review_checkpoint.py`: `TestPhaseReviewCheckpointPresence` + `TestPhaseReviewCheckpointSkipLabels`（~280 行）
  - `test_phase_review_guard.py`: `TestPhaseReviewCriticalFindings` + `TestPhaseReviewForceWarning`（~300 行）
  - `test_merge_gate_integration.py`: `TestMergeGateExecuteIntegration`（~70 行）
- 重複する fixture があれば `conftest.py` へ移動する
- 元のファイル `test_merge_gate_phase_review.py` を削除する

## Capabilities

### New Capabilities

なし（テストコードのリファクタリングのみ）

### Modified Capabilities

- テストファイルの分割による可読性向上
- 各ファイルが単独で `pytest <file>` 実行可能になる

## Impact

- 影響範囲: `cli/twl/tests/autopilot/` ディレクトリ
- `pyproject.toml` や CI scripts で特定ファイルを参照している箇所は更新が必要
- テスト動作・カバレッジへの変更なし
