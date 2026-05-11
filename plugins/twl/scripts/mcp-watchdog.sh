#!/usr/bin/env bash
# MCP server watchdog — auto-restart on process death (#1612)
# Monitors the twl MCP server process and restarts it when it dies.
# Provides permanence guarantee for long-running sessions (3.5h+ stability).
#
# Usage:
#   mcp-watchdog.sh [--interval N] [--daemon]
#     --interval N  : check interval in seconds (default: 30)
#     --daemon      : run in background (daemonize)
#
# DAEMON mode: forks to background, writes PID to ~/.local/state/twl/mcp-watchdog.pid
# On-demand: run once, restart if dead, then exit

set -euo pipefail

INTERVAL="${TWL_MCP_WATCHDOG_INTERVAL:-30}"
DAEMON=0
PID_FILE="${HOME}/.local/state/twl/mcp-watchdog.pid"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --interval)
      if ! [[ "${2:-}" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --interval requires a non-negative integer" >&2; exit 1
      fi
      INTERVAL="$2"; shift 2 ;;
    --daemon) DAEMON=1; shift ;;
    *) break ;;
  esac
done

# 環境変数 INTERVAL の数値検証（非整数はデフォルトにフォールバック）
if ! [[ "$INTERVAL" =~ ^[0-9]+$ ]]; then
  INTERVAL=30
fi

_is_mcp_running() {
  pgrep -f 'fastmcp run.*src/twl/mcp_server/server.py' >/dev/null 2>&1
}

_restart_mcp() {
  twl mcp restart 2>/dev/null || true
}

_watchdog_loop() {
  while true; do
    sleep "$INTERVAL"
    if ! _is_mcp_running; then
      echo "mcp-watchdog: MCP server not running — triggering restart" >&2
      _restart_mcp
    fi
  done
}

if [[ "$DAEMON" -eq 1 ]]; then
  mkdir -p "$(dirname "$PID_FILE")"
  if [[ -f "$PID_FILE" ]]; then
    pid_val=$(cat "$PID_FILE")
    # PID ファイルの内容を数値検証してから kill -0 に渡す（TOCTOU 対策）
    if [[ "$pid_val" =~ ^[0-9]+$ ]] && kill -0 "$pid_val" 2>/dev/null; then
      echo "mcp-watchdog: already running (PID $pid_val)"
      exit 0
    fi
    rm -f "$PID_FILE"
  fi
  _watchdog_loop &
  echo $! > "$PID_FILE"
  echo "mcp-watchdog: started (PID $!)"
else
  # on-demand: check once, restart if dead
  if ! _is_mcp_running; then
    echo "mcp-watchdog: MCP server not running — triggering restart" >&2
    _restart_mcp
  else
    echo "mcp-watchdog: MCP server is running"
  fi
fi
