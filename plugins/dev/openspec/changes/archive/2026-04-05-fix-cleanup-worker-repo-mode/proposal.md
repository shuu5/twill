## Why

`autopilot-orchestrator.sh` の `cleanup_worker` 関数が `REPO_MODE` を確認せずに常に `worktree-delete.sh` を呼び出す。bare repo 以外（`REPO_MODE=standard`）の環境では worktree が存在しないため、毎回「⚠️ worktree削除失敗」警告が出力される（Issue #228）。

## What Changes

- `cleanup_worker` 関数に `REPO_MODE` 自動判定ロジックを追加
- `REPO_MODE=standard` の場合は `worktree-delete.sh` の呼び出しをスキップ
- `REPO_MODE=worktree`（bare repo）の場合は従来どおり実行

## Capabilities

### New Capabilities

- なし

### Modified Capabilities

- **cleanup_worker**: `REPO_MODE` に基づく条件分岐でworktree削除をスキップ可能

## Impact

- **変更ファイル**: `scripts/autopilot-orchestrator.sh`（`cleanup_worker` 関数のみ）
- **影響範囲**: `cleanup_worker` を呼び出すすべての箇所（Issue完了・失敗時のクリーンアップ）
- **後方互換性**: bare repo 環境（`REPO_MODE=worktree`）は動作変更なし
- **依存関係**: `auto-merge.sh` および `merge-gate-execute.sh` と同一の `REPO_MODE` 判定パターンを使用
