## ADDED Requirements

### Requirement: Issue の Project Board 自動追加

Issue が opened, reopened, transferred されたとき、GitHub Actions workflow が `actions/add-to-project` Action を使用して対象 Issue を Project Board に自動追加しなければならない（SHALL）。

#### Scenario: 新規 Issue 作成時の自動追加
- **WHEN** リポジトリで新しい Issue が作成される
- **THEN** Issue が Project Board（#3: loom-dev-ecosystem）に自動追加される

#### Scenario: Issue reopen 時の再追加
- **WHEN** クローズ済みの Issue が reopen される
- **THEN** Issue が Project Board に追加される（既に存在する場合は冪等に処理される）

#### Scenario: Issue transfer 時の追加
- **WHEN** 他リポジトリから Issue が transfer される
- **THEN** 転送先リポジトリの workflow により Issue が Project Board に追加される

#### Scenario: PAT 未設定時のエラー
- **WHEN** `ADD_TO_PROJECT_PAT` Secret が未登録の状態で workflow が実行される
- **THEN** workflow run が失敗し、Secret 未設定が原因であることがログから判別できる
