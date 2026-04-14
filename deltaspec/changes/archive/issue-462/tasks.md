## 1. Phase A: guard 関数群の抽出

- [x] 1.1 `mergegate.py` の行 98-197 の guard 関数 4 つ（`_check_worktree_guard`, `_check_worker_window_guard`, `_check_running_guard`, `_check_phase_review_guard`）と `_PHASE_REVIEW_SKIP_LABELS` 定数を確認する
- [x] 1.2 `cli/twl/src/twl/autopilot/mergegate_guards.py` を新規作成し、上記 4 関数と定数を移動する
- [x] 1.3 `mergegate.py` の抽出対象を削除し、`from twl.autopilot.mergegate_guards import ...` に置き換える
- [x] 1.4 `cli/twl/tests/autopilot/test_merge_gate_phase_review.py` のインポートパスを `twl.autopilot.mergegate_guards` に更新する

## 2. deps.yaml 更新

- [x] 2.1 `plugins/twl/deps.yaml` に `autopilot-mergegate-guards` エントリを追加する（`consumed_by: [autopilot-mergegate]` 設定）
- [x] 2.2 `twl check` を実行してエラーがないことを確認する
- [x] 2.3 `twl update-readme` を実行する

## 3. 行数確認と Phase B 判定

- [x] 3.1 `wc -l cli/twl/src/twl/autopilot/mergegate.py` で行数を確認する（857行 → Phase B 必要）
- [x] 3.2 Phase B 実施: `MergeGateOperationsMixin` を `mergegate_ops.py` に作成し、内部メソッドを全移動。329行に削減

## 4. テストと検証

- [x] 4.1 `pytest cli/twl/tests/test_autopilot_mergegate.py` を実行して全 pass を確認する
- [x] 4.2 `pytest cli/twl/tests/autopilot/test_merge_gate_phase_review.py` を実行して全 pass を確認する
