---
type: atomic
tools: [Bash, Read]
effort: medium
maxTurns: 10
---
# issue-draft-from-observation: 検出結果から Issue draft 生成

problem-detect の検出結果（+ optional: observer-evaluator の出力）から Issue draft markdown を生成する。

## 引数

- `--input <json-file>` (必須): problem-detect が出力した JSON ファイルパス
- `--evaluator-output <json-file>` (optional): observer-evaluator specialist の JSON 出力

## 処理フロー（MUST）

### Step 1: 入力読み込み

`--input` の JSON を Read し、`detections` 配列を取得。
`--evaluator-output` が指定されていれば追加で Read。

detections が空配列の場合は空の drafts 配列を出力して終了。

### Step 2: detection ごとに draft 生成

各 detection について以下の markdown テンプレートで draft を生成:

```markdown
# [Observation][<severity>] <category>: <pattern>

## 検出元
- window: <window>
- timestamp: <timestamp>
- source: co-self-improve observation

## 検出内容
Line <line_number>: `<line excerpt>`

## 推測される根本原因
<evaluator output の該当 detection 分析があれば記載、なければ "rule-based detection only — specialist 分析未実施">

## 提案される対応
- [ ] 詳細調査
- [ ] 関連 component 確認
- [ ] 再現手順の整理

## 推奨ラベル
- `from-observation`
- `ctx/observation`
- `scope/plugins-twl`
```

### Step 3: JSON 出力

```json
{
  "window": "<window>",
  "timestamp": "<timestamp>",
  "drafts": [
    {
      "severity": "error",
      "category": "merge-gate-failure",
      "title": "[Observation][error] merge-gate-failure: MergeGateError:",
      "body": "<markdown draft>",
      "labels": ["from-observation", "ctx/observation", "scope/plugins-twl"]
    }
  ]
}
```

## 禁止事項（MUST NOT）

- `gh issue create` を実行しない（起票は controller の Step 5 でユーザー確認後）
- draft の内容を独断で省略・要約しない
- evaluator-output が無い場合でもエラーにしない（specialist との独立性を保つ）
