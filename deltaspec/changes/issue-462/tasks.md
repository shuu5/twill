## 1. Phase A: guard 関数群の抽出

- [ ] 1.1 `mergegate.py` の行 98-197 の guard 関数 4 つ（`_check_worktree_guard`, `_check_worker_window_guard`, `_check_running_guard`, `_check_phase_review_guard`）と `_PHASE_REVIEW_SKIP_LABELS` 定数を確認する
- [ ] 1.2 `cli/twl/src/twl/autopilot/mergegate_guards.py` を新規作成し、上記 4 関数と定数を移動する
- [ ] 1.3 `mergegate.py` の抽出対象を削除し、`from twl.autopilot.mergegate_guards import ...` に置き換える
- [ ] 1.4 `cli/twl/tests/autopilot/test_merge_gate_phase_review.py` のインポートパスを `twl.autopilot.mergegate_guards` に更新する

## 2. deps.yaml 更新

- [ ] 2.1 `plugins/twl/deps.yaml` に `autopilot-mergegate-guards` エントリを追加する（`consumed_by: [autopilot-mergegate]` 設定）
- [ ] 2.2 `twl check` を実行してエラーがないことを確認する
- [ ] 2.3 `twl update-readme` を実行する

## 3. 行数確認と Phase B 判定

- [ ] 3.1 `wc -l cli/twl/src/twl/autopilot/mergegate.py` で行数を確認する
- [ ] 3.2 500 行以下であれば完了。超過する場合は Phase B（`_check_base_drift`, `_check_deps_yaml_conflict_and_rebase` の mixin 化）を実施する

## 4. テストと検証

- [ ] 4.1 `pytest cli/twl/tests/test_autopilot_mergegate.py` を実行して全 pass を確認する
- [ ] 4.2 `pytest cli/twl/tests/autopilot/test_merge_gate_phase_review.py` を実行して全 pass を確認する
