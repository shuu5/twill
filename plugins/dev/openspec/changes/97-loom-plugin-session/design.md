## Context

dev plugin の autopilot は tmux セッション管理機能（session-state.sh, cld-spawn 等）に依存しているが、これらは ubuntu-note-system のユーザースコープに散在している。loom の plugin 型管理に統合することで、配布可能・追跡可能な共有基盤とする。

移植対象:
- scripts 7 件（798 行）: session-state.sh(271L), session-comm.sh(315L), cld(28L), cld-spawn(54L), cld-observe(104L), cld-fork(26L)
- skills 3 件（256 行）: spawn, observe, fork
- cld-fork-cd は DEPRECATED のため除外、cld-ch は Discord plugin スコープのため除外

## Goals / Non-Goals

**Goals:**

- bare repo + main worktree 構成で `shuu5/loom-plugin-session` リポジトリを作成する
- deps.yaml v3 に全コンポーネントを登録し loom check / loom validate を PASS させる
- スクリプトのパス参照を plugin-relative に更新する
- SKILL.md 内のパス参照を ubuntu-note-system 絶対パスから plugin-relative に更新する

**Non-Goals:**

- dev plugin 側の参照切り替え（別 Issue #B）
- ユーザースコープの廃止（別 Issue #E）
- loom 本体の plugin 間依存サポート（別 Issue #D）
- cld-ch の移植（Discord plugin スコープ）
- スクリプトのリファクタリング（機能変更なしの移植）

## Decisions

### D1: リポジトリ構成は bare repo + worktree

loom-plugin-dev と同じ構成を採用。`.bare/` + `main/` worktree。loom 管轄の plugin として一貫した構造を保つ。

### D2: deps.yaml v3 フォーマット

loom の標準フォーマットに従う。scripts は `type: script`、skills は `type: skill` で登録。

### D3: パス参照は plugin-relative

移植時にハードコードされた `~/ubuntu-note-system/scripts/` や `~/.claude/skills/` パスを、plugin ルートからの相対パスに書き換える。SKILL.md 内のスクリプト呼び出しは `$PLUGIN_DIR/scripts/` パターンを使用。

### D4: cld 本体はスクリプトとして移植

cld は Claude Code のラッパーとして `scripts/cld` に配置。PATH 経由で実行される前提は変えない（symlink は別 Issue で対応）。

### D5: session-state.sh のテストは query/wait/list サブコマンドに限定

スモークテスト範囲。tmux セッション操作のフルテストは CI 環境依存のため、ローカル tmux 環境での手動検証とする。

## Risks / Trade-offs

- **PATH 依存**: cld, cld-spawn 等は PATH 経由で呼び出される前提。plugin 化しても symlink/PATH 設定は別途必要（ユーザースコープ廃止 Issue で対応）
- **tmux 依存**: テスト実行に tmux セッションが必要。CI での自動テストは困難
- **session-state.sh の複雑性**: 271 行で最大のスクリプト。移植時のパス書き換えミスリスク
- **plugin 間依存未サポート**: dev plugin から session plugin を参照する仕組みは loom 本体の対応待ち
