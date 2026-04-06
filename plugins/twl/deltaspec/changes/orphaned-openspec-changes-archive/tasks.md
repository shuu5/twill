## 1. トリアージリスト作成

- [x] 1.1 `openspec/changes/` 配下の全 change ディレクトリを列挙（archive/ 除外）
- [x] 1.2 各 change について tasks.md の存在・完了状況を確認
- [x] 1.3 各 change について関連ブランチの存在を確認（`git branch -a | grep <name>`）
- [x] 1.4 各 change について最終更新日を確認（`git log` ベース）
- [x] 1.5 トリアージリスト（アーカイブ対象 / 保留 / 要調査）をユーザーに提示
- [x] 1.6 ユーザーからアーカイブ対象リストの承認を得る

## 2. 承認済み change の一括アーカイブ

- [x] 2.1 deltaspec コマンドの動作確認（`deltaspec list` が正常動作するか）
- [x] 2.2 各アーカイブ対象 change の日付を `.openspec.yaml` の `created` または `git log` で取得
- [x] 2.3 deltaspec 正常時: `deltaspec archive <name> --yes --skip-specs` を実行
- [x] 2.4 deltaspec 使用不可時: `mv openspec/changes/<name> openspec/changes/archive/<date>-<name>` で手動移動
- [x] 2.5 全アーカイブ完了後、`openspec/changes/` の残留 change を確認

## 3. 既存 archive の命名統一

- [x] 3.1 `openspec/changes/archive/` 内の日付プレフィックスなしのエントリを列挙（17 件）
- [x] 3.2 各エントリの日付を `.openspec.yaml` または `git log` で取得
- [x] 3.3 `mv openspec/changes/archive/<name> openspec/changes/archive/<date>-<name>` でリネーム
- [x] 3.4 日付が取得できないエントリは `1970-01-01-<name>` としてリネーム

## 4. 事後確認

- [x] 4.1 `openspec/changes/` の残留 change が保留・要調査のもののみであることを確認
- [x] 4.2 `openspec/changes/archive/` 内の全エントリが `YYYY-MM-DD-<name>` 命名であることを確認
- [ ] 4.3 （shuu5/deltaspec#1 完了後）`deltaspec list` で active changes が正確に表示されることを検証
