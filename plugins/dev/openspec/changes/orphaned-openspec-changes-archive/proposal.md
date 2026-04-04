## Why

deltaspec archive の autopilot 統合が未実装だったため（#235）、実装完了済みの change が `openspec/changes/` に 89 件蓄積しており、active な仕様と完了済み変更が混在している状態が続いている。この状態を手動トリアージにより解消し、openspec の状態を正常化する。

## What Changes

- `openspec/changes/` 配下の全 change を調査し、トリアージリストを作成する
- ユーザー承認を経て、完了済み change を `openspec/changes/archive/YYYY-MM-DD-<name>/` へ一括移動する
- 既存 `archive/` 内 17 件（日付プレフィックスなし）の命名を `YYYY-MM-DD-<name>` 形式に統一する

## Capabilities

### New Capabilities

- トリアージリスト生成: 各 change の tasks.md 完了状況・関連ブランチ存在・最終更新日を調査してリストを作成する
- 一括アーカイブ実行: `deltaspec archive` コマンドまたは手動 `mv` で承認済み change をアーカイブする
- 既存 archive 命名統一: 既存 17 件に日付プレフィックスを付与する

### Modified Capabilities

- なし（既存の automated archive フローは変更しない）

## Impact

- `openspec/changes/`: 多数の change ディレクトリが削除・移動される
- `openspec/changes/archive/`: 新規アーカイブが追加され、既存エントリの命名が変更される
- deps.yaml / CLAUDE.md: 変更なし
- 依存: shuu5/deltaspec#1（`deltaspec list` 構文エラー修正）が完了すると検証精度が向上するが、アーカイブ自体は手動でも実行可能
