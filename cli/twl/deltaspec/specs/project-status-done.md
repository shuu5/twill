## Requirements

### Requirement: Issue クローズ時に Status を Done に更新

Issue がクローズされた場合、GraphQL API で Project Item の Status を Done に更新しなければならない（SHALL）。

#### Scenario: Board 登録済み Issue のクローズ
- **WHEN** Project Board に登録済みの Issue がクローズされる
- **THEN** その Issue の Project Board Status が Done に更新される

#### Scenario: Board 未登録 Issue のクローズ
- **WHEN** Project Board に未登録の Issue がクローズされる
- **THEN** workflow run は success (green) で完了し、エラーは発生しない（MUST）

### Requirement: GraphQL による Item 検索と条件付き更新

workflow は `gh api graphql` を使用して Project Item を検索し、存在する場合のみ Status を更新しなければならない（MUST）。

#### Scenario: Item 検索成功時の Status 更新
- **WHEN** GraphQL クエリで Issue に対応する Project Item が見つかる
- **THEN** `updateProjectV2ItemFieldValue` mutation で Status field を Done option に更新する

#### Scenario: Item 検索結果が空の場合
- **WHEN** GraphQL クエリで Issue に対応する Project Item が見つからない
- **THEN** 更新ステップをスキップし、workflow は正常終了する（MUST）
