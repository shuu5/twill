---
type: atomic
tools: [Bash]
effort: low
maxTurns: 5
---
# observe-once: 単発 session capture 取得

指定 tmux window の capture を 1 回取得し、JSON で stdout 出力する。

## 引数

- `--window <name>` (必須): tmux ウィンドウ名
- `--lines <N>` (optional, default: 30): キャプチャ行数

## 処理フロー（MUST）

### Step 1: Window 存在確認

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/observe-wrapper.sh" "<window>" --lines 1
```

失敗時は以下を stderr に出力して終了 (exit 2):
```json
{"error": "window '<window>' not found", "exit_code": 2}
```

### Step 2: capture 取得

```bash
CAPTURE=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/observe-wrapper.sh" "<window>" --lines <N>)
```

### Step 3: session_state 取得

```bash
STATE=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/session-state-wrapper.sh" state "<window>" 2>/dev/null || echo "unknown")
```

### Step 4: JSON 出力

以下の JSON を stdout に出力:

```json
{
  "window": "<window>",
  "timestamp": "<ISO8601>",
  "lines": <N>,
  "capture": "<capture content>",
  "session_state": "<idle|input-waiting|processing|error|exited|unknown>"
}
```

timestamp は `date -u +%Y-%m-%dT%H:%M:%SZ` で取得。

## 禁止事項（MUST NOT）

- 対象 window に inject / send-keys しない（観察のみ）
- capture 内容を AI で要約・解釈しない（生データのみ出力）
- session plugin のスクリプトを改変しない
