#!/usr/bin/env bash
# detect-input-waiting.sh — detect_input_waiting() ロジックの test double
#
# 引数:
#   --pane-output "<テキスト>"   検査対象の pane テキスト（必須）
#   --issue N                    Issue 番号（デバウンス用、省略時は "0"）
#
# 環境変数:
#   SEEN_FILE                    デバウンス状態ファイルのパス（省略時はデバウンス無効）
#   AUTOPILOT_DIR                state write 先の .autopilot ディレクトリ
#   STATE_WRITE_LOG              state write 呼び出しをログするファイル（テスト用）
#
# 出力:
#   stdout: 検知した pattern name（未検知時は空）
# 終了コード: 常に 0

set -euo pipefail

PANE_OUTPUT=""
ISSUE="0"

# --- 引数パース ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pane-output) PANE_OUTPUT="$2"; shift 2 ;;
    --issue)       ISSUE="$2";       shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# パターン定義
# ---------------------------------------------------------------------------

# Menu UI パターン
declare -a MENU_PATTERNS
MENU_PATTERNS=(
  "Enter to select"
  "↑/↓ to navigate"
  "❯[[:space:]]*[0-9]+\."
)

declare -a MENU_NAMES
MENU_NAMES=(
  "menu_enter_select"
  "menu_arrow_navigate"
  "menu_prompt_number"
)

# Free-form text パターン
declare -a FREEFORM_PATTERNS
FREEFORM_PATTERNS=(
  "よろしいですか[？?]"
  "続けますか|進んでよいですか|実行しますか"
  "\[[Yy]/[Nn]\]"
)

declare -a FREEFORM_NAMES
FREEFORM_NAMES=(
  "freeform_yoroshii"
  "freeform_tsuzukemasu"
  "freeform_yn_bracket"
)

# ---------------------------------------------------------------------------
# パターンマッチ
# ---------------------------------------------------------------------------

matched_pattern=""

# Menu UI
for i in "${!MENU_PATTERNS[@]}"; do
  if echo "$PANE_OUTPUT" | grep -qE "${MENU_PATTERNS[$i]}"; then
    matched_pattern="${MENU_NAMES[$i]}"
    break
  fi
done

# Free-form（Menu UI 未検知時）
if [[ -z "$matched_pattern" ]]; then
  for i in "${!FREEFORM_PATTERNS[@]}"; do
    if echo "$PANE_OUTPUT" | grep -qE "${FREEFORM_PATTERNS[$i]}"; then
      matched_pattern="${FREEFORM_NAMES[$i]}"
      break
    fi
  done
fi

# 未検知
if [[ -z "$matched_pattern" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# デバウンス: SEEN_FILE が指定されている場合のみ有効
# ---------------------------------------------------------------------------

if [[ -z "${SEEN_FILE:-}" ]]; then
  # デバウンス無効 — 即時出力
  echo "$matched_pattern"
  exit 0
fi

SEEN_KEY="${ISSUE}:${matched_pattern}"

if grep -qF "$SEEN_KEY" "$SEEN_FILE" 2>/dev/null; then
  # 2 回目検知 — state write を実行
  echo "[detect-input-waiting] debounce confirmed: issue=${ISSUE} pattern=${matched_pattern}" >&2

  # state write (python3 -m twl.autopilot.state または STATE_WRITE_LOG へ記録)
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [[ -n "${STATE_WRITE_LOG:-}" ]]; then
    echo "--type issue --issue ${ISSUE} --role pilot --set input_waiting_detected=${matched_pattern} --set input_waiting_at=${ts}" \
      >> "$STATE_WRITE_LOG"
  else
    python3 -m twl.autopilot.state write \
      --type issue --issue "$ISSUE" --role pilot \
      --set "input_waiting_detected=${matched_pattern}" \
      --set "input_waiting_at=${ts}" \
      ${AUTOPILOT_DIR:+--autopilot-dir "$AUTOPILOT_DIR"} 2>&1 || true
  fi

  # trace log 追記
  if [[ -n "${AUTOPILOT_DIR:-}" ]]; then
    trace_dir="${AUTOPILOT_DIR}/trace"
    mkdir -p "$trace_dir"
    trace_file="${trace_dir}/input-waiting-$(date -u +"%Y%m%d").log"
    echo "[${ts}] issue=${ISSUE} pattern=${matched_pattern} window=" >> "$trace_file"
  fi

  echo "$matched_pattern"
else
  # 1 回目検知 — SEEN_FILE に記録して warn ログのみ
  echo "$SEEN_KEY" >> "$SEEN_FILE"
  echo "[WARN] input-waiting first detection: issue=${ISSUE} pattern=${matched_pattern} — waiting for 2nd cycle" >&2
  # stdout は空（state write しない）
fi

exit 0
