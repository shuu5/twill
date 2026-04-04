## ADDED Requirements

### Requirement: Controller tools フィールドによる Agent スポーン制限

Controller（skills/ 配下の SKILL.md）の frontmatter に `tools` フィールドを追加し、`Agent(agent_type)` 形式でスポーン可能なエージェントを制限しなければならない（SHALL）。

#### Scenario: co-autopilot のスポーン制限
- **WHEN** skills/co-autopilot/SKILL.md の frontmatter を確認する
- **THEN** `tools` フィールドに Worker 系・e2e 系エージェントのスポーン許可が宣言されていなければならない（MUST）

#### Scenario: co-issue のスポーン制限
- **WHEN** skills/co-issue/SKILL.md の frontmatter を確認する
- **THEN** `tools` フィールドに issue-critic, issue-feasibility, context-checker, template-validator のスポーン許可が宣言されていなければならない（MUST）

#### Scenario: スポーン制限外のエージェント呼び出し
- **WHEN** Controller が tools フィールドに宣言されていないエージェントをスポーンしようとする
- **THEN** Claude Code が当該スポーンを制限する（MUST）
