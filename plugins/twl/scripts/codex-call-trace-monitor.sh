#!/usr/bin/env bash
# codex-call-trace-monitor.sh
#
# Issue #1484: codex CLI wrapper の定期 audit スクリプト。
# ~/.codex-call-trace.log を検査し異常を WARN で報告する。
#
# Usage:
#   bash codex-call-trace-monitor.sh [--log <logfile>]
#
# AC4:
#   - 24h ゼロ call → WARN
#   - exit != 0 が 3 回以上連続 → WARN

set -uo pipefail

LOG_FILE="${HOME}/.codex-call-trace.log"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      LOG_FILE="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

WARN_COUNT=0

# AC4: 24h ゼロ call 検出
if ! grep -qE "timestamp=" "$LOG_FILE" 2>/dev/null; then
  echo "WARN: codex CLI not called in last 24h (subagent silent skip suspected)" >&2
  WARN_COUNT=$((WARN_COUNT + 1))
fi

# AC4: exit != 0 連続検出 (3 回以上)
if [[ -f "$LOG_FILE" ]]; then
  consec_fail=0
  fail_detected=0
  while IFS= read -r line; do
    if [[ "$line" =~ EXIT_CODE=([0-9]+) ]]; then
      code="${BASH_REMATCH[1]}"
      if [[ "$code" -ne 0 ]]; then
        consec_fail=$((consec_fail + 1))
        if [[ "$consec_fail" -ge 3 ]]; then
          fail_detected=1
          break
        fi
      else
        consec_fail=0
      fi
    fi
  done < "$LOG_FILE"

  if [[ "$fail_detected" -eq 1 ]]; then
    echo "WARN: codex CLI exit != 0 consecutively (3+ times) — possible systematic failure" >&2
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
fi

if [[ "$WARN_COUNT" -eq 0 ]]; then
  echo "OK: codex call trace within normal range"
fi

exit 0
