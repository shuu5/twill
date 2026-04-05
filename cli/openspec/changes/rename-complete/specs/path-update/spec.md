## MODIFIED Requirements

### Requirement: path フィールドの自動更新

`rename_component()` は、対象コンポーネントの `path` フィールド内で old_name を new_name に置換しなければならない（SHALL）。置換はパスコンポーネント境界でのみ行い、部分文字列への波及を防がなければならない（MUST）。

#### Scenario: 標準的な path 更新
- **WHEN** `twl rename controller-project co-project` を実行し、対象の path が `skills/controller-project/SKILL.md` である
- **THEN** path は `skills/co-project/SKILL.md` に更新される

#### Scenario: 部分一致しない
- **WHEN** `twl rename co-auto co-autopilot` を実行し、別コンポーネントの path に `skills/co-autopilot-launch/SKILL.md` がある
- **THEN** 別コンポーネントの path は変更されない

#### Scenario: dry-run での path 変更表示
- **WHEN** `twl rename controller-project co-project --dry-run` を実行する
- **THEN** path の変更が `path: skills/controller-project/SKILL.md → skills/co-project/SKILL.md` 形式でプレビュー表示される
