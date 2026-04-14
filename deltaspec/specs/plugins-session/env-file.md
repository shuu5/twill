## Requirements

### Requirement: cld-spawn --env-file オプション

`cld-spawn` は `--env-file PATH` オプションを受け付け、起動する Worker セッションのランチャースクリプト内で指定ファイルをソースしなければならない（SHALL）。

#### Scenario: --env-file で env file を指定して起動
- **WHEN** `cld-spawn --env-file ~/.secrets` を実行する
- **THEN** 起動した tmux window の bash セッションで `~/.secrets` の環境変数が利用可能である

#### Scenario: --env-file にチルダパスを指定
- **WHEN** `cld-spawn --env-file ~/path/to/secrets` のように `~` を含むパスを指定する
- **THEN** `~` が `$HOME` に展開され、正しいパスが参照される

#### Scenario: env file が存在しない場合
- **WHEN** 指定した `--env-file` のパスにファイルが存在しない
- **THEN** エラーを発生させず、既存の起動フローが継続される（`2>/dev/null || true`）

### Requirement: CLD_ENV_FILE 環境変数による自動ソース

`cld-spawn` は `--env-file` 未指定時に `CLD_ENV_FILE` 環境変数が設定されていれば、その値をデフォルト env file として自動ソースしなければならない（SHALL）。

#### Scenario: CLD_ENV_FILE が設定されている場合
- **WHEN** `CLD_ENV_FILE=~/.secrets` が設定された状態で `cld-spawn` を実行する（`--env-file` 未指定）
- **THEN** `~/.secrets` が Worker セッションで自動ソースされる

#### Scenario: --env-file も CLD_ENV_FILE も未設定の場合
- **WHEN** `--env-file` 引数も `CLD_ENV_FILE` 環境変数も未指定で `cld-spawn` を実行する
- **THEN** 既存動作に変更なく、ランチャースクリプトに source 行が追加されない

### Requirement: issue-lifecycle-orchestrator.sh の cld-spawn 呼び出し

`issue-lifecycle-orchestrator.sh` は cld-spawn を呼び出す箇所で `--env-file ~/.secrets` を渡さなければならない（MUST）。

#### Scenario: orchestrator が Worker セッションを起動する
- **WHEN** `issue-lifecycle-orchestrator.sh` が cld-spawn を呼び出す
- **THEN** `--env-file ~/.secrets` が引数として渡され、Worker セッションで `~/.secrets` が利用可能になる
