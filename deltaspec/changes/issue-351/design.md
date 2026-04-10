## Context

ADR-014 Decision 1 が Observer → Supervisor の改名を決定した。対象は `plugins/twl/architecture/domain/model.md` のみ。コード実装（Python/Shell）への変更は含まない。本 Issue は Phase 5（ドメインモデル + Context 更新）の一部であり、後続 C1 が依存する。

## Goals / Non-Goals

**Goals:**

- model.md 内のすべての `Observer` クラス定義を `Supervisor` に更新
- `InterventionRecord.observer` フィールドを `supervisor` に更新
- Mermaid クラス図・関係図の `co-observer` ノードを `su-observer` に更新
- `intervention-{N}.json` スキーマの `observer` フィールドを `supervisor` に更新
- Spawning ルール説明文の `co-observer` 参照を `su-observer` に更新

**Non-Goals:**

- Python/Shell コードの変更（別 Issue）
- ADR ドキュメントの編集
- co-observer 以外のコントローラー名の変更

## Decisions

**D1: テキスト置換のみ、構造変更なし**
クラス図・関係図の構造（関係線・依存方向）は変更しない。名前のみを更新する。

**D2: `co-*` prefix から `su-*` prefix への変更**
ADR-014 の su- prefix 規則に従い、Observer クラスの `name: co-*` を `name: su-*` に変更する。Mermaid ノード ID も `CO` → `SO` に更新する。

**D3: フィールド名の一貫した置換**
`InterventionRecord.observer` と `intervention-{N}.json` の `observer` フィールドを同時に `supervisor` に変更し、スキーマの整合性を保つ。

## Risks / Trade-offs

- **リスク**: Spawning ルール説明文に `co-observer` の文字列参照が複数箇所ある。見落としがあると不整合が残る。
  - **対策**: Grep で model.md 全体の `observer`（大文字小文字含む）を確認してから変更する。
- **トレードオフ**: なし（純粋なリネーム）
