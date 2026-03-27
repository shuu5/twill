## MODIFIED Requirements

### Requirement: template-b-check ドリフト検出

`chain_generate_check()` に Template B のドリフト検出を追加し、`--check` 時に frontmatter description 内の called-by 文の乖離を検出しなければならない（SHALL）。

#### Scenario: called-by 一致
- **WHEN** `--check` を実行し、frontmatter description 内の called-by 文が期待値と一致する
- **THEN** 当該コンポーネントを `ok` としてレポートする

#### Scenario: called-by 不一致
- **WHEN** `--check` を実行し、frontmatter description 内の called-by 文が期待値と異なる
- **THEN** 当該コンポーネントを `DRIFT` としてレポートし、差分を出力しなければならない（MUST）

#### Scenario: called-by 欠落
- **WHEN** `--check` を実行し、`template_b` に含まれるコンポーネントの description に called-by 文が存在しない
- **THEN** 当該コンポーネントを `DRIFT` としてレポートする

#### Scenario: Template A と B の両方を検証
- **WHEN** `--check` を実行する
- **THEN** Template A と Template B の両方のドリフトを検出し、統合結果を返さなければならない（SHALL）
