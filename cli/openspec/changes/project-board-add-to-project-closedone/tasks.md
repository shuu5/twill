## 1. add-to-project workflow

- [x] 1.1 `.github/workflows/add-to-project.yml` を作成（`actions/add-to-project@v1`、トリガー: issues opened/reopened/transferred、project-url・Secret 設定）

## 2. project-status-done workflow

- [x] 2.1 `.github/workflows/project-status-done.yml` を作成（トリガー: issues closed、GraphQL で Item 検索 → 存在時のみ Status Done 更新、Item 未存在時はスキップ）

## 3. 検証

- [x] 3.1 workflow YAML の構文確認（actionlint or 目視）
- [x] 3.2 ハードコード ID（Project ID, Field ID, Option ID）が Issue #56 body と一致することを確認
