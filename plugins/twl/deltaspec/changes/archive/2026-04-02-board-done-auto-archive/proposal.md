## Why

Project Board の Done アイテムが蓄積し続け（現在105件）、`gh project item-list --limit 200` の結果の96%が不要データとなっている。将来的には `--limit 200` でも全件取得できなくなるスケーラビリティ問題が生じる。merge-gate PASS 時に自動でアーカイブすることで、Board を常に軽量に保つ。

## What Changes

- `chain-runner.sh` に `step_board_archive()` 関数を追加（Project 検出 → アイテムID取得 → `gh project item-archive`）
- `merge-gate-execute.sh` の PASS 時フロー末尾（worktree 削除後）に `board-archive` ステップを追加
- エラー時は警告のみでマージフローをブロックしない

## Capabilities

### New Capabilities

- `bash scripts/chain-runner.sh board-archive "<ISSUE_NUM>"` コマンドで Issue の Board アイテムをアーカイブできる
- merge-gate PASS 後に Done Issue が Board から自動的に非表示になる

### Modified Capabilities

- `merge-gate-execute.sh`: PASS フロー末尾に `board-archive` 呼び出しを追加
- `chain-runner.sh`: `board-archive` サブコマンドとその実装関数を追加

## Impact

- **変更ファイル**: `scripts/chain-runner.sh`、`scripts/merge-gate-execute.sh`
- **依存**: `gh` CLI（`project item-archive` サブコマンド）、既存の Project 検出ロジック（`step_board_status_update()` と同パターン）
- **副作用なし**: `gh project item-archive --undo` で復元可能、既存 `item-list` の挙動に影響しない
