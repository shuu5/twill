## Why

su-observer の設計意図（ADR-014）は「常駐 + 全 controller を session:spawn → observe」だが、architecture spec（supervision.md / observation.md / context-map.md / model.md）がこのパターンを正確に反映しておらず、仕様と実装の乖離が生じている。

## What Changes

- **supervision.md**: 常駐ループ mermaid 図に co-self-improve / co-utility / co-project への spawn パスを追加。「委譲」が session:spawn メカニズムであることを明記。co-autopilot のみ能動 observe、他は spawn 後即指示待ちという差異を明記
- **observation.md**: Observe ループ mermaid の開始ノードを「su-observer が session:spawn で co-self-improve を起動」に変更し、spawn 関係を明示
- **context-map.md**: Supervision → Live Observation の関係を「session:spawn → observe」と具体化し、`SOBS -->|"Customer-Supplier session:spawn → observe"| OBS` に更新
- **model.md**: Supervisor コンポーネントの `type: observer` を `type: supervisor` に修正（タイポ修正）

## Capabilities

### New Capabilities

なし（既存設計の文書化修正）

### Modified Capabilities

- **Supervision Context 文書**: 常駐 observer パターンの全 controller spawn パスが可視化される
- **Observation Context 文書**: su-observer → session:spawn → co-self-improve の起動関係が明示される
- **Context Map 文書**: Supervision と Live Observation の具体的な通信メカニズムが明記される
- **Domain Model 文書**: Supervisor の type フィールドが正確になる

## Impact

影響ファイル（文書のみ、実装コードなし）:
- `plugins/twl/architecture/domain/contexts/supervision.md`
- `plugins/twl/architecture/domain/contexts/observation.md`
- `plugins/twl/architecture/domain/context-map.md`
- `plugins/twl/architecture/domain/model.md`
