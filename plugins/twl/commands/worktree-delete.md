---
type: atomic
tools: [Bash, Skill, Read]
effort: low
maxTurns: 10
---
# worktree 削除

指定した worktree とブランチを安全に削除する。

## 使用方法

```
/twl:worktree-delete <branch-name>
```

## スクリプト実行（MUST）

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-delete.sh" <branch-name>
```

スクリプトが以下を全て処理する:
- 入力バリデーション（パストラバーサル防止）
- CWD ガード（不変条件 B: Worker からの削除禁止）
- bare repo ルート特定
- worktree ディレクトリ削除
- ローカルブランチ削除

## 安全制約

- **Pilot (main/) からのみ実行可能**: worktrees/ 配下からの実行は拒否される
- **自身の CWD 削除防止**: CWD が削除対象に含まれる場合はエラー
- **パストラバーサル防止**: `..` や絶対パスを含むブランチ名は拒否

## エラーハンドリング

| エラー | 対処 |
|--------|------|
| worktree が存在しない | 警告表示、ブランチ削除のみ試行 |
| ブランチ削除失敗 | 警告表示、続行 |
| Worker からの実行 | エラー終了 |

## 禁止事項（MUST NOT）

- 直接 `git worktree remove` を実行してはならない（スクリプト経由のみ）
- Worker (worktrees/ 配下) から実行してはならない
