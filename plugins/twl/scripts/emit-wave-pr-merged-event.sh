#!/usr/bin/env bash
# emit-wave-pr-merged-event.sh — Issue #1428 Layer 1 post-merge event emitter
#
# Usage: emit-wave-pr-merged-event.sh --issue N --pr N --branch BRANCH
#
# 処理:
#   1. .supervisor/wave-queue.json から current_wave を取得（失敗時 wave=-1）
#   2. .supervisor/events/wave-{N}-pr-merged-{issue}.json を atomic write で生成
#   3. Python one-liner で twl_notify_supervisor_handler を呼び出し（best-effort）
#
# exit 0 を常に返す（best-effort: 失敗は WARN のみ stderr 出力）

set -uo pipefail

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
ISSUE_NUM=""
PR_NUM=""
BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)  ISSUE_NUM="$2"; shift 2 ;;
    --pr)     PR_NUM="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    *)        shift ;;
  esac
done

if [[ -z "$ISSUE_NUM" || -z "$PR_NUM" || -z "$BRANCH" ]]; then
  printf '[emit-wave-pr-merged-event] WARN: --issue, --pr, --branch が必要です\n' >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# .supervisor ディレクトリ解決
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd 2>/dev/null || echo "")"
SUPERVISOR_DIR="${SUPERVISOR_DIR:-${REPO_ROOT}/main/.supervisor}"

if [[ ! -d "$SUPERVISOR_DIR" ]]; then
  # fallback: CWD 基準
  SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
fi

EVENTS_DIR="${SUPERVISOR_DIR}/events"
WAVE_QUEUE="${SUPERVISOR_DIR}/wave-queue.json"

# ---------------------------------------------------------------------------
# Step 1: wave 番号取得
# ---------------------------------------------------------------------------
WAVE=-1
WAVE_WARNING=""

if [[ -f "$WAVE_QUEUE" ]]; then
  WAVE_VAL="$(jq -r '.current_wave // empty' "$WAVE_QUEUE" 2>/dev/null || echo "")"
  if [[ "$WAVE_VAL" =~ ^-?[0-9]+$ ]]; then
    WAVE="$WAVE_VAL"
  else
    WAVE_WARNING="wave-queue.json に current_wave が見つからない"
    printf '[emit-wave-pr-merged-event] WARN: %s\n' "$WAVE_WARNING" >&2
  fi
else
  WAVE_WARNING="wave-queue.json が存在しない: $WAVE_QUEUE"
  printf '[emit-wave-pr-merged-event] WARN: %s\n' "$WAVE_WARNING" >&2
fi

# ---------------------------------------------------------------------------
# Step 2: event JSON を atomic write
# ---------------------------------------------------------------------------
mkdir -p "$EVENTS_DIR" || {
  printf '[emit-wave-pr-merged-event] WARN: events/ ディレクトリ作成失敗: %s\n' "$EVENTS_DIR" >&2
  exit 0
}

EVENT_FILE="${EVENTS_DIR}/wave-${WAVE}-pr-merged-${ISSUE_NUM}.json"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")"

# JSON 生成（jq で安全にエスケープ）
PAYLOAD_JSON="$(jq -n \
  --arg event "WAVE-PR-MERGED" \
  --argjson wave "$WAVE" \
  --argjson issue "$ISSUE_NUM" \
  --argjson pr "$PR_NUM" \
  --arg branch "$BRANCH" \
  --arg timestamp "$TIMESTAMP" \
  --arg host "$HOST" \
  '{event: $event, wave: $wave, issue: $issue, pr: $pr, branch: $branch, timestamp: $timestamp, host: $host}')" || {
  printf '[emit-wave-pr-merged-event] WARN: event JSON 生成失敗\n' >&2
  exit 0
}

# warning フィールドを追加（wave=-1 の場合）
if [[ -n "$WAVE_WARNING" ]]; then
  PAYLOAD_JSON="$(echo "$PAYLOAD_JSON" | jq --arg w "$WAVE_WARNING" '. + {warning: $w}')"
fi

# atomic write: mktemp → write → mv
TMPFILE="$(mktemp "${EVENTS_DIR}/.wave-pr-merged-${ISSUE_NUM}.XXXXXX.tmp")" || {
  printf '[emit-wave-pr-merged-event] WARN: tmpfile 作成失敗\n' >&2
  exit 0
}

echo "$PAYLOAD_JSON" > "$TMPFILE" && mv "$TMPFILE" "$EVENT_FILE" || {
  rm -f "$TMPFILE" 2>/dev/null || true
  printf '[emit-wave-pr-merged-event] WARN: event ファイル atomic write 失敗: %s\n' "$EVENT_FILE" >&2
  exit 0
}

printf '[emit-wave-pr-merged-event] event 書き出し完了: %s\n' "$EVENT_FILE"

# ---------------------------------------------------------------------------
# Step 3: twl_notify_supervisor_handler を Python one-liner で呼び出す（best-effort）
# ---------------------------------------------------------------------------
AUTOPILOT_DIR="${AUTOPILOT_DIR:-}"

NOTIFY_RESULT="$(python3 -c "
import json, sys, os
try:
    from twl.mcp_server.tools_comm import twl_notify_supervisor_handler
    payload = json.loads(sys.argv[1])
    autopilot_dir = os.environ.get('AUTOPILOT_DIR') or None
    result = twl_notify_supervisor_handler(
        event='WAVE-PR-MERGED',
        payload=payload,
        autopilot_dir=autopilot_dir,
    )
    parsed = json.loads(result)
    if parsed.get('status') == 'error':
        print('NOTIFY_ERROR: ' + parsed.get('error', ''), file=sys.stderr)
    else:
        print('OK', file=sys.stdout)
except Exception as e:
    print('NOTIFY_EXCEPTION: ' + str(e), file=sys.stderr)
" "$PAYLOAD_JSON" 2>&1)" || true

if echo "$NOTIFY_RESULT" | grep -q "NOTIFY_"; then
  printf '[emit-wave-pr-merged-event] WARN: mailbox push 失敗 (best-effort): %s\n' "$NOTIFY_RESULT" >&2
  if [[ -n "${TWL_NOTIFY_SUPERVISOR_CALL_LOG:-}" ]]; then
    echo "FAILED: $NOTIFY_RESULT" >> "$TWL_NOTIFY_SUPERVISOR_CALL_LOG"
  fi
else
  printf '[emit-wave-pr-merged-event] mailbox push 完了\n'
  if [[ -n "${TWL_NOTIFY_SUPERVISOR_CALL_LOG:-}" ]]; then
    echo "CALLED: WAVE-PR-MERGED $PAYLOAD_JSON" >> "$TWL_NOTIFY_SUPERVISOR_CALL_LOG"
  fi
fi

exit 0
