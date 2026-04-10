## Why

Context Map の Cross-cutting Context が `Observer` と命名されているが、実態は全 controller のメタ認知監視・介入レイヤーであり、`Supervision` がより正確な概念を表す。ADR-013 で定義された `su-observer`（supervision observer）への統一に合わせて Context 名を更新する必要がある。

## What Changes

- `plugins/twl/architecture/domain/context-map.md`
  - Context 分類テーブル: `Cross-cutting | Observer` → `Cross-cutting | Supervision`
  - 依存関係図: `COBS["Observer<br/>(Meta-cognitive)"]` ノードを `SOBS["Supervision<br/>(Meta-cognitive)"]` に更新（COBS ノード名変更は意味的整合のため許容）
  - DCI フロー図: `subgraph "co-observer"` → `subgraph "su-observer"` に更新
  - 関係の詳細テーブル: `Observer` 行を `Supervision` に更新

## Capabilities

### New Capabilities

なし（ドキュメント更新のみ）

### Modified Capabilities

- **Context Map の Supervision Context**: Cross-cutting 分類の Context 名が `Observer` から `Supervision` に変更され、ADR-013 の命名規則と一致する

## Impact

- 対象ファイル: `plugins/twl/architecture/domain/context-map.md` の 3 箇所（テーブル行・依存関係図・DCI フロー図）
- 他ファイルへの影響なし
- 実装・動作変更なし
