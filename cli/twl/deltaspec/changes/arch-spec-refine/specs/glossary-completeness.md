## MODIFIED Requirements

### Requirement: glossary.md の deps.yaml フィールド網羅
domain/glossary.md は deps.yaml のトップレベルフィールド名（plugin_name, version, entry_points, components, chains 等）およびコンポーネントフィールド名（type, path, description, calls, model 等）を全て用語として含まなければならない（SHALL）。

#### Scenario: deps.yaml フィールド名の網羅性検証
- **WHEN** glossary.md を確認する
- **THEN** deps.yaml で使用される全フィールド名が用語テーブルに存在する

### Requirement: glossary.md の types.yaml 型名網羅
domain/glossary.md は types.yaml で定義される全型名（controller, workflow, atomic, composite, specialist, reference, script の7型）を用語として含まなければならない（SHALL）。

#### Scenario: types.yaml 型名の網羅性検証
- **WHEN** glossary.md を確認する
- **THEN** types.yaml の7型が全て用語テーブルに存在する

### Requirement: 検証コマンドの差異定義
domain/glossary.md は check, validate, deep-validate, audit の4段階検証コマンドの差異を明確に定義しなければならない（MUST）。各コマンドの入力・出力・検証範囲を区別する。

#### Scenario: 検証コマンド4種の定義確認
- **WHEN** glossary.md の検証コマンド定義を確認する
- **THEN** check, validate, deep-validate, audit の4つが個別に定義され、それぞれの検証範囲が明記されている
