#!/usr/bin/env bash
# codex-wrapper.sh
#
# Issue #1484: codex CLI 透過 wrapper。
# ~/.local/bin/codex として配置し、全呼び出しを ~/.codex-call-trace.log に記録する。
#
# インストール:
#   mv ~/.local/bin/codex ~/.local/bin/codex.real
#   cp plugins/twl/scripts/codex-wrapper.sh ~/.local/bin/codex
#   chmod +x ~/.local/bin/codex
#
# ロールバック (AC5):
#   mv ~/.local/bin/codex.real ~/.local/bin/codex

set -uo pipefail

LOG="${HOME}/.codex-call-trace.log"
CODEX_REAL="${HOME}/.local/bin/codex.real"

# Pre-execution logging (AC2)
{
  echo "===== $(date -Iseconds) PID=$$ PPID=$PPID ====="
  echo "timestamp=$(date -Iseconds)"
  echo "PID=$$"
  echo "PPID=$PPID"
  echo "PWD=$PWD"
  printf 'ARGS=%s\n' "$(printf '%q ' "$@")"
  echo "PARENT=$(ps -o args= -p "$PPID" 2>/dev/null | head -c 300)"
} >> "$LOG"

# Stdin handling (AC2: STDIN_LEN only — STDIN_HEAD omitted to avoid logging sensitive data)
TMP=""
if [[ ! -t 0 ]]; then
  TMP=$(mktemp)
  cat > "$TMP"
  echo "STDIN_LEN=$(wc -c < "$TMP")" >> "$LOG"
fi

# Interactive TTY: exec codex.real for true transparency (AC1)
if [[ -t 0 && -t 1 && -z "$TMP" ]]; then
  exec "${CODEX_REAL}" "$@"
fi

# Non-interactive: capture stderr for quota detection, pass stdout through (AC2/AC3)
STDERR_TMP=$(mktemp)
EXIT=0
if [[ -n "$TMP" ]]; then
  "${CODEX_REAL}" "$@" < "$TMP" 2>"$STDERR_TMP"
  EXIT=$?
  rm -f "$TMP"
else
  "${CODEX_REAL}" "$@" 2>"$STDERR_TMP"
  EXIT=$?
fi

# Pass stderr back to caller's stderr
cat "$STDERR_TMP" >&2

# Log exit code and quota detection (AC2, AC6)
{
  echo "EXIT_CODE=${EXIT}"
  # Quota/exceeded pattern detection (AC6)
  if grep -qE '[Qq]uota|exceeded' "$STDERR_TMP" 2>/dev/null; then
    CODEX_SKIP_REASON="quota_exceeded"
    echo "CODEX_SKIP_REASON=${CODEX_SKIP_REASON}"
  fi
  echo "===== END exit=${EXIT} ====="
} >> "$LOG"

rm -f "$STDERR_TMP"
exit "$EXIT"
