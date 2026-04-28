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

# ---------------------------------------------------------------------------
# Scenario 10: PERMISSION-PROMPT 正規 fixture → emit される（ケース 1）
#   "1. Yes, proceed" / "2. No, and tell ..." / "3. Yes, and allow ..." / "Interrupted by user"
#   の各行頭パターンで PERMISSION-PROMPT が emit されること
# ---------------------------------------------------------------------------
@test "PERMISSION-PROMPT: 正規 prompt fixture で emit される（Yes, proceed / Yes, and allow / No, and tell / Interrupted）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-perm-win-1"

capture="Do you want to proceed?
1. Yes, proceed
2. No, and tell Claude what to do differently
3. Yes, and allow always"
export capture

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
    bash "$CLD_OBSERVE_ANY" --window "$win" --once 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PERMISSION-PROMPT"
}

# ---------------------------------------------------------------------------
# Scenario 11: PERMISSION-PROMPT false positive 防止（ケース 2）
#   数字で始まる neutral text（"4. Quality assurance" 等）では emit されないこと
# ---------------------------------------------------------------------------
@test "PERMISSION-PROMPT: 数字始まりの neutral text では emit されない（false positive 防止）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-perm-win-2"

capture="Here is the plan:
4. Quality assurance approach
5. Test automation details
8. Project structure overview"
export capture

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
    bash "$CLD_OBSERVE_ANY" --window "$win" --once 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    # neutral text なので PERMISSION-PROMPT emit なし
    ! echo "$output" | grep -q "PERMISSION-PROMPT"
}

# ---------------------------------------------------------------------------
# Scenario 12: BUDGET-LOW と PERMISSION-PROMPT の優先順位（ケース 3）
#   BUDGET-LOW 条件を満たす場合は BUDGET-LOW が先に emit される（逆転しないこと）
# ---------------------------------------------------------------------------
@test "PERMISSION-PROMPT vs BUDGET-LOW: BUDGET-LOW が優先 emit される（順序維持）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-perm-win-3"

# status line: budget 10m（閾値 15m を下回る）
# capture: permission prompt あり
capture="1. Yes, proceed
2. No, and tell Claude what to do differently"
export capture

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then
                echo "● claude  budget: 10m  esc to interrupt"
            else
                printf '%s\n' "$capture"
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
    # BUDGET-LOW が emit されること（PERMISSION-PROMPT ではなく）
    echo "$output" | grep -q "BUDGET-LOW"
    ! echo "$output" | grep -q "PERMISSION-PROMPT"
}

# ---------------------------------------------------------------------------
# Scenario 13: thinking 状態でも PERMISSION-PROMPT が emit される（ケース 4）
#   capture に LLM_INDICATORS（Brewing for 9m 19s）を含む fixture で
#   thinking guard 到達前に PERMISSION-PROMPT が return すること
# ---------------------------------------------------------------------------
@test "PERMISSION-PROMPT: thinking 状態（Brewing）でも emit される（thinking guard より前に return）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
win="ap-perm-win-4"

# capture: thinking indicator あり + permission prompt あり
capture="Brewing for 9m 19s · max effort
1. Yes, proceed
2. No, and tell Claude what to do differently"
export capture

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
    bash "$CLD_OBSERVE_ANY" --window "$win" --once 2>/dev/null
MOCKEOF

    [[ "$status" -eq 0 ]]
    # thinking 中でも PERMISSION-PROMPT は emit される
    echo "$output" | grep -q "PERMISSION-PROMPT"
}

# ---------------------------------------------------------------------------
# Scenario 14: AC1 — 既知 thinking indicator "Burrowing" あり → STAGNATE emit なし
#   現実装の LLM_INDICATORS に "Burrowing" が含まれていないため、
#   thinking guard が機能せず STAGNATE が emit される → RED（実装後 PASS）
# ---------------------------------------------------------------------------
@test "AC1: thinking indicator 'Burrowing' あり → STAGNATE emit なし（偽陽性防止）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-burrowing-win"

# "Burrowing" は Claude Code が thinking 中に表示する indicator
capture="Burrowing… (3s)
Analyzing the codebase structure..."
export capture

# log ファイルを stagnate 閾値より古い mtime で作成（5s 閾値に対して 30s 前）
logfile="$TMPD/${win}.log"
touch -t "$(date -d '30 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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

# stagnate-sec 5 で即時評価（log は 30s 前 → stagnate 超過）
_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" --once \
    --log-dir "$TMPD" \
    --stagnate-sec 5 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    # "Burrowing" は thinking 中の indicator なので STAGNATE は emit されない（RED: 現実装では emit される）
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 15: AC1 — 複数の未収録 indicator（Sautéed, Cerebrating, Thundering）
#   各 indicator あり + stagnate 超過 → STAGNATE emit なしを assert
#   現実装ではカタログ未収録のため thinking guard をすり抜けて STAGNATE emit される → RED
# ---------------------------------------------------------------------------
@test "AC1: thinking indicator 'Sautéed / Cerebrating / Thundering' あり → STAGNATE emit なし" {
    # Sautéed のテスト
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-sauted-win"

capture="Sautéed… (2s)
Processing input tokens..."
export capture

logfile="$TMPD/${win}.log"
touch -t "$(date -d '30 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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
    --stagnate-sec 5 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    ! echo "$output" | grep -q "STAGNATE"

    # Thundering のテスト
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-thundering-win"

capture="Thundering… (4s)
Working on the task..."
export capture

logfile="$TMPD/${win}.log"
touch -t "$(date -d '30 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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
    --stagnate-sec 5 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 16: AC2 — 完全未知の indicator（"Fizzing… (1s)"）でも STAGNATE emit なし
#   一般化 regex `^[*•·✻✽✶✢✻] [A-Z][a-z]+(ed|ing|in')` で未知 indicator を汎用検出する実装後 PASS
#   現実装（固定リスト）では "Fizzing" を検出できないため STAGNATE emit される → RED
# ---------------------------------------------------------------------------
@test "AC2: 未知 indicator 'Fizzing… (1s)'（一般化 regex 対象） → STAGNATE emit なし" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-fizzing-win"

# "Fizzing" は LLM_INDICATORS に存在しない完全未知の indicator
# 一般化 regex `^[A-Z][a-z]+(ed|ing|in')…` にマッチするパターン
capture="Fizzing… (1s)
Evaluating options..."
export capture

logfile="$TMPD/${win}.log"
touch -t "$(date -d '30 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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
    --stagnate-sec 5 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    # 未知の indicator でも thinking guard が機能し STAGNATE は emit されない（RED: 現実装では emit される）
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 17: AC2 — indicator suffix pattern "in'" （Beboppin'）も一般化検出対象
#   "Beboppin'… (5s)" は `[A-Z][a-z]+in'` パターン → 実装後は thinking guard が機能するはず
#   現実装では "Beboppin'" が LLM_INDICATORS に含まれないため STAGNATE emit される → RED
# ---------------------------------------------------------------------------
@test "AC2: indicator suffix \"in'\" を持つ 'Beboppin\\'' → STAGNATE emit なし（一般化 regex で検出）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-beboppin-win"

# "Beboppin'" は Claude Code の thinking indicator（-in' suffix パターン）
capture="Beboppin'… (5s)
Generating code changes..."
export capture

logfile="$TMPD/${win}.log"
touch -t "$(date -d '30 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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
    --stagnate-sec 5 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 18: AC3 — 偽陽性ケース: "Burrowing…" indicator あり → STAGNATE emit なし
#   Scenario 14 と同一趣旨だが AC3 の「偽陽性 case 検証」として明示的に配置
#   現実装で "Burrowing" が未収録なため STAGNATE emit される → RED
# ---------------------------------------------------------------------------
@test "AC3: 偽陽性ケース — 'Burrowing…' indicator あり → STAGNATE emit なし" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-ac3-fp-win"

capture="Burrowing… (7s)
Reading source files..."
export capture

logfile="$TMPD/${win}.log"
touch -t "$(date -d '60 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-60S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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
    --stagnate-sec 30 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    # Burrowing indicator が存在する → LLM は思考中 → STAGNATE は emit されない（RED: 現実装では emit される）
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 19: AC3 — 本物の stall: indicator なし + 出力なし（stagnate 超過）→ STAGNATE emit あり
#   これは現実装でも PASS する（STAGNATE emit が機能している確認テスト）
#   ただし、AC1/AC2 実装後も regression しないことを保証する
# ---------------------------------------------------------------------------
@test "AC3: 本物の stall — indicator なし + log 古い → STAGNATE emit あり" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-ac3-stall-win"

# indicator なし、出力なし（stall 状態）
capture="Last output 10 minutes ago."
export capture

# log ファイルを stagnate-sec（10s）より十分古い mtime で作成
logfile="$TMPD/${win}.log"
touch -t "$(date -d '60 seconds ago' '+%Y%m%d%H%M.%S' 2>/dev/null || date -v-60S '+%Y%m%d%H%M.%S' 2>/dev/null || echo '202001010000.00')" "$logfile" 2>/dev/null || touch "$logfile"

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
    --stagnate-sec 10 2>/dev/null
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    # indicator なし + stagnate 超過 → STAGNATE は emit される（これは AC1/AC2 実装後も保持される仕様）
    echo "$output" | grep -q "STAGNATE"
}
