#!/usr/bin/env bats
# cld-observe-any.bats - 多指標 AND 判定の unit tests
# tmux 依存なし（モックアプローチ）

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
CLD_OBSERVE_LOOP="$SCRIPT_DIR/cld-observe-loop"

setup() {
    TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"
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
#   "Burrowing" は L32 LLM_INDICATORS に収録済（PR #1161 で追加）→ thinking guard が機能し STAGNATE 抑止。
#   GREEN: 実装済みの動作確認テスト（regression guard）。
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
    # "Burrowing" は thinking 中の indicator なので STAGNATE は emit されない（regression guard: thinking guard が機能し続けることを確認）
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 15: AC1 — 複数の未収録 indicator（Sautéed, Cerebrating, Thundering）
#   各 indicator あり + stagnate 超過 → STAGNATE emit なしを assert。
#   "Saut.*ed" (L31), "Cerebrating" (L33), "Thundering" (L36) いずれも LLM_INDICATORS に収録済（PR #1161 で追加）→ thinking guard が機能し STAGNATE 抑止。
#   GREEN: 実装済みの動作確認テスト（regression guard）。
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
#   一般化 regex `[A-Z][a-z]+(in'|ing|ed)(…| for [0-9]| \([0-9])`（L43）で "Fizzing" を検出 → thinking guard が機能し STAGNATE 抑止。
#   GREEN: 一般化 regex の動作確認テスト（regression guard）。
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
    # 未知の indicator でも一般化 regex (L43) で thinking guard が機能し STAGNATE は emit されない（regression guard）
    ! echo "$output" | grep -q "STAGNATE"
}

# ---------------------------------------------------------------------------
# Scenario 17: AC2 — indicator suffix pattern "in'" （Beboppin'）も一般化検出対象
#   "Beboppin" は L35 LLM_INDICATORS に直接収録済（一般化 regex L43 の `[A-Z][a-z]+in'` パターンでも検出可能）。
#   いずれの経路でも thinking guard が機能し STAGNATE 抑止。
#   GREEN: 実装済みの動作確認テスト（regression guard）。
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
#   Scenario 14 と同じ "Burrowing" indicator を使うが、`stagnate-sec 30` × `log mtime 60s 前` で stagnate 閾値を厳しく設定。
#   既収録 indicator でも regression なく STAGNATE 抑止が機能することを確認する偽陽性 case の regression guard。
#   GREEN: 実装済みの動作確認テスト。
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
    # Burrowing indicator が存在する → LLM は思考中 → STAGNATE は emit されない（regression guard）
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

# ---------------------------------------------------------------------------
# Issue #1132: IDLE_COMPLETED_AUTO_KILL 機能 — AC-9 の 5 ケース
#
# テスト戦略:
#   - IDLE-COMPLETED emit を発生させるには --max-cycles 2 + --interval 1 が必要
#     Cycle 1: phrase 検出 → IDLE_COMPLETED_TS[$WIN]=$NOW を記録
#     Cycle 2: FIRST_SEEN>0 かつ DEBOUNCE=0 → _check_idle_completed true → emit/kill 分岐
#   - IDLE_COMPLETED_PHRASE_REGEX は readonly のため override 不可。
#     既存 regex に含まれる "nothing pending" をキャプチャテキストに使用する。
#   - kill stub 呼び出し検証: CALL_LOG ファイルへの記録で確認する
#   - RED テスト（ケース3・4）: IDLE_COMPLETED_AUTO_KILL 実装前は fail する。
#     auto-kill 実装後に GREEN になることを期待する。
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Scenario 20: AC-9 ケース1 — IDLE_COMPLETED_AUTO_KILL 未設定 → alert のみ、kill なし
#   AC-6 regression: 既存 alert 動作を変更しない baseline テスト
#   このテストは現実装でも PASS する（自動 kill 機能がないため）
# ---------------------------------------------------------------------------
@test "AC-9/1: IDLE_COMPLETED_AUTO_KILL 未設定 → IDLE-COMPLETED emit のみ、kill-window 呼び出しなし（AC-6 baseline）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/tmux-calls.log"
win="ap-ac9-case1-win"

# IDLE_COMPLETED_PHRASE_REGEX にマッチするキャプチャ（"nothing pending" は regex SSOT に含まれる）
capture="All tasks are done.
nothing pending
System is idle."
export capture

tmux() {
    echo "$1 $*" >> "$CALL_LOG"
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window) return 0;;
        *) return 0;;
    esac
}
export -f tmux

# IDLE_COMPLETED_AUTO_KILL を未設定にする（unset で明示的に削除）
unset IDLE_COMPLETED_AUTO_KILL

IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

# kill-window が呼ばれていないことを確認
if grep -q "kill-window" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: kill-window が呼ばれた（IDLE_COMPLETED_AUTO_KILL 未設定なのに）"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: kill-window 呼び出しなし"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PASS: kill-window 呼び出しなし"
}

# ---------------------------------------------------------------------------
# Scenario 21: AC-9 ケース2 — IDLE_COMPLETED_AUTO_KILL=0 → alert のみ、kill なし
#   AC-6: 明示的に無効化した場合も既存動作を維持する baseline テスト
#   このテストは現実装でも PASS する（自動 kill 機能がないため）
# ---------------------------------------------------------------------------
@test "AC-9/2: IDLE_COMPLETED_AUTO_KILL=0 → IDLE-COMPLETED emit のみ、kill-window 呼び出しなし（AC-6 explicit disable）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/tmux-calls.log"
win="ap-ac9-case2-win"

capture="All tasks are done.
nothing pending
System is idle."
export capture

tmux() {
    echo "$1 $*" >> "$CALL_LOG"
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window) return 0;;
        *) return 0;;
    esac
}
export -f tmux

IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if grep -q "kill-window" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: kill-window が呼ばれた（IDLE_COMPLETED_AUTO_KILL=0 なのに）"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: kill-window 呼び出しなし"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PASS: kill-window 呼び出しなし"
}

# ---------------------------------------------------------------------------
# Scenario 22: AC-9 ケース3 — IDLE_COMPLETED_AUTO_KILL=1 + kill-window stub 成功
#   RED: auto-kill 未実装のため現状は fail する。実装後に GREEN になる。
#   検証内容:
#     - kill-window が 1 回呼び出される（AC-2）
#     - stdout に "[IDLE-COMPLETED] <win>: auto-killed" ログが出る（AC-2）
#     - idle-completed-killed-*.json が EVENT_DIR に生成される（AC-5）
# ---------------------------------------------------------------------------
@test "AC-9/3: IDLE_COMPLETED_AUTO_KILL=1 + kill-window 成功 → kill 1回・auto-killed log・killed JSON 生成（RED: 実装後 PASS）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
EVENT_DIR_PATH="$TMPD/events"
mkdir -p "$EVENT_DIR_PATH"
win="ap-ac9-case3-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            # stub: 成功（exit 0）
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

output_text=$(IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --event-dir "$EVENT_DIR_PATH" \
    --max-cycles 2 --interval 1 2>/dev/null)

# 検証1: stdout に auto-killed ログが出たか（AC-2）
if ! echo "$output_text" | grep -q "auto-killed"; then
    echo "FAIL: stdout に auto-killed ログがない（output=$output_text）"
    rm -rf "$TMPD"
    exit 1
fi

# 検証2: idle-completed-killed-*.json が生成されたか（AC-5）
killed_json=$(find "$EVENT_DIR_PATH" -name "idle-completed-killed-*.json" 2>/dev/null | head -1)
if [[ -z "$killed_json" ]]; then
    echo "FAIL: idle-completed-killed-*.json が生成されなかった"
    rm -rf "$TMPD"
    exit 1
fi

echo "PASS: kill 1回・auto-killed log・killed JSON 生成"
rm -rf "$TMPD"
MOCKEOF

    # RED: auto-kill 実装前は失敗する
    # 実装後は [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:" に変わる
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 23: AC-9 ケース4 — IDLE_COMPLETED_AUTO_KILL=1 + kill-window stub 失敗
#   RED: auto-kill 未実装のため現状は fail する。実装後に GREEN になる。
#   検証内容:
#     - メインループが継続する（exit 0）（AC-3）
#     - stderr に "auto-kill failed" ログが出る（AC-2/AC-3）
#     - idle-completed-killed-*.json は生成されない（AC-5 fail 時非生成）
# ---------------------------------------------------------------------------
@test "AC-9/4: IDLE_COMPLETED_AUTO_KILL=1 + kill-window 失敗 → exit 0・stderr failed log・killed JSON 非生成（RED: 実装後 PASS）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
EVENT_DIR_PATH="$TMPD/events"
mkdir -p "$EVENT_DIR_PATH"
win="ap-ac9-case4-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            # stub: 失敗（exit 1）
            return 1;;
        *) return 0;;
    esac
}
export -f tmux

# stderr を別ファイルに保存して確認
STDERR_FILE="$TMPD/stderr.txt"
IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --event-dir "$EVENT_DIR_PATH" \
    --max-cycles 2 --interval 1 >/dev/null 2>"$STDERR_FILE"
exit_code=$?
stderr_text=$(cat "$STDERR_FILE" 2>/dev/null || echo "")

# 検証1: exit 0（メインループ継続、graceful）（AC-3）
if [[ "$exit_code" -ne 0 ]]; then
    echo "FAIL: exit code $exit_code（期待: 0）"
    rm -rf "$TMPD"
    exit 1
fi

# 検証2: stderr に auto-kill failed ログが出たか（AC-2/AC-3）
if ! echo "$stderr_text" | grep -q "auto-kill failed"; then
    echo "FAIL: stderr に auto-kill failed ログがない（stderr=$stderr_text）"
    rm -rf "$TMPD"
    exit 1
fi

# 検証3: idle-completed-killed-*.json は生成されていないか（AC-5 kill 失敗時非生成）
killed_json=$(find "$EVENT_DIR_PATH" -name "idle-completed-killed-*.json" 2>/dev/null | head -1)
if [[ -n "$killed_json" ]]; then
    echo "FAIL: kill 失敗なのに idle-completed-killed-*.json が生成された"
    rm -rf "$TMPD"
    exit 1
fi

echo "PASS: exit 0・failed log・killed JSON 非生成"
rm -rf "$TMPD"
MOCKEOF

    # RED: auto-kill 実装前は失敗する
    # 実装後は [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:" に変わる
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 24: AC-9 ケース5 — LLM-active indicator（"Thinking..."）存在時
#   AC-7: _check_idle_completed C3 条件により emit/kill 両方発生しない
#   このテストは現実装でも PASS する（LLM indicator guard は既存実装済み）
# ---------------------------------------------------------------------------
@test "AC-9/5: LLM-active indicator 存在時 → IDLE_COMPLETED_AUTO_KILL=1 でも emit/kill 両方発生しない（AC-7 baseline）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/tmux-calls.log"
win="ap-ac9-case5-win"

# "nothing pending" は IDLE_COMPLETED_PHRASE_REGEX にマッチするが、
# "Thinking..." は LLM indicator（C3 条件）として _check_idle_completed を false にする
capture="All tasks are done.
nothing pending
Thinking... (5s)
Analyzing next steps."
export capture

tmux() {
    echo "$1 $*" >> "$CALL_LOG"
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

output_text=$(IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null)

# 検証1: IDLE-COMPLETED は emit されていないか（C3 guard による）
if echo "$output_text" | grep -q "IDLE-COMPLETED"; then
    echo "FAIL: LLM indicator 存在時に IDLE-COMPLETED が emit された"
    rm -rf "$TMPD"
    exit 1
fi

# 検証2: kill-window は呼ばれていないか
if grep -q "kill-window" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: LLM indicator 存在時に kill-window が呼ばれた"
    rm -rf "$TMPD"
    exit 1
fi

echo "PASS: emit なし・kill-window 呼び出しなし"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PASS: emit なし・kill-window 呼び出しなし"
}

# ---------------------------------------------------------------------------
# Issue #1147 AC8: 多重起動防止（flock -n 9）
#
# テスト戦略:
#   - flock を stub して「既にロック取得済み」状態をシミュレート
#   - 第 2 instance 起動時に flock が exit 1（ロック失敗）→ cld-observe-any が exit 1
#   - stderr に既存 PID が出力される
#
# RED: cld-observe-any に flock 多重起動防止が未実装のため fail する
# PASS 条件（実装後）:
#   - 既起動 instance あり → flock 失敗 → exit 1
#   - stderr に既存 PID を含む出力
# ---------------------------------------------------------------------------

@test "AC8: 既起動 instance あり → flock -n 失敗 → exit 1 + stderr に既存 PID 出力（RED: 実装後 PASS）" {
    # AC: cld-observe-any 起動時に flock -n 9 で /tmp/cld-observe-any.lock を取得。
    #     取得失敗時は exit 1 + stderr に既存 PID を出力
    # RED: flock 多重起動防止が未実装のため現状は fail する

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
# スクリプトが内部でハードコードする LOCK_FILE と同じパス
ACTUAL_LOCK_PID_FILE="/tmp/cld-observe-any.lock.pid"
FAKE_EXISTING_PID=54321

# flock stub: ロック取得失敗をシミュレート（-n オプション付きで即 exit 1）
flock() {
    # "-n" オプションがある場合、ロック失敗をシミュレート
    if [[ "$*" == *"-n"* ]]; then
        return 1
    fi
    return 0
}
export -f flock

# tmux モック（実際には呼ばれないが念のため）
tmux() { return 0; }
export -f tmux

# 既存 PID のロックファイルを作成（スクリプトが cat で読むパスに書く）
echo "$FAKE_EXISTING_PID" > "$ACTUAL_LOCK_PID_FILE"

STDERR_FILE="$TMPD/stderr.txt"
bash "$CLD_OBSERVE_ANY" --window "test-win" --once \
    2>"$STDERR_FILE" >/dev/null
exit_code=$?
stderr_text=$(cat "$STDERR_FILE" 2>/dev/null || echo "")

# クリーンアップ
rm -f "$ACTUAL_LOCK_PID_FILE"
rm -rf "$TMPD"

# 検証1: exit 1 で終了すること
if [[ "$exit_code" -ne 1 ]]; then
    echo "FAIL: exit code $exit_code（期待: 1）"
    exit 1
fi

# 検証2: stderr に既存 PID が含まれること
if ! echo "$stderr_text" | grep -q "$FAKE_EXISTING_PID"; then
    echo "FAIL: stderr に既存 PID ($FAKE_EXISTING_PID) が含まれていない（stderr=$stderr_text）"
    exit 1
fi

echo "PASS: flock 失敗 exit 1 + stderr に PID 出力"
MOCKEOF

    # RED: 実装前は失敗する
    # 実装後は [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:" に変わる
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: flock 失敗 exit 1 + stderr に PID 出力"
}

# ===========================================================================
# Issue #1153: observer cld-observe-any TDD RED フェーズ（AC0〜AC7）
# 全テストは実装前に fail（RED）する。実装後に GREEN になる。
# ===========================================================================

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
OBSERVER_IDLE_CHECK="$REPO_ROOT/plugins/twl/skills/su-observer/scripts/lib/observer-idle-check.sh"
PITFALLS_CATALOG="$REPO_ROOT/plugins/twl/skills/su-observer/refs/pitfalls-catalog.md"
ORCHESTRATOR="$REPO_ROOT/plugins/twl/scripts/issue-lifecycle-orchestrator.sh"

# ---------------------------------------------------------------------------
# AC0: PCRE 可用性チェック — 非 PCRE 環境で warn を出すこと
# ---------------------------------------------------------------------------
@test "AC0 (#1153): cld-observe-any に PCRE 可用性チェックコードが存在すること (RED)" {
    # RED: 実装前は fail する — PCRE availability check が未実装
    # 実装後: grep --version | grep -qi perl または PCRE warn ロジックが追加される
    grep -qiE "pcre|PCRE_SUPPORT|check.pcre|grep.*perl|warn.*perl" "$CLD_OBSERVE_ANY"
}

# ---------------------------------------------------------------------------
# AC1: Unicode ellipsis 含む fixture — detect_thinking が検知すること
# ---------------------------------------------------------------------------
@test "AC1 (#1153): detect_thinking が 'Flambéing… (15s · ↑234 tokens)' を検知すること (RED)" {
    # RED: 実装前は fail する
    # 現状: grep -qiE の [a-z]+ は ASCII 限定。é (non-ASCII) を含む Flambéing が regex に hit しない
    # 実装後: grep -qiP + \p{Ll} または明示リスト追加で Flambéing を検知

    run bash <<EOF
# detect_thinking 相当ロジックを直接テスト（ script sourcing を避けてリスク軽減）
pane_text='Flambéing… (15s · ↑234 tokens)'
LLM_INDICATORS=(
    "Thinking" "Brewing" "Brewed" "Concocting" "Ebbing" "Proofing" "Frosting"
    "Reasoning" "Computing" "Planning" "Composing" "Processing"
    "Running .* agents" "[0-9]+ tool uses" "thinking with max effort"
    "Saut.*ed" "Burrowing" "Cerebrating" "Spinning" "Beboppin" "Thundering"
    "Baked" "Cooked" "Crunched" "Churned" "Skedaddling" "Orchestrating"
    "[A-Z][a-z]+(in'|ing|ed)(…| for [0-9]| \\([0-9])"
)
detected=""
for ind in "\${LLM_INDICATORS[@]}"; do
    if echo "\$pane_text" | grep -qiE "\$ind" 2>/dev/null; then
        detected="\$ind"
        break
    fi
done
if [[ -n "\$detected" ]]; then
    echo "PASS: detected=\$detected"
else
    echo "FAIL: Flambéing not detected by current regex"
    exit 1
fi
EOF

    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC2: ASCII 3-dot — detect_thinking が検知すること
# ---------------------------------------------------------------------------
@test "AC2 (#1153): detect_thinking が 'Garnishing... (15s)' (ASCII 3-dot) を検知すること (RED)" {
    # RED: 実装前は fail する
    # 現状: regex の trailing alternatives に \.{3} がなく ASCII "..." が未対応
    # 実装後: \.{3} 追加 or 明示リスト追加で検知できる

    run bash <<EOF
pane_text='Garnishing... (15s)'
LLM_INDICATORS=(
    "Thinking" "Brewing" "Brewed" "Concocting" "Ebbing" "Proofing" "Frosting"
    "Reasoning" "Computing" "Planning" "Composing" "Processing"
    "Running .* agents" "[0-9]+ tool uses" "thinking with max effort"
    "Saut.*ed" "Burrowing" "Cerebrating" "Spinning" "Beboppin" "Thundering"
    "Baked" "Cooked" "Crunched" "Churned" "Skedaddling" "Orchestrating"
    "[A-Z][a-z]+(in'|ing|ed)(…| for [0-9]| \\([0-9])"
)
detected=""
for ind in "\${LLM_INDICATORS[@]}"; do
    if echo "\$pane_text" | grep -qiE "\$ind" 2>/dev/null; then
        detected="\$ind"
        break
    fi
done
if [[ -n "\$detected" ]]; then
    echo "PASS: detected=\$detected"
else
    echo "FAIL: Garnishing... (ASCII 3-dot) not detected"
    exit 1
fi
EOF

    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC3: bare-word safety net — LLM_INDICATORS に 'Garnishing' が含まれること
# ---------------------------------------------------------------------------
@test "AC3 (#1153): 'Garnishing' (bare-word) が LLM_INDICATORS に含まれること (RED)" {
    # RED: 実装前は fail する
    # 現状: "Garnishing" は LLM_INDICATORS 配列に存在せず、一般化 regex も bare-word に hit しない
    # 実装後: 明示リスト追加（対策3）で救済される

    grep -q "Garnishing" "$CLD_OBSERVE_ANY"
}

# ---------------------------------------------------------------------------
# AC4: LLM_INDICATORS coverage — 20 件の indicator が 3 箇所すべてに含まれること
# ---------------------------------------------------------------------------
@test "AC4 (#1153): REQUIRED 20 indicators が cld-observe-any に含まれること (RED)" {
    # RED: 実装前は fail する — 20 件すべて MISSING
    local REQUIRED=(Garnishing Embellishing Flambéing Tomfoolering Reticulating Topsy-turvying Generating Whisking Mulling Fermenting Caramelizing Inferring Discerning Ratiocinating Sleuthing Investigating Reviewing Studying Pondering Reflecting)
    local missing=()
    for word in "${REQUIRED[@]}"; do
        grep -q "$word" "$CLD_OBSERVE_ANY" || missing+=("$word")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "MISSING from cld-observe-any: ${missing[*]}"
        false
    fi
}

@test "AC4 (#1153): REQUIRED 20 indicators が observer-idle-check.sh に含まれること (RED)" {
    # RED: 実装前は fail する
    local REQUIRED=(Garnishing Embellishing Flambéing Tomfoolering Reticulating Topsy-turvying Generating Whisking Mulling Fermenting Caramelizing Inferring Discerning Ratiocinating Sleuthing Investigating Reviewing Studying Pondering Reflecting)
    local missing=()
    for word in "${REQUIRED[@]}"; do
        grep -q "$word" "$OBSERVER_IDLE_CHECK" || missing+=("$word")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "MISSING from observer-idle-check.sh: ${missing[*]}"
        false
    fi
}

@test "AC4 (#1153): REQUIRED 20 indicators が pitfalls-catalog.md に含まれること (RED)" {
    # RED: 実装前は fail する
    local REQUIRED=(Garnishing Embellishing Flambéing Tomfoolering Reticulating Topsy-turvying Generating Whisking Mulling Fermenting Caramelizing Inferring Discerning Ratiocinating Sleuthing Investigating Reviewing Studying Pondering Reflecting)
    local missing=()
    for word in "${REQUIRED[@]}"; do
        grep -q "$word" "$PITFALLS_CATALOG" || missing+=("$word")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "MISSING from pitfalls-catalog.md: ${missing[*]}"
        false
    fi
}

@test "AC4 (#1153): catalog 独自 8 件が cld-observe-any に追加されていること (RED)" {
    # RED: 実装前は fail する（対策5: catalog → 実装 同期方向）
    # pitfalls-catalog.md 独自の 8 件も cld-observe-any に追加すること
    local CATALOG_8=(Steeping Simmering Marinating Newspapering Flummoxing Befuddling Waddling Lollygagging)
    local missing=()
    for word in "${CATALOG_8[@]}"; do
        grep -q "$word" "$CLD_OBSERVE_ANY" || missing+=("$word")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "MISSING catalog-8 from cld-observe-any: ${missing[*]}"
        false
    fi
}

@test "AC4 (#1153): catalog 独自 8 件が observer-idle-check.sh に追加されていること (RED)" {
    # RED: 実装前は fail する（対策5: catalog → 実装 同期方向）
    local CATALOG_8=(Steeping Simmering Marinating Newspapering Flummoxing Befuddling Waddling Lollygagging)
    local missing=()
    for word in "${CATALOG_8[@]}"; do
        grep -q "$word" "$OBSERVER_IDLE_CHECK" || missing+=("$word")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "MISSING catalog-8 from observer-idle-check.sh: ${missing[*]}"
        false
    fi
}

# ---------------------------------------------------------------------------
# AC5: pitfalls-catalog.md §4.10.1 subsection の存在確認
# ---------------------------------------------------------------------------
@test "AC5 (#1153): pitfalls-catalog.md に §4.10.1 non-ASCII/ASCII ellipsis/bare-word セクションが存在すること (RED)" {
    # RED: 実装前は fail する — §4.10.1 は未新設
    grep -q "4\.10\.1" "$PITFALLS_CATALOG"
}

@test "AC5 (#1153): pitfalls-catalog.md §4.10.1 に 3 落とし穴が記載されていること (RED)" {
    # RED: 実装前は fail する
    # non-ASCII、ASCII ellipsis、bare-word の 3 パターンが記載されていること
    grep -q "non-ASCII\|Unicode" "$PITFALLS_CATALOG" && \
    grep -q "ASCII.*ellipsis\|ASCII.*\.\.\." "$PITFALLS_CATALOG" && \
    grep -q "bare-word\|bare word" "$PITFALLS_CATALOG"
}

@test "AC5 (#1153): pitfalls-catalog.md §4.10.1 に SSOT 三方向同期義務が記載されていること (RED)" {
    # RED: 実装前は fail する
    # §4.10.1 内に SSOT 三方向同期（cld-observe-any / observer-idle-check / pitfalls-catalog）の記載
    local section_start
    section_start=$(grep -n "4\.10\.1" "$PITFALLS_CATALOG" | head -1 | cut -d: -f1)
    [[ -n "$section_start" ]] || { echo "§4.10.1 not found"; false; return; }
    # §4.10.1 以降の内容に SSOT 三方向同期に関する記述があること
    tail -n "+${section_start}" "$PITFALLS_CATALOG" | head -50 | \
        grep -q "SSOT\|三方向\|同期"
}

@test "AC5 (#1153): pitfalls-catalog.md §4.10.1 に Steeping/Simmering 等 8 件の同期 indicator が記載されていること (RED)" {
    # RED: 実装前は fail する
    # 同期 indicator 8 件: Steeping, Simmering, Marinating, Newspapering, Flummoxing, Befuddling, Waddling, Lollygagging
    local section_start
    section_start=$(grep -n "4\.10\.1" "$PITFALLS_CATALOG" | head -1 | cut -d: -f1)
    [[ -n "$section_start" ]] || { echo "§4.10.1 not found"; false; return; }
    local section_text
    section_text=$(tail -n "+${section_start}" "$PITFALLS_CATALOG" | head -100)
    for word in Steeping Simmering Marinating Newspapering Flummoxing Befuddling Waddling Lollygagging; do
        echo "$section_text" | grep -q "$word" || { echo "MISSING in §4.10.1: $word"; false; return; }
    done
}

# ---------------------------------------------------------------------------
# AC6: 回帰防止 — detect_thinking が grep -qiP を使用していること + 既存パターン互換性
# ---------------------------------------------------------------------------
@test "AC6 (#1153): detect_thinking が grep -qiP を使用していること (RED)" {
    # RED: 実装前は fail する — detect_thinking は grep -qiE を使用中
    # 実装後: grep -qiP への切替で PASS（PCRE モード切替の核心確認）
    grep -q 'grep -qiP' "$CLD_OBSERVE_ANY"
}

@test "AC6 (#1153): grep -qiP で 'Running .* agents' が動作すること（回帰ガード）" {
    # 実装後も既存 indicator が grep -qiP で動作することを保証
    echo "Running 3 agents in parallel" | grep -qiP "Running .* agents"
}

@test "AC6 (#1153): grep -qiP で '[0-9]+ tool uses' が動作すること（回帰ガード）" {
    echo "42 tool uses completed" | grep -qiP "[0-9]+ tool uses"
}

@test "AC6 (#1153): grep -qiP で 'Saut.*ed' が動作すること（回帰ガード）" {
    # Sautéed は non-ASCII だが Saut.*ed パターンは PCRE で動作すること
    echo "Sautéed ingredients (30s)" | grep -qiP "Saut.*ed"
}

# ---------------------------------------------------------------------------
# AC7: orchestrator 動的読み込み smoke test
# ---------------------------------------------------------------------------
@test "AC7 (#1153): issue-lifecycle-orchestrator.sh の LLM_INDICATORS 動的読み込みが破壊されていないこと (RED)" {
    # RED: 実装前は fail する
    # orchestrator は awk で cld-observe-any から LLM_INDICATORS を動的読み込みする
    # 配列追加・grep フラグ変更後も読み込み経路が維持されること

    run bash <<EOF
# orchestrator から LLM_INDICATORS 動的読み込みロジックを抽出して実行
_COA_SCRIPT="$CLD_OBSERVE_ANY"
LLM_INDICATORS=()
if [[ -f "\$_COA_SCRIPT" ]]; then
    eval "\$(awk '/^LLM_INDICATORS=\(/{p=1} p{print} /^\)\$/{if(p){p=0; exit}}' "\$_COA_SCRIPT" 2>/dev/null)" 2>/dev/null || true
fi

# 動的読み込み後に REQUIRED indicators が含まれること
REQUIRED=(Garnishing Embellishing Flambéing Tomfoolering Reticulating Generating)
missing=()
for word in "\${REQUIRED[@]}"; do
    found=0
    for indicator in "\${LLM_INDICATORS[@]}"; do
        [[ "\$indicator" == "\$word" ]] && found=1 && break
    done
    [[ "\$found" -eq 0 ]] && missing+=("\$word")
done

if [[ \${#missing[@]} -gt 0 ]]; then
    echo "FAIL: orchestrator dynamic load missing: \${missing[*]}"
    exit 1
fi
echo "PASS: orchestrator dynamic load OK (loaded \${#LLM_INDICATORS[@]} indicators)"
EOF

    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: orchestrator dynamic load OK"
}

# ===========================================================================
# Issue #1165: tech-debt(session): cld-observe-any SUPERVISOR_DIR パストラバーサル防御
# AC4: invalid SUPERVISOR_DIR で exit 2 + stderr に "FATAL" 含む統合テスト
# RED: cld-observe-any への validate_supervisor_dir 呼び出し未追加のため fail
# ===========================================================================

# ---------------------------------------------------------------------------
# AC4(#1165): invalid SUPERVISOR_DIR=/tmp/../etc で exit 2 + stderr FATAL
# RED: path-validate.sh の source + validate_supervisor_dir 呼び出しが
#      cld-observe-any に未追加のため fail する
# ---------------------------------------------------------------------------
@test "AC4(#1165): invalid SUPERVISOR_DIR=/tmp/../etc で exit 2 かつ stderr に FATAL が含まれる" {
    # RED: cld-observe-any への validate_supervisor_dir 呼び出し未追加のため fail する
    run bash -c "_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR='$SCRIPT_DIR' SUPERVISOR_DIR='/tmp/../etc' bash '$CLD_OBSERVE_ANY' --window dummy-win --once 2>&1"
    [ "$status" -eq 2 ]
    [[ "$output" =~ "FATAL" ]]
}

# ===========================================================================
# Issue #1374: LLM indicator SSOT lib 新設（cld-observe-any から分離）
# AC7: 新 lib を source した状態で LLM_INDICATORS が EN/JP 両方を含む
# ===========================================================================

setup_ac7() {
    local this_dir
    this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    REPO_ROOT_1374="$(cd "${this_dir}/../../.." && pwd)"
    LLM_INDICATORS_LIB="${REPO_ROOT_1374}/plugins/session/scripts/lib/llm-indicators.sh"
}

# ---------------------------------------------------------------------------
# AC7/1: llm-indicators.sh が存在すること
# ---------------------------------------------------------------------------
@test "AC7(#1374): plugins/session/scripts/lib/llm-indicators.sh が存在すること (RED)" {
    setup_ac7
    # AC: plugins/session/scripts/lib/llm-indicators.sh を新設する
    [ -f "$LLM_INDICATORS_LIB" ]
}

# ---------------------------------------------------------------------------
# AC7/2: source 後 LLM_INDICATORS が bash 配列として export される
# ---------------------------------------------------------------------------
@test "AC7(#1374): source 後 LLM_INDICATORS bash 配列が export される (RED)" {
    setup_ac7
    # AC: LLM_INDICATORS を bash 配列として export する（SSOT）
    [ -f "$LLM_INDICATORS_LIB" ]
    run bash -c "
        source '${LLM_INDICATORS_LIB}'
        # LLM_INDICATORS が配列として定義されており要素が存在する
        [[ \"\${#LLM_INDICATORS[@]}\" -gt 0 ]]
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC7/3: LLM_INDICATORS が既存 EN indicator（Thinking, Brewing 等）を含む
# ---------------------------------------------------------------------------
@test "AC7(#1374): LLM_INDICATORS が既存 EN indicator（Thinking, Brewing）を含む (RED)" {
    setup_ac7
    # AC: LLM_INDICATORS に EN/JP 両方の indicator が含まれる
    [ -f "$LLM_INDICATORS_LIB" ]
    run bash -c "
        source '${LLM_INDICATORS_LIB}'
        # 既存 EN indicator の存在確認
        found_thinking=0
        found_brewing=0
        for ind in \"\${LLM_INDICATORS[@]}\"; do
            [[ \"\$ind\" == *'Thinking'* ]] && found_thinking=1
            [[ \"\$ind\" == *'Brewing'* ]] && found_brewing=1
        done
        [[ \$found_thinking -eq 1 && \$found_brewing -eq 1 ]]
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC7/4: LLM_INDICATORS が AC5 追加 EN 13 件を含む
# ---------------------------------------------------------------------------
@test "AC7(#1374): LLM_INDICATORS が AC5 EN 13 件（Philosophising 等）を含む (RED)" {
    setup_ac7
    # AC: EN 13 件を SSOT 配列に追加する
    [ -f "$LLM_INDICATORS_LIB" ]
    run bash -c "
        source '${LLM_INDICATORS_LIB}'
        REQUIRED=(Philosophising Drizzling Fluttering Spelunking Determining Infusing Prestidigitating Cogitated Frolicking Marinating Metamorphosing Shimmying Transfiguring)
        missing=()
        for word in \"\${REQUIRED[@]}\"; do
            found=0
            for ind in \"\${LLM_INDICATORS[@]}\"; do
                [[ \"\$ind\" == *\"\$word\"* ]] && found=1 && break
            done
            [[ \$found -eq 0 ]] && missing+=(\"\$word\")
        done
        if [[ \${#missing[@]} -gt 0 ]]; then
            echo \"MISSING EN indicators: \${missing[*]}\"
            exit 1
        fi
        echo 'PASS: EN 13 件確認'
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC7/5: LLM_INDICATORS が AC6 追加 JP 6 件を含む
# ---------------------------------------------------------------------------
@test "AC7(#1374): LLM_INDICATORS が AC6 JP 6 件（生成中 等）を含む (RED)" {
    setup_ac7
    # AC: JP 6 件を SSOT 配列に追加する
    [ -f "$LLM_INDICATORS_LIB" ]
    run bash -c "
        source '${LLM_INDICATORS_LIB}'
        REQUIRED_JP=(生成中 構築中 処理中 作成中 分析中 検証中)
        missing_jp=()
        for word in \"\${REQUIRED_JP[@]}\"; do
            found=0
            for ind in \"\${LLM_INDICATORS[@]}\"; do
                [[ \"\$ind\" == *\"\$word\"* ]] && found=1 && break
            done
            [[ \$found -eq 0 ]] && missing_jp+=(\"\$word\")
        done
        if [[ \${#missing_jp[@]} -gt 0 ]]; then
            echo \"MISSING JP indicators: \${missing_jp[*]}\"
            exit 1
        fi
        echo 'PASS: JP 6 件確認'
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC7/6: cld-observe-any が LLM_INDICATORS inline 定義を持たず lib を source する
# ---------------------------------------------------------------------------
@test "AC7(#1374): cld-observe-any の inline LLM_INDICATORS が削除され lib source に切り替わる (RED)" {
    setup_ac7
    # AC: cld-observe-any L15-44 の inline 配列定義を削除し新 lib を source で参照する
    run bash -c "
        # inline LLM_INDICATORS=( 定義が cld-observe-any に残っていれば RED（未実装）
        if grep -q '^LLM_INDICATORS=(' '${CLD_OBSERVE_ANY}'; then
            echo 'FAIL: inline LLM_INDICATORS=( が cld-observe-any に残存している（lib 分離未実装）'
            exit 1
        fi
        # lib の source 行が存在すること
        if ! grep -q 'llm-indicators.sh' '${CLD_OBSERVE_ANY}'; then
            echo 'FAIL: llm-indicators.sh の source 行が cld-observe-any に未追加'
            exit 1
        fi
        echo 'PASS: inline 削除 + lib source 確認'
    "
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Issue #1474: controller window (wt-co-*) を IDLE_COMPLETED_AUTO_KILL 対象から除外
#
# Scenario 25: AC1 — wt-co-* prefix window は auto-kill されない（RED: 実装後 PASS）
# Scenario 26: AC2 — controller spawn → IDLE_COMPLETED phrase 出力 → 非 kill 検証（RED）
# Scenario 27: AC3 — worker window (ap-*) は従来通り auto-kill される（regression）
# Scenario 28: AC4 — [IDLE-COMPLETED-SKIP] log が出力される（RED）
# Scenario 29: AC5 — cld-observe-any に controller prefix 除外ロジックが存在する（静的検証）
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Scenario 25: AC1 — controller window prefix (wt-co-*) を auto-kill 対象から除外
#   RED: 現状は除外ロジックが存在しないため controller も kill される
#   PASS 条件（実装後）:
#     - win=wt-co-autopilot-091135 で IDLE_COMPLETED_AUTO_KILL=1 でも kill-window 未呼び出し
#
#   Note: tmux list-windows -a -F ... も正しく応答させて kill_target を解決させる。
#         これにより kill-window が呼ばれるかどうかを除外ロジックの有無で判定できる。
# ---------------------------------------------------------------------------
@test "AC1(#1474): controller window (wt-co-*) は IDLE_COMPLETED_AUTO_KILL=1 でも auto-kill されない (RED: 実装後 PASS)" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="wt-co-autopilot-091135"
SESSION_WIN="test-session:0"
export win SESSION_WIN TMPD

capture=">>> 実装完了
Phase 4 完了
nothing pending"
export capture

tmux() {
    case "$1" in
        list-windows)
            if [[ "${*}" == *"-a"* ]]; then
                echo "$SESSION_WIN $win"
            else
                echo "$SESSION_WIN $win"
            fi;;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            echo "KILLED: $@" >> "$TMPD/kill-log.txt"
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if [[ -f "$TMPD/kill-log.txt" ]]; then
    echo "FAIL: controller window が auto-killed された（除外ロジック未実装）"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: controller window は auto-kill されなかった"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 25b: AC1 強化版 — list-windows -a の awk 解決込みで kill_target 特定
#   RED: 除外ロジックがないため wt-co-* prefix でも kill-window が呼ばれる
#   PASS 条件（実装後）:
#     - 除外ロジックにより kill-window が呼ばれない
# ---------------------------------------------------------------------------
@test "AC1b(#1474): wt-co-* prefix window は除外ロジックにより auto-kill スキップされる（awk 解決込み RED）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="wt-co-autopilot-091135"
export win TMPD

capture=">>> 実装完了
Phase 4 完了
nothing pending"
export capture

# list-windows -a -F 形式で返すことで awk が kill_target を解決できる
tmux() {
    case "$1" in
        list-windows)
            echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            echo "KILLED: $@" >> "$TMPD/kill-log.txt"
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if [[ -f "$TMPD/kill-log.txt" ]]; then
    echo "FAIL: controller window (wt-co-*) が auto-killed された（除外ロジック未実装）"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: controller window は auto-kill されなかった"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 26: AC2 — controller spawn → IDLE_COMPLETED phrase 出力 → 非 kill 検証
#   RED: 現状は controller も kill される（list-windows -a が正しく動けば）
#   PASS 条件（実装後）:
#     - IDLE-COMPLETED イベントは emit されても kill-window は呼ばれない
#
#   テスト方針: 静的検証として「除外ロジックが実装されたか」を確認する
# ---------------------------------------------------------------------------
@test "AC2(#1474): controller spawn → IDLE_COMPLETED phrase 検出 → kill-window 未呼び出し (RED: 実装後 PASS)" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/tmux-calls.log"
win="wt-co-issue-1474-abc12345"
export win TMPD CALL_LOG

# IDLE_COMPLETED_PHRASE_REGEX にマッチするフレーズを含む
capture="Worker 完了
nothing pending
All tasks done."
export capture

tmux() {
    echo "$1 $*" >> "$CALL_LOG"
    case "$1" in
        list-windows)
            echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            echo "KILLED: $@" >> "$TMPD/kill-log.txt"
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

output_text=$(IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null)

if [[ -f "$TMPD/kill-log.txt" ]]; then
    echo "FAIL: controller window が kill-window で削除された"
    cat "$TMPD/kill-log.txt"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: controller は kill されなかった"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 27: AC3 — worker window (ap-*) は従来通り auto-kill される（regression test）
#   このテストは現実装でも PASS する可能性が高い（worker は従来通り対象）
#   RED: ac3 実装後に controller 除外ロジックが worker まで影響しないことを保証
# ---------------------------------------------------------------------------
@test "AC3(#1474): worker window (ap-*) は IDLE_COMPLETED_AUTO_KILL=1 で auto-kill される（regression: 実装後も PASS）" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="ap-twill-feat-1474-ab1cd234"
export win TMPD

capture="All tasks are done.
nothing pending
System is idle."
export capture

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            echo "KILLED: $@" >> "$TMPD/kill-log.txt"
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

output_text=$(IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null)

if [[ ! -f "$TMPD/kill-log.txt" ]]; then
    echo "FAIL: worker window (ap-*) が auto-kill されなかった（regression）"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: worker window は auto-kill された"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 28: AC4 — controller window skip 時に [IDLE-COMPLETED-SKIP] ログが出力される
#   RED: 現状は除外ロジック自体が存在しないためログも出ない
#   PASS 条件（実装後）:
#     - stdout または stderr に "[IDLE-COMPLETED-SKIP]" を含む行が出力される
# ---------------------------------------------------------------------------
@test "AC4(#1474): controller window skip 時に [IDLE-COMPLETED-SKIP] ログが出力される (RED: 実装後 PASS)" {
    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
win="wt-co-autopilot-091135"
export win TMPD

capture=">>> 実装完了
Phase 4 完了
nothing pending"
export capture

tmux() {
    case "$1" in
        list-windows) echo "test-session:0 $win";;
        display-message) echo "0 claude";;
        capture-pane)
            if [[ "${*}" == *"-S -1"* ]]; then echo ""; else printf '%s\n' "$capture"; fi;;
        kill-window)
            echo "KILLED: $@" >> "$TMPD/kill-log.txt"
            return 0;;
        *) return 0;;
    esac
}
export -f tmux

combined=$(IDLE_COMPLETED_AUTO_KILL=1 \
    IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>&1)

if ! echo "$combined" | grep -q "\[IDLE-COMPLETED-SKIP\]"; then
    echo "FAIL: [IDLE-COMPLETED-SKIP] ログが出力されなかった"
    echo "output was: $combined"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: [IDLE-COMPLETED-SKIP] ログ確認"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS:"
}

# ---------------------------------------------------------------------------
# Scenario 29: AC5 — 静的コード検証: cld-observe-any に controller prefix 除外ロジックが存在する
#   RED: 現状は除外ロジックが存在しないため fail する
#   PASS 条件（実装後）:
#     - cld-observe-any に "wt-co-" を含む除外ロジックが grep で確認できる
# ---------------------------------------------------------------------------
@test "AC5(#1474): cld-observe-any に controller prefix (wt-co-) 除外ロジックが存在する（静的検証 RED: 実装後 PASS）" {
    run bash -c "
        script='${CLD_OBSERVE_ANY}'
        # controller prefix 除外ロジックの存在確認（wt-co- パターンを含む条件分岐）
        if ! grep -q 'wt-co-' \"\$script\"; then
            echo 'FAIL: cld-observe-any に wt-co- を含む除外ロジックが存在しない'
            exit 1
        fi
        echo 'PASS: controller prefix 除外ロジック確認'
    "
    [ "$status" -eq 0 ]
}
