## Why

dev plugin の autopilot が session-state.sh, cld-spawn 等に外部依存（ubuntu-note-system）しており配布不可。spawn/observe/fork はユーザースコープ（~/.claude/skills/）に散在し loom 管轄外で追跡不能。今後 paper/trading 等の plugin も tmux 機能を高度利用するため、共有基盤が必要。

## What Changes

- 新規リポジトリ `shuu5/loom-plugin-session` を bare repo + main worktree 構成で作成
- ubuntu-note-system からスクリプト 7 件を移植: session-state.sh, session-comm.sh, cld, cld-spawn, cld-observe, cld-fork（cld-fork-cd は DEPRECATED のため除外）
- スキル 3 件を移植: spawn, observe, fork
- deps.yaml v3 を構築し全コンポーネントを登録
- loom check / loom validate を PASS させる

## Capabilities

### New Capabilities

- **loom-plugin-session**: tmux セッション管理を独立 plugin として提供
- **session-state.sh**: query/wait/list サブコマンドによるセッション状態管理
- **cld-spawn**: 新規 Claude Code セッションを tmux window で起動
- **cld-observe**: tmux ペイン出力を観察し AI 分析で状態要約
- **cld-fork**: 現在のセッションを fork して並行実行

### Modified Capabilities

- SKILL.md 内のパス参照を plugin-relative に更新（ubuntu-note-system 絶対パスから脱却）

## Impact

- **新規リポジトリ**: shuu5/loom-plugin-session（loom-plugin-dev とは別リポジトリ）
- **依存元**: dev plugin の autopilot が session 機能に依存（将来 #B で参照切り替え）
- **移植元**: ubuntu-note-system の scripts/ と ~/.claude/skills/ 配下
- **loom-plugin-dev Project Board (#3)**: 新リポジトリを参加させる
