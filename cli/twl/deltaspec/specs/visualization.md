## Requirements

### Requirement: graphviz で script ノードをオレンジ六角形で表示する
generate_graphviz 関数は script ノードをオレンジ（#FF9800）の hexagon 形状で描画しなければならない（MUST）。

#### Scenario: graphviz 出力での script ノード
- **WHEN** `twl --graphviz` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** DOT 出力に `shape=hexagon, style=filled, fillcolor="#FF9800"` を持つ script ノードが含まれる

#### Scenario: scripts がない場合
- **WHEN** deps.yaml に scripts セクションがない
- **THEN** graphviz 出力に script ノード定義が含まれない

### Requirement: subgraph_graphviz でも script ノードを描画する
generate_subgraph_graphviz 関数も同様に script ノードをオレンジ六角形で描画しなければならない（SHALL）。

#### Scenario: サブグラフでの script 表示
- **WHEN** `twl --update-readme` でサブグラフ SVG を生成する
- **THEN** script ノードがサブグラフ内に含まれ、オレンジ六角形で描画される

### Requirement: classify_layers に scripts レイヤーを追加する
classify_layers 関数は scripts セクションのコンポーネント名リストを返さなければならない（MUST）。

#### Scenario: レイヤー分類
- **WHEN** classify_layers を実行し、scripts セクションにコンポーネントが存在する
- **THEN** 返り値の dict に `scripts` キーが存在し、スクリプト名のリストが含まれる

### Requirement: mermaid で script ノードを表示する
generate_mermaid 関数は script ノードを六角形構文 `{{name}}` で表示し、オレンジのスタイルを適用しなければならない（SHALL）。

#### Scenario: mermaid 出力での script ノード
- **WHEN** `twl --mermaid` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** Mermaid 出力に script ノードが六角形構文で含まれ、style 定義にオレンジ色が指定される

## MODIFIED Requirements

### Requirement: tree 表示で script ノードを含める
print_tree 関数は calls に含まれる script ノードを子ノードとして表示しなければならない（MUST）。

#### Scenario: tree での script 表示
- **WHEN** `twl --target autopilot-launch` を実行し、そのコンポーネントが `{script: autopilot-plan}` を呼ぶ
- **THEN** ツリー出力に `script:autopilot-plan` が子ノードとして表示される

### Requirement: list 表示で SCRIPTS セクションを追加する
`twl --list` 出力に `## SCRIPTS` セクションを追加し、script ノードをリスト表示しなければならない（SHALL）。

#### Scenario: list での script 表示
- **WHEN** `twl --list` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** `## SCRIPTS` セクションに script ノードが名前・説明付きで表示される

### Requirement: tokens 表示で Scripts セクションを追加する
`twl --tokens` 出力に `## Scripts` セクションを追加し、スクリプトのトークン数を表示しなければならない（SHALL）。

#### Scenario: tokens での script 表示
- **WHEN** `twl --tokens` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** `## Scripts` セクションに各スクリプトのトークン数が表示される

### Requirement: graphviz のエッジ描画で script ノードへの接続を含める
generate_graphviz のエッジ生成ループで、calls の target が `script:` prefix を持つ場合もエッジを描画しなければならない（MUST）。

#### Scenario: script へのエッジ
- **WHEN** command ノードが script ノードを calls に含む
- **THEN** graphviz 出力に command → script の有向エッジが含まれる


### Requirement: tree 表示で script ノードを含める
print_tree 関数は calls に含まれる script ノードを子ノードとして表示しなければならない（MUST）。

#### Scenario: tree での script 表示
- **WHEN** `twl --target autopilot-launch` を実行し、そのコンポーネントが `{script: autopilot-plan}` を呼ぶ
- **THEN** ツリー出力に `script:autopilot-plan` が子ノードとして表示される

### Requirement: list 表示で SCRIPTS セクションを追加する
`twl --list` 出力に `## SCRIPTS` セクションを追加し、script ノードをリスト表示しなければならない（SHALL）。

#### Scenario: list での script 表示
- **WHEN** `twl --list` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** `## SCRIPTS` セクションに script ノードが名前・説明付きで表示される

### Requirement: tokens 表示で Scripts セクションを追加する
`twl --tokens` 出力に `## Scripts` セクションを追加し、スクリプトのトークン数を表示しなければならない（SHALL）。

#### Scenario: tokens での script 表示
- **WHEN** `twl --tokens` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** `## Scripts` セクションに各スクリプトのトークン数が表示される

### Requirement: graphviz のエッジ描画で script ノードへの接続を含める
generate_graphviz のエッジ生成ループで、calls の target が `script:` prefix を持つ場合もエッジを描画しなければならない（MUST）。

#### Scenario: script へのエッジ
- **WHEN** command ノードが script ノードを calls に含む
- **THEN** graphviz 出力に command → script の有向エッジが含まれる
