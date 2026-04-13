---
type: atomic
tools: [Bash, Read]
effort: low
maxTurns: 5
---
# problem-detect: rule-based パターン検出

observe-once の JSON 出力を入力として、capture 内のエラーパターンを rule-based で検出する。

## 引数

- `--input <json-file>` (必須): observe-once が出力した JSON ファイルパス
- `--patterns <pattern-file>` (optional): パターンカタログファイル（未指定時は内部 stub 使用）

## 処理フロー（MUST）

### Step 1: JSON 読み込み

`--input` の JSON ファイルを Read し、`capture` フィールドを取得。

### Step 2: パターン定義

`refs/observation-pattern-catalog.md` が存在すれば Read してパターンリストを取得。
未実装（ファイル不在）の場合は以下の **stub パターン** を使用:

| pattern | severity | category |
|---------|----------|----------|
| `Error:` | warning | general-error |
| `APIError:` | error | api-error |
| `MergeGateError:` | error | merge-gate-failure |
| `failed to` | warning | general-failure |
| `\[CRITICAL\]` | error | critical-level |
| `nudge sent` | info | worker-stall |
| `silent.*deletion` | error | silent-deletion |
| `AC.*矮小化\|矮小化` | error | ac-diminishment |
| `force.with.lease` | warning | pilot-rebase-intervention |
| `input-waiting\|Enter to select\|承認しますか\|\[y/N\]` | warning | input-waiting (`[INPUT-WAIT]` チャネル) |
| `Skedaddling\|Frolicking\|Background.*poll` | warning | pilot-idle (`[PILOT-IDLE]` チャネル) |
| `state.*stagnate\|mtime.*600\|state file.*not updated` | warning | state-stagnate (`[STAGNATE]` チャネル) |

### Step 3: パターンマッチ

capture 内容を行ごとにスキャンし、各パターンで grep マッチを実行。
マッチした行について以下を記録:

- `pattern`: マッチしたパターン名
- `severity`: パターンに紐づく severity
- `category`: パターンに紐づくカテゴリ
- `line`: マッチした行の内容
- `line_number`: capture 内の行番号（1-indexed）

### Step 4: JSON 出力

```json
{
  "window": "<observe-once の window>",
  "timestamp": "<observe-once の timestamp>",
  "detections": [
    {
      "pattern": "MergeGateError:",
      "severity": "error",
      "category": "merge-gate-failure",
      "line": "MergeGateError: base drift detected: ...",
      "line_number": 17
    }
  ]
}
```

detections が 0 件の場合は空配列 `[]` を返す。

## 禁止事項（MUST NOT）

- LLM による判定・分類を行わない（rule-based first-pass のみ）
- severity を動的に変更しない（パターン定義の severity をそのまま使用）
- 入力 JSON を改変しない
