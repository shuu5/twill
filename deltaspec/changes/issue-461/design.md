## Context

`cli/twl/tests/autopilot/test_merge_gate_phase_review.py` は 644 行で CRITICAL 閾値（500 行）を超過している。ファイルには共通 fixture（行 34-107）と 5 つのテストクラスが含まれており、責務でグループ化してファイル分割が可能。

既存の共通 fixture（`autopilot_dir`, `scripts_root`, `gate`, `gate_force`, `_phase_review_json`, `_write_phase_review`）は分割後のファイル間で共有されるため、`conftest.py` へ移動する。

## Goals / Non-Goals

**Goals:**
- `test_merge_gate_phase_review.py` を 3 ファイルに分割し、全ファイルが 500 行未満になる
- 分割後も `pytest cli/twl/tests/autopilot/` の結果が完全一致する
- 各ファイルが単独で `pytest <file>` 実行可能になる
- 共通 fixture を `conftest.py` に移動する（副作用のない範囲に限定）

**Non-Goals:**
- テストロジックの変更
- テストカバレッジの変更
- 分割以外のリファクタリング

## Decisions

### ファイル分割方針
| ファイル名 | 収容クラス | 責務 |
|---|---|---|
| `test_phase_review_checkpoint.py` | `TestPhaseReviewCheckpointPresence` + `TestPhaseReviewCheckpointSkipLabels` | checkpoint 存在確認と skip label 処理 |
| `test_phase_review_guard.py` | `TestPhaseReviewCriticalFindings` + `TestPhaseReviewForceWarning` | CRITICAL findings ガードと --force-warning 動作 |
| `test_merge_gate_integration.py` | `TestMergeGateExecuteIntegration` | end-to-end merge-gate 統合テスト |

### conftest.py への共通 fixture 移動
- `autopilot_dir`, `scripts_root`, `gate`, `gate_force` fixture を移動
- `_phase_review_json`, `_write_phase_review` ヘルパー関数も移動
- 既存の `conftest.py` が存在する場合は追記する

### 元ファイルの扱い
- 分割完了後に `test_merge_gate_phase_review.py` を削除する

## Risks / Trade-offs

- **CI/pyproject.toml 参照**: 特定ファイルパスが参照されている場合は更新が必要（AC-4）
- **import パス**: 移動先でも同じ import が必要（`from twl.autopilot.mergegate import ...`）
- **fixture スコープ衝突**: `conftest.py` に既存の同名 fixture がある場合は注意が必要
