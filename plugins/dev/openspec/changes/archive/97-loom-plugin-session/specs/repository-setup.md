## ADDED Requirements

### Requirement: bare repo リポジトリ作成

shuu5/loom-plugin-session リポジトリを bare repo + main worktree 構成で作成しなければならない（SHALL）。

#### Scenario: リポジトリ初期化
- **WHEN** `gh repo create shuu5/loom-plugin-session --public` でリポジトリを作成し、bare repo 構成でクローンする
- **THEN** `.bare/` ディレクトリが存在し、`main/.git` がファイルで `.bare` を指す

#### Scenario: worktree 構成の検証
- **WHEN** リポジトリのルートを確認する
- **THEN** `main/` ディレクトリが worktree として機能し、`git worktree list` で表示される

### Requirement: CLAUDE.md 作成

プロジェクトルートに CLAUDE.md を配置し、plugin の基本情報とルールを記載しなければならない（MUST）。

#### Scenario: CLAUDE.md の内容
- **WHEN** CLAUDE.md を確認する
- **THEN** bare repo 構造検証ルール、編集フロー、loom CLI 必須ルールが記載されている
