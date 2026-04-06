## 1. project-board-backfill.sh 修正

- [x] 1.1 既存 Board アイテムの Issue 番号リストを取得するロジックを追加（GitHub GraphQL）
- [x] 1.2 バックフィル対象 Issue が既存アイテムに含まれる場合はスキップする冪等性ロジックを実装
- [x] 1.3 新規追加時のデフォルト Status を In Progress → Todo に変更
- [x] 1.4 既存テスト `tests/bats/scripts/board-*.bats` がパスすることを確認

## 2. merge-gate-execute.sh 修正

- [x] 2.1 merge 成功後の `chain-runner.sh board-archive` 呼び出しを削除
- [x] 2.2 代わりに `chain-runner.sh board-status-update <issue> "Done"` を呼び出す処理を追加
- [x] 2.3 既存テスト `tests/bats/scripts/merge-gate*.bats` がパスすることを確認

## 3. autopilot-orchestrator.sh 修正

- [x] 3.1 Phase 完了処理で `plan.yaml` から当該 Phase の Issue 番号リストを取得するロジックを実装
- [x] 3.2 取得した Issue 番号の Done アイテムのみを対象に `chain-runner.sh board-archive` を呼び出す処理を追加
- [x] 3.3 他 Phase・手動 Issue がアーカイブ対象外であることをテストで確認

## 4. chain-runner.sh 維持確認

- [x] 4.1 `board-archive` コマンドが残っていることを確認（削除禁止）
- [x] 4.2 コメントで「Phase 完了処理から呼び出される用途」であることを明記

## 5. 統合テスト

- [x] 5.1 全 bats テスト実行（`tests/bats/scripts/board-*.bats`, `tests/bats/scripts/merge-gate*.bats`）
- [x] 5.2 手動で Status 遷移フロー全体（Todo→In Progress→Done→Archive）を確認（bats テストで各遷移を自動検証済み）
