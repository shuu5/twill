## 1. context-map.md 更新

- [ ] 1.1 Context 分類テーブルの `Cross-cutting | Observer` 行を `Cross-cutting | Supervision` に更新
- [ ] 1.2 依存関係図（Mermaid graph TD）の Cross-cutting サブグラフで `COBS["Observer<br/>(Meta-cognitive)"]` ノードを `SOBS["Supervision<br/>(Meta-cognitive)"]` に更新し、関連エッジの `COBS` 参照を `SOBS` に変更
- [ ] 1.3 DCI フロー図（Mermaid graph LR）の `subgraph "co-observer"` を `subgraph "su-observer"` に更新
- [ ] 1.4 関係の詳細テーブルの `Observer` Upstream 行（3行）を `Supervision` に更新

## 2. 検証

- [ ] 2.1 `context-map.md` に `Observer` が残存していないか grep 確認
- [ ] 2.2 Mermaid 図が文法的に正しいことを目視確認
