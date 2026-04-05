# /twl:project-create

プロジェクトを新規作成します。

## 使用方法

```bash
/twl:project-create <name> [--type <type>] [--root <path>] [--no-github]
```

## 引数

- `<name>`: プロジェクト名（必須、英小文字・数字・ハイフンのみ）
- `--type <type>`: プロジェクトタイプ（rnaseq/webapp-llm/webapp-hono）
- `--root <path>`: プロジェクトルートパス（未指定→タイプ別デフォルト）
- `--no-github`: GitHubリポジトリを作成しない

## 実行

```bash
python3 -m twl.autopilot.project create $ARGUMENTS
```

## 実行フロー

1. プロジェクトルート解決（--root or タイプ別デフォルト）
2. ベアリポジトリ作成 + main worktree
3. テンプレートCLAUDE.md適用
4. タイプ別初期化（renv/pnpm）
5. OpenSpec初期化
6. GitHubリポジトリ作成（--no-github除く）
7. code-review-graph 導入確認（AskUserQuestion で「code-review-graph を導入しますか？」→ はい: `/twl:setup-crg` 実行、いいえ: スキップ）

## プロジェクトタイプ

| タイプ | カテゴリ | デフォルトルート |
|--------|---------|----------------|
| `rnaseq` | omics | `${OMICS_PROJECTS_ROOT:-$HOME/projects}` |
| `webapp-llm` | webapp | `${WEBAPP_PROJECTS_ROOT:-$HOME/projects}` |
| `webapp-hono` | webapp-hono | `${WEBAPP_PROJECTS_ROOT:-$HOME/projects}` |

## 完了後

```
次のステップ:
  cd <project-path>/main
  /twl:co-issue → Issue作成
  /twl:workflow-setup → 直接開発開始
```
