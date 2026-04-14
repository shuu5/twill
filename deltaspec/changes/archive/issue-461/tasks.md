## 1. 共通 fixture の conftest.py 移動

- [x] 1.1 `cli/twl/tests/autopilot/conftest.py` に `autopilot_dir`, `scripts_root`, `gate`, `gate_force` fixture を追記する
- [x] 1.2 `_phase_review_json`, `_write_phase_review` ヘルパー関数を `conftest.py` に追記する

## 2. テストファイルの分割作成

- [x] 2.1 `test_phase_review_checkpoint.py` を作成し、`TestPhaseReviewCheckpointPresence` と `TestPhaseReviewCheckpointSkipLabels` を移動する
- [x] 2.2 `test_phase_review_guard.py` を作成し、`TestPhaseReviewCriticalFindings` と `TestPhaseReviewForceWarning` を移動する
- [x] 2.3 `test_merge_gate_integration.py` を作成し、`TestMergeGateExecuteIntegration` を移動する

## 3. 元ファイルの削除と CI 確認

- [x] 3.1 `test_merge_gate_phase_review.py` を削除する
- [x] 3.2 `pyproject.toml` と CI scripts で旧ファイルへの参照がないか確認・更新する（archive のみ、更新不要）

## 4. 動作確認

- [x] 4.1 `pytest cli/twl/tests/autopilot/test_phase_review_checkpoint.py` が単独で全 PASS することを確認する
- [x] 4.2 `pytest cli/twl/tests/autopilot/test_phase_review_guard.py` が単独で全 PASS することを確認する
- [x] 4.3 `pytest cli/twl/tests/autopilot/test_merge_gate_integration.py` が単独で全 PASS することを確認する
- [x] 4.4 `pytest cli/twl/tests/autopilot/` が分割前と同じ PASS 数・テスト名で完全一致することを確認する
