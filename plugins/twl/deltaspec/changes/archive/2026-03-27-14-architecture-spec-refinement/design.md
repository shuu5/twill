## Context

B-1 (#3) で architecture/ ディレクトリに設計判断14項がスケルトンレベルで文書化された。現在、ADR 5件、Context 6件、Contract 2件、Context Map、Glossary が存在する。本変更は各ファイルを ref-architecture-spec.md の仕様レベルまで精緻化し、「各ファイルが仕様書として自己完結している」状態にする。

既存ファイル構成:
- `architecture/vision.md` — 設計哲学・制約・Non-Goals
- `architecture/domain/model.md` — 状態機械・エンティティ定義
- `architecture/domain/glossary.md` — 用語集
- `architecture/domain/context-map.md` — Context 間依存
- `architecture/domain/contexts/*.md` — 6 Bounded Context
- `architecture/decisions/ADR-001〜005.md` — 設計判断記録
- `architecture/contracts/*.md` — Context 間インターフェース
- `architecture/phases/01.md, 02.md` — Phase 計画
- `architecture/migration/` — 移行マッピング

## Goals / Non-Goals

**Goals:**

- vision.md に「機械 vs LLM」境界の詳細定義を追加する
- model.md に Controller spawning 関係と Chain フローの Mermaid 図を追加する
- glossary.md に旧→新用語対応表と廃止概念セクションを追加する
- 各 contexts/*.md に Key Entities 列挙と controller/workflow/command マッピングを追加する
- phases/*.md に Issue 間依存関係と Implementation Status 列を追加する

**Non-Goals:**

- 新しい ADR の追加（5件で十分）
- contracts/ の新規追加（autopilot ↔ issue-mgmt は Issue #14 AC にあるが、既存の2件で Context 間通信は十分定義済み）
- コードの実装や deps.yaml の変更
- loom CLI 側の変更（loom リポジトリの Issue 管理）

## Decisions

1. **ファイル単位の精緻化**: 各ファイルを独立して編集可能なため、ファイル単位でタスクを分割する。依存順序は vision → model → glossary → contexts → phases とする

2. **Mermaid 図の形式統一**: model.md の図は既存の stateDiagram-v2 形式に合わせ、新しい spawning 関係図も Mermaid で統一する

3. **旧→新対応表の形式**: glossary.md 内に Markdown テーブルとして追記する。別ファイル化はしない

4. **Implementation Status の管理**: phases/*.md 内のテーブルに列として追加。動的な更新は GitHub Issue の状態を参照する前提（phases/*.md は計画時点のスナップショット）

## Risks / Trade-offs

- **リスク: 情報の重複**: contexts/ と contracts/ と model.md で同じ概念を異なる粒度で記述するため、将来の変更時に不整合が発生する可能性がある。対策: context-map.md を各 Context の参照ハブとして維持し、詳細は各 Context ファイルに委譲する

- **トレードオフ: 詳細度 vs 保守性**: 詳細に書くほど仕様書としての価値は上がるが、実装との乖離リスクも増える。判断: 「設計意図（Why）」と「制約（Invariant）」を中心に記述し、実装詳細は避ける
