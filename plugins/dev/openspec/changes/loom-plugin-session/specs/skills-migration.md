## ADDED Requirements

### Requirement: spawn スキルの移植

spawn SKILL.md を `skills/spawn/SKILL.md` に移植し、パス参照を `${CLAUDE_PLUGIN_ROOT}/scripts/` ベースに更新しなければならない（SHALL）。

#### Scenario: 引数なし spawn
- **WHEN** ユーザーが `/spawn` を実行する
- **THEN** 現在のディレクトリで新規 tmux ウィンドウが作成され cld が起動する

#### Scenario: プロンプト付き spawn
- **WHEN** ユーザーが `/spawn "テストを実行して"` を実行する
- **THEN** 初期プロンプトとしてテキストが渡された新規セッションが起動する

#### Scenario: --cd 付き spawn
- **WHEN** ユーザーが `/spawn --cd ~/other-project` を実行する
- **THEN** 指定ディレクトリで新規セッションが起動する

### Requirement: observe スキルの移植

observe SKILL.md を `skills/observe/SKILL.md` に移植し、パス参照を plugin-relative に更新しなければならない（SHALL）。

#### Scenario: 単一ウィンドウ自動選択
- **WHEN** 他に 1 つだけ Claude Code ウィンドウが存在する状態で `/observe` を実行する
- **THEN** そのウィンドウの内容を自動的にキャプチャして要約する

#### Scenario: 複数ウィンドウ選択
- **WHEN** 複数の Claude Code ウィンドウが存在する状態で `/observe` を実行する
- **THEN** ウィンドウ選択ダイアログを表示する

#### Scenario: 詳細モード
- **WHEN** `/observe verbose` または `/observe 詳しく` を実行する
- **THEN** 100 行分のキャプチャを行う

### Requirement: fork スキルの移植

fork SKILL.md を `skills/fork/SKILL.md` に移植し、パス参照を plugin-relative に更新しなければならない（SHALL）。

#### Scenario: 基本 fork
- **WHEN** ユーザーが `/fork` を実行する
- **THEN** 現在のセッションのコンテキストを引き継いだ新ウィンドウが作成される

#### Scenario: 監視付き fork
- **WHEN** ユーザーが `/fork 監視して` を実行する
- **THEN** fork 後にセッション状態の非同期監視が開始される

### Requirement: SKILL.md パス参照の統一

全 SKILL.md 内のスクリプト参照は `${CLAUDE_PLUGIN_ROOT}/scripts/` を使用しなければならない（MUST）。ハードコードされた絶対パスは禁止。

#### Scenario: パス参照の検証
- **WHEN** 任意の SKILL.md 内でスクリプトパスを参照する
- **THEN** `${CLAUDE_PLUGIN_ROOT}/scripts/<script-name>` 形式で記述されている
