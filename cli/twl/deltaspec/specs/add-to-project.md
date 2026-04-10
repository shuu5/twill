## Requirements

### Requirement: Issue を Project Board に自動追加

Issue が opened, reopened, transferred された場合、`actions/add-to-project@v1` を使用して twill-ecosystem Project Board に自動追加しなければならない（SHALL）。

#### Scenario: 新規 Issue 作成時の自動追加
- **WHEN** twill リポジトリで新規 Issue が作成される
- **THEN** Issue が Project Board (twill-ecosystem) に自動追加される

#### Scenario: Issue reopen 時の自動追加
- **WHEN** クローズされた Issue が再度オープンされる
- **THEN** Issue が Project Board に追加される（既に存在する場合は重複なし）

#### Scenario: Issue transfer 時の自動追加
- **WHEN** 他リポから Issue が twill リポジトリに転送される
- **THEN** 転送された Issue が Project Board に自動追加される
