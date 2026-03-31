# Worker 起動

tmux window を作成し Worker（cld）を起動する。
issue-{N}.json を state-write.sh で初期化し、DEV_AUTOPILOT_SESSION 環境変数は使用しない。
autopilot-phase-execute から呼び出される。

## 前提変数

| 変数 | 説明 |
|------|------|
| `$ISSUE` | Issue 番号（数値） |
| `$PROJECT_DIR` | プロジェクトディレクトリ（デフォルトリポジトリ） |
| `$SESSION_STATE_FILE` | session.json のパス |
| `$CROSS_ISSUE_WARNINGS` | cross-issue 警告の連想配列（Issue番号→警告メッセージ） |
| `$PHASE_INSIGHTS` | 前 Phase の retrospective 知見（空の場合あり） |
| `$ISSUE_REPO_ID` | リポジトリ識別子（クロスリポジトリ時。省略時は _default） |
| `$ISSUE_REPO_OWNER` | リポジトリ owner（クロスリポジトリ時） |
| `$ISSUE_REPO_NAME` | リポジトリ name（クロスリポジトリ時） |
| `$ISSUE_REPO_PATH` | リポジトリパス（クロスリポジトリ時） |
| `$PILOT_AUTOPILOT_DIR` | Pilot 側の .autopilot/ パス（クロスリポジトリ時、Worker の AUTOPILOT_DIR に設定） |

## 実行ロジック（MUST）

### Step 0.5: ISSUE 変数バリデーション

```bash
if [[ ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  echo "Error: ISSUE は正の整数で指定してください"
  return 1
fi
```

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
# クロスリポジトリ: --repo で名前空間化されたパスに初期化
REPO_ARG=""
if [ -n "${ISSUE_REPO_ID:-}" ] && [ "$ISSUE_REPO_ID" != "_default" ]; then
  REPO_ARG="--repo $ISSUE_REPO_ID"
fi
bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role worker $REPO_ARG --init
```

status=running で初期化される。

### Step 3: プロンプト構築

```bash
WINDOW_NAME="ap-#${ISSUE}"
PROMPT="/dev:workflow-setup #${ISSUE}"
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

### Step 4.5: 入力バリデーション

```bash
# ISSUE_REPO_OWNER バリデーション（^[a-zA-Z0-9_-]+$）
if [ -n "${ISSUE_REPO_OWNER:-}" ]; then
  if [[ ! "$ISSUE_REPO_OWNER" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "Error: ISSUE_REPO_OWNER の形式が正しくありません（許可パターン: ^[a-zA-Z0-9_-]+$）"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"invalid_repo_owner\", \"step\": \"launch_worker\"}"
    return 1
  fi
fi

# ISSUE_REPO_NAME バリデーション（^[a-zA-Z0-9_.-]+$）
if [ -n "${ISSUE_REPO_NAME:-}" ]; then
  if [[ ! "$ISSUE_REPO_NAME" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "Error: ISSUE_REPO_NAME の形式が正しくありません（許可パターン: ^[a-zA-Z0-9_.-]+$）"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"invalid_repo_name\", \"step\": \"launch_worker\"}"
    return 1
  fi
fi

# PILOT_AUTOPILOT_DIR バリデーション（絶対パス必須 + パストラバーサル禁止）
if [ -n "${PILOT_AUTOPILOT_DIR:-}" ]; then
  if [[ ! "$PILOT_AUTOPILOT_DIR" =~ ^/ ]]; then
    echo "Error: PILOT_AUTOPILOT_DIR は絶対パスで指定してください"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"invalid_autopilot_dir\", \"step\": \"launch_worker\"}"
    return 1
  fi
  if [[ "$PILOT_AUTOPILOT_DIR" =~ /\.\./ || "$PILOT_AUTOPILOT_DIR" =~ /\.\.$ ]]; then
    echo "Error: PILOT_AUTOPILOT_DIR にパストラバーサルは使用できません"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"invalid_autopilot_dir\", \"step\": \"launch_worker\"}"
    return 1
  fi
fi
```

### Step 5: tmux window 作成 + cld 起動

```bash
# クロスリポジトリ: ISSUE_REPO_PATH が設定されていれば外部リポジトリで起動
EFFECTIVE_PROJECT_DIR="$PROJECT_DIR"
if [ -n "${ISSUE_REPO_PATH:-}" ]; then
  # ISSUE_REPO_PATH バリデーション（絶対パス必須 + パストラバーサル禁止）
  if [[ ! "$ISSUE_REPO_PATH" =~ ^/ ]]; then
    echo "Error: ISSUE_REPO_PATH は絶対パスで指定してください"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"invalid_repo_path\", \"step\": \"launch_worker\"}"
    return 1
  fi
  if [[ "$ISSUE_REPO_PATH" =~ /\.\./ || "$ISSUE_REPO_PATH" =~ /\.\.$ ]]; then
    echo "Error: ISSUE_REPO_PATH にパストラバーサルは使用できません"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"invalid_repo_path\", \"step\": \"launch_worker\"}"
    return 1
  fi
  if [ ! -d "$ISSUE_REPO_PATH" ]; then
    echo "Error: リポジトリパスが見つかりません"
    bash $SCRIPTS_ROOT/state-write.sh --type issue --issue "$ISSUE" --role pilot $REPO_ARG \
      --set "status=failed" \
      --set "failure={\"message\": \"repo_path_not_found\", \"step\": \"launch_worker\"}"
    return 1
  fi
  EFFECTIVE_PROJECT_DIR="$ISSUE_REPO_PATH"
fi

# bare repo では main/ worktree で起動する（CLAUDE.md 制約: main/ 配下必須）
if [ -d "$EFFECTIVE_PROJECT_DIR/.bare" ]; then
  LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR/main"
else
  LAUNCH_DIR="$EFFECTIVE_PROJECT_DIR"
fi

# クロスリポジトリ: AUTOPILOT_DIR を Pilot 側に固定（Worker が状態を共有するため）
AUTOPILOT_ENV=""
if [ -n "${PILOT_AUTOPILOT_DIR:-}" ]; then
  QUOTED_AUTOPILOT_DIR=$(printf '%q' "$PILOT_AUTOPILOT_DIR")
  AUTOPILOT_ENV="AUTOPILOT_DIR=${QUOTED_AUTOPILOT_DIR}"
fi

# クロスリポジトリ: REPO_OWNER/REPO_NAME を環境変数で Worker に渡す
REPO_ENV=""
if [ -n "${ISSUE_REPO_OWNER:-}" ] && [ -n "${ISSUE_REPO_NAME:-}" ]; then
  QUOTED_REPO_OWNER=$(printf '%q' "$ISSUE_REPO_OWNER")
  QUOTED_REPO_NAME=$(printf '%q' "$ISSUE_REPO_NAME")
  REPO_ENV="REPO_OWNER=${QUOTED_REPO_OWNER} REPO_NAME=${QUOTED_REPO_NAME}"
fi

QUOTED_CLD=$(printf '%q' "$CLD_PATH")
QUOTED_PROMPT=$(printf '%q' "$PROMPT")
# プロンプトは positional arg で渡す。-p/--print は禁止（非対話モードで即終了する）
tmux new-window -n "$WINDOW_NAME" -c "$LAUNCH_DIR" \
  "env ${AUTOPILOT_ENV} ${REPO_ENV} $QUOTED_CLD $CONTEXT_ARGS $QUOTED_PROMPT"
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
- `cld -p` / `cld --print` を使用してはならない（非対話 print モードで起動し、Worker が即終了する）
