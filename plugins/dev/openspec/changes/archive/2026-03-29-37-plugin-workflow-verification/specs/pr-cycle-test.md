## ADDED Requirements

### Requirement: workflow-pr-cycle の自律的完了

workflow-setup の成果物に対して /dev:workflow-pr-cycle を実行し、verify → review → test → report が自律的に完了しなければならない（SHALL）。

#### Scenario: PR-cycle の実行
- **WHEN** workflow-setup 完了後の worktree で /dev:workflow-pr-cycle を実行する
- **THEN** verify（型チェック・lint）→ review（並列レビュー）→ test → report の各フェーズが順次完了する

#### Scenario: PR 作成とレビュー結果
- **WHEN** pr-cycle が完了する
- **THEN** GitHub PR が作成され、レビュー結果がコメントとして投稿されている
