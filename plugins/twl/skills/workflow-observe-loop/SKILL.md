---
name: twl:workflow-observe-loop
description: |
  observed session を継続観察し、検出された問題を集約する workflow。
  co-self-improve controller から呼ばれる。

  Use when invoked by twl:co-self-improve controller (Step 2).
type: workflow
effort: high
spawnable_by:
- controller
---

# workflow-observe-loop

## 引数 (controller から渡される)

- `OBSERVED_WINDOW`: 観察対象 tmux window 名 (MUST)
- `INTERVAL`: polling 間隔秒 (default 30)
- `MAX_CYCLES`: 最大サイクル数 (default 60, 30 秒 x 60 = 30 分)
- `STOP_ON_DETECT`: 1 件検出で停止するか (default false)

## フロー (MUST)

### Step 1: 事前確認

1. OBSERVED_WINDOW の存在確認 (`bash "$CLAUDE_PLUGIN_ROOT/scripts/session-state-wrapper.sh" state "$OBSERVED_WINDOW"`)
2. 自 window と異なることを確認 (自分自身を観察すると無限ループ)
   - 自 window 名: `tmux display-message -p '#W'` で取得
   - 一致する場合は exit 2 で終了
3. ユーザーに「observe loop を開始します。停止は Ctrl-C」と通知

### Step 2: ループ本体 (MUST: bash ループで実装)

**MUST**: ループは bash で実装し、各サイクルの中間出力は捨てる (集約 JSON のみ retain)。
LLM がサイクルごとに Skill 呼び出しすると token が線形増加するため、observe-and-detect composite のロジックを bash 内で直接実行する (observe-wrapper.sh + observe-detect.sh)。

```bash
SESSION_ID="$(date +%s)-${OBSERVED_WINDOW}"
WORK_DIR=".observation/${SESSION_ID}"
mkdir -p "$WORK_DIR"
DETECTIONS_FILE="$WORK_DIR/detections_raw.jsonl"
: > "$DETECTIONS_FILE"

for cycle in $(seq 1 $MAX_CYCLES); do
  # 1. observe-once (bash 直接実行)
  CAPTURE_JSON=$("$CLAUDE_PLUGIN_ROOT/scripts/observe-wrapper.sh" "$OBSERVED_WINDOW" --lines 30)
  if [ $? -ne 0 ]; then
    echo "observed session exited or error" >&2
    break
  fi

  # 2. capture を tmp ファイルに書き出し
  CAPTURE_FILE="$WORK_DIR/capture_${cycle}.json"
  echo "$CAPTURE_JSON" > "$CAPTURE_FILE"

  # 3. problem-detect (grep ベースのパターンマッチ)
  #    problem-detect.md の stub パターンを bash で直接実行
  DETECT_JSON=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/observe-detect.sh" "$CAPTURE_FILE" "$cycle")

  # 4. 検出結果を JSONL に追記
  echo "$DETECT_JSON" >> "$DETECTIONS_FILE"

  # 5. 新規 detection があれば通知
  NEW_COUNT=$(echo "$DETECT_JSON" | jq '.detections | length')
  if [ "$NEW_COUNT" -gt 0 ]; then
    echo "[cycle $cycle] $NEW_COUNT detection(s) found" >&2
    if [ "$STOP_ON_DETECT" = "true" ]; then
      break
    fi
  fi

  # 6. session 状態チェック
  STATE=$("$CLAUDE_PLUGIN_ROOT/scripts/session-state-wrapper.sh" state "$OBSERVED_WINDOW" 2>/dev/null || echo "unknown")
  if [ "$STATE" = "exited" ] || [ "$STATE" = "error" ]; then
    break
  fi

  # 7. capture tmp を削除 (context budget 維持)
  rm -f "$CAPTURE_FILE"

  sleep "$INTERVAL"
done
```

### Step 3: 集約

ループ終了後、DETECTIONS_FILE (JSONL) を集約:

1. 全サイクルの detections を統合
2. 同一パターンの重複除去 (`pattern` + `line_number` でキー化)
3. severity 別に集計
4. top 10 検出を抽出
5. 集約結果を `$WORK_DIR/aggregated.json` に書き出し

集約は `jq` で実行:

```bash
jq -s '[.[].detections[]] | group_by(.pattern + "_" + (.line_number|tostring))
  | map(.[0]) | sort_by(
    if .severity == "critical" then 0
    elif .severity == "warning" then 1
    else 2 end
  ) | .[0:10]' "$DETECTIONS_FILE" > "$WORK_DIR/top_detections.json"
```

### Step 4: 結果報告

集約結果を controller に返す:

```json
{
  "observed_window": "<window>",
  "cycles_executed": 60,
  "detections_total": 7,
  "detections_unique": 3,
  "by_severity": {"critical": 1, "warning": 2, "info": 0},
  "top_detections": [],
  "aggregated_path": ".observation/<session_id>/aggregated.json"
}
```

## 禁止事項 (MUST NOT)

- 自 window を観察対象にしてはならない
- ユーザー停止を無視してループを継続してはならない
- 各サイクルの生 capture を context に retain してはならない (集約のみ)
- ループ中に observed session に inject してはならない
