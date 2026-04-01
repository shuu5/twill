# loom-plugin-session

tmux セッション管理 plugin。Claude Code の tmux ウィンドウ操作（spawn/observe/fork）と状態検出を提供する。

## 構成

- bare repo: `~/projects/local-projects/loom-plugin-session/.bare`
- main worktree: `~/projects/local-projects/loom-plugin-session/main/`
- feature worktrees: `~/projects/local-projects/loom-plugin-session/worktrees/<branch>/`

## Bare repo 構造検証（セッション開始時チェック）

以下の3条件を全て満たすこと:

1. `.bare/` が存在する（`.git/` ディレクトリではない）
2. `main/.git` がファイル（ディレクトリではない）で `.bare` を指す
3. CWD が `main/` 配下である（`worktrees/` 配下での起動は禁止）

## 編集フロー（必須）

```
コンポーネント編集 → deps.yaml 更新 → loom check → loom update-readme
```

## 視覚化

`loom` CLI 必須（独自スクリプト禁止）。
