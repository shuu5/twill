#!/usr/bin/env bash
# observer-window-check.sh: tmux window 存在確認ヘルパー関数
#
# 背景（Issue #948, R6）:
#   tmux の has-session コマンドは session specifier を受け取るため、
#   window 名を -t に渡しても常に false を返し false positive [WINDOW-GONE] を引き起こす。
#   本ライブラリはその正しい代替実装（list-windows ベース）を提供する。
#
# 使用方法:
#   source "$(dirname "$0")/lib/observer-window-check.sh"
#   _check_window_alive "wt-co-explore-114550" && echo "alive" || echo "gone"

# NOTE: set -euo pipefail は意図的に省略（source 専用ライブラリ。strict mode は親シェルに継承される）

# _check_window_alive: tmux window が実在するか確認する
#
# 引数:
#   $1: window 名（例: wt-co-explore-114550, ap-948）
#   $2: (optional) session 名。省略時は全セッションを検索
#
# 戻り値:
#   0: window が存在する（alive）
#   1: window が存在しない（gone）
#
# 実装根拠（Issue #948, R6）:
#   has-session は session specifier を受け取るため window 名の確認に使ってはならない（MUST NOT）
#   詳細は refs/monitor-channel-catalog.md §window 存在確認の正しい方法 を参照
#   正しい方法 A: tmux list-windows -a -F '#W' | grep -Fxq <window-name>
#   正しい方法 B: tmux list-windows -t <session> -F '#W' | grep -Fxq <window-name>
#   正しい方法 C: tmux display-message -t <session>:<window> -p '#{window_id}' 2>/dev/null
_check_window_alive() {
  local window_name="${1:-}"
  local session_name="${2:-}"

  if [[ -z "$window_name" ]]; then
    echo "[observer-window-check] ERROR: window_name が未指定" >&2
    return 1
  fi

  if [[ -n "$session_name" ]]; then
    # 方法 B: 特定 session の window 一覧から検索
    tmux list-windows -t "$session_name" -F '#{window_name}' 2>/dev/null \
      | grep -Fxq "$window_name"
  else
    # 方法 A: 全セッションの window 一覧から検索
    tmux list-windows -a -F '#{window_name}' 2>/dev/null \
      | grep -Fxq "$window_name"
  fi
}

# _get_window_session: window が所属する session 名を返す
#
# 引数:
#   $1: window 名
#
# 出力:
#   session 名（stdout）。不在時は空文字列
_get_window_session() {
  local window_name="${1:-}"

  if [[ -z "$window_name" ]]; then
    return 1
  fi

  tmux list-windows -a -F '#{session_name} #{window_name}' 2>/dev/null \
    | awk -v win="$window_name" '$2 == win { print $1; exit }'
}
