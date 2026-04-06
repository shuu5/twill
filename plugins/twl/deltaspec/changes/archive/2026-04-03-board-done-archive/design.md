## Context

Project Board には Done アイテムが大量蓄積する運用上の問題がある。`project-board-backfill.sh` が確立した Project 検出ロジック（GraphQL + OWNER 解決）を再利用し、アーカイブ特化のスクリプトを作成する。`gh project item-archive` コマンドで item ID を指定してアーカイブ実行する。

## Goals / Non-Goals

**Goals:**

- `scripts/project-board-archive.sh` の新規作成
- Done アイテムの全件一括アーカイブ（`gh project item-archive`）
- `--dry-run` フラグによる対象確認モード
- 実行サマリー（アーカイブ件数）の表示
- rate limit 対策として各アーカイブ間に 0.5 秒 sleep

**Non-Goals:**

- Done 以外ステータスのアーカイブ
- 自動アーカイブのトリガー設定（#131 対応）
- deps.yaml への登録

## Decisions

1. **`project-board-backfill.sh` のパターン踏襲**: Project 検出ロジック（GraphQL でリンクリポ確認）を再利用し、OWNER/PROJECT_NUM を自動解決する
2. **アイテム取得**: `gh project item-list "$PROJECT_NUM" --owner "$OWNER" --format json --limit 200` でアイテム取得し、`jq` で `status == "Done"` をフィルタ
3. **アーカイブ API**: `gh project item-archive "$PROJECT_NUM" --owner "$OWNER" --id "$ITEM_ID"` を各アイテムに実行
4. **dry-run 実装**: `--dry-run` フラグ検出時は archive コマンドをスキップし、対象 Issue 番号とタイトルを一覧表示するのみ

## Risks / Trade-offs

- **rate limit**: 105 件を一括処理すると GitHub API の rate limit に引っかかる可能性がある → 0.5 秒 sleep で緩和
- **item ID vs content URL**: `gh project item-list` の出力形式に依存するため、CLI バージョン差異に注意が必要
- **limit 200**: 200 件超の Done アイテムが蓄積していると取りこぼす → 現時点では 105 件のため許容
