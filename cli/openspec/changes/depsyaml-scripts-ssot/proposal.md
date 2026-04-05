## Why

twl CLI は skills/commands/agents の3セクションを追跡するが、scripts/ 配下の実行スクリプト（.sh/.py）は deps.yaml で管理されていない。これにより可視化・存在確認・rename追従・dead component検出が不可能であり、SSOT原則に反している。

## What Changes

- types.yaml に `script` 型を追加（section: scripts, can_spawn: [], spawnable_by: [atomic, composite]）
- deps.yaml パーサーで `scripts` セクションを読み込み、グラフノードとして構築
- calls の型名キーに `script` を追加（呼び出し元から `{script: name}` で参照）
- validate/deep-validate/audit で script 型に対して frontmatter/body-ref/tools/model チェックをスキップ
- graphviz/tree/mermaid で script ノードをオレンジ・六角形で表示
- orphans/complexity で script を対象に含める
- rename で script 名変更に対応
- 旧形式のコンポーネント内 `scripts:` フィールドに WARNING を出す

## Capabilities

### New Capabilities

- deps.yaml の `scripts` セクションでスクリプトを型付きコンポーネントとして定義可能
- `--check` でスクリプトファイルの存在確認
- `--validate` で script の can_spawn/spawnable_by ルール検証
- `--graphviz / --tree / --mermaid` でスクリプトノードの表示（オレンジ・六角形）
- `--orphans / --complexity` で未使用スクリプトの検出
- `--rename` でスクリプト名変更時の呼び出し元追従
- `--list / --tokens` でスクリプトのリスト表示・トークン数表示

### Modified Capabilities

- `build_graph()`: scripts セクションからノード構築、parse_calls に `script` キー追加
- `validate_types()`: scripts セクションの型ルール検証、edge チェックで script キー対応
- `generate_graphviz()` / `generate_subgraph_graphviz()`: script レイヤーのノード描画追加
- `find_orphans()` / `check_dead_components()`: script ノードを対象に含める
- `rename_component()`: scripts セクションのキー名変更と calls 内 script 参照更新
- `audit_report()` / `deep_validate()`: script 型は frontmatter/tools チェックをスキップ

## Impact

- **types.yaml**: `script` 型エントリ追加（1箇所）
- **twl-engine.py**: build_graph, parse_calls, classify_layers, generate_graphviz, generate_subgraph_graphviz, generate_mermaid, validate_types, validate_v3_schema, find_orphans, check_dead_components, rename_component, audit_report, deep_validate, complexity_report, main 等の関数に変更
- **tests/**: 既存テストの更新 + script 型用の新規テスト追加
- **下位互換性**: scripts セクション未定義のプラグインには影響なし
