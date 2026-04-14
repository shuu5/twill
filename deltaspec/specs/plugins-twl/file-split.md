## Requirements

### Requirement: テストファイル分割

`test_merge_gate_phase_review.py`（644 行）を責務ごとに 3 ファイルへ分割しなければならない（SHALL）。分割後のファイルはそれぞれ 500 行未満でなければならない（SHALL）。

#### Scenario: test_phase_review_checkpoint.py が作成される
- **WHEN** 分割作業が完了する
- **THEN** `test_phase_review_checkpoint.py` が存在し、`TestPhaseReviewCheckpointPresence` と `TestPhaseReviewCheckpointSkipLabels` を含む

#### Scenario: test_phase_review_guard.py が作成される
- **WHEN** 分割作業が完了する
- **THEN** `test_phase_review_guard.py` が存在し、`TestPhaseReviewCriticalFindings` と `TestPhaseReviewForceWarning` を含む

#### Scenario: test_merge_gate_integration.py が作成される
- **WHEN** 分割作業が完了する
- **THEN** `test_merge_gate_integration.py` が存在し、`TestMergeGateExecuteIntegration` を含む

#### Scenario: 元ファイルが削除される
- **WHEN** 分割作業が完了する
- **THEN** `test_merge_gate_phase_review.py` が存在しない

### Requirement: 共通 fixture の conftest.py 移動

共通 fixture（`autopilot_dir`, `scripts_root`, `gate`, `gate_force`）とヘルパー関数（`_phase_review_json`, `_write_phase_review`）を `conftest.py` に移動しなければならない（SHALL）。

#### Scenario: fixture が conftest.py で定義される
- **WHEN** 分割後に `pytest <any_split_file>` を単体実行する
- **THEN** fixture が解決され、テストが PASS する

### Requirement: テスト実行結果の完全一致

分割前後で `pytest cli/twl/tests/autopilot/` の結果が完全一致しなければならない（SHALL）。PASS 数・テスト名ともに変化がないこと。

#### Scenario: 全テストが PASS する
- **WHEN** 分割後に `pytest cli/twl/tests/autopilot/` を実行する
- **THEN** 分割前と同じ数・同じ名前のテストが全て PASS する

#### Scenario: 各ファイルが単独で実行可能
- **WHEN** 分割後に `pytest test_phase_review_checkpoint.py` を単体で実行する
- **THEN** そのファイル内のテストが全て PASS する（他 2 ファイルも同様）

### Requirement: CI 設定の更新

`pyproject.toml` や CI scripts で `test_merge_gate_phase_review.py` を参照している箇所があれば更新しなければならない（SHALL）。

#### Scenario: CI で特定ファイルが参照されている場合に更新される
- **WHEN** `pyproject.toml` または CI 設定ファイルが `test_merge_gate_phase_review.py` を参照している
- **THEN** 参照が削除または適切に置換される
