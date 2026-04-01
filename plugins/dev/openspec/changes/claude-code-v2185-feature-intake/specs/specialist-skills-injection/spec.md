## MODIFIED Requirements

### Requirement: specialist への ref-* スキル事前注入

specialist エージェント（type: specialist）の frontmatter に `skills` フィールドを追加し、body 内で参照している ref-* スキルを事前注入しなければならない（SHALL）。

#### Scenario: reviewer 系 specialist に共通 ref を注入
- **WHEN** worker-code-reviewer.md の frontmatter を確認する
- **THEN** `skills` フィールドに `ref-specialist-output-schema` と `ref-specialist-few-shot` が含まれていなければならない（MUST）

#### Scenario: body 内参照と skills フィールドの一致
- **WHEN** specialist の body 内に `ref-*` パターンの参照がある
- **THEN** 対応する ref-* が `skills` フィールドに宣言されていなければならない（MUST）

#### Scenario: ref-* 未参照の specialist
- **WHEN** specialist の body 内に ref-* 参照がない
- **THEN** `skills` フィールドは追加しない（不要なフィールドを強制してはならない）
