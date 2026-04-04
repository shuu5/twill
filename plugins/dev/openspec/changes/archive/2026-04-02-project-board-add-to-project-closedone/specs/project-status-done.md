## ADDED Requirements

### Requirement: Issue close 時の Status Done 自動更新

Issue が closed されたとき、GitHub Actions workflow が GraphQL API を使用して Project Board の Status を Done に更新しなければならない（SHALL）。

#### Scenario: Board 登録済み Issue の close
- **WHEN** Project Board に登録済みの Issue が close される
- **THEN** 該当 Issue の Project Board Status が Done に更新される

#### Scenario: Board 未登録 Issue の close
- **WHEN** Project Board に未登録の Issue が close される
- **THEN** workflow run は success（green）で完了し、エラーを発生させてはならない（MUST NOT）

#### Scenario: GraphQL mutation の実行
- **WHEN** Issue の Project Item が検出された場合
- **THEN** `updateProjectV2ItemFieldValue` mutation で Status field を Done option に更新しなければならない（MUST）

#### Scenario: Item 検索の実装
- **WHEN** workflow が実行される
- **THEN** `gh api graphql` で Project items を取得し、Issue number と repository でフィルタして対象 Item を特定しなければならない（SHALL）
