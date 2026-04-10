## Why

`cli/twl/deltaspec/changes/` に残る 17 の旧 OpenSpec 形式ディレクトリ（`.openspec.yaml`）が `twl spec list`、`twl spec status` 等の現行コマンドで正しく認識されず、Spec Management の統一管理が機能していない。全て実装済みであるため、標準形式（`.deltaspec.yaml`）に移行して archive すべき。

## What Changes

- `cli/twl/deltaspec/changes/` 内 16 active change の `.openspec.yaml` を `.deltaspec.yaml` にリネームし、`name`/`status` フィールドを補完する
- リネーム済みの 16 active changes を全て `twl spec archive --yes` で archive する
- `cli/twl/deltaspec/changes/archive/` 内の既存 1 件（`chain-generate-check-all`）の `.openspec.yaml` も `.deltaspec.yaml` にリネームする

## Capabilities

### New Capabilities

- なし

### Modified Capabilities

- `twl spec list`（`cli/twl` から実行）が全 active change を正しく認識・表示できるようになる
- `twl spec status` が archive 済み change を含む全 change を正しく処理できるようになる

## Impact

- `cli/twl/deltaspec/changes/*/.openspec.yaml` → `.deltaspec.yaml`（16 active + 1 archived = 17 ファイルのリネーム）
- `cli/twl/deltaspec/changes/archive/`（16 changes の移動先）
- `cli/twl/deltaspec/specs/`（specs/ サブディレクトリを持つ changes がある場合、archive 時に自動統合）
- コード変更なし（データ移行のみ）
