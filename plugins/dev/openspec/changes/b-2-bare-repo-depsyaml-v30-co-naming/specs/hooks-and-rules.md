## ADDED Requirements

### Requirement: PostToolUse hook による loom validate 自動実行

hooks.json に PostToolUse hook を定義し、Edit/Write 操作後に `loom validate` を自動実行しなければならない（MUST）。

#### Scenario: Edit 操作後に loom validate が実行される
- **WHEN** Edit ツールでファイルを変更する
- **THEN** PostToolUse hook が発火し `loom validate` が実行される

#### Scenario: validate 違反時に報告される
- **WHEN** loom validate が violation を検出する
- **THEN** 違反内容がユーザーに報告される

### Requirement: PostToolUse hook による Bash エラー記録

PostToolUse hook で Bash コマンドの exit_code != 0 を検出し、`.self-improve/errors.jsonl` にエラー情報を記録しなければならない（SHALL）。これは B-7 (Self-Improve Review) の基盤となる。

#### Scenario: Bash コマンド失敗時にエラーが記録される
- **WHEN** Bash ツールで実行したコマンドが exit_code != 0 で終了する
- **THEN** `.self-improve/errors.jsonl` にタイムスタンプ、コマンド、exit_code、出力を含む JSON 行が追記される

#### Scenario: Bash コマンド成功時にエラーが記録されない
- **WHEN** Bash ツールで実行したコマンドが exit_code == 0 で終了する
- **THEN** `.self-improve/errors.jsonl` にエントリが追加されない

### Requirement: CLAUDE.md に bare repo 検証ルール記載

CLAUDE.md に bare repo 構造検証の3条件を記載しなければならない（MUST）:
1. `.bare/` が存在する
2. `main/.git` がファイルで `.bare` を指す
3. CWD が `main/` 配下である

#### Scenario: CLAUDE.md に bare repo 検証が記載されている
- **WHEN** CLAUDE.md を読み込む
- **THEN** bare repo 構造検証の3条件が全て記載されている

#### Scenario: セッション起動ルールが記載されている
- **WHEN** CLAUDE.md を読み込む
- **THEN** Pilot は `main/` でセッションを起動する必要があること、Worker は Pilot が作成した `worktrees/{branch}/` ディレクトリで起動されることが明記されている

### Requirement: .gitignore の配置

.gitignore を配置し、`.self-improve/` ディレクトリと `.code-review-graph/` ディレクトリを除外しなければならない（SHALL）。

#### Scenario: .gitignore が適切な除外パターンを含む
- **WHEN** .gitignore を読み込む
- **THEN** `.self-improve/` と `.code-review-graph/` が除外パターンに含まれている
