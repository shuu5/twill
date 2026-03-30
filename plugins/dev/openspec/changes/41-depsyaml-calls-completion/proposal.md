## Why

deps.yaml の `calls` フィールドが広範に不完全で、64件のコンポーネントが Isolated 状態。
`loom orphans` で検出される未使用ノードの大半は `calls` 宣言漏れが原因であり、
SVG 依存グラフでエッジが描画されない根本原因となっている。

## What Changes

- 各コマンド/スキルの `calls` に `- reference:`, `- agent:`, `- script:` エントリを追加
- controller の `calls` に `- workflow:` 参照を追加
- 親コマンドの `calls` に sub-command 参照を追加
- composite コマンドの `calls` に動的 spawn される specialist を追加

## Capabilities

### New Capabilities

なし（新機能の追加ではなく、既存宣言の完全化）

### Modified Capabilities

- deps.yaml の `calls` が実際の呼び出し関係を正確に反映
- `loom orphans` の Isolated が 64件 → 10件以下に減少
- SVG 依存グラフに全依存関係エッジが描画される

## Impact

- **deps.yaml**: calls フィールドの大量追加（5カテゴリ: refs, agents, scripts, workflows, sub-commands）
- **SVG**: `loom update-readme` で再生成、エッジ数が大幅に増加
- **loom check / validate**: 継続 PASS が必須（回帰禁止）
- **依存関係**: shuu5/loom#50（graph 修正）と並行実装可。#42（deep-validate）とは独立
