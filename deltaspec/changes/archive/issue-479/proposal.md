## Why

`/twl:test-project-init` は現状ローカル orphan branch + `test-fixtures/minimal-plugin/` 展開のみ対応しており、co-autopilot の chain 遷移（GitHub Issue + PR の実体を必要とする再現シナリオ）を実行できない。`--mode real-issues` フラグと専用 GitHub リポとの紐付けにより、実 Issue/PR を使ったリグレッションテストが可能になる。

## What Changes

- `commands/test-project-init.md` に `--mode real-issues --repo <owner>/<name>` 分岐を追加
- `--mode real-issues` 時のリポ存在確認・空リポ検証・パーミッション確認・自動作成フローを実装
- test-target worktree と専用リポの関連付けを `.test-target/config.json` に記録
- `plugins/twl/architecture/domain/contexts/observation.md` の `TestProject` エンティティに `mode` / `repo` / `loaded_issues_file` フィールドを追加
- `test-project-init.md` の禁止事項「git push 禁止」を `--mode local` のみに条件付き化
- 既存 bats テスト（`smoke.bats`, `regression.bats`）を `--mode local` 明示に更新

## Capabilities

### New Capabilities

- `--mode real-issues --repo <owner>/<name>` で専用 GitHub リポを作成または既存リポを検証して test-target と紐付ける
- `.test-target/config.json` への設定永続化（mode / repo / initialized_at / worktree_path / branch）
- リポ作成失敗時（rate limit / 権限不足 / 名前衝突）のエラーハンドリング

### Modified Capabilities

- `test-project-init.md` の禁止事項が `--mode local` 限定に変更され、`--mode real-issues` では gh CLI 経由 remote push を許可
- `TestProject` ドメインエンティティが `mode` / `repo` / `loaded_issues_file` フィールドを保持

## Impact

- `plugins/twl/commands/test-project-init.md` — 主要変更対象
- `plugins/twl/architecture/domain/contexts/observation.md` — `TestProject` エンティティ拡張
- `plugins/twl/tests/bats/e2e/co-self-improve-smoke.bats` — `--mode local` 明示
- `plugins/twl/tests/bats/e2e/co-self-improve-regression.bats` — `--mode local` 明示
