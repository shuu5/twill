## MODIFIED Requirements

### Requirement: project-create.sh の複数リポジトリリンク

project-create.sh が repos セクションの全リポジトリに対して `linkProjectV2ToRepository` を呼び出さなければならない（SHALL）。

#### Scenario: 2 リポジトリのリンク
- **WHEN** `repos: { lpd: ..., loom: ... }` を持つプロジェクトが作成される
- **THEN** `linkProjectV2ToRepository` が lpd と loom の両方に対して呼び出される

### Requirement: project-board-sync のクロスリポジトリ対応

project-board-sync が repos セクションの全リポジトリの Issue を Project Board に同期しなければならない（SHALL）。

#### Scenario: クロスリポジトリ Issue の同期
- **WHEN** autopilot セッションで lpd#42 と loom#50 が管理されている
- **THEN** 両方の Issue が同一 Project Board に追加され、Status が正しく更新される

### Requirement: co-autopilot SKILL.md の repos 引数解析

co-autopilot が `--repos` 引数または plan.yaml の repos セクションを解析し、autopilot-plan.sh に受け渡さなければならない（SHALL）。

#### Scenario: repos 引数の受け渡し
- **WHEN** co-autopilot に `--repos lpd=~/projects/.../loom-plugin-dev,loom=~/projects/.../loom` が渡される
- **THEN** autopilot-plan.sh に repos 情報が渡され、plan.yaml に repos セクションが生成される

#### Scenario: repos 引数省略時の後方互換
- **WHEN** co-autopilot に repos 引数が省略される
- **THEN** 従来の単一リポジトリ動作が維持されなければならない（MUST）
