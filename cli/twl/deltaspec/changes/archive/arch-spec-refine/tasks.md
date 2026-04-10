## 1. vision.md 精緻化

- [x] 1.1 Constraints に Python バージョン要件、外部依存制限、スキーマバージョン制約を追記
- [x] 1.2 Non-Goals の各項目に理由を付記

## 2. domain/model.md 精緻化

- [x] 2.1 Plugin, Component, Type, Chain の属性を型付きで詳細化（deps.yaml/types.yaml の実フィールドを反映）
- [x] 2.2 集約境界の明確化（ルートエンティティと境界内エンティティの関係を記述）
- [x] 2.3 値オブジェクト（Path, Section, Call, StepIn 等）を識別・列挙
- [x] 2.4 Context Map を Mermaid フローチャートで追記

## 3. domain/glossary.md 精緻化

- [x] 3.1 deps.yaml のトップレベルフィールド名を用語として追加
- [x] 3.2 deps.yaml のコンポーネントフィールド名を用語として追加
- [x] 3.3 types.yaml の7型名を用語として追加
- [x] 3.4 check/validate/deep-validate/audit の4段階検証コマンドの差異を定義

## 4. domain/contexts/ 精緻化

- [x] 4.1 全6 Context ファイルを Key Entities / Dependencies / Constraints の3セクション構造に変換
- [x] 4.2 各 Context の Key Entities にエンティティ名・責務を列挙
- [x] 4.3 各 Context に対応する twl CLI コマンドをマッピング

## 5. decisions/ 新規作成

- [x] 5.1 ADR-0001-python-single-file.md を作成（Status/Context/Decision/Consequences）
- [x] 5.2 ADR-0002-types-yaml-externalization.md を作成（Status/Context/Decision/Consequences）

## 6. phases/01.md 更新

- [x] 6.1 各 Issue に Context フィールドを設定（既存の表を拡充）
- [x] 6.2 実装順序の依存関係を明記

## 7. 整合性確認

- [x] 7.1 plugins/twl#14 との整合性を確認
