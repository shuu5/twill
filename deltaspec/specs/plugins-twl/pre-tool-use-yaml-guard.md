## Requirements

### Requirement: PreToolUse YAML syntax guard スクリプト

deps.yaml への Write/Edit ツール実行前に YAML syntax を検証するスクリプト `plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh` が存在しなければならない（SHALL）。スクリプトは stdin から JSON を受け取り、YAML syntax エラー検出時は exit 2 で実行をブロックしなければならない（MUST）。

#### Scenario: Write ツールで不正な YAML を送信した場合
- **WHEN** `Write(deps.yaml)` で YAML parse エラーになるコンテンツが `tool_input.content` に含まれる
- **THEN** exit 2 で終了し、stderr に YAML syntax エラーメッセージが表示される

#### Scenario: Edit ツールで不正な YAML になる変更を送信した場合
- **WHEN** `Edit(deps.yaml)` で `old_string`/`new_string` の simulated apply 後に YAML parse エラーになる
- **THEN** exit 2 で終了し、stderr に YAML syntax エラーメッセージが表示される

#### Scenario: 正常な YAML の Write を送信した場合
- **WHEN** `Write(deps.yaml)` で有効な YAML コンテンツが送信される
- **THEN** exit 0 で正常通過し、ツールの実行がブロックされない

#### Scenario: 正常な YAML になる Edit を送信した場合
- **WHEN** `Edit(deps.yaml)` の simulated apply 後も有効な YAML が維持される
- **THEN** exit 0 で正常通過する

### Requirement: hooks.json への PreToolUse エントリ追加

`plugins/twl/hooks/hooks.json` に PreToolUse エントリを追加し、deps.yaml を対象とする Edit/Write のみに絞り込まなければならない（SHALL）。

#### Scenario: deps.yaml 以外のファイルへの Edit/Write
- **WHEN** deps.yaml 以外のファイルに対して Edit または Write ツールが実行される
- **THEN** hook が発火しない（`if` 条件による除外）

#### Scenario: PreToolUse hook のタイムアウト
- **WHEN** hook スクリプトが実行される
- **THEN** 3000ms 以内に完了する（SHALL）

### Requirement: deps.yaml へのスクリプトコンポーネント登録

`plugins/twl/deps.yaml` の scripts セクションに `pre-tool-use-deps-yaml-guard.sh` のコンポーネントエントリを追加しなければならない（SHALL）。

#### Scenario: deps.yaml コンポーネント登録の整合性
- **WHEN** `twl --check` を実行する
- **THEN** 新規スクリプトが deps.yaml に登録されており、コンポーネント整合性チェックが通過する
