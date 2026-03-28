## ADDED Requirements

### Requirement: deps.yaml への script エントリ追加

移植した 16 scripts を deps.yaml の scripts セクションに登録しなければならない（MUST）。各エントリは type: script, path, description を含む。

#### Scenario: 全 script が deps.yaml に登録される
- **WHEN** 移植完了後に deps.yaml を確認する
- **THEN** 既存 10 scripts + 移植 16 scripts = 計 26 scripts が scripts セクションに登録されている

#### Scenario: script パスの一貫性
- **WHEN** deps.yaml の script エントリの path を確認する
- **THEN** 全て `scripts/<name>.sh` または `scripts/<name>.py` の形式である

## MODIFIED Requirements

### Requirement: COMMAND.md のスクリプトパス更新

worktree-create, project-create, project-migrate の COMMAND.md が参照するスクリプトパスを `$HOME/.claude/plugins/dev/scripts/` から新リポジトリ内の相対パスに更新しなければならない（MUST）。

#### Scenario: worktree-create COMMAND.md のパス更新
- **WHEN** commands/worktree-create/COMMAND.md を確認する
- **THEN** スクリプト呼び出しが `bash $SCRIPT_DIR/../../scripts/worktree-create.sh` または同等の相対パスを使用している
