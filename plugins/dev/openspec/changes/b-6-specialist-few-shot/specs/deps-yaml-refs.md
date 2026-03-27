## ADDED Requirements

### Requirement: deps.yaml refs セクション

deps.yaml に `refs` セクションを追加し、reference コンポーネントを管理しなければならない（MUST）。

refs セクションは以下のエントリを含まなければならない（SHALL）:
- `ref-specialist-output-schema`: type=reference, path=refs/ref-specialist-output-schema.md
- `ref-specialist-few-shot`: type=reference, path=refs/ref-specialist-few-shot.md

#### Scenario: refs セクションの存在
- **WHEN** deps.yaml をパースする
- **THEN** `refs` セクションが存在し、2 つのエントリが定義されている

#### Scenario: reference エントリの形式
- **WHEN** refs セクションの各エントリを検査する
- **THEN** 全エントリに `type: reference`, `path`, `description` が存在する

### Requirement: loom check の通過

refs セクション追加後の deps.yaml が `loom check` で pass しなければならない（MUST）。

#### Scenario: loom check が pass する
- **WHEN** deps.yaml 更新後に `loom check` を実行する
- **THEN** exit code が 0 で、エラーが報告されない

### Requirement: loom validate の通過

refs 追加後に `loom validate` で新規 violation が 0 件でなければならない（SHALL）。

#### Scenario: loom validate が新規 violation なしで完了する
- **WHEN** `loom validate` を実行する
- **THEN** 新規 violation が 0 件である
