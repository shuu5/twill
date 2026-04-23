---
type: atomic
tools: [AskUserQuestion, Bash, Skill, Read]
effort: low
maxTurns: 10
---
# /twl:project-migrate

既存プロジェクトを最新のテンプレートに移行します。

## 使用方法

```bash
/twl:project-migrate [--type <type>] [--dry-run]
```

## 引数

- `--type <type>`: プロジェクトタイプ（rnaseq/webapp-llm）省略時は自動検出
- `--dry-run`: 変更をシミュレーションのみ（実際には変更しない）

## 実行

```bash
python3 -m twl.autopilot.project migrate $ARGUMENTS
```

## 動作フロー

### 1. 分析

現在のプロジェクト構造を分析:

- **CLAUDE.md**: テンプレートバージョン推定
- **ディレクトリ構造**: タイプ推定

### 2. プラン生成

移行内容を表示:

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
- はい → `/twl:setup-crg` を実行
- いいえ → スキップ

`.mcp.json` に既にエントリがある場合はこのステップを表示しない。

## 例

```bash
# dry-runで変更内容を確認
/twl:project-migrate --dry-run

# webapp-llmタイプとして移行
/twl:project-migrate --type webapp-llm

# 自動検出で移行
/twl:project-migrate
```
