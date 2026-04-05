# 開発状態の判定

現在のブランチとプロジェクト状態を分析し、推奨アクションを返す。

## 出力形式

| フィールド | 値 | 説明 |
|-----------|-----|------|
| repo_mode | `worktree` | リポジトリ形式（bare repo + worktree 固定） |
| branch | `main` / `feat/xxx` / `detached` | 現在のブランチ |
| openspec | `true` / `false` | openspec/ が存在するか |
| change_exists | `true` / `false` | changes/ 内にディレクトリがあるか |
| change_id | `xxx` / `null` | 最新の change ID |
| proposal_status | `approved` / `pending` / `none` | proposal.md の状態 |
| recommended_action | 下記参照 | 推奨される次のアクション |
| environment | 下記参照 | 環境情報 |

### recommended_action の値

| 値 | 意味 |
|----|------|
| `worktree` | main ブランチなので worktree 作成が必要 |
| `propose` | OpenSpec 使用プロジェクトで変更提案が必要 |
| `apply` | 承認済み proposal あり → 実装開始可能 |
| `direct` | 軽微変更 or OpenSpec 未使用 → 直接実装 |

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
2. **openspec/ 確認**: なし → `direct`、changes/ 空 → 変更規模判定、proposal.md あり → ステップ 3 へ
3. **proposal 状態**: `status: approved` あり → `apply`、なし → `pending`
4. **環境判定**: コンテナ・パッケージマネージャを検出
5. **変更規模判定**: 10 行未満 → `direct`、それ以外 → `propose`

## 禁止事項（MUST NOT）

- 直接実装を開始してはならない（判定結果を返すのみ）
- ユーザーに代わって判断してはならない

## チェックポイント（MUST）

`/twl:worktree-create` を Skill tool で自動実行。

