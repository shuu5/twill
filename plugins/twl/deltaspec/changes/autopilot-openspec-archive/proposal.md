## Why

autopilot ワークフローが Issue を完了してもそれに紐づく openspec change がアーカイブされないため、`openspec/changes/` に完了済み change が蓄積し続けている。deltaspec の設計意図（「完了した change をアーカイブすることで status を暗黙表現する」）が機能していない。

## What Changes

- `archive_done_issues()` に `deltaspec archive` ステップを追加（`.openspec.yaml` の `issue` フィールドで対象 change を特定）
- `.openspec.yaml` に `issue` フィールドを追加（change と Issue のマッピング）
- `auto-merge.sh` の非 autopilot パスで `head -1`（アルファベット順最初）を Issue 番号ベースの change 特定に置換
- `merge-gate-execute.sh` L163 コメントと実装を一致させる

## Capabilities

### New Capabilities

- `archive_done_issues()`: done な Issue に紐づく openspec change を `deltaspec archive` で自動アーカイブ
- `.openspec.yaml` の `issue` フィールド: change と Issue のマッピングを機械的に記録

### Modified Capabilities

- `auto-merge.sh`: 非 autopilot パスで Issue 番号に紐づく change を正しく特定してアーカイブ
- `merge-gate-execute.sh`: L163 コメントを実装と一致するよう更新

## Impact

- **変更ファイル**: `scripts/autopilot-orchestrator.sh`, `scripts/auto-merge.sh`, `scripts/merge-gate-execute.sh`
- **影響範囲**: autopilot Phase 完了フロー、非 autopilot merge-gate フロー
- **依存**: `deltaspec` CLI（未インストール時は WARNING でスキップ）、`state-read.sh`（Issue 番号取得）
- **境界条件**: `issue` フィールド未設定の change は WARNING ログ付きでスキップ、複数 change は全件アーカイブ（WARNING ログ）、deltaspec CLI 未インストール時は WARNING でスキップ
