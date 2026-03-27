## MODIFIED Requirements

### Requirement: Constraints の技術的制約詳細化
vision.md の Constraints セクションは、Python バージョン要件、外部依存ライブラリの制限、deps.yaml/types.yaml のスキーマバージョン制約を含まなければならない（SHALL）。

#### Scenario: 技術的制約の網羅性
- **WHEN** vision.md の Constraints セクションを確認する
- **THEN** Python バージョン、外部依存の制限、スキーマバージョンに関する記述が存在する

### Requirement: Non-Goals の具体化
vision.md の Non-Goals セクションは、各 Non-Goal に理由（なぜスコープ外なのか）を付記しなければならない（MUST）。

#### Scenario: Non-Goals の理由付き確認
- **WHEN** vision.md の Non-Goals セクションを確認する
- **THEN** 各 Non-Goal に理由が記述されている
