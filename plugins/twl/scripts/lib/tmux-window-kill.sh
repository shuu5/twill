#!/usr/bin/env bash
# lib/tmux-window-kill.sh — safe tmux window kill helper
#
# safe_kill_window <window_name>
#   Resolves <window_name> to session:index via list-windows -a, then kills it.
#   Silently skips if the window is not found.
#   Never errors on ambiguous targets (multiple sessions): picks the first match.
#
# Issue #1360: tmux server burst-kill 緩和。
#   連続 kill-window で tmux server が SIGSEGV 死するインシデントが
#   2026-05-03 (#1310 / #1302 cleanup) で 2 件発生。本ヘルパーは
#   kill 直後に SAFE_KILL_WINDOW_SLEEP 秒（default 1 秒）待機して
#   server への rapid kill burst を緩和する。0 で無効化（テスト用）。

safe_kill_window() {
  local window_name="$1"
  local target
  target=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' 2>/dev/null \
    | awk -v wn="$window_name" '$2 == wn {print $1; exit}')
  if [[ -n "$target" ]]; then
    tmux kill-window -t "$target" 2>/dev/null || true
    sleep "${SAFE_KILL_WINDOW_SLEEP:-1}"
  fi
}
export -f safe_kill_window
