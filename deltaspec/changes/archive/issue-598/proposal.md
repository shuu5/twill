## Why

autopilot orchestrator の merge-gate 成功後に実行される自動 archive 処理により、Done アイテムが即座に Board から消えてしまい、直後の状況確認ができない。archive は手動で任意のタイミングで行えば十分であり、自動実行は不要。

## What Changes

- `autopilot-orchestrator.sh` の `archive_done_issues()` 関数・`_archive_deltaspec_changes_for_issue()` 関数・`SKIPPED_ARCHIVES` 配列・全呼び出し箇所・関連コメントを削除
- `orchestrator.py` の `_archive_done_issues()` メソッド・`_archive_deltaspec_changes()` メソッド・全呼び出し箇所を削除
- 関連テスト（`test_autopilot_orchestrator.py` の archive テスト）を削除
- 全スクリプトで `gh project item-list` の `--limit` が 200 であることを確認（変更不要の見込み）

## Capabilities

### New Capabilities

なし（機能削除のみ）

### Modified Capabilities

- **merge-gate 後フロー**: merge-gate 成功後に Done アイテムが自動 archive されなくなる。Board に Done 状態で残り、手動 archive まで確認可能
- **フェーズレポート**: `skipped_archives` フィールドが phase report から除去される

## Impact

- `plugins/twl/scripts/autopilot-orchestrator.sh`: `archive_done_issues()`・`_archive_deltaspec_changes_for_issue()`・`SKIPPED_ARCHIVES` 関連コードの削除（L1130, L1137, L1147, L1208-1239, L1242+, L1353-1354, L1439-1446）
- `cli/twl/src/twl/autopilot/orchestrator.py`: `_archive_done_issues()`・`_archive_deltaspec_changes()` メソッド・呼び出し箇所の削除（L208, L220, L704, L717+, L755+）
- `cli/twl/tests/test_autopilot_orchestrator.py`: archive 関連テストの削除
- `chain-runner.sh` の `step_board_archive()` 関数定義は**残存**（手動 archive 用）
