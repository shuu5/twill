## Context

architecture/ ディレクトリはスケルトン状態で、vision.md/model.md/glossary.md/contexts/*/phases/ の構造は整っているが内容が概要レベル。loom-plugin-dev の設計判断や Issue 起票の根拠として使うには不十分。

本変更はコード変更を伴わず、architecture/ 配下の Markdown ファイルのみを編集・追加する。

## Goals / Non-Goals

**Goals:**

- glossary.md が deps.yaml 全フィールド名と types.yaml 全型名（8型: controller, workflow, atomic, composite, specialist, reference, script + user/launcher は spawnable_by のみ）をカバーする
- 各 Context ファイルが Key Entities, Dependencies, Constraints の3セクション構造を持つ
- ADR-0001（Python 単一ファイル）と ADR-0002（types.yaml 外部化）を decisions/ に作成する
- model.md のクラス図に全エンティティの属性と集約境界を記述する

**Non-Goals:**

- loom-engine.py のコード変更
- 新しい Context の追加（既存6 Context の精緻化のみ）
- Phase 2 以降の計画策定

## Decisions

1. **ADR フォーマット**: Michael Nygard の軽量 ADR 形式（Status/Context/Decision/Consequences）を採用。短く実用的。
2. **Context ファイル構造**: ref-architecture-spec.md の3セクション構造（Key Entities/Dependencies/Constraints）を準拠。既存の2セクション（Responsibility/Dependencies）から拡張。
3. **glossary.md の網羅性**: deps.yaml のトップレベルフィールド + コンポーネントフィールド + types.yaml の型名を全て収録。検証コマンド（check/validate/deep-validate/audit）の4段階の差異を明示。
4. **Context Map**: Mermaid フローチャートで Context 間の upstream/downstream 関係を図示。model.md に追記。

## Risks / Trade-offs

- **陳腐化リスク**: ドキュメントはコードと同期されないため、loom-engine.py の変更時に architecture/ が古くなる可能性がある。ADR は不変だが glossary/model は保守が必要
- **loom-plugin-dev#14 との整合性**: 並行して精緻化が進む場合に矛盾が生じる可能性。本 Issue 完了後に整合性確認を実施
- **スコープ膨張**: glossary の網羅性を追求すると工数が膨らむ。deps.yaml/types.yaml のフィールド名に限定し、実装詳細は含めない
