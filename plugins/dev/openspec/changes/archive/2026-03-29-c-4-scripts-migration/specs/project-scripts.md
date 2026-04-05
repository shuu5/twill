## ADDED Requirements

### Requirement: project-create スクリプト移植

project-create.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。bare repo 初期化、worktree 設定、テンプレート適用のロジックを維持する。

#### Scenario: 新規プロジェクト作成
- **WHEN** `bash scripts/project-create.sh --name my-project --template default` を実行する
- **THEN** bare repo が作成され、main worktree が設定される

### Requirement: project-migrate スクリプト移植

project-migrate.sh を新リポジトリの `scripts/` に移植しなければならない（SHALL）。既存プロジェクトのテンプレート更新・ガバナンス再適用のロジックを維持する。

#### Scenario: テンプレート更新
- **WHEN** `bash scripts/project-migrate.sh --project-dir $PWD` を実行する
- **THEN** 最新テンプレートとの差分が検出され、更新が適用される
