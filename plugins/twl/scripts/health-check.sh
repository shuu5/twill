#!/usr/bin/env bash
# health-check.sh - Worker 論理的異常検知（proactive monitoring）
# crash-detect.sh（プロセス死亡）とは責務が異なる:
#   crash-detect = プロセス死亡検知
#   health-check = 論理的異常検知（chain停止、エラー出力、input-waiting長時間）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"

# 閾値（環境変数で上書き可能）
CHAIN_STALL_MIN="${DEV_HEALTH_CHAIN_STALL_MIN:-10}"
INPUT_WAIT_MIN="${DEV_HEALTH_INPUT_WAIT_MIN:-5}"

# session-state.sh の解決
SESSION_STATE_CMD="${SESSION_STATE_CMD-${SCRIPT_DIR}/session-state-wrapper.sh}"
if [[ -n "$SESSION_STATE_CMD" && "$SESSION_STATE_CMD" == /* && "$SESSION_STATE_CMD" != *..* && -x "$SESSION_STATE_CMD" ]]; then
  USE_SESSION_STATE=true
else
  USE_SESSION_STATE=false
fi

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --issue N --window <window-name>

Worker の論理的異常を検知する。crash-detect.sh（プロセス死亡）とは責務分離。

Options:
  --issue N               Issue番号（必須）
  --window <window-name>  tmux ウィンドウ名（必須）
  -h, --help              このヘルプを表示

Exit codes:
  0: 異常なし
  1: 異常検知（stdout に検知パターンを出力）
  3: API overload stall 検知（529 overloaded_error + input-waiting 状態）

Environment:
  DEV_HEALTH_CHAIN_STALL_MIN   chain 停止閾値（分、デフォルト: 10）
  DEV_HEALTH_INPUT_WAIT_MIN    input-waiting 閾値（分、デフォルト: 5）
  AUTOPILOT_DIR                autopilot ディレクトリ
  SESSION_STATE_CMD            session-state.sh パス
EOF
}

issue=""
window=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) issue="$2"; shift 2 ;;
    --window) window="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$issue" || -z "$window" ]]; then
  echo "ERROR: --issue と --window は必須です" >&2
  exit 1
fi

if [[ ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --issue は正の整数を指定してください: $issue" >&2
  exit 1
fi

# window 名のバリデーション（tmux ターゲット記法の安全な文字のみ許可）
if [[ ! "$window" =~ ^[a-zA-Z0-9_.:#-]+$ ]]; then
  echo "ERROR: 不正なウィンドウ名: $window（英数字、ハイフン、アンダースコア、ドット、コロン、#のみ許可）" >&2
  exit 1
fi

# --- tmux 出力サニタイズ ---
sanitize_capture() {
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '\000-\010\016-\037'
}

# --- tmux capture を1回だけ取得（全検知とレポートで共有） ---
PANE_CAPTURE=$(tmux capture-pane -t "$window" -p -S -50 2>/dev/null | sanitize_capture || echo "")

# --- 検知結果を stdout に返す関数群 ---
# 各関数は検知時に "pattern:detail" 形式で stdout に出力し、未検知時は何も出力しない

check_chain_stall() {
  local updated_at
  updated_at=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field updated_at 2>/dev/null || echo "")

  if [[ -z "$updated_at" ]]; then
    return
  fi

  # ISO8601 形式のバリデーション
  if [[ ! "$updated_at" =~ ^[0-9T:.Z+-]+$ ]]; then
    return
  fi

  local updated_epoch now_epoch elapsed_min
  updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "")
  if [[ -z "$updated_epoch" ]]; then
    return
  fi

  now_epoch=$(date +%s)
  elapsed_min=$(( (now_epoch - updated_epoch) / 60 ))

  if [[ "$elapsed_min" -gt "$CHAIN_STALL_MIN" ]]; then
    echo "chain_stall:${elapsed_min} minutes since last update (threshold: ${CHAIN_STALL_MIN})"
  fi
}

check_error_output() {
  if [[ -z "$PANE_CAPTURE" ]]; then
    return
  fi

  local error_lines
  error_lines=$(echo "$PANE_CAPTURE" | grep -iE 'Error|FATAL|panic|Traceback' 2>/dev/null || echo "")

  if [[ -n "$error_lines" ]]; then
    echo "error_output:$(echo "$error_lines" | head -5 | tr '\n' '; ' | sed 's/; $//')"
  fi
}

check_input_waiting() {
  if [[ "$USE_SESSION_STATE" != "true" ]]; then
    return
  fi

  local state
  state=$("$SESSION_STATE_CMD" state "$window" 2>/dev/null || echo "")

  if [[ "$state" != "input-waiting" ]]; then
    return
  fi

  local state_info since_epoch now_epoch elapsed_min
  state_info=$("$SESSION_STATE_CMD" get "$window" 2>/dev/null || echo "")

  if [[ -z "$state_info" ]]; then
    return
  fi

  since_epoch=$(echo "$state_info" | jq -r '.since // empty' 2>/dev/null || echo "")
  if [[ -n "$since_epoch" ]]; then
    now_epoch=$(date +%s)
    elapsed_min=$(( (now_epoch - since_epoch) / 60 ))
  else
    local updated_at
    updated_at=$(python3 -m twl.autopilot.state read --type issue --issue "$issue" --field updated_at 2>/dev/null || echo "")
    if [[ -z "$updated_at" ]]; then
      return
    fi
    local updated_epoch
    updated_epoch=$(date -d "$updated_at" +%s 2>/dev/null || echo "")
    now_epoch=$(date +%s)
    elapsed_min=$(( (now_epoch - updated_epoch) / 60 ))
  fi

  if [[ "$elapsed_min" -gt "$INPUT_WAIT_MIN" ]]; then
    echo "input_waiting:${elapsed_min} minutes in input-waiting state (threshold: ${INPUT_WAIT_MIN})"
  fi
}

check_api_overload_stall() {
  if [[ -z "$PANE_CAPTURE" ]]; then
    return
  fi

  # 529 overloaded_error パターンを検知
  if ! echo "$PANE_CAPTURE" | grep -qP '529.*overloaded_error|overloaded_error.*529'; then
    return
  fi

  # input-waiting 状態を確認（リトライ上限到達でスタックしている条件）
  if [[ "$USE_SESSION_STATE" != "true" ]]; then
    return
  fi

  local state
  state=$("$SESSION_STATE_CMD" state "$window" 2>/dev/null || echo "")

  if [[ "$state" != "input-waiting" ]]; then
    return
  fi

  echo "api_overload_stall:529 overloaded_error detected in tmux capture and worker is input-waiting (retry limit reached)"
}

# --- 検知実行（各関数の stdout を集約） ---
RESULTS=()
while IFS= read -r line; do
  [[ -n "$line" ]] && RESULTS+=("$line")
done < <(check_chain_stall; check_error_output; check_input_waiting; check_api_overload_stall)

if [[ ${#RESULTS[@]} -eq 0 ]]; then
  exit 0
fi

# pattern と detail を分離して stdout に出力
DETECTED_PATTERNS=()
DETECTED_DETAILS=()
HAS_API_OVERLOAD=false
for result in "${RESULTS[@]}"; do
  pattern="${result%%:*}"
  detail="${result#*:}"
  DETECTED_PATTERNS+=("$pattern")
  DETECTED_DETAILS+=("${pattern}: ${detail}")
  echo "${pattern}: ${detail}"
  [[ "$pattern" == "api_overload_stall" ]] && HAS_API_OVERLOAD=true
done

# --- health-report 生成 ---
build_action_suggestions() {
  local suggestions=""
  for pattern in "${DETECTED_PATTERNS[@]}"; do
    case "$pattern" in
      chain_stall)
        suggestions+="- Worker の chain 実行が停止している可能性。ログを確認し、手動で再開またはリスタートを検討"$'\n'
        ;;
      error_output)
        suggestions+="- Worker にエラー出力を検出。tmux capture-pane でエラー内容を確認し、根本原因を調査"$'\n'
        ;;
      input_waiting)
        suggestions+="- Worker が入力待ち状態で長時間停止。AskUserQuestion への応答が必要か、またはハング状態の可能性"$'\n'
        ;;
      api_overload_stall)
        suggestions+="- API 529 過負荷によるスタックを検知。orchestrator が自動的に fallback モデルへの切替を実行します（fallback_count が 0 の場合）"$'\n'
        ;;
    esac
  done
  echo "$suggestions"
}

write_report_file() {
  local report_file="$1"
  local patterns_str detection_time details_str capture_tail action_suggestions

  patterns_str=$(printf '%s, ' "${DETECTED_PATTERNS[@]}")
  patterns_str="${patterns_str%, }"
  detection_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  details_str=""
  for detail in "${DETECTED_DETAILS[@]}"; do
    details_str+="- ${detail}"$'\n'
  done

  capture_tail=$(echo "$PANE_CAPTURE" | tail -20)
  action_suggestions=$(build_action_suggestions)

  {
    printf '# Health Check Report\n\n'
    printf '**Issue**: #%s\n' "$issue"
    printf '**Window**: %s\n' "$window"
    printf '**検知時刻**: %s\n' "$detection_time"
    printf '**検知パターン**: %s\n\n' "$patterns_str"
    printf '## 検知詳細\n\n%s\n' "$details_str"
    printf '## tmux capture-pane 出力（最新 50 行）\n\n```\n%s\n```\n\n' "$PANE_CAPTURE"
    printf '## Issue Draft\n\n'
    printf '**Title**: [autopilot] Worker #%s: %s\n\n' "$issue" "$patterns_str"
    printf '**Body**:\n\n'
    printf '### 概要\n\n'
    printf 'Pilot の proactive health check により Worker #%s で論理的異常を検知しました。\n' "$issue"
    printf '検知パターン: %s\n\n' "$patterns_str"
    printf '### 再現状況\n\n%s\n\n' "$capture_tail"
    printf '### 対応候補\n\n%s\n' "$action_suggestions"
  } > "$report_file"
}

report_dir="$AUTOPILOT_DIR/health-reports"
mkdir -p "$report_dir"
report_file="$report_dir/issue-${issue}-$(date +"%Y%m%d-%H%M%S").md"
write_report_file "$report_file"
echo "health-report: $report_file" >&2

# exit 3: API overload stall 検知（fallback 判定のため exit code を分離）
if [[ "$HAS_API_OVERLOAD" == "true" ]]; then
  exit 3
fi
exit 1
