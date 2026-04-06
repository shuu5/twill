## ADDED Requirements

### Requirement: session-state.sh の移植

session-state.sh を `scripts/session-state.sh` に移植し、state/list/wait サブコマンドが動作しなければならない（SHALL）。

#### Scenario: state サブコマンド
- **WHEN** `session-state.sh state <window-name>` を実行する
- **THEN** idle/input-waiting/processing/error/exited のいずれかの状態を返す

#### Scenario: list サブコマンド
- **WHEN** `session-state.sh list --json` を実行する
- **THEN** 全 Claude Code ウィンドウの名前と状態を JSON 配列で返す

#### Scenario: wait サブコマンド
- **WHEN** `session-state.sh wait <window-name> idle --timeout 10` を実行する
- **THEN** 指定状態に到達するまでポーリングし、タイムアウト時は非ゼロ終了する

### Requirement: session-comm.sh の移植

session-comm.sh を `scripts/session-comm.sh` に移植し、capture/inject/wait-ready サブコマンドが動作しなければならない（SHALL）。session-state.sh への参照は同一ディレクトリ相対パスで解決すること（MUST）。

#### Scenario: capture サブコマンド
- **WHEN** `session-comm.sh capture <window> --lines 30` を実行する
- **THEN** ANSI エスケープを除去したペイン内容を返す

#### Scenario: inject サブコマンド（状態チェック付き）
- **WHEN** `session-comm.sh inject <window> "text"` を実行し、対象が processing 状態
- **THEN** エラーを返し、テキストは送信されない

#### Scenario: inject サブコマンド（--force）
- **WHEN** `session-comm.sh inject <window> "text" --force` を実行する
- **THEN** 状態チェックをバイパスしてテキストを送信する

### Requirement: cld の移植

cld を `scripts/cld` に移植しなければならない（SHALL）。plugin ディレクトリの自動検出と systemd-run によるリソース制限を維持すること。

#### Scenario: plugin 自動検出
- **WHEN** `cld` を実行する
- **THEN** `$HOME/.claude/plugins/*/` を走査し `--plugin-dir` 引数を組み立てる

#### Scenario: リソース制限
- **WHEN** systemd-run が利用可能な環境で `cld` を実行する
- **THEN** MemoryMax=12G の制限付きで claude が起動する

### Requirement: cld-spawn の移植

cld-spawn を `scripts/cld-spawn` に移植しなければならない（SHALL）。

#### Scenario: 基本 spawn
- **WHEN** `cld-spawn` を引数なしで実行する
- **THEN** `spawn-HHmmss` 形式の新 tmux ウィンドウが作成され、cld が起動する

#### Scenario: --cd オプション
- **WHEN** `cld-spawn --cd /path/to/dir "initial prompt"` を実行する
- **THEN** 指定ディレクトリに移動してから cld が起動し、初期プロンプトが渡される

### Requirement: cld-observe の移植

cld-observe を `scripts/cld-observe` に移植しなければならない（SHALL）。

#### Scenario: デフォルト行数
- **WHEN** `cld-observe <window>` を実行する
- **THEN** 30 行分のペイン内容をキャプチャし、状態メタデータ付きで出力する

#### Scenario: --all オプション
- **WHEN** `cld-observe <window> --all` を実行する
- **THEN** 全スクロールバックをキャプチャする

### Requirement: cld-fork の移植

cld-fork を `scripts/cld-fork` に移植しなければならない（SHALL）。

#### Scenario: 基本 fork
- **WHEN** `cld-fork` を実行する
- **THEN** `fork-HHmmss` 形式の新 tmux ウィンドウが作成され、`--continue --fork-session` 付きで cld が起動する

### Requirement: claude-session-save.sh の移植

claude-session-save.sh を `scripts/claude-session-save.sh` に移植しなければならない（SHALL）。

#### Scenario: セッション ID マッピング
- **WHEN** SessionStart hook から session_id を含む JSON が stdin で渡される
- **THEN** tmux-pane-map.tsv と tmux-session-map.tsv にマッピングが保存される

#### Scenario: 排他制御
- **WHEN** 複数の Claude ウィンドウが同時に起動する
- **THEN** flock による排他制御で TSV ファイルの競合を防ぐ
