## Name
Visualization

## Key Entities

- **Graph**: コンポーネント間の依存関係グラフ。ノードとエッジで構成
- **Node**: グラフのノード。コンポーネント名、型、トークン数を持つ
- **Edge**: グラフのエッジ。calls フィールドから生成される呼び出し関係
- **SVG**: Graphviz から生成される SVG ファイル。README.md に埋め込まれる
- **Subgraph**: entry_point を起点とした部分グラフ。大規模プラグインの可視化に使用

## Dependencies

- **Plugin Structure (upstream)**: コンポーネントグラフを入力として受け取る

## Constraints

- 可視化は deps.yaml の calls フィールドのみを情報源とする。can_spawn は可視化に影響しない
- Graphviz（dot コマンド）はオプショナル依存。未インストール時は DOT テキスト出力のみ
- SVG 生成は plugin_root 直下に出力。サブグラフ SVG は entry_point 単位で分割

## CLI Commands

| コマンド | 説明 |
|---------|------|
| `twl` (デフォルト) | Graphviz DOT 形式で出力 |
| `twl --graphviz` | Graphviz DOT 形式で出力（明示指定） |
| `twl --mermaid` | Mermaid 形式で出力 |
| `twl --tree` | ASCII ツリー形式で出力 |
| `twl --rich` | Rich ライブラリによるカラーツリー出力 |
| `twl --update-readme` | SVG を生成し README.md に埋め込み |
| `twl --target <name>` | 指定コンポーネントの依存を追跡表示 |
| `twl --reverse <name>` | 指定コンポーネントの逆依存を表示 |
