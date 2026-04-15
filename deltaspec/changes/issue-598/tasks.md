## 1. autopilot-orchestrator.sh の自動 archive コード削除

- [x] 1.1 `SKIPPED_ARCHIVES=()` 配列宣言（L1209 付近）とそのコメント（L1208）を削除
- [x] 1.2 `archive_done_issues()` 関数定義（L1210-1239）を削除
- [x] 1.3 `_archive_deltaspec_changes_for_issue()` 関数定義（L1242+）を削除
- [x] 1.4 `generate_phase_report` 内の `--argjson skipped_archives ...` 行（L1137）を削除
- [x] 1.5 `generate_phase_report` 内の `skipped_archives: $skipped_archives` 出力行（L1147）とそのコメント（L1130）を削除
- [x] 1.6 `archive_done_issues "${ALL_ISSUE_NUMS[@]}"` 呼び出し箇所 2 箇所（L1354, L1444）とそのコメント（L1353, L1439, L1446）を削除

## 2. orchestrator.py の自動 archive コード削除

- [x] 2.1 `self._archive_done_issues(all_nums)` 呼び出し（L208）を削除
- [x] 2.2 `self._archive_done_issues(all_nums)` 呼び出し（L220）を削除
- [x] 2.3 Issue #138 関連コメント（L704 付近）を削除
- [x] 2.4 `_archive_done_issues()` メソッド定義（L717+）を削除
- [x] 2.5 `_archive_deltaspec_changes()` メソッド定義（L755+）を削除

## 3. テスト削除

- [x] 3.1 `cli/twl/tests/test_autopilot_orchestrator.py` の archive 関連テスト（`test_archive_done_issues` 等、L352-431 付近）を削除

## 4. limit 200 確認

- [x] 4.1 `chain-runner.sh` の `gh project item-list` limit が 200 であることを確認
- [x] 4.2 `project-board-archive.sh` の limit が 200 であることを確認
- [x] 4.3 `autopilot-plan-board.sh` の limit が 200 であることを確認
- [x] 4.4 `project-board-backfill.sh` の `--limit 500` が意図的であることをコメントで明記されていることを確認

## 5. 動作確認

- [x] 5.1 `chain-runner.sh` の `step_board_archive()` 関数定義が残存していることを確認
- [x] 5.2 orchestrator.sh がシンタックスエラーなく実行できることを確認（`bash -n`）
- [x] 5.3 Python orchestrator のテスト（archive 以外）がパスすることを確認
