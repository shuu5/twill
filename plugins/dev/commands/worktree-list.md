# worktree 一覧表示

現在のプロジェクトの worktree 一覧を表示する。

## 実行

```bash
PROJECTS_ROOT="$HOME/projects"
CURRENT_DIR=$(pwd)
if [[ "$CURRENT_DIR" =~ ^$PROJECTS_ROOT/([^/]+)/ ]]; then
    PROJECT_NAME="${BASH_REMATCH[1]}"
    git -C "$PROJECTS_ROOT/$PROJECT_NAME/.bare" worktree list
fi
```

## 出力フォーマット

```
/path/to/main                       abc1234 [main]
/path/to/worktrees/feat/feature-a   def5678 [feat/feature-a]
```

| 状態 | 表示 |
|------|------|
| prunable | `(prunable)` — 削除可能 |
| locked | `(locked)` — ロック状態 |
| detached | `(detached HEAD)` |

## クリーンアップ

```bash
git worktree prune --dry-run  # 確認
git worktree prune            # 実行
```
