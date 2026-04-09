---
type: composite
tools: [Agent, Bash, Read]
effort: medium
maxTurns: 20
parallel: true
---
# prompt-audit-review

prompt-audit-scan の対象コンポーネントに対して worker-prompt-reviewer を parallel Task spawn し、
PASS/WARN/FAIL 結果を収集する。

## 引数

- `<component-list>`: prompt-audit-scan が出力したコンポーネント名リスト

## 処理フロー

### Step 1: 対象コンポーネントの確認

component 名リストを受け取り、各コンポーネントのファイルパスを deps.yaml から取得する。

### Step 2: parallel Task spawn

対象コンポーネントごとに `twl:worker-prompt-reviewer` を Task spawn（最大 15 並列）。

各 specialist への指示:
```
対象コンポーネント: <name>
ファイルパス: <path>
ref-prompt-guide を参照してプロンプト品質をレビューし、PASS/WARN/FAIL を判定してください。
```

### Step 3: 結果収集

全 Task の完了を待つ。タイムアウト/エラーで結果が返らない specialist は WARN 扱いとして記録:
```
WARN: <name> — レビュー不完了（タイムアウトまたはエラー）
```

### Step 4: 結果サマリー出力

```
レビュー結果サマリー:
  PASS: <count> 件 — <names...>
  WARN: <count> 件 — <names...>
  FAIL: <count> 件 — <names...>
```

結果は JSON 形式で保存し、prompt-audit-apply に渡す:
```json
{
  "pass": ["component-a", "component-b"],
  "warn": [{"name": "component-c", "findings": "..."}],
  "fail": [{"name": "component-d", "findings": "..."}]
}
```
