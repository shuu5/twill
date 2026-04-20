#!/usr/bin/env bats
# cld-observe-any.bats - 多指標 AND 判定の unit tests
# tmux 依存なし（モックアプローチ）

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
CLD_OBSERVE_LOOP="$SCRIPT_DIR/cld-observe-loop"

setup() {
    TMPDIR_TEST="$(mktemp -d)"
    FAKE_WIN="test-win-$$"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"
}

# ---------------------------------------------------------------------------
# ヘルパー: tmux/session-state.sh をモックして cld-observe-any --once を実行
# ---------------------------------------------------------------------------
# pane_info: "pane_dead pane_cmd"（例: "0 claude"）
# capture_content: tmux capture-pane が返す scrollback テキスト
# status_line: status line（budget パース対象、空可）
run_observe_once() {
    local win="$1"
    local pane_info="${2:-0 claude}"
    local capture_content="${3:-}"
    local status_line="${4:-}"
    local extra_args="${5:-}"

    local pane_dead="${pane_info%% *}"
    local pane_cmd="${pane_info#* }"

    local capture_file="$TMPDIR_TEST/capture.txt"
    printf '%s\n' "$capture_content" > "$capture_file"
    local status_file="$TMPDIR_TEST/status.txt"
    printf '%s\n' "$status_line" > "$status_file"
    local list_file="$TMPDIR_TEST/list.txt"
    printf 'test-session:0 %s\n' "$win" > "$list_file"

    run bash <<EOF
_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR"

# tmux モック
tmux() {
    case "\$1" in
        list-windows)
            if [[ "\${2:-}" == "-a" ]]; then
                # get_target_windows の呼び出し
                printf 'test-session:0\n'
                return
            fi
            cat "$list_file"
            ;;
        display-message)
            # pane_dead + pane_current_command
            echo "${pane_dead} ${pane_cmd}"
            ;;
        capture-pane)
            # status line または scrollback
            if [[ "\${*}" == *"-S -1"* ]]; then
                cat "$status_file"
            else
                cat "$capture_file"
            fi
            ;;
        *)
            return 0 ;;
    esac
}
export -f tmux

# session-state.sh モック
"$SCRIPT_DIR/session-state.sh"() { echo "processing"; }
export -f "$SCRIPT_DIR/session-state.sh" 2>/dev/null || true

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once $extra_args
EOF
}

# ---------------------------------------------------------------------------
# Scenario 1: LLM indicator あり → event emit されないこと（false positive 再発防止）
# ---------------------------------------------------------------------------
@test "LLM indicator 'Brewing' あり → event emit なし" {
    local win="ap-test-win-1"
    local capture
    capture="Brewing for 9m 19s · max effort
Some task in progress..."

    # tmux モック（indicator あり、log age は十分古い）
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-test-win-1"
capture="Brewing for 9m 19s · max effort
Some task in progress..."

tmux() {
    case "$1" in
        list-windows)
            echo "test-session:0 $win";;
        display-message)
            echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --complete-regex "PHASE_COMPLETE" --stagnate-sec 10 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    # LLM indicator があるので何も emit されない
    [[ -z "$output" ]]
}

# ---------------------------------------------------------------------------
# Scenario 2: menu UI あり AND indicator なし AND log 静止 → [MENU-READY] emit
# ---------------------------------------------------------------------------
@test "MENU-READY: indicator なし + Enter to select + log age 60s → emit" {
    local win="ap-test-win-2"
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-test-win-2"

capture="Please select an option:
❯ 1. Yes
  2. No
Enter to select · ↑/↓ to navigate · Esc to cancel"

# log ファイルを60秒以上前の mtime で作成
logfile="$TMPD/${win}.log"
touch -t "$(date -d '2 minutes ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-2M '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

tmux() {
    case "$1" in
        list-windows)
            echo "test-session:0 $win";;
        display-message)
            echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --log-dir "$TMPD" 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "MENU-READY"
}

# ---------------------------------------------------------------------------
# Scenario 3: pane_dead=1 → [PANE-DEAD] 即 emit
# ---------------------------------------------------------------------------
@test "PANE-DEAD: pane_dead=1 → 即 emit" {
    local win="ap-dead-win"
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-dead-win"

tmux() {
    case "$1" in
        list-windows)
            echo "test-session:0 $win";;
        display-message)
            echo "1 bash";;
        capture-pane)
            echo "";;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PANE-DEAD"
}

# ---------------------------------------------------------------------------
# Scenario 4: budget 10m → [BUDGET-LOW] emit
# ---------------------------------------------------------------------------
@test "BUDGET-LOW: budget 10m (threshold 15) → emit" {
    local win="ap-budget-win"
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-budget-win"

tmux() {
    case "$1" in
        list-windows)
            echo "test-session:0 $win";;
        display-message)
            echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then
                echo "● claude-sonnet-4-6  budget: 10m  esc to interrupt"
            else
                echo "Working..."
            fi;;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --budget-threshold 15 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "BUDGET-LOW"
}

# ---------------------------------------------------------------------------
# Scenario 5: PHASE-COMPLETE --complete-require-cmd-echo 指定時
#   phrase のみでは emit せず、コマンドエコー検出時のみ emit
# ---------------------------------------------------------------------------
@test "PHASE-COMPLETE: phrase のみでは emit しない（cmd-echo 未検出）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-phase-win"

capture="Task completed successfully!
Refine 完了 (PHASE_COMPLETE)"

logfile="$TMPD/${win}.log"
touch -t "$(date -d '2 minutes ago' '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --log-dir "$TMPD" \
    --complete-regex "PHASE_COMPLETE" \
    --complete-require-cmd-echo "gh issue edit [0-9]+ --add-label refined" 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    # cmd-echo 未検出なので emit なし
    [[ -z "$output" ]]
}

@test "PHASE-COMPLETE: phrase + cmd-echo 両方検出 → emit" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-phase-win2"

capture="Refine 完了 (PHASE_COMPLETE)
gh issue edit 741 --add-label refined"

logfile="$TMPD/${win}.log"
touch -t "$(date -d '2 minutes ago' '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --log-dir "$TMPD" \
    --complete-regex "PHASE_COMPLETE" \
    --complete-require-cmd-echo "gh issue edit [0-9]+ --add-label refined" 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PHASE-COMPLETE"
}

# ---------------------------------------------------------------------------
# Scenario 6: --event-dir 指定時に atomic write される JSON スキーマ確認
# ---------------------------------------------------------------------------
@test "event-dir: PANE-DEAD イベント JSON に必須フィールドが含まれる" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-json-win"
EVENT_DIR="$TMPD/events"

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "1 bash";;
        capture-pane) echo "";;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --event-dir "$EVENT_DIR" 2>/dev/null

# JSON ファイルが生成されていることを確認
f=$(find "$EVENT_DIR" -name "PANE-DEAD-*.json" 2>/dev/null | head -1)
if [[ -z "$f" ]]; then echo "No JSON file generated"; exit 1; fi

# 必須フィールド確認
jq -e '.event and .window and .timestamp' "$f" >/dev/null || { echo "Missing required fields"; cat "$f"; exit 1; }
echo "OK: $(cat "$f")"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "OK:"
}

# ---------------------------------------------------------------------------
# Scenario 7: --log-dir 未指定時 → log_age=999 で event 抑制しない（他指標が有効なら evaluate 継続）
# ---------------------------------------------------------------------------
@test "log-dir 未指定: log_age=999 でも MENU-READY は emit される（log_age 条件を満たす）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-nolog-win"

capture="❯ 1. Option A
Enter to select · ↑/↓ to navigate · Esc to cancel"

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        *) return 0;;
    esac
}
export -f tmux

# log-dir 未指定 → log_age=999 → 30s 条件を満たすのでMENU-READY emit
_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "MENU-READY"
}

# ---------------------------------------------------------------------------
# Scenario 8: --notify-dir パススルー（cld-observe-loop wrapper 経由）
# ---------------------------------------------------------------------------
@test "cld-observe-loop wrapper: --notify-dir が cld-observe-any に透過転送される" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_LOOP="$SCRIPT_DIR/cld-observe-loop"
TMPD="$(mktemp -d)"
NOTIFY="$TMPD/notifications"
mkdir -p "$NOTIFY"

# NOTIFY ディレクトリに attention JSON を配置
cat > "$NOTIFY/ap-notify-win:abc123.json" <<'JSON'
{"state": "attention", "seen": false, "session_id": "test-123"}
JSON

win="ap-notify-win"

tmux() {
    case "$1" in
        list-windows)
            if [[ "${*}" == *"-F #{window_name}"* ]] || [[ "${*}" == *"-a"* ]]; then
                echo "$win"
            else
                echo "test-session:0 $win"
            fi;;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else echo "Processing..."; fi;;
        list-sessions) echo "test-session";;
        list-panes) echo "claude	0	%0	/home/test";;
        *) return 0;;
    esac
}
export -f tmux

# max-cycles=1 で1サイクルのみ実行
_TEST_MODE=1 CLD_OBSERVE_LOOP_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_LOOP" "$win" --max-cycles 1 \
    --notify-dir "$NOTIFY" --interval 1 2>/dev/null || true

rm -rf "$TMPD"
echo "wrapper executed"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "wrapper executed"
}

# ---------------------------------------------------------------------------
# Scenario 9: 複数 window 同時監視 - 逐次 polling が全 window を evaluate
# ---------------------------------------------------------------------------
@test "複数 window: --pattern で 2 window を評価し各々にイベントを発火" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"

capture_dead="(exited)"
capture_menu="❯ 1. Opt
Enter to select · Esc to cancel"

tmux() {
    case "$1" in
        list-windows)
            if [[ "${*}" == *"-a -F #{window_name}"* ]] || [[ "${*}" == *"-a"* ]]; then
                printf "ap-win-dead\nap-win-menu\n"
                return
            fi
            # display-message target で分岐
            case "${2:-}" in
                *ap-win-dead*) echo "test-session:0 ap-win-dead";;
                *ap-win-menu*) echo "test-session:1 ap-win-menu";;
                *) printf "test-session:0 ap-win-dead\ntest-session:1 ap-win-menu\n";;
            esac;;
        display-message)
            local t="${@: -1}"
            if echo "$t" | grep -q "dead"; then echo "1 bash"
            else echo "0 claude"; fi;;
        capture-pane)
            if [[ "${*}" == *"dead"* ]]; then echo "";
            elif [[ "${*}" == *"-S -1"* ]]; then echo "";
            else printf '%s\n' "$capture_menu"; fi;;
        *) return 0;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" \
    --window "ap-win-dead" --window "ap-win-menu" \
    --once 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    # PANE-DEAD が含まれること
    echo "$output" | grep -q "PANE-DEAD"
}
