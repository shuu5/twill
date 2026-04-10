## Requirements

### Requirement: types.yaml に script 型を定義
types.yaml の types セクションに `script` 型を追加しなければならない（SHALL）。section は `scripts`、can_spawn は `[]`、spawnable_by は `[atomic, composite]` とする。

#### Scenario: types.yaml 読み込み
- **WHEN** twl-engine.py が起動し types.yaml を読み込む
- **THEN** TYPE_RULES に `script` キーが存在し、section=`scripts`, can_spawn=`set()`, spawnable_by=`{'atomic', 'composite'}` が設定される

#### Scenario: twl rules 表示
- **WHEN** `twl rules` を実行する
- **THEN** script 型の行が表示され、section/can_spawn/spawnable_by が正しく出力される

### Requirement: deps.yaml の scripts セクションをパースする
load_deps から返される dict の `scripts` セクションを build_graph で処理し、`script:{name}` 形式のグラフノードを構築しなければならない（MUST）。

#### Scenario: scripts セクション付き deps.yaml の読み込み
- **WHEN** deps.yaml に `scripts:` セクションが定義され、エントリに type/path/description/calls が含まれる
- **THEN** build_graph が `script:{name}` ノードを生成し、type=`script`、path/description/calls が正しく設定される

#### Scenario: scripts セクションが存在しない deps.yaml
- **WHEN** deps.yaml に `scripts:` セクションがない
- **THEN** build_graph は script ノードを生成せず、エラーも発生しない

### Requirement: parse_calls で script キーを解釈する
parse_calls 内の key_map に `'script': 'script'` を追加し、`{script: name}` 形式の calls エントリを解析しなければならない（SHALL）。

#### Scenario: calls 内の script 参照
- **WHEN** コンポーネントの calls に `{script: autopilot-plan}` が含まれる
- **THEN** parse_calls が `('script', 'autopilot-plan', None)` タプルを返す

#### Scenario: step 付き script 参照
- **WHEN** calls に `{script: build, step: "2.1"}` が含まれる
- **THEN** parse_calls が `('script', 'build', '2.1')` タプルを返す

## MODIFIED Requirements

### Requirement: find_node の prefix リストに script を追加する
find_node 関数の検索 prefix リストに `script` を追加しなければならない（MUST）。これにより `--target` や `--reverse` で script ノードを名前指定で検索できる。

#### Scenario: script ノードの名前検索
- **WHEN** `twl --target autopilot-plan` を実行し、`script:autopilot-plan` ノードが存在する
- **THEN** find_node が `script:autopilot-plan` を返す

### Requirement: 逆依存グラフで script ノードを含める
build_graph の逆依存構築ループで、script ノードへの calls エッジが required_by に反映されなければならない（SHALL）。

#### Scenario: script の逆依存
- **WHEN** `command:autopilot-launch` が `{script: autopilot-plan}` を calls に持つ
- **THEN** `script:autopilot-plan` の required_by に `('command', 'autopilot-launch')` が含まれる


### Requirement: find_node の prefix リストに script を追加する
find_node 関数の検索 prefix リストに `script` を追加しなければならない（MUST）。これにより `--target` や `--reverse` で script ノードを名前指定で検索できる。

#### Scenario: script ノードの名前検索
- **WHEN** `twl --target autopilot-plan` を実行し、`script:autopilot-plan` ノードが存在する
- **THEN** find_node が `script:autopilot-plan` を返す

### Requirement: 逆依存グラフで script ノードを含める
build_graph の逆依存構築ループで、script ノードへの calls エッジが required_by に反映されなければならない（SHALL）。

#### Scenario: script の逆依存
- **WHEN** `command:autopilot-launch` が `{script: autopilot-plan}` を calls に持つ
- **THEN** `script:autopilot-plan` の required_by に `('command', 'autopilot-launch')` が含まれる
