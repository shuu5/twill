## Context

`plugins/twl/architecture/domain/context-map.md` は twill-ecosystem の Bounded Context 間の依存関係を定義するドキュメント。ADR-013 で `co-observer` が `su-observer`（Supervision Observer）として再定義されたが、Context Map の Cross-cutting Context 名が旧名 `Observer` のまま残っている。本変更はドキュメントのみの更新で、実装変更なし。

## Goals / Non-Goals

**Goals:**
- Context Map の Cross-cutting Context 名を `Observer` → `Supervision` に統一する
- 依存関係図・DCI フロー図・関係テーブルを同時に整合させる

**Non-Goals:**
- `co-observer` スキル/コマンドのリネームは対象外
- 他の architecture/ ファイルの更新は対象外
- COBS ノード名の変更はオプション（レンダリング影響なしのため）

## Decisions

1. **ノード名の変更**: `COBS["Observer<br/>(Meta-cognitive)"]` → `SOBS["Supervision<br/>(Meta-cognitive)"]`
   - 意味的整合のために変更。Mermaid ID の変更は内部参照のため他ファイルへの影響なし
2. **DCI フロー図のサブグラフ**: `co-observer` → `su-observer`
   - ADR-013 の命名規則に合わせる
3. **テーブル行**: `Observer` 3 行すべてを `Supervision` に置換

## Risks / Trade-offs

- **リスク低**: ドキュメント専用の変更のため、動作への影響ゼロ
- **注意点**: COBS ノード ID を変更する場合、Mermaid 図内の参照（`COBS -->` 等）もすべて `SOBS -->` に更新が必要
