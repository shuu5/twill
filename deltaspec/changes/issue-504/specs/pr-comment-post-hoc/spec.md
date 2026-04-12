## ADDED Requirements

### Requirement: PR #501 post-hoc note コメント投稿

PR #501 に `[post-hoc note]` コメントを投稿し、`autopilot-launch.sh` 無変更の理由を GitHub 履歴として記録しなければならない（SHALL）。コメントは以下をすべて満たさなければならない（MUST）:

- `[post-hoc note]` プレフィックスで始まる
- L84（`--autopilot-dir` 引数パース）/ L217（`export AUTOPILOT_DIR`）/ L309（`AUTOPILOT_ENV` 変数構築）/ L366（`tmux new-window` への env 引き渡し）の 4 箇所すべてに言及する
- Issue #478 Touched files セクションにおける「確認対象」としての記載と、修正が不要と確認済みである事実を明示する

#### Scenario: コメント投稿成功
- **WHEN** `gh pr comment 501 --repo shuu5/twill --body "<コメント本文>"` を実行する
- **THEN** PR #501 のコメントに上記投稿が追加され、パーマリンクが取得できる

#### Scenario: 重複投稿防止
- **WHEN** PR #501 のコメント一覧を取得したとき、`[post-hoc note]` を含む既存コメントが存在する
- **THEN** 重複投稿をスキップし、既存コメントの URL を記録する

### Requirement: Issue #504 クローズ時の permalink 記録

Issue #504 クローズ時に、投稿されたコメントへの permalink を Issue コメントに記載しなければならない（SHALL）。

#### Scenario: Issue クローズ
- **WHEN** Issue #504 を close する
- **THEN** `gh issue comment 504 --repo shuu5/twill --body "Closed. PR #501 comment permalink: <URL>"` を実行し、permalink が Issue に記録される
