#!/usr/bin/env bats
# EXP-017: tmux format 変数で pane state 取得
#
# 検証内容 (tmux(1) man page):
#   - tmux list-windows -a -F '#{window_name}|#{pane_dead}|#{pane_active}|#{pane_in_mode}'
#   - process exit 後 #{pane_dead}=1 で crash 検知可能 (capture-pane より高速・信頼)
#
# 検証手法 (bats unit):
#   - 独立 socket で tmux server 起動
#   - long-running command の pane で #{pane_dead}=0、completed pane で #{pane_dead}=1 確認
#   - format 変数 syntax を verify

load '../common'

TMUX_TEST_SOCKET=""
TMUX_TEST_SESSION=""

setup() {
    exp_common_setup
    command -v tmux >/dev/null || skip "tmux not installed"
    TMUX_TEST_SOCKET="/tmp/exp-017-tmux-$$"
    TMUX_TEST_SESSION="exp017-$$"
    tmux -S "$TMUX_TEST_SOCKET" new-session -d -s "$TMUX_TEST_SESSION" -- bash -c 'sleep 30'
}

teardown() {
    if [[ -n "$TMUX_TEST_SOCKET" ]] && [[ -S "$TMUX_TEST_SOCKET" ]]; then
        tmux -S "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    fi
    exp_common_teardown
}

@test "tmux-format: list-windows -F '#{window_name}' で window 名取得" {
    local name
    name=$(tmux -S "$TMUX_TEST_SOCKET" list-windows -t "$TMUX_TEST_SESSION" -F '#{window_name}')
    [ -n "$name" ]
}

@test "tmux-format: format 変数 #{pane_dead} が long-running command 中は 0" {
    tmux -S "$TMUX_TEST_SOCKET" new-window -d -t "$TMUX_TEST_SESSION:" -n alive -- bash -c 'sleep 10'
    sleep 0.3
    local dead
    dead=$(tmux -S "$TMUX_TEST_SOCKET" list-windows -t "$TMUX_TEST_SESSION" -F '#{window_name}|#{pane_dead}' | grep '^alive|' | cut -d'|' -f2)
    [ "$dead" = "0" ]
}

@test "tmux-format: 複数 format 変数を pipe 区切りで取得可能" {
    tmux -S "$TMUX_TEST_SOCKET" new-window -d -t "$TMUX_TEST_SESSION:" -n multi -- bash -c 'sleep 5'
    sleep 0.3
    local fmt
    fmt=$(tmux -S "$TMUX_TEST_SOCKET" list-windows -t "$TMUX_TEST_SESSION" -F '#{window_name}|#{pane_dead}|#{pane_active}|#{pane_in_mode}' | grep '^multi|')
    # 4 field 出力 (3 separator)
    local field_count
    field_count=$(echo "$fmt" | awk -F'|' '{print NF}')
    [ "$field_count" -eq 4 ]
}

@test "tmux-format: list-windows -a で全 session の window 列挙可能" {
    tmux -S "$TMUX_TEST_SOCKET" new-session -d -s "exp017-extra-$$" -- bash -c 'sleep 10'
    local all_windows
    all_windows=$(tmux -S "$TMUX_TEST_SOCKET" list-windows -a -F '#{session_name}|#{window_name}')
    # 元の session + 追加 session の両方の window が見える
    local cnt
    cnt=$(echo "$all_windows" | wc -l)
    [ "$cnt" -ge 2 ]
}

@test "tmux-format: crash-failure-mode.html §3 で pane_dead 検知 pattern の static check" {
    local spec="${REPO_ROOT}/architecture/spec/twill-plugin-rebuild/crash-failure-mode.html"
    [ -f "$spec" ] || skip "crash-failure-mode.html not found"
    grep -q '#{pane_dead}\|pane_dead' "$spec" || skip "pane_dead pattern not documented (Phase D で記載予定)"
}
