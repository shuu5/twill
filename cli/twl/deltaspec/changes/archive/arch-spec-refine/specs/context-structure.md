## MODIFIED Requirements

### Requirement: Context ファイルの3セクション構造
各 Context ファイル（architecture/domain/contexts/*.md）は Key Entities, Dependencies, Constraints の3セクションを含まなければならない（SHALL）。既存の Responsibility セクションは Key Entities に統合する。

#### Scenario: Context ファイル構造検証
- **WHEN** architecture/domain/contexts/ 配下の任意の .md ファイルを確認する
- **THEN** Key Entities, Dependencies, Constraints の3セクションが存在する

### Requirement: Key Entities の具体化
各 Context の Key Entities セクションは、エンティティ名・属性・責務を列挙しなければならない（MUST）。1段落の概要ではなく、構造化されたリストとする。

#### Scenario: Key Entities の詳細度検証
- **WHEN** 任意の Context ファイルの Key Entities セクションを確認する
- **THEN** 各エンティティに名前と責務の説明が記載されている

### Requirement: CLI コマンドマッピング
各 Context ファイルは、その Context が担う twl CLI コマンドの一覧を含まなければならない（SHALL）。

#### Scenario: CLI コマンドマッピング検証
- **WHEN** 任意の Context ファイルを確認する
- **THEN** その Context に対応する twl CLI コマンドが列挙されている
