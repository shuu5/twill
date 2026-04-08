# project-create

co-project によるプロジェクト新規作成（bare repo→worktree→テンプレート→Board）を定義するシナリオ。

## Scenario: 正常系プロジェクト作成

- **WHEN** ユーザーが `co-project create my-project` を実行する
- **THEN** `my-project/.bare/` が git bare repository として初期化される
- **AND** `my-project/main/` worktree が作成され `.git` ファイルが `.bare` を指す
- **AND** テンプレートファイルが `main/` に配置される
- **AND** `openspec/config.yaml` が作成される

## Scenario: bare repo 構造検証

- **WHEN** プロジェクト作成完了後にセッションを開始する
- **THEN** 検証条件 1: `.bare/` が存在する
- **AND** 検証条件 2: `main/.git` がファイルで `.bare` を指す
- **AND** 検証条件 3: CWD が `main/` 配下である
- **AND** 全条件を満たさない場合はエラーメッセージが表示される

## Scenario: Project Board 自動作成

- **WHEN** プロジェクト作成時に GitHub リポジトリが指定されている
- **THEN** GitHub Project V2 が自動作成される
- **AND** リポジトリにリンクされる
- **AND** Status フィールド（Todo, In Progress, Done）が初期設定される

## Scenario: テンプレート種類指定

- **WHEN** ユーザーが `co-project create my-plugin --template plugin` を実行する
- **THEN** plugin テンプレートが適用される（deps.yaml v3.0 scaffold 含む）
- **AND** 旧 controller-plugin 相当の初期構造が生成される

## Scenario: ガバナンス自動適用

- **WHEN** プロジェクト作成が完了する
- **THEN** project-governance が自動実行される
- **AND** PostToolUse hook が `.claude/settings.json` に設定される
- **AND** CLAUDE.md に `<!-- GOVERNANCE-START -->` マーカーが追加される

## Scenario: worktrees/ ディレクトリ構造

- **WHEN** プロジェクト作成完了後に worktree を作成する
- **THEN** `my-project/worktrees/feat/42-xxx/` に worktree が作成される
- **AND** `main/` と `worktrees/` は独立した作業ディレクトリとして機能する

## Scenario: GitHub リポジトリ未指定時のローカルプロジェクト

- **WHEN** `co-project create my-local-project` を GitHub リポジトリ指定なしで実行する
- **THEN** bare repo + worktree の構造はローカルに作成される
- **AND** Project Board 作成はスキップされる（GitHub リポジトリが未指定のため）

## Scenario: 重複プロジェクト検出

- **WHEN** 既に存在するプロジェクト名で `co-project create` を実行する
- **THEN** エラーメッセージが表示され作成が中止される
- **AND** 既存プロジェクトのパスが表示される

## Scenario: Rich Mode（manifest.yaml 存在時）

- **WHEN** テンプレートに manifest.yaml が存在する
- **THEN** スタック情報テーブルが表示される
- **AND** containers セクションがあれば `/twl:container-dependency-check` が実行される
- **AND** post_create セクションがあれば表示される

## Scenario: Board ビュー標準設定

- **WHEN** プロジェクト作成完了後に Board 設定が実行される
- **AND** `--no-github` が指定されていない
- **THEN** `/twl:project-board-configure` が実行される
- **AND** 不足フィールドが検出された場合はブラウザが開き設定が案内される
- **WHEN** `--no-github` が指定されている
- **THEN** Board ビュー設定はスキップされる
