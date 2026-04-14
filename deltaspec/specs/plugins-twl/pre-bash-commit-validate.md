## Requirements

### Requirement: PreToolUse commit validate hook
`.claude/settings.json` の `hooks.PreToolUse` に Bash ツール向けのエントリを追加し、`git commit` 実行前に `plugins/twl/scripts/hooks/pre-bash-commit-validate.sh` が呼び出されなければならない（SHALL）。

#### Scenario: git commit 時に validate hook が起動する
- **WHEN** ユーザーが Claude Code から `git commit` を含む Bash コマンドを実行する
- **THEN** `pre-bash-commit-validate.sh` が PreToolUse フェーズで自動実行される

### Requirement: validate 失敗時のコミットブロック
deps.yaml に型ルール違反がある状態で `git commit` を実行した場合、hook は exit 2 を返してコミットをブロックしなければならない（SHALL）。stderr に違反内容が表示されなければならない（SHALL）。

#### Scenario: deps.yaml 型ルール違反ありの場合
- **WHEN** `twl --validate` の実行結果で violations > 0 である
- **THEN** スクリプトが exit 2 を返し、コミットがブロックされ、stderr に違反内容が出力される

### Requirement: validate 通過時のコミット許可
deps.yaml に型ルール違反がない状態では、hook は exit 0 を返してコミットを通過させなければならない（SHALL）。

#### Scenario: deps.yaml に違反なしの場合
- **WHEN** `twl --validate` の実行結果で violations == 0 である
- **THEN** スクリプトが exit 0 を返し、コミットが通過する

### Requirement: git commit 以外のコマンドはスキップ
`git commit` を含まない Bash コマンドに対しては、hook は何もせず exit 0 を返さなければならない（SHALL）。

#### Scenario: git status など git commit 以外の Bash コマンド
- **WHEN** `$TOOL_INPUT_command` に `git commit` パターンが含まれない
- **THEN** スクリプトが即 exit 0 を返し、何も実行しない

### Requirement: deps.yaml 不在時のスキップ
`plugins/twl/deps.yaml` が存在しないディレクトリ（worktree 外など）では、hook は exit 0 を返してスキップしなければならない（SHALL）。

#### Scenario: deps.yaml が存在しない場合
- **WHEN** スクリプトが `cd plugins/twl` した後に `deps.yaml` が見つからない
- **THEN** スクリプトが exit 0 を返し、コミットをブロックしない

### Requirement: TWL_SKIP_COMMIT_GATE によるバイパス
`TWL_SKIP_COMMIT_GATE=1` 環境変数が設定されている場合、hook は `twl --validate` を実行せず exit 0 を返さなければならない（SHALL）。

#### Scenario: TWL_SKIP_COMMIT_GATE=1 設定時
- **WHEN** 環境変数 `TWL_SKIP_COMMIT_GATE` が `1` に設定された状態で `git commit` を実行する
- **THEN** スクリプトが exit 0 を返し、コミットが通過する

### Requirement: タイムアウト制限
hook は `timeout: 5000`（5000ms）以内に完了しなければならない（SHALL）。

#### Scenario: 通常の validate 実行時間
- **WHEN** `twl --validate` が正常に実行される
- **THEN** 5000ms 以内に完了し、timeout エラーが発生しない

### Requirement: deps.yaml スクリプトエントリ
`plugins/twl/deps.yaml` の `scripts` セクションに `hooks/pre-bash-commit-validate.sh` のエントリが追加されなければならない（SHALL）。

#### Scenario: deps.yaml へのスクリプト登録
- **WHEN** `plugins/twl/deps.yaml` を参照する
- **THEN** `scripts` セクションに `pre-bash-commit-validate` エントリが存在し、path と description が設定されている
