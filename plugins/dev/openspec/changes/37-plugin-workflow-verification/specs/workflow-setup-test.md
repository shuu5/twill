## ADDED Requirements

### Requirement: workflow-setup の自律的完了

テストプロジェクト loom-plugin-test で /dev:workflow-setup を実行し、worktree 作成から OpenSpec propose → apply まで自律的に完了しなければならない（SHALL）。

#### Scenario: テスト Issue の作成と workflow-setup 実行
- **WHEN** loom-plugin-test にテスト用 Issue を作成し、/dev:workflow-setup #N を実行する
- **THEN** worktree が作成され、OpenSpec の propose が自律的に実行され、apply まで完了する

#### Scenario: 生成された成果物の確認
- **WHEN** workflow-setup が完了した後に worktree 内を確認する
- **THEN** openspec/changes/ 配下に proposal.md, design.md, specs/, tasks.md が生成されており、実装コードが存在する
