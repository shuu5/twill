## Why

dev plugin の autopilot が session-state.sh, cld-spawn 等に外部依存（ubuntu-note-system）しており配布不可。spawn/observe/fork はユーザースコープに散在し loom 管轄外で追跡不能。paper/trading 等の plugin も tmux 機能を高度利用する改修予定があり、共有基盤が必要。

## What Changes

- 新規リポジトリ `shuu5/loom-plugin-session` を bare repo + deps.yaml v3 構成で作成
- ubuntu-note-system からスクリプト 7 件を移植: session-state.sh, session-comm.sh, cld, cld-spawn, cld-observe, cld-fork（cld-fork-cd は DEPRECATED のため移植しない）
- スキル 3 件を移植: spawn, observe, fork
- deps.yaml v3 に全コンポーネント登録
- loom check / loom validate が PASS する状態にする

## Capabilities

### New Capabilities

- **loom-plugin-session plugin**: tmux セッション管理を独立 plugin として提供
- **session-state.sh**: query/wait/list サブコマンドによるセッション状態管理
- **cld**: Claude Code セッション起動スクリプト（tmux window 作成）
- **cld-spawn**: 新規セッション spawn（コンテキスト非継承）
- **cld-observe**: tmux ウィンドウ/ペインの出力観察・AI 分析
- **cld-fork**: 現在のセッションを fork して新 tmux ウィンドウで起動
- **session-comm.sh**: セッション間通信
- **spawn/observe/fork スキル**: 各スクリプトの SKILL.md によるスキル定義

### Modified Capabilities

- なし（新規 plugin のため既存コンポーネントへの変更なし）

## Impact

- **新規リポジトリ**: `shuu5/loom-plugin-session`（本 Issue 完了後に transfer 予定）
- **依存元**: ubuntu-note-system の `scripts/` および `~/.claude/skills/` 配下
- **依存先**: dev plugin の autopilot が session 機能を利用（参照切り替えは別 Issue #B）
- **loom-plugin-dev Project Board**: #3 に参加
- **ユーザースコープ廃止**: 別 Issue #E で対応
