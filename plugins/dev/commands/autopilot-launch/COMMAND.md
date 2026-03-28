# Worker 起動

tmux window を作成し Worker（cld）を起動する。
issue-{N}.json を state-write.sh で初期化し、DEV_AUTOPILOT_SESSION 環境変数は使用しない。
autopilot-phase-execute から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$ISSUE` | Issue 番号（数値） |
| `$PROJECT_DIR` | プロジェクトディレクトリ |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列（Issue番号→警告メッセージ） |
| `$PHASE_INSIGHTS` | 前 Phase の retrospective 知見（空の場合あり） |

## 実行ロジック（MUST）

### Step 1: cld パス解決

```bash
CLD_PATH=$(command -v cld 2>/dev/null)
if [ -z "$CLD_PATH" ]; then
  echo "Error: cld が見つかりません"
  bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot \
    --set "status=failed" \
    --set "failure={\"message\": \"cld_not_found\", \"step\": \"launch_worker\"}"
  return 1
fi
```

### Step 2: issue-{N}.json 初期化

```bash
bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role worker --init
```

status=running で初期化される。

### Step 3: プロンプト構築

```bash
WINDOW_NAME="ap-#${ISSUE}"
PROMPT="/dev:workflow-setup --auto --auto-merge #${ISSUE}"
```

### Step 4: コンテキスト注入構築

```bash
CONTEXT_ARGS=""
CONTEXT_TEXT=""

# cross-issue 警告（high confidence のみ）
if [ -n "${CROSS_ISSUE_WARNINGS[$ISSUE]:-}" ]; then
  CONTEXT_TEXT="[Cross-Issue Warning] 以下のIssueが関連ファイルを変更済みです（競合に注意）:"$'\n'"${CROSS_ISSUE_WARNINGS[$ISSUE]}"
fi

# retrospective 知見
if [ -n "${PHASE_INSIGHTS:-}" ]; then
  [ -n "$CONTEXT_TEXT" ] && CONTEXT_TEXT="${CONTEXT_TEXT}"$'\n\n'
  CONTEXT_TEXT="${CONTEXT_TEXT}[Retrospective] 前Phaseからの参考情報（ワーカーの判断を制約しない）:"$'\n'"${PHASE_INSIGHTS}"
fi

if [ -n "$CONTEXT_TEXT" ]; then
  QUOTED_CONTEXT=$(printf '%q' "$CONTEXT_TEXT")
  CONTEXT_ARGS="--append-system-prompt $QUOTED_CONTEXT"
fi
```

### Step 5: tmux window 作成 + cld 起動

```bash
QUOTED_CLD=$(printf '%q' "$CLD_PATH")
QUOTED_PROMPT=$(printf '%q' "$PROMPT")
tmux new-window -n "$WINDOW_NAME" -c "$PROJECT_DIR" \
  "$QUOTED_CLD $CONTEXT_ARGS $QUOTED_PROMPT"
```

**重要**: DEV_AUTOPILOT_SESSION 環境変数は設定しない。Worker は state-read.sh で自身の issue-{N}.json を参照して autopilot 配下であることを判定する。

### Step 6: クラッシュ検知フック設定

```bash
tmux set-option -t "$WINDOW_NAME" remain-on-exit on
tmux set-hook -t "$WINDOW_NAME" pane-died \
  "run-shell 'bash $SCRIPTS_ROOT/crash-detect.sh --issue $ISSUE --window $WINDOW_NAME'"
```

pane-died 時に crash-detect.sh が state-write で status=failed に遷移させる。

## 禁止事項（MUST NOT）

- DEV_AUTOPILOT_SESSION 環境変数を設定してはならない
- マーカーファイル (.pilot-controlled 等) を作成してはならない
- issue-{N}.json を直接作成してはならない（state-write.sh --init に委譲）
