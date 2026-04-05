# worktree 作成

現在のプロジェクトに新しい worktree を作成する。

## 引数

- `<branch-name>`: 新しいブランチ名（必須）。`#N` 形式で Issue 番号指定可
- `--from <base-branch>`: 派生元ブランチ（デフォルト: main）

## ブランチ名のバリデーション

| ルール | 例（OK） | 例（NG） |
|--------|---------|---------|
| 英小文字・数字・ハイフン・スラッシュ | `feat/auth`, `fix-bug` | `Feature_Auth` |
| 50 文字以下 | `feat/add-login` | （長すぎるブランチ名） |
| 予約語禁止 | `feat/main-feature` | `main`, `master`, `HEAD` |
| 許可されたプレフィックス | `feat/`, `fix/`, `refactor/`, `docs/`, `test/`, `chore/` | `feature/`, `bug/` |

## スクリプト実行（MUST）

```bash
SCRIPT_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
bash "$SCRIPT_DIR/worktree-create.sh" $ARGUMENTS
```

スクリプトが worktree 作成・依存同期・コンテナ検出を全て処理する。

## エラーハンドリング

| エラー | 対処 |
|--------|------|
| 不正なブランチ名 | バリデーション参照、修正候補を表示 |
| 既存 worktree | `/twl:worktree-list` で確認 |
| 派生元が存在しない | `git fetch origin && git branch -a` で確認 |

## 禁止事項（MUST NOT）

- 直接 `git worktree add` を実行してはならない（スクリプト経由のみ）
- 既存ブランチを勝手に使用しない

## チェックポイント（MUST）

`/twl:project-board-status-update` を Skill tool で自動実行。

