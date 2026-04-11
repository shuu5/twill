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

失敗時（window 不在、session plugin 不在等）は stderr にエラーメッセージを出力して終了 (exit 2)。
エラー出力は wrapper/cld-observe のプレーンテキスト形式をそのまま伝播する（JSON 変換しない）。

### Step 2: capture 取得

```bash
CAPTURE=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/observe-wrapper.sh" "<window>" --lines <N>)
```

### Step 3: session_state 取得

```bash
STATE=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/session-state-wrapper.sh" state "<window>" 2>/dev/null || echo "unknown")
```

### Step 3.5: state file mtime チェック（stagnate 検知）

`AUTOPILOT_STAGNATE_SEC` 環境変数（デフォルト 600）を基準に、`.autopilot/issues/issue-*.json` の mtime をチェックする:

```bash
STAGNATE_SEC="${AUTOPILOT_STAGNATE_SEC:-600}"
STAGNATE_MIN=$(( STAGNATE_SEC / 60 ))
STAGNATE_FILES=$(find .autopilot/issues/ -name "issue-*.json" -mmin +${STAGNATE_MIN} 2>/dev/null || true)
```

stagnate が検出された場合は stderr に WARN を出力する:

```bash
while IFS= read -r f; do
  [[ -n "$f" ]] && echo "WARN: state stagnate detected: $f (>${STAGNATE_SEC}s)" >&2
done <<< "$STAGNATE_FILES"
```

`STAGNATE_FILES` は JSON 出力の `stagnate_files` フィールドに含める（空の場合は空配列 `[]`）。

### Step 4: JSON 出力

以下の JSON を stdout に出力:

```json
{
  "window": "<window>",
  "timestamp": "<ISO8601>",
  "lines": <N>,
  "capture": "<capture content>",
  "session_state": "<idle|input-waiting|processing|error|exited|unknown>",
  "stagnate_files": ["<path>", ...]
}
```

timestamp は `date -u +%Y-%m-%dT%H:%M:%SZ` で取得。`stagnate_files` は Step 3.5 で検出されたファイルパスの配列（未検出時は `[]`）。

## 禁止事項（MUST NOT）

- 対象 window に inject / send-keys しない（観察のみ）
- capture 内容を AI で要約・解釈しない（生データのみ出力）
- session plugin のスクリプトを改変しない
