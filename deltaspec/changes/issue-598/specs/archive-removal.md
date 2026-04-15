## REMOVED Requirements

### Requirement: 自動 archive 処理の除去（Bash）

`autopilot-orchestrator.sh` から自動 archive に関するコードを除去しなければならない（SHALL）。具体的には `archive_done_issues()` 関数定義・`_archive_deltaspec_changes_for_issue()` 関数定義・`SKIPPED_ARCHIVES` グローバル配列・全呼び出し箇所・関連コメントを削除する（MUST）。

#### Scenario: merge-gate 成功後の自動 archive 除去
- **WHEN** merge-gate が成功する
- **THEN** `archive_done_issues` は呼び出されず、Done アイテムが Project Board に残ること

#### Scenario: phase report から skipped_archives フィールドの除去
- **WHEN** フェーズレポートが生成される
- **THEN** `skipped_archives` フィールドが JSON 出力に含まれないこと

### Requirement: 自動 archive 処理の除去（Python）

`orchestrator.py` から `_archive_done_issues()` メソッド・`_archive_deltaspec_changes()` メソッド・全呼び出し箇所を削除しなければならない（SHALL）。

#### Scenario: Python orchestrator からの archive メソッド除去
- **WHEN** `orchestrator.py` の `run()` メソッドが実行される
- **THEN** `_archive_done_issues()` は呼び出されないこと

#### Scenario: 関連テストの除去
- **WHEN** `test_autopilot_orchestrator.py` のテストスイートが実行される
- **THEN** archive 関連のテスト（`test_archive_done_issues` 等）が存在しないこと

## MODIFIED Requirements

### Requirement: gh project item-list の limit 統一確認

全スクリプト（`project-board-backfill.sh` を除く）において `gh project item-list` の `--limit` が 200 であることを確認しなければならない（SHALL）。

#### Scenario: limit 200 確認（chain-runner.sh）
- **WHEN** `chain-runner.sh` 内で `gh project item-list` が実行される
- **THEN** `--limit 200` が指定されていること

#### Scenario: backfill スクリプトは除外
- **WHEN** `project-board-backfill.sh` 内で `gh project item-list` が実行される
- **THEN** `--limit 500` が意図的に維持されていること（全件取得のため）

### Requirement: chain-runner.sh の手動 archive 機能保持

`chain-runner.sh` の `step_board_archive()` 関数定義は削除せず保持しなければならない（SHALL）。手動 archive フロー用として機能させ続けること（MUST）。

#### Scenario: 手動 archive 機能の保持
- **WHEN** `chain-runner.sh` の `step_board_archive` が参照される
- **THEN** 関数が存在し、呼び出し可能であること
