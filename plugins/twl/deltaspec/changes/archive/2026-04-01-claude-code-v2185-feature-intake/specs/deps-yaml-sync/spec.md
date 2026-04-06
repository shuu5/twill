## MODIFIED Requirements

### Requirement: deps.yaml 新フィールド反映

deps.yaml v3.0 のコンポーネント定義に `effort`, `skills`, `tools` フィールドを反映し、実ファイルの frontmatter と一貫性を保たなければならない（SHALL）。

#### Scenario: Controller の effort が deps.yaml に反映
- **WHEN** skills/co-autopilot/SKILL.md に `effort: high` が設定される
- **THEN** deps.yaml の co-autopilot コンポーネント定義にも `effort: high` が反映されていなければならない（MUST）

#### Scenario: specialist の skills が deps.yaml に反映
- **WHEN** agents/worker-code-reviewer.md に `skills: [ref-specialist-output-schema, ref-specialist-few-shot]` が設定される
- **THEN** deps.yaml の worker-code-reviewer コンポーネント定義にも skills が反映されていなければならない（MUST）

#### Scenario: loom check が PASS
- **WHEN** 全変更完了後に `loom check` を実行する
- **THEN** エラーなく PASS しなければならない（MUST）

#### Scenario: loom validate が PASS
- **WHEN** 全変更完了後に `loom validate` を実行する
- **THEN** エラーなく PASS しなければならない（MUST）
