---
type: atomic
tools: [Bash, Skill, Read]
effort: low
maxTurns: 10
---
# 開発状態の判定

現在のブランチとプロジェクト状態を分析し、推奨アクションを返す。

## 出力形式

| フィールド | 値 | 説明 |
|-----------|-----|------|
| repo_mode | `worktree` | リポジトリ形式（bare repo + worktree 固定） |
| branch | `main` / `feat/xxx` / `detached` | 現在のブランチ |
| recommended_action | 下記参照 | 推奨される次のアクション |
| environment | 下記参照 | 環境情報 |

### recommended_action の値

| 値 | 意味 |
|----|------|
| `worktree` | main ブランチなので worktree 作成が必要 |
| `implement` | feature ブランチ → 直接実装 |
| `direct` | 軽微変更 or quick ラベル → 直接実装 |

### environment の構造

```yaml
environment:
  container_name: null    # webapp-dev | omics-dev | null
  package_manager: null   # pnpm | npm | uv | renv | null
  execution_map:
    git: host
    file_edit: host
    package_manager: host  # or container
    test: host             # or container
```

## 判定フロー（MUST）

1. **ブランチ確認**: `main` / `master` → `recommended_action: worktree`、feature ブランチ → 次へ
2. **ラベル確認**: `quick` / `scope/direct` → `direct`
3. **環境判定**: コンテナ・パッケージマネージャを検出
4. それ以外 → `implement`

## 禁止事項（MUST NOT）

- 直接実装を開始してはならない（判定結果を返すのみ）
- ユーザーに代わって判断してはならない

## チェックポイント（MUST）

`/twl:worktree-create` を Skill tool で自動実行。

