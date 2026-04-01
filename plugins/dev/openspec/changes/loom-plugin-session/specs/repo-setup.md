## ADDED Requirements

### Requirement: bare repo 構成の作成

`shuu5/loom-plugin-session` リポジトリを bare repo + main worktree 構成で作成しなければならない（SHALL）。

#### Scenario: リポジトリ初期化
- **WHEN** `loom-plugin-session` リポジトリを新規作成する
- **THEN** `.bare/` ディレクトリが存在し、`main/.git` がファイルとして `.bare` を指す

#### Scenario: worktree 構成の検証
- **WHEN** `main/` ディレクトリで `git status` を実行する
- **THEN** `main` ブランチとして正常に動作する

### Requirement: CLAUDE.md の作成

plugin のルートに CLAUDE.md を配置し、plugin の目的と構成を記述しなければならない（MUST）。

#### Scenario: CLAUDE.md の内容
- **WHEN** CLAUDE.md を読む
- **THEN** plugin 名、設計哲学、bare repo 構造検証ルール、編集フローが記載されている
