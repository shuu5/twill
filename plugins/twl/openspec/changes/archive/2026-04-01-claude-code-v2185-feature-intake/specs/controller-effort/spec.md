## MODIFIED Requirements

### Requirement: Controller effort フィールド追加

全 9 Controller（skills/ 配下の SKILL.md）の frontmatter に `effort` フィールドを追加しなければならない（SHALL）。effort 値は design.md D2 のマッピングに従う。

#### Scenario: co-autopilot に effort: high を設定
- **WHEN** skills/co-autopilot/SKILL.md の frontmatter を確認する
- **THEN** `effort: high` が宣言されていなければならない（MUST）

#### Scenario: workflow-dead-cleanup に effort: low を設定
- **WHEN** skills/workflow-dead-cleanup/SKILL.md の frontmatter を確認する
- **THEN** `effort: low` が宣言されていなければならない（MUST）

#### Scenario: 全 Controller に effort が存在する
- **WHEN** skills/ 配下の全 SKILL.md を走査する
- **THEN** 全ファイルの frontmatter に `effort` フィールドが存在しなければならない（MUST）

#### Scenario: effort 値は許可値のみ
- **WHEN** effort フィールドの値を確認する
- **THEN** `low`, `medium`, `high` のいずれかでなければならない（MUST）
