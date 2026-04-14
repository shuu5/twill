## Context

autopilot orchestrator（Bash: `autopilot-orchestrator.sh`、Python: `orchestrator.py`）は merge-gate 成功後に `archive_done_issues()` を呼び出し、Done 状態の Board アイテムを自動 archive していた。この処理により、merge 直後に Done アイテムを Board で確認できない問題が発生。

削除対象は純粋なコード除去であり、動作を変更するのではなく機能を廃止する。

## Goals / Non-Goals

**Goals:**
- `autopilot-orchestrator.sh` から自動 archive 関連コードを完全除去
- `orchestrator.py` から自動 archive 関連メソッドを完全除去
- 関連テストの削除
- `chain-runner.sh` の手動 archive 関数（`step_board_archive`）は保持

**Non-Goals:**
- 手動 archive 機能の変更・削除
- `project-board-archive.sh` の変更
- `project-board-backfill.sh` の `--limit 500` 変更
- 新しい archive 戦略の設計

## Decisions

1. **段階的削除**: Bash 側と Python 側を独立して削除する。両者は同じ機能を持つが実行パスが異なるため、それぞれの呼び出し箇所を追跡して削除する
2. **`chain-runner.sh` の `step_board_archive` は残存**: 手動 archive フロー（`/twl:workflow-pr-merge` 等）で使用される可能性があるため削除しない
3. **テスト削除**: archive 機能自体が消えるため、archive テストも削除する
4. **limit 200 確認**: `gh project item-list` の limit を全スクリプトで確認するが、変更は不要な見込み

## Risks / Trade-offs

- **リスク低**: 削除のみの変更で、新機能追加なし。merge-gate の既存フローには影響しない
- **テスト削除**: archive テスト削除後、テストカバレッジが一部低下するが、削除された機能のテストのため許容
- **手動 archive 忘れ**: Done アイテムが Board に溜まりやすくなるが、これは意図的なトレードオフ
