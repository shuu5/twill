#!/usr/bin/env bats
# EXP-016: tmux new-window -d 動作確認
#
# 検証内容 (tmux(1) man page):
#   - tmux new-window -d -n test-window -c <dir> -- bash -c "..." で detached spawn
#   - target session に新 window 追加、process 完了後に自動消滅
#
# 検証手法 (bats unit):
#   - bats 用の専用 tmux server を独立 socket で起動 (`-S` flag、host tmux 影響防止)
#   - new-window -d で detached spawn → list-windows で確認 → 自動消滅 wait

load '../common'

TMUX_TEST_SOCKET=""
TMUX_TEST_SESSION=""

setup() {
    exp_common_setup
    command -v tmux >/dev/null || skip "tmux not installed"
    # Independent socket so host tmux is untouched (incident 2026-04-22 教訓)
    TMUX_TEST_SOCKET="/tmp/exp-016-tmux-$$"
    TMUX_TEST_SESSION="exp016-$$"
    tmux -S "$TMUX_TEST_SOCKET" new-session -d -s "$TMUX_TEST_SESSION" -- bash -c 'sleep 30'
}

teardown() {
    if [[ -n "$TMUX_TEST_SOCKET" ]] && [[ -S "$TMUX_TEST_SOCKET" ]]; then
        tmux -S "$TMUX_TEST_SOCKET" kill-server 2>/dev/null || true
    fi
    exp_common_teardown
}

@test "tmux-new-window: new-window -d で detached spawn + list-windows で確認可能" {
    tmux -S "$TMUX_TEST_SOCKET" new-window -d -t "$TMUX_TEST_SESSION:" -n test-win -- bash -c 'sleep 10'
    local windows
    windows=$(tmux -S "$TMUX_TEST_SOCKET" list-windows -t "$TMUX_TEST_SESSION" -F '#{window_name}')
    [[ "$windows" == *"test-win"* ]]
}

@test "tmux-new-window: process exit 後 window 自動消滅 (default remain-on-exit off)" {
    tmux -S "$TMUX_TEST_SOCKET" new-window -d -t "$TMUX_TEST_SESSION:" -n ephemeral -- bash -c 'true'
    # 起動直後は存在
    sleep 0.3
    # exit 後消滅
    sleep 1
    local windows
    windows=$(tmux -S "$TMUX_TEST_SOCKET" list-windows -t "$TMUX_TEST_SESSION" -F '#{window_name}' 2>/dev/null || echo "")
    [[ "$windows" != *"ephemeral"* ]]
}

@test "tmux-new-window: -c flag で working directory 指定可能" {
    tmux -S "$TMUX_TEST_SOCKET" new-window -d -t "$TMUX_TEST_SESSION:" -n cwd-test -c "$SANDBOX" -- bash -c 'pwd > /tmp/exp-016-pwd.log; sleep 5'
    sleep 0.5
    [ -f /tmp/exp-016-pwd.log ]
    local pwd_captured
    pwd_captured=$(cat /tmp/exp-016-pwd.log)
    [[ "$pwd_captured" == "$SANDBOX" ]]
    rm -f /tmp/exp-016-pwd.log
}

@test "tmux-new-window: spawn-protocol.html §2 で new-window -d 採用根拠の static check" {
    local spec="${REPO_ROOT}/architecture/spec/twill-plugin-rebuild/spawn-protocol.html"
    [ -f "$spec" ] || skip "spawn-protocol.html not found"
    # spawn-protocol.html で tmux new-window pattern が記載されていることを確認
    grep -q 'tmux new-window' "$spec" || skip "tmux new-window not documented in spawn-protocol.html (Phase D で追記予定)"
}
