## Context

loom-engine.py (4640行) は Claude Code プラグインの依存関係解析CLIである。現在 skills/commands/agents の3セクションを deps.yaml から読み込み、グラフノードとして構築している。scripts/ 配下の実行スクリプトは deps.yaml で管理されておらず、SSOT原則に反している。

types.yaml が型ルールの SSOT であり、各型の section/can_spawn/spawnable_by を定義する。loom-engine.py は起動時にこれを読み込み TYPE_RULES を構築する。

Issue #31 の設計判断により `script` 型は types.yaml に新規追加し、既存の型システムコードパスに乗せる方針が確定している。

## Goals / Non-Goals

**Goals:**

- types.yaml に `script` 型を追加し、TYPE_RULES で正しく読み込まれること
- deps.yaml の `scripts` セクションをパースし、グラフノード `script:{name}` として構築
- 既存の全コマンド（check, validate, graphviz, tree, mermaid, orphans, complexity, rename, list, tokens）で script ノードが正しく処理される
- script 型に対して不要な検証（frontmatter, body-ref, tools, model）をスキップ
- 旧形式のコンポーネント内 `scripts:` フィールドに対する非推奨 WARNING

**Non-Goals:**

- スクリプト間依存の追跡（can_spawn: [] で固定）
- スクリプトの内容解析（bash/python パース）
- controller → script の直接呼び出し対応
- chain への script 参加

## Decisions

### D1: グラフノード ID は `script:{name}`

既存パターン（`skill:{name}`, `command:{name}`, `agent:{name}`）に合わせる。`find_node()` の prefix リストに `script` を追加する。

### D2: build_graph で scripts セクションを処理

skills/commands/agents と同様のループで `deps.get('scripts', {})` を走査。ノード構造は既存と同じだが、`script_type` はなく代わりに `type: 'script'` とする。

### D3: parse_calls に `script` キーを追加

`key_map` に `'script': 'script'` を追加。これにより `{script: name}` 形式の calls エントリが解析される。

### D4: validate_types で scripts セクションを走査

`section_map` に `'scripts': 'script'` を追加。Check 1〜4 のループに scripts セクションを含める。`call_key_to_section` に `'script': 'scripts'` を追加。

### D5: validate_v3_schema の v3_type_keys に `script` 追加

v3.0 calls キーバリデーションで `script` を許可する。

### D6: graphviz 表示スタイル

- 色: `#FF9800`（オレンジ）
- 形: hexagon
- classify_layers に `scripts` レイヤーを追加

### D7: deep_validate / audit で script をスキップ

- frontmatter チェック: script ノードはスキップ（.sh/.py にはない）
- body-ref チェック: スキップ
- tools 整合性チェック: スキップ
- Self-Contained チェック: スキップ
- Inline Implementation チェック: スキップ

### D8: rename_component で scripts セクション対応

検索対象セクションに `scripts` を追加。calls 内の `script` キー値も更新。ファイルリネームは行わない（スクリプトファイルは path フィールドで管理）。

### D9: 旧形式 WARNING

validate_v3_schema に追加: コンポーネントが `scripts` フィールド（リスト）を持つ場合、WARNING を出す。

## Risks / Trade-offs

- **hexagon 形状**: Graphviz の hexagon はノードラベルが長い場合に見づらくなる可能性がある。ただし script 名は通常短い。
- **spawnable_by の拡張**: 現在 `[atomic, composite]` だが、将来 workflow → script の直接呼び出しが必要になる可能性がある。types.yaml を変更するだけで対応可能。
- **scripts セクション未定義時**: `deps.get('scripts', {})` で空辞書が返るため、既存プラグインに影響なし。
