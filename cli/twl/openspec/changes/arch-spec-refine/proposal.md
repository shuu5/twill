## Why

architecture/ ディレクトリは現在スケルトン状態（構造と概要のみ）で、設計意図の詳細が欠落している。
loom-plugin-dev の新規構築や今後の Issue 起票において、アーキテクチャ判断の根拠となるドキュメントが不十分。

## What Changes

- vision.md の Constraints/Non-Goals を具体化
- domain/model.md に全エンティティの属性・集約境界・値オブジェクトを追加
- domain/glossary.md に deps.yaml 全フィールド名、types.yaml 全型名、検証コマンドの定義を追加
- 各 Context ファイルに Key Entities 詳細、Context Map、CLI コマンドマッピングを追加
- phases/01.md に Context フィールドと依存関係を明記
- decisions/ に ADR-0001（Python 単一ファイル）、ADR-0002（types.yaml 外部化）を新規作成

## Capabilities

### New Capabilities

- ADR（Architecture Decision Records）による設計判断の永続化
- Context Map による Bounded Context 間依存の可視化
- 検証コマンド間の差異の明確な定義（check/validate/deep-validate/audit）

### Modified Capabilities

- glossary.md: 10 用語 → deps.yaml/types.yaml 全フィールドをカバー
- model.md: 概要図 → 属性レベルの詳細クラス図
- contexts/*.md: 1 段落 → Key Entities/Dependencies/Constraints の 3 セクション構成

## Impact

- 対象ファイル: architecture/ 配下の全 .md ファイル（10 既存 + 2 新規 ADR）
- コードへの影響: なし（ドキュメント変更のみ）
- loom-plugin-dev#14 との整合性確認が必要
