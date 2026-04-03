## Why

Project Board に Done アイテムが 105 件蓄積されており、`gh project item-list --limit 200` の結果の 96% が不要データとなっている。自動アーカイブ（#131）導入後も既存の蓄積は手動対処が必要なため、一括アーカイブスクリプトを提供する。

## What Changes

- `scripts/project-board-archive.sh` を新規作成
- Done ステータスのアイテムを `gh project item-archive` で一括処理
- `--dry-run` フラグで実際のアーカイブなしに対象確認が可能
- 実行後にアーカイブ件数のサマリーを表示

## Capabilities

### New Capabilities

- **一括アーカイブ**: Project Board の Done アイテムを全件アーカイブ
- **dry-run モード**: `--dry-run` フラグで対象一覧（Issue 番号 + タイトル）を表示し、実際の操作はスキップ
- **実行サマリー**: アーカイブ件数を標準出力に表示

### Modified Capabilities

なし（スタンドアロンユーティリティ）

## Impact

- 新規ファイル: `scripts/project-board-archive.sh`
- 依存: `gh` CLI、`jq`
- deps.yaml への登録なし（`project-board-backfill.sh` と同分類のスタンドアロンユーティリティ）
- 既存コンポーネントへの影響なし
