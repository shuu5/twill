# loom-plugin-dev

Claude Code dev plugin（chain-driven + autopilot-first）。claude-plugin-dev の後継として新規構築。

## 構成

- bare repo: `~/projects/local-projects/loom-plugin-dev/.bare`
- main worktree: `~/projects/local-projects/loom-plugin-dev/main/`

## ルール

### プラグイン編集フロー
`コンポーネント編集 → deps.yaml更新 → loom --check → loom --update-readme`

### deps.yaml = SSOT
追加・削除時は必ず更新。型ルールは loom CLI (types.yaml) を参照。

### 視覚化
`loom` CLI 必須（独自スクリプト禁止）。
