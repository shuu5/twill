---
type: atomic
tools: [Bash]
effort: low
maxTurns: 5
---
# prompt-audit-scan

`twl --audit --section 7 --format json` から stale/unreviewed コンポーネントを抽出し、
優先度順に最大 N 件を返す。

## 引数

- `--limit N`: 上限件数（デフォルト 15）

## 処理フロー

### Step 1: audit 実行

```bash
twl --audit --section 7 --format json
```

### Step 2: stale/unreviewed 分類

JSON の `.items[]` を以下で分類:

- **stale**: `severity == "warning"` かつ message に `stale` を含む
- **unreviewed**: `severity == "info"` かつ message に `未レビュー` を含む
- **ok**: `severity == "ok"`

### Step 3: 優先度ソートと上限適用

1. stale → unreviewed の順（同順位は name アルファベット順）
2. 上限 N 件に絞り込み

### Step 4: 結果出力

対象 0 件の場合:
```
✓ 全コンポーネント最新（stale/unreviewed なし）
```

1 件以上の場合:
```
対象コンポーネント: <N> 件
  stale (<count>): <names...>
  unreviewed (<count>): <names...>
```

component 名のリストを後続コマンド（prompt-audit-review）に渡す形式で出力する。
