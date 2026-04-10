## Requirements

### Requirement: orphans で script ノードを検出する
find_orphans 関数は script ノードを走査対象に含め、呼び出し元がない script を unused として報告しなければならない（MUST）。

#### Scenario: 未使用 script の検出
- **WHEN** `twl --orphans` を実行し、どのコンポーネントからも calls されていない script が存在する
- **THEN** unused リストにその `script:{name}` が含まれる

#### Scenario: 使用中 script は報告しない
- **WHEN** script が atomic コンポーネントの calls から参照されている
- **THEN** その script は unused リストに含まれない

### Requirement: dead component 検出で script を含める
check_dead_components 関数は script ノードを走査対象に含め、controller から到達不能な script を dead として報告しなければならない（SHALL）。

#### Scenario: 到達不能 script の検出
- **WHEN** `twl --complexity` を実行し、controller → ... → atomic → script の経路が存在しない script がある
- **THEN** Dead Components リストにその script が含まれる

### Requirement: check でスクリプトファイルの存在確認をする
check_files 関数は script ノードの path フィールドが指すファイルの存在を確認しなければならない（MUST）。

#### Scenario: スクリプトファイルが存在する
- **WHEN** `twl --check` を実行し、script の path が指すファイルが存在する
- **THEN** そのノードは `ok` と判定される

#### Scenario: スクリプトファイルが見つからない
- **WHEN** `twl --check` を実行し、script の path が指すファイルが存在しない
- **THEN** そのノードは `missing` と判定され、エラー出力に含まれる

## MODIFIED Requirements

### Requirement: rename で scripts セクションのキー名を変更する
rename_component 関数は scripts セクション内のコンポーネント名を変更し、全コンポーネントの calls 内の `{script: old_name}` 参照を更新しなければならない（MUST）。

#### Scenario: script の rename
- **WHEN** `twl --rename old-script new-script` を実行し、`old-script` が scripts セクションに存在する
- **THEN** deps.yaml の scripts セクションのキーが `new-script` に変更され、全 calls 内の `{script: old-script}` が `{script: new-script}` に更新される

#### Scenario: rename 対象が見つからない
- **WHEN** `twl --rename nonexistent new-name` を実行し、skills/commands/agents/scripts/chains のいずれにも `nonexistent` が存在しない
- **THEN** エラーメッセージが表示され、変更は行われない

### Requirement: complexity_report で script を含める
complexity_report 関数は script ノードの depth/fan-out/cost を計算対象に含めなければならない（SHALL）。

#### Scenario: complexity での script 集計
- **WHEN** `twl --complexity` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** Type Balance セクションに `script` の件数が表示される


### Requirement: rename で scripts セクションのキー名を変更する
rename_component 関数は scripts セクション内のコンポーネント名を変更し、全コンポーネントの calls 内の `{script: old_name}` 参照を更新しなければならない（MUST）。

#### Scenario: script の rename
- **WHEN** `twl --rename old-script new-script` を実行し、`old-script` が scripts セクションに存在する
- **THEN** deps.yaml の scripts セクションのキーが `new-script` に変更され、全 calls 内の `{script: old-script}` が `{script: new-script}` に更新される

#### Scenario: rename 対象が見つからない
- **WHEN** `twl --rename nonexistent new-name` を実行し、skills/commands/agents/scripts/chains のいずれにも `nonexistent` が存在しない
- **THEN** エラーメッセージが表示され、変更は行われない

### Requirement: complexity_report で script を含める
complexity_report 関数は script ノードの depth/fan-out/cost を計算対象に含めなければならない（SHALL）。

#### Scenario: complexity での script 集計
- **WHEN** `twl --complexity` を実行し、scripts セクションにコンポーネントが存在する
- **THEN** Type Balance セクションに `script` の件数が表示される
