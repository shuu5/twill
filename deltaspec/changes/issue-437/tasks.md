## 1. .openspec.yaml → .deltaspec.yaml リネームと必須フィールド補完

- [x] 1.1 `cli/twl/deltaspec/changes/` 内（`archive/` 除く）の全ディレクトリで `.openspec.yaml` を `.deltaspec.yaml` にリネームする（16 件）
- [x] 1.2 各 `.deltaspec.yaml` に `name` フィールドが欠けている場合は追加する
- [x] 1.3 各 `.deltaspec.yaml` に `status: pending` フィールドが欠けている場合は追加する

## 2. archive/ 内の旧形式リネーム

- [x] 2.1 `cli/twl/deltaspec/changes/archive/` 内の `.openspec.yaml`（`chain-generate-check-all`）を `.deltaspec.yaml` にリネームする

## 3. active changes の archive

- [x] 3.1 `twl spec list --json` で全 active change 名を取得する（`cli/twl` ディレクトリから実行）
- [x] 3.2 各 active change に対して `twl spec archive <change-name> --yes` を実行する
- [x] 3.3 archive 中に specs 統合コンフリクトが発生した場合は手動レビューし解消する

## 4. 完了確認

- [x] 4.1 `find cli/twl/deltaspec/changes -name ".openspec.yaml"` が 0 件を返すことを確認する
- [x] 4.2 `twl spec list`（`cli/twl` ディレクトリから実行）がエラーなく終了し、アクティブ change が 0 件と表示されることを確認する
- [x] 4.3 `cli/twl/deltaspec/changes/archive/` に 17 件（16 active + 1 既存）の change が存在することを確認する
