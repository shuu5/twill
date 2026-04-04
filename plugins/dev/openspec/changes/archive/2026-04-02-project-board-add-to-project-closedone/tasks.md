## 1. add-to-project workflow

- [x] 1.1 `actions/add-to-project` の最新メジャーバージョンを確認
- [x] 1.2 `.github/workflows/add-to-project.yml` を作成（トリガー: issues opened/reopened/transferred）

## 2. project-status-done workflow

- [x] 2.1 `.github/workflows/project-status-done.yml` を作成（トリガー: issues closed）
- [x] 2.2 GraphQL で Project Item 検索 → 条件付き Status 更新ロジックを実装
- [x] 2.3 Item 未存在時の graceful スキップを実装

## 3. PAT セットアップ手順

- [x] 3.1 PR description に PAT 作成手順を記載（スコープ: project read/write + repo）
- [x] 3.2 PR description に 3 リポへの Secret 登録手順を記載
