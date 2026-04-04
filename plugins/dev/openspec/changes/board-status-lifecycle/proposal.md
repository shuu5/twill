## Why

Project Board の Status 遷移が呼び出し元ごとに統一されておらず、merge 成功時に Done を経由せず直接 Archive されるため、Issue の履歴が失われている。

## What Changes

- `scripts/project-board-backfill.sh`: 新規 Issue のデフォルト Status を In Progress → Todo に変更し、既存アイテムをスキップする冪等性ロジックを追加
- `scripts/merge-gate-execute.sh`: merge 成功後のフローを `board-archive` → `board-status-update <issue> "Done"` に変更
- `scripts/autopilot-orchestrator.sh`: Phase 完了処理に当該 Phase の Done アイテムのみを対象とした `board-archive` 呼び出しを追加

## Capabilities

### New Capabilities

- Issue 作成/バックフィル時の Todo 遷移（冪等性付き）
- merge 成功時の Done 遷移（履歴保持）
- autopilot Phase 完了時の Phase 限定 Archive

### Modified Capabilities

- `project-board-backfill.sh`: 既存 Board アイテムをスキップして冪等化
- `merge-gate-execute.sh`: Done 遷移を経由する正しいライフサイクル
- `autopilot-orchestrator.sh`: Phase 完了時に対象 Issue のみをアーカイブ

## Impact

- 影響スクリプト: `project-board-backfill.sh`, `merge-gate-execute.sh`, `autopilot-orchestrator.sh`, `chain-runner.sh`（board-archive コマンドは維持）
- 関連テスト: `tests/bats/scripts/board-*.bats`, `tests/bats/scripts/merge-gate*.bats`
- 依存 API: GitHub Project GraphQL API（Status 遷移）
