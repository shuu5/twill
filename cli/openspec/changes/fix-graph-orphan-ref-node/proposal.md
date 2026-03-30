## Why

`loom graph` / `loom update-svgs` が生成する DOT/SVG で、orphan 分類が不正確であり ref ノード描画にも不備がある。sub-commands が誤って Orphan（ピンク）として描画され、reference 型スキルが Legend に含まれない。

## What Changes

- `build_graph()` で agent.skills フィールドを reverse dependency 計算に反映
- `classify_layers()` の再帰走査を L1→L2 のみから全階層に拡張
- `generate_graphviz()` の Legend に reference 型を追加

## Capabilities

### New Capabilities

- Legend に reference 型（shape=note）が表示される

### Modified Capabilities

- agent.skills で参照されるスキルが required_by に正しく反映される
- cmd→cmd チェーンで到達可能な sub-commands が Orphan ではなく適切なレイヤーに分類される

## Impact

- **対象ファイル**: `loom-engine.py`（build_graph, classify_layers, generate_graphviz の 3 関数）
- **推定変更量**: 約 45 行
- **既存テスト**: 変更後も全テスト PASS が必須
- **依存関係**: shuu5/loom-plugin-dev#41（deps.yaml calls 完全化）と並行実装可能
