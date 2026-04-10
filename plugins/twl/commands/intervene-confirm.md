---
type: atomic
tools: [Bash, AskUserQuestion]
effort: medium
---
# Layer 1 確認付き介入（intervene-confirm）

Supervisor がユーザーの確認を得てから実行する Layer 1 介入。Worker 長時間 idle と Wave 再計画に対応する。

## 引数

- `--pattern <id>`: 介入パターン ID（`worker-idle` | `wave-replan`）
- `--issue <num>`: 対象 Issue 番号（worker-idle 時）
- `--branch <name>`: 対象 branch 名（worker-idle 時）
- `--context <text>`: 追加コンテキスト（状況説明）

## フロー

### Step 1: 状況確認

現在の状態を収集して提示する。

**worker-idle の状況収集**:

```bash
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$(git rev-parse --show-toplevel)/.autopilot}"
STATE_FILE="$AUTOPILOT_DIR/issues/issue-${ISSUE_NUM}.json"

# 現在の状態を取得
cat "$STATE_FILE" | jq '{status, current_step, last_active: .updated_at}'
```

### Step 2: ユーザーに選択肢を提示

**AskUserQuestion tool** でユーザーに確認:

**worker-idle の場合**:
> 「Worker (Issue #<num>, branch: <branch>) が <N> 分間 idle 状態です。
> 現在の状態: status=<status>, current_step=<step>
>
> どのように対応しますか？
> A: nudge 送信（プロンプトを再送）
> B: force-done（強制的に merge-ready に遷移）
> C: status=failed（失敗として記録）
> D: 待機継続（5 分後に再確認）」

**wave-replan の場合**:
> 「Wave 再計画が必要な状況を検出しました。
> <context>
>
> どのように対応しますか？
> A: 現行 Wave を継続し次 Wave で対応
> B: 現行 Wave を中断して再計画
> C: 新規 Issue を既存 Phase に追加
> D: 手動で対応（Supervisor は何もしない）」

### Step 3: 選択に応じた実行

**worker-idle + 選択 A (nudge)**:

```bash
tmux send-keys -t "$TMUX_WINDOW" "" Enter
```

**worker-idle + 選択 B (force-done)**:

```bash
python3 -m twl.autopilot.state write \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "status=merge-ready" --force-done
```

**worker-idle + 選択 C (failed)**:

```bash
python3 -m twl.autopilot.state write \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$ISSUE_NUM" --role worker \
  --set "status=failed"
```

**wave-replan + 選択 B または C**: ユーザーの指示に従って実行。

**選択 D / 待機**: InterventionRecord に記録のみ。

### Step 4: InterventionRecord 記録

```bash
OBSERVATION_DIR="$(git rev-parse --show-toplevel)/.observation/interventions"
mkdir -p "$OBSERVATION_DIR"
TIMESTAMP=$(date -u +"%Y%m%d-%H%M%S")
cat > "$OBSERVATION_DIR/${TIMESTAMP}-${PATTERN_ID}.json" <<JSON
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "pattern_id": "${PATTERN_ID}",
  "layer": "confirm",
  "issue_num": ${ISSUE_NUM:-0},
  "branch": "${BRANCH:-}",
  "action_taken": "${ACTION_TAKEN}",
  "user_choice": "${USER_CHOICE}",
  "result": "${RESULT}",
  "notes": "${CONTEXT:-}"
}
JSON
```

## 出力

- 実行: `✓ Layer 1 Confirm介入完了: <pattern-id> (選択: <choice>)`
- スキップ: `- Layer 1 Confirm介入スキップ: ユーザーが待機を選択`
