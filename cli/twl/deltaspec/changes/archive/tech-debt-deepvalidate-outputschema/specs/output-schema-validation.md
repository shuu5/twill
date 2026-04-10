## MODIFIED Requirements

### Requirement: output_schema 空文字列の検出

`deep_validate()` section E は `output_schema: ""` を invalid value として検出し、専用の警告メッセージを出力しなければならない（SHALL）。

#### Scenario: 空文字列の output_schema
- **WHEN** specialist コンポーネントが `output_schema: ""` を宣言している
- **THEN** `[specialist-output-schema] {cname}: empty output_schema value (expected 'custom' or omit)` 警告が出力される

#### Scenario: 有効な custom 値
- **WHEN** specialist コンポーネントが `output_schema: custom` を宣言している
- **THEN** output_schema 関連の警告は出力されない（MUST）

#### Scenario: 未宣言（None）
- **WHEN** specialist コンポーネントが `output_schema` を宣言していない
- **THEN** output_schema の invalid value 警告は出力されず、スキーマキーワード検証が実行される（SHALL）

#### Scenario: その他の無効な値
- **WHEN** specialist コンポーネントが `output_schema: "invalid"` など `custom` 以外の非空値を宣言している
- **THEN** `[specialist-output-schema] {cname}: invalid output_schema value '{value}' (expected 'custom' or omit)` 警告が出力される（SHALL）
