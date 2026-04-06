## 1. リポジトリ初期化

- [x] 1.1 GitHub に `shuu5/loom-plugin-session` リポジトリを作成する
- [x] 1.2 bare repo + main worktree 構成をセットアップする（`.bare/`, `main/.git` → `.bare`）
- [x] 1.3 CLAUDE.md を作成する（plugin 目的、bare repo 構造検証、編集フロー）

## 2. スクリプト移植

- [x] 2.1 `scripts/session-state.sh` を移植する（271L, state/list/wait サブコマンド）
- [x] 2.2 `scripts/session-comm.sh` を移植する（315L, capture/inject/wait-ready）。session-state.sh への参照を同一ディレクトリ相対パスに更新
- [x] 2.3 `scripts/cld` を移植する（28L, plugin 自動検出 + systemd-run）
- [x] 2.4 `scripts/cld-spawn` を移植する（54L, --cd オプション + spawn-HHmmss 命名）
- [x] 2.5 `scripts/cld-observe` を移植する（104L, session-comm.sh/session-state.sh 参照を更新）
- [x] 2.6 `scripts/cld-fork` を移植する（26L, --continue --fork-session）
- [x] 2.7 `scripts/claude-session-save.sh` を移植する（60L, flock 排他制御）
- [x] 2.8 全スクリプトに実行権限を付与する（`chmod +x`）

## 3. スキル移植

- [x] 3.1 `skills/spawn/SKILL.md` を移植する。パス参照を `${CLAUDE_PLUGIN_ROOT}/scripts/` に更新
- [x] 3.2 `skills/observe/SKILL.md` を移植する。パス参照を `${CLAUDE_PLUGIN_ROOT}/scripts/` に更新
- [x] 3.3 `skills/fork/SKILL.md` を移植する。パス参照を `${CLAUDE_PLUGIN_ROOT}/scripts/` に更新

## 4. deps.yaml 構築

- [x] 4.1 deps.yaml v3.0 を作成する（version, plugin, entry_points）
- [x] 4.2 skills セクションに spawn/observe/fork を登録する（type, path, calls）
- [x] 4.3 scripts セクションに 7 件のスクリプトを登録する（依存関係含む）

## 5. 検証

- [x] 5.1 `loom check` を実行し Missing 0 を確認する
- [x] 5.2 `loom validate` を実行し Violations 0 を確認する
- [x] 5.3 session-state.sh の query/wait/list サブコマンドをスモークテストする
- [x] 5.4 cld-spawn, cld-observe が tmux 環境で動作することを確認する

## 6. Project Board

- [x] 6.1 loom-plugin-dev Project Board (#3) に Issue を追加する
