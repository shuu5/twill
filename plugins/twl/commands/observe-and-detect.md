---
type: composite
tools: [Bash, Read]
effort: medium
maxTurns: 10
---
# observe-and-detect: 1 サイクル分の observe + detect + (optional) evaluate

observe-once と problem-detect を順次実行し、統合 JSON を出力する composite。

## 引数

- `--window <name>` (必須): tmux ウィンドウ名
- `--evaluator-on` (optional): severity >= medium 時に observer-evaluator specialist を spawn

## 処理フロー (MUST)

### Step 1: observe-once 実行

`commands/observe-once.md` を Read し、その手順に従い capture JSON を取得。

```bash
CAPTURE_FILE=$(mktemp /tmp/observe-XXXXXX.json)
# observe-once の Step 2-4 を実行し JSON を $CAPTURE_FILE に書き出し
```

### Step 2: problem-detect 実行

`commands/problem-detect.md` を Read し、その手順に従い detection JSON を取得。

```bash
# problem-detect に --input $CAPTURE_FILE を渡して実行
```

### Step 3: evaluator 判定

`--evaluator-on` が指定されており、detection に severity `error` or `warning` が含まれる場合:

```
Agent(subagent_type="twl:observer-evaluator", prompt="<detection-json>")
```

specialist の結果を `evaluator_output` フィールドに統合。
`--evaluator-on` 未指定、または severity が `info` のみの場合は `evaluator_output: null`。

### Step 4: 統合 JSON 出力

```json
{
  "cycle_id": 1,
  "window": "<window>",
  "timestamp": "<ISO8601>",
  "detections": [],
  "evaluator_output": null
}
```

## 禁止事項 (MUST NOT)

- observe-once / problem-detect の実行順序を入れ替えない
- evaluator を severity 条件なしに呼ばない
- 対象 window に inject しない
