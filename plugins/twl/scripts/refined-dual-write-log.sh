#!/usr/bin/env bash
# plugins/twl/scripts/refined-dual-write-log.sh
# dual-write observability helper (Issue #1212)
#
# Usage: source this file, then call:
#   dual_write_log <level> <event_type> <issue_num> [key=value ...]
#
# level:      WARN | OK
# event_type: label_add_failed | status_update_failed | dual_write
# issue_num:  digits only ('#' is prepended by this function)
#
# Log file: ${REFINED_DUAL_WRITE_LOG:-/tmp/refined-dual-write.log}
# Physical separation from /tmp/refined-status-gate.log is intentional (Issue #1212).

dual_write_log() {
  local level="$1"
  local event="$2"
  local issue="$3"
  shift 3
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local _log_file="${REFINED_DUAL_WRITE_LOG:-/tmp/refined-dual-write.log}"
  printf '[%s] %s %s issue=#%s %s\n' "$ts" "$level" "$event" "$issue" "$*" \
    >> "$_log_file" 2>/dev/null || true
}
