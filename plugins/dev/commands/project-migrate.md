# /dev:project-migrate

既存プロジェクトを最新のテンプレートに移行します。

## 使用方法

```bash
/dev:project-migrate [--type <type>] [--dry-run]
```

## 引数

- `--type <type>`: プロジェクトタイプ（rnaseq/webapp-llm）省略時は自動検出
- `--dry-run`: 変更をシミュレーションのみ（実際には変更しない）

## 実行

```bash
SCRIPT_DIR="$(git rev-parse --show-toplevel)/scripts"
bash "$SCRIPT_DIR/project-migrate.sh" $ARGUMENTS
```

## 動作フロー

### 1. 分析

現在のプロジェクト構造を分析:

- **OpenSpec構造**: config.yaml? project.md?
- **CLAUDE.md**: テンプレートバージョン推定
- **ディレクトリ構造**: タイプ推定

### 2. プラン生成

移行内容を表示:

- OpenSpec移行（v0.x → v1.x）
- CLAUDE.md差分
- 不足ファイル

### 3. 確認

ユーザー選択:

- `[A]` 全て適用
- `[C]` キャンセル

### 4. 適用

選択された変更を実行

### 5. code-review-graph 導入確認

`--dry-run` 時はこのステップをスキップする。

`.mcp.json` に `code-review-graph` エントリが存在しない場合のみ:
- AskUserQuestion で「code-review-graph を導入しますか？」と確認
- はい → `/dev:setup-crg` を実行
- いいえ → スキップ

`.mcp.json` に既にエントリがある場合はこのステップを表示しない。

## 例

```bash
# dry-runで変更内容を確認
/dev:project-migrate --dry-run

# webapp-llmタイプとして移行
/dev:project-migrate --type webapp-llm

# 自動検出で移行
/dev:project-migrate
```
