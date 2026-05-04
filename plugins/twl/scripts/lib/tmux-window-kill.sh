#!/usr/bin/env bash
# lib/tmux-window-kill.sh — safe tmux window kill helper
#
# safe_kill_window <window_name>
#   Resolves <window_name> to session:index via list-windows -a, then kills it.
#   Silently skips if the window is not found.
#   Never errors on ambiguous targets (multiple sessions): picks the first match.

safe_kill_window() {
  local window_name="$1"
  local target
  target=$(tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}' 2>/dev/null \
    | awk -v wn="$window_name" '$2 == wn {print $1; exit}')
  if [[ -n "$target" ]]; then
    tmux kill-window -t "$target" 2>/dev/null || true
  fi
}
export -f safe_kill_window
