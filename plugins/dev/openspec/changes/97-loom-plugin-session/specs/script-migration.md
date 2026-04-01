## ADDED Requirements

### Requirement: session-state.sh 移植

session-state.sh（271 行）を plugin の `scripts/` 配下に移植し、パス参照を plugin-relative に更新しなければならない（SHALL）。

#### Scenario: query サブコマンド動作
- **WHEN** `session-state.sh query` を tmux 環境で実行する
- **THEN** 現在のセッション状態を正しく返す

#### Scenario: wait サブコマンド動作
- **WHEN** `session-state.sh wait --timeout 5` を実行する
- **THEN** 指定タイムアウトで待機し、状態変更を検知する

#### Scenario: list サブコマンド動作
- **WHEN** `session-state.sh list` を実行する
- **THEN** アクティブなセッション一覧を返す

### Requirement: session-comm.sh 移植

session-comm.sh（315 行）を plugin の `scripts/` 配下に移植しなければならない（SHALL）。

#### Scenario: 移植完了
- **WHEN** `scripts/session-comm.sh` を確認する
- **THEN** ファイルが存在し実行可能で、パス参照が plugin-relative に更新されている

### Requirement: cld 本体移植

cld（28 行）を plugin の `scripts/` 配下に移植しなければならない（SHALL）。

#### Scenario: 移植完了
- **WHEN** `scripts/cld` を確認する
- **THEN** ファイルが存在し実行可能で、Claude Code ラッパーとして機能する

### Requirement: cld-spawn 移植

cld-spawn（54 行）を plugin の `scripts/` 配下に移植しなければならない（SHALL）。

#### Scenario: tmux 環境での動作
- **WHEN** tmux セッション内で `cld-spawn` を実行する
- **THEN** 新しい tmux window で Claude Code セッションが起動する

### Requirement: cld-observe 移植

cld-observe（104 行）を plugin の `scripts/` 配下に移植しなければならない（SHALL）。

#### Scenario: 移植完了
- **WHEN** `scripts/cld-observe` を確認する
- **THEN** ファイルが存在し実行可能で、パス参照が plugin-relative に更新されている

### Requirement: cld-fork 移植

cld-fork（26 行）を plugin の `scripts/` 配下に移植しなければならない（SHALL）。

#### Scenario: 移植完了
- **WHEN** `scripts/cld-fork` を確認する
- **THEN** ファイルが存在し実行可能で、パス参照が plugin-relative に更新されている

### Requirement: パス参照の plugin-relative 化

全スクリプトの ubuntu-note-system 絶対パスおよびユーザースコープパスを plugin-relative パスに更新しなければならない（MUST）。

#### Scenario: 絶対パスが残っていない
- **WHEN** 全スクリプトで `~/ubuntu-note-system` や `~/.claude/skills/` を grep する
- **THEN** マッチが 0 件である
