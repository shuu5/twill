## MODIFIED Requirements

### Requirement: エンティティ属性の詳細化
domain/model.md のクラス図は、全エンティティの属性を型付きで定義しなければならない（SHALL）。現在の概要レベルから、deps.yaml/types.yaml の実フィールドを反映した詳細図に拡張する。

#### Scenario: クラス図の属性詳細度
- **WHEN** domain/model.md のクラス図を確認する
- **THEN** Plugin, Component, Type, Chain の各エンティティに型付き属性が定義されている

### Requirement: 集約境界の明確化
domain/model.md は集約（Aggregate）の境界と、集約ルート経由のアクセスルールを明記しなければならない（MUST）。

#### Scenario: 集約境界の記述確認
- **WHEN** domain/model.md の集約セクションを確認する
- **THEN** 各集約のルートエンティティと境界内エンティティが明示されている

### Requirement: 値オブジェクトの列挙
domain/model.md は値オブジェクト（Path, Section, Call 等）を識別し、エンティティと区別して記述しなければならない（SHALL）。

#### Scenario: 値オブジェクトの識別
- **WHEN** domain/model.md を確認する
- **THEN** 値オブジェクトがエンティティとは別に列挙されている
