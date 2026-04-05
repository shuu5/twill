## Why

`project-board-status-update.md` の Step 2 Project 検出ロジックが曖昧で、autopilot Worker が実装した Issue (#41-#58, #62等) が正しい Project Board (#3) に追加されない。`project-board-sync.md` (#45) では修正済みの TITLE_MATCH_PROJECT パターンが未移植。

## What Changes

- `commands/project-board-status-update.md` の Step 2 を `project-board-sync.md` と同等のリポジトリ名マッチング＋タイトル優先ロジックに書き換え
- 欠落 Issue を一括追加するバッチスクリプト `scripts/project-board-backfill.sh` を新規作成
- バッチスクリプトの検証方法を定義

## Capabilities

### New Capabilities

- `scripts/project-board-backfill.sh`: 指定範囲の Issue を Project Board に一括追加し、Status を設定するバッチスクリプト

### Modified Capabilities

- `commands/project-board-status-update.md` Step 2: GraphQL による全 Project のリポジトリリンク確認 → MATCHED_PROJECTS 収集 → TITLE_MATCH_PROJECT 優先選択の 3 段階ロジックに変更

## Impact

- **変更対象**: `commands/project-board-status-update.md`, 新規 `scripts/project-board-backfill.sh`
- **依存**: `project-board-sync.md` を参照実装として利用（変更なし）
- **影響範囲**: `workflow-setup` chain 内の Step 2.3 で呼ばれるため、全 Issue 実装フローに影響
- **deps.yaml**: 変更なし（project-board-status-update は既に atomic として登録済み）
