## Context

twill リポジトリの Issue を GitHub Projects (twill-ecosystem, Project #3) と連携させる。`actions/add-to-project@v1` Action と `gh api graphql` による Status 更新の 2 つの workflow を配置する。PAT Secret (`ADD_TO_PROJECT_PAT`) は plugins/twl#114 で一括登録される前提。

Project Board 情報はすべて Issue #56 の body にハードコードされている:
- Project URL: `https://github.com/users/shuu5/projects/3`
- Project ID: `PVT_kwHOCNFEd84BS03g`
- Status field ID: `PVTSSF_lAHOCNFEd84BS03gzhAPzog`
- Done option ID: `98236657`

## Goals / Non-Goals

**Goals:**

- Issue opened/reopened/transferred → Project Board 自動追加
- Issue closed → Status を Done に自動更新
- Board に未登録の Issue を close した場合もエラーなく完了

**Non-Goals:**

- PAT 作成・Secret 登録（別 Issue で対応）
- 他リポへの workflow 配置
- Project Board フィールドの自動作成

## Decisions

1. **add-to-project workflow**: `actions/add-to-project@v1` を使用。メジャーバージョンタグで固定し、メンテナンスコストを最小化。
2. **project-status-done workflow**: `gh api graphql` で直接 GraphQL mutation を実行。Item 検索 → 存在確認 → Status 更新の 3 ステップ。
3. **ID ハードコード**: Project ID、Field ID、Option ID を workflow YAML に直接記載。動的取得は不要（固定値のため）。
4. **Item 未存在時の処理**: GraphQL で Item を検索し、存在しない場合はステップをスキップ。workflow run は常に success (green)。

## Risks / Trade-offs

- PAT の権限スコープ: `project` スコープが必要。Secret 未登録時は workflow が失敗するが、想定内（plugins/twl#114 の完了が前提）。
- Project Board の ID 変更リスク: ID をハードコードしているため、Project を再作成した場合は workflow の更新が必要。現実的にはほぼ発生しない。
