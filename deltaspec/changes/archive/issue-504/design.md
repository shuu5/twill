## Context

PR #501 は Issue #478 の実装 PR で、`autopilot-launch.sh` の `--autopilot-dir → AUTOPILOT_DIR` 伝搬確認が Touched files に記載されていた。実際には既存実装（L84/L217/L309/L366）が既に完全対応していたため変更不要だったが、PR 本文にその旨の説明がない。

コメント先: `https://github.com/shuu5/twill/pull/501`（MERGED 状態）

## Goals / Non-Goals

**Goals:**
- PR #501 に post-hoc note として `gh pr comment` でコメントを投稿する
- L84/L217/L309/L366 の 4 箇所すべてに言及する
- Issue #478 Touched files との関係（「確認対象」であり修正不要と確認済み）を明示する

**Non-Goals:**
- `autopilot-launch.sh` のコード変更
- PR #501 の description 編集（マージ済みのため）

## Decisions

- **コメント方式**: `gh pr comment 501 --repo shuu5/twill --body "..."` で投稿する
- **コメント形式**: `[post-hoc note]` プレフィックスで識別しやすくする
- **permalink 記録**: コメント投稿後 `gh pr view 501 --repo shuu5/twill --json comments` でコメント URL を取得し、Issue #504 クローズ時に記録する

## Risks / Trade-offs

- GitHub API の呼び出しは冪等ではない（重複投稿リスクあり）→ 投稿前に既存コメントを確認する
- `gh` コマンドが認証済みであること前提（コンテナ内では `gh auth status` で確認）
