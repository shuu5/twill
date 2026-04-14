## Why

PR #501（Issue #478 実装）の diff に `autopilot-launch.sh` の変更がゼロだった。これは既存実装が既に `--autopilot-dir → AUTOPILOT_DIR` 伝搬を完全実装していたためだが、PR 本文に「変更不要だった理由」の記載がなく、将来のレビュワーが混乱する可能性がある。このポストホックコメントで行番号を明示し、「確認済み・変更不要」の根拠を GitHub 履歴として残す。

## What Changes

- PR #501 に post-hoc note コメントを投稿する（GitHub API 経由）
- コメント本文は L84/L217/L309/L366 の 4 箇所すべてに言及し、Issue #478 Touched files との関係を明示する

## Capabilities

### New Capabilities

なし（コードベース変更なし）

### Modified Capabilities

なし（コードベース変更なし）

## Impact

- リポジトリコード変更なし
- `gh pr comment` による GitHub PR コメント投稿のみ
- Issue #504 クローズ時にコメントへの permalink を記録する
