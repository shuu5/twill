#!/usr/bin/env bats
# test_1430_auto_next_spawn_bind.bats — Issue #1430 TDD RED フェーズ
#
# AC: IDLE_COMPLETED_AUTO_NEXT_SPAWN を AUTO_KILL=0 経路でも呼び出せるように
#     cld-observe-any の IDLE-COMPLETED 検知ブロックを修正する
#
# 全テストは実装前に fail（RED）する。実装後に GREEN になる。

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"

setup() {
    TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"
}

# ===========================================================================
# Issue #1430 AC テスト群
# ===========================================================================

# ---------------------------------------------------------------------------
# AC1: IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 かつ IDLE_COMPLETED_AUTO_KILL=0 の組み合わせで
#      IDLE-COMPLETED 検知時に auto-next-spawn.sh が呼び出される（wave-queue 完了条件成立時）
#
# RED: 現在コードでは AUTO_NEXT_SPAWN の評価が AUTO_KILL=1 分岐の内側にネストされているため、
#      AUTO_KILL=0 では auto-next-spawn.sh が呼び出されない。実装後 PASS。
# ---------------------------------------------------------------------------
@test "ac1(#1430): AUTO_NEXT_SPAWN=1 + AUTO_KILL=0 → auto-next-spawn.sh が呼び出される（wave-queue 完了条件成立時）" {
    # AC: IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 かつ IDLE_COMPLETED_AUTO_KILL=0 の組み合わせで、
    #     IDLE-COMPLETED 検知時に auto-next-spawn.sh が呼び出される（wave-queue 完了条件成立時）
    # RED: AUTO_KILL=0 では auto-next-spawn.sh が呼び出されない（実装前）

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
win="ap-ac1-1430-win"
export win

# IDLE_COMPLETED_PHRASE_REGEX にマッチするキャプチャ
capture="All tasks are done.
nothing pending
System is idle."
export capture

# wave-queue stub（current_wave 成立、全 window IDLE-COMPLETED 済み）
WAVE_QUEUE="$TMPD/wave-queue.json"
cat > "$WAVE_QUEUE" <<'JSON'
{"current_wave": 1, "waves": [{"wave": 1, "windows": ["ap-ac1-1430-win"]}]}
JSON
export WAVE_QUEUE

# observer-wave-check.sh を stub（_all_current_wave_idle_completed が必ず true を返す）
WAVE_CHECK_LIB="$TMPD/observer-wave-check.sh"
cat > "$WAVE_CHECK_LIB" <<'STUB'
_all_current_wave_idle_completed() {
    return 0  # 常に wave 完了
}
STUB
export WAVE_CHECK_LIB

# auto-next-spawn.sh を stub（呼び出し記録のみ）
AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn called: \$*" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

# _WAVE_CHECK_LIB と _AUTO_NEXT_SPAWN を override して実行
# 実装後: AUTO_NEXT_SPAWN の評価が AUTO_KILL 分岐の外に出るため呼ばれる
_WAVE_CHECK_LIB_OVERRIDE="$WAVE_CHECK_LIB" \
_AUTO_NEXT_SPAWN_OVERRIDE="$AUTO_NEXT_SPAWN" \
IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 \
IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
SUPERVISOR_DIR="$TMPD" \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

# 検証: auto-next-spawn.sh が呼び出されたか
if grep -q "auto-next-spawn called" "$CALL_LOG" 2>/dev/null; then
    echo "PASS: auto-next-spawn.sh called with AUTO_KILL=0"
    rm -rf "$TMPD"
    exit 0
else
    echo "FAIL: auto-next-spawn.sh not called (AUTO_KILL=0 path blocked)"
    rm -rf "$TMPD"
    exit 1
fi
MOCKEOF

    # RED: 実装前は fail する
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: auto-next-spawn.sh called with AUTO_KILL=0"
}

# ---------------------------------------------------------------------------
# AC2: IDLE_COMPLETED_AUTO_NEXT_SPAWN=0（既定値）の場合は AUTO_KILL の値に関係なく
#      auto-next-spawn.sh を呼び出さない
#
# 注: この動作は現行コードでも（AUTO_KILL=0 パス限定では）維持されている。
#     実装後も regression しないことを確認する GREEN 寄りのテスト。
# ---------------------------------------------------------------------------
@test "ac2(#1430): AUTO_NEXT_SPAWN=0（既定値）→ AUTO_KILL の値に関係なく auto-next-spawn.sh を呼ばない" {
    # AC: IDLE_COMPLETED_AUTO_NEXT_SPAWN=0（既定値）の場合は AUTO_KILL の値に関係なく
    #     auto-next-spawn.sh を呼び出さない

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
win="ap-ac2-1430-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn UNEXPECTED CALL: \$*" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

# AUTO_NEXT_SPAWN=0（明示的に無効）、AUTO_KILL=1 でも呼ばれないことを確認
IDLE_COMPLETED_AUTO_NEXT_SPAWN=0 \
IDLE_COMPLETED_AUTO_KILL=1 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if grep -q "auto-next-spawn UNEXPECTED CALL" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: auto-next-spawn.sh が呼び出された（AUTO_NEXT_SPAWN=0 なのに）"
    rm -rf "$TMPD"
    exit 1
fi

# AUTO_NEXT_SPAWN 未設定でも呼ばれないことを確認
unset IDLE_COMPLETED_AUTO_NEXT_SPAWN
IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if grep -q "auto-next-spawn UNEXPECTED CALL" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: auto-next-spawn.sh が呼び出された（AUTO_NEXT_SPAWN 未設定なのに）"
    rm -rf "$TMPD"
    exit 1
fi

echo "PASS: AUTO_NEXT_SPAWN=0 では auto-next-spawn.sh 呼び出しなし"
rm -rf "$TMPD"
MOCKEOF

    [[ "$status" -eq 0 ]]
    echo "$output" | grep -q "PASS: AUTO_NEXT_SPAWN=0 では auto-next-spawn.sh 呼び出しなし"
}

# ---------------------------------------------------------------------------
# AC3: _all_current_wave_idle_completed が false の場合は auto-next-spawn.sh を呼び出さない
#      （queue file 不在 / current_wave 取得失敗 / wave window 0 件 / 同 wave に active window 残存）
#
# RED: 実装後に AUTO_KILL=0 経路からも同関数が呼ばれるようになり、その false 判定が効くことを確認する
# ---------------------------------------------------------------------------
@test "ac3(#1430): _all_current_wave_idle_completed=false → auto-next-spawn.sh を呼ばない（queue 不在ケース）" {
    # AC: _all_current_wave_idle_completed が false（queue file 不在）の場合は
    #     auto-next-spawn.sh を呼び出さない
    # RED: 実装前は AUTO_KILL=0 経路自体が存在しないため fail する

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
win="ap-ac3-1430-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

# wave-queue.json は存在しない（queue file 不在ケース）
# SUPERVISOR_DIR を存在しない wave-queue がある tmpdir に設定
EMPTY_SUPERVISOR="$TMPD/empty-supervisor"
mkdir -p "$EMPTY_SUPERVISOR"
# wave-queue.json を作成しない

AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn UNEXPECTED CALL: \$*" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

# AUTO_KILL=0、wave-queue 不在 → _all_current_wave_idle_completed は false → 呼ばれない
IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 \
IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
SUPERVISOR_DIR="$EMPTY_SUPERVISOR" \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if grep -q "auto-next-spawn UNEXPECTED CALL" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: wave-queue 不在なのに auto-next-spawn.sh が呼び出された"
    rm -rf "$TMPD"
    exit 1
fi
echo "PASS: wave-queue 不在時は auto-next-spawn.sh 呼び出しなし"
rm -rf "$TMPD"
MOCKEOF

    # RED: 実装前は AUTO_KILL=0 経路自体がないため、このテストで検証したい動作が届かない
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: wave-queue 不在時は auto-next-spawn.sh 呼び出しなし"
}

# ---------------------------------------------------------------------------
# AC4: IDLE_COMPLETED_AUTO_NEXT_SPAWN=dry-run を設定した場合に
#      auto-next-spawn.sh --dry-run で起動する（既存挙動維持）
#
# RED: 実装前は AUTO_KILL=0 + dry-run 組み合わせが未サポートのため fail
# ---------------------------------------------------------------------------
@test "ac4(#1430): AUTO_NEXT_SPAWN=dry-run + AUTO_KILL=0 → auto-next-spawn.sh --dry-run で起動" {
    # AC: IDLE_COMPLETED_AUTO_NEXT_SPAWN=dry-run を設定した場合に
    #     auto-next-spawn.sh --dry-run で起動する（既存挙動維持）
    # RED: AUTO_KILL=0 経路が存在しないため fail

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
win="ap-ac4-1430-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

# wave-queue stub（完了条件成立）
WAVE_QUEUE="$TMPD/wave-queue.json"
cat > "$WAVE_QUEUE" <<'JSON'
{"current_wave": 1, "waves": [{"wave": 1, "windows": ["ap-ac4-1430-win"]}]}
JSON

# _all_current_wave_idle_completed stub: 常に true
WAVE_CHECK_LIB="$TMPD/observer-wave-check.sh"
cat > "$WAVE_CHECK_LIB" <<'STUB'
_all_current_wave_idle_completed() {
    return 0
}
STUB

# auto-next-spawn.sh stub: 引数を記録
AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn args: \$*" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

_WAVE_CHECK_LIB_OVERRIDE="$WAVE_CHECK_LIB" \
_AUTO_NEXT_SPAWN_OVERRIDE="$AUTO_NEXT_SPAWN" \
IDLE_COMPLETED_AUTO_NEXT_SPAWN=dry-run \
IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
SUPERVISOR_DIR="$TMPD" \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

# 検証: --dry-run フラグ付きで呼ばれたか
if grep -q "auto-next-spawn args:.*--dry-run" "$CALL_LOG" 2>/dev/null; then
    echo "PASS: auto-next-spawn.sh --dry-run で起動"
    rm -rf "$TMPD"
    exit 0
else
    echo "FAIL: --dry-run フラグなしで呼ばれた、または呼ばれなかった（log=$(cat "$CALL_LOG" 2>/dev/null)）"
    rm -rf "$TMPD"
    exit 1
fi
MOCKEOF

    # RED: 実装前は AUTO_KILL=0 経路が存在しないため fail
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: auto-next-spawn.sh --dry-run で起動"
}

# ---------------------------------------------------------------------------
# AC5: AUTO_KILL=1 経路（既存の auto-kill 後 AUTO_NEXT_SPAWN fire）も regression なく動作する
#      （auto-kill → auto-next-spawn 連鎖が失われない）
#
# 注: 現行コードの AUTO_KILL=1 経路は動作しているが、実装後も regression がないことを確認する
# ---------------------------------------------------------------------------
@test "ac5(#1430): AUTO_KILL=1 経路の auto-kill → auto-next-spawn 連鎖が regression なく動作" {
    # AC: AUTO_KILL=1 経路（既存の auto-kill 後 AUTO_NEXT_SPAWN fire）も regression なく動作する
    # 現状: 現行コードで AUTO_KILL=1 + AUTO_NEXT_SPAWN=1 は AUTO_KILL=1 分岐内のみで動作
    # 実装後: 同動作が維持されること（regression なし）

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
win="ap-ac5-1430-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

WAVE_QUEUE="$TMPD/wave-queue.json"
cat > "$WAVE_QUEUE" <<'JSON'
{"current_wave": 1, "waves": [{"wave": 1, "windows": ["ap-ac5-1430-win"]}]}
JSON

WAVE_CHECK_LIB="$TMPD/observer-wave-check.sh"
cat > "$WAVE_CHECK_LIB" <<'STUB'
_all_current_wave_idle_completed() {
    return 0
}
STUB

AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn args: \$*" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

_WAVE_CHECK_LIB_OVERRIDE="$WAVE_CHECK_LIB" \
_AUTO_NEXT_SPAWN_OVERRIDE="$AUTO_NEXT_SPAWN" \
IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 \
IDLE_COMPLETED_AUTO_KILL=1 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
SUPERVISOR_DIR="$TMPD" \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

if grep -q "auto-next-spawn args:" "$CALL_LOG" 2>/dev/null; then
    echo "PASS: AUTO_KILL=1 経路で auto-next-spawn 連鎖が動作"
    rm -rf "$TMPD"
    exit 0
else
    echo "FAIL: AUTO_KILL=1 経路で auto-next-spawn が呼ばれなかった（regression）"
    rm -rf "$TMPD"
    exit 1
fi
MOCKEOF

    # 現行コードでは AUTO_KILL=1 + stub 未接続のため PASS 不可（_WAVE_CHECK_LIB_OVERRIDE 未実装）
    # 実装後（override 機構の追加を含む）に PASS
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: AUTO_KILL=1 経路で auto-next-spawn 連鎖が動作"
}

# ---------------------------------------------------------------------------
# AC6: AUTO_NEXT_SPAWN 起動時に .supervisor/intervention-log.md へ起動経路を識別できる log 行を記録する
#      "[IDLE-COMPLETED] auto-next-spawn fire via=auto_kill_${IDLE_COMPLETED_AUTO_KILL:-0} triggered_by=${WIN}"
#
# RED: 現行コードでは log 行が intervention-log.md ではなく tee 経由で自然に書き込まれるが、
#      via=auto_kill_0 の形式（AUTO_KILL=0 経路）のログは存在しない。実装後 PASS。
# ---------------------------------------------------------------------------
@test "ac6(#1430): AUTO_NEXT_SPAWN 起動時に intervention-log.md へ起動経路 log を記録する（via=auto_kill_0）" {
    # AC: AUTO_NEXT_SPAWN 起動時に .supervisor/intervention-log.md へ
    #     "[IDLE-COMPLETED] auto-next-spawn fire via=auto_kill_${IDLE_COMPLETED_AUTO_KILL:-0} triggered_by=${WIN}" を記録する
    # RED: 実装前は AUTO_KILL=0 経路自体が存在せず、via= ログ行も存在しない

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
SUPERVISOR_DIR_TEST="$TMPD/supervisor"
mkdir -p "$SUPERVISOR_DIR_TEST"
INTERVENTION_LOG="$SUPERVISOR_DIR_TEST/intervention-log.md"
win="ap-ac6-1430-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

WAVE_QUEUE="$TMPD/wave-queue.json"
cat > "$WAVE_QUEUE" <<'JSON'
{"current_wave": 1, "waves": [{"wave": 1, "windows": ["ap-ac6-1430-win"]}]}
JSON
cp "$WAVE_QUEUE" "$SUPERVISOR_DIR_TEST/wave-queue.json"

WAVE_CHECK_LIB="$TMPD/observer-wave-check.sh"
cat > "$WAVE_CHECK_LIB" <<'STUB'
_all_current_wave_idle_completed() {
    return 0
}
STUB

AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn called" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

_WAVE_CHECK_LIB_OVERRIDE="$WAVE_CHECK_LIB" \
_AUTO_NEXT_SPAWN_OVERRIDE="$AUTO_NEXT_SPAWN" \
IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 \
IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
SUPERVISOR_DIR="$SUPERVISOR_DIR_TEST" \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>/dev/null

# 検証: intervention-log.md に via=auto_kill_0 の log 行が記録されているか
if grep -q "auto-next-spawn fire" "$INTERVENTION_LOG" 2>/dev/null && \
   grep -q "via=auto_kill_0" "$INTERVENTION_LOG" 2>/dev/null; then
    echo "PASS: intervention-log.md に via=auto_kill_0 log 行が記録"
    rm -rf "$TMPD"
    exit 0
else
    echo "FAIL: intervention-log.md に期待の log 行がない"
    echo "intervention-log content: $(cat "$INTERVENTION_LOG" 2>/dev/null || echo '(not found)')"
    rm -rf "$TMPD"
    exit 1
fi
MOCKEOF

    # RED: 実装前は fail する
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: intervention-log.md に via=auto_kill_0 log 行が記録"
}

# ---------------------------------------------------------------------------
# AC7: bash -n plugins/session/scripts/cld-observe-any が syntax error なく通過する
# ---------------------------------------------------------------------------
@test "ac7(#1430): bash -n で cld-observe-any に syntax error がないこと" {
    # AC: bash -n plugins/session/scripts/cld-observe-any が syntax error なく通過する
    run bash -n "$CLD_OBSERVE_ANY"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC8: 修正前 L588-590 の WARN ブランチが削除されている
#      "IDLE_COMPLETED_AUTO_NEXT_SPAWN requires AUTO_KILL=1" warning ブランチの削除確認
#
# RED: 現行コードに "requires AUTO_KILL=1" warning 文字列が存在するため fail する
# ---------------------------------------------------------------------------
@test "ac8(#1430): 'IDLE_COMPLETED_AUTO_NEXT_SPAWN requires AUTO_KILL=1' warning ブランチが削除されている" {
    # AC: 修正前 L588-590 の WARN ブランチが削除されている
    # RED: 現行コードに warning 文字列が存在するため grep で 0 件を期待するが実際は 1 件あり fail
    run bash -c "grep -c 'IDLE_COMPLETED_AUTO_NEXT_SPAWN requires AUTO_KILL=1' '$CLD_OBSERVE_ANY'"
    # 削除されていれば grep -c の結果が 0 行 → exit 1（no match）
    # またはカウントが 0
    [ "$status" -ne 0 ] || [ "$output" = "0" ]
}

# ---------------------------------------------------------------------------
# AC9: _WAVE_CHECK_LIB が存在しない場合は既存挙動（WARN を stderr に出力してスキップ）を維持する
#
# RED: 実装前は AUTO_KILL=0 経路自体が存在しないため、この分岐に到達しない
#      実装後: AUTO_KILL=0 経路が追加され、_WAVE_CHECK_LIB 不在時の WARN が stderr に出ることを確認
# ---------------------------------------------------------------------------
@test "ac9(#1430): _WAVE_CHECK_LIB 不在時 → WARN を stderr に出力してスキップ（既存挙動維持）" {
    # AC: _WAVE_CHECK_LIB が存在しない場合は WARN を stderr に出力してスキップ
    # RED: AUTO_KILL=0 経路が存在しないため fail

    run bash <<'MOCKEOF'
SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"
TMPD="$(mktemp -d)"
CALL_LOG="$TMPD/calls.log"
win="ap-ac9-1430-win"
export win

capture="All tasks are done.
nothing pending
System is idle."
export capture

# auto-next-spawn.sh stub（呼ばれたら記録）
AUTO_NEXT_SPAWN="$TMPD/auto-next-spawn.sh"
cat > "$AUTO_NEXT_SPAWN" <<STUB
#!/usr/bin/env bash
echo "auto-next-spawn UNEXPECTED CALL" | tee -a "$CALL_LOG"
exit 0
STUB
chmod +x "$AUTO_NEXT_SPAWN"
export AUTO_NEXT_SPAWN

tmux() {
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

STDERR_FILE="$TMPD/stderr.txt"

# _WAVE_CHECK_LIB_OVERRIDE を存在しないパスに設定（_WAVE_CHECK_LIB 不在）
_WAVE_CHECK_LIB_OVERRIDE="/nonexistent/path/observer-wave-check.sh" \
IDLE_COMPLETED_AUTO_NEXT_SPAWN=1 \
IDLE_COMPLETED_AUTO_KILL=0 \
IDLE_COMPLETED_DEBOUNCE_SEC=0 \
SUPERVISOR_DIR="$TMPD" \
    _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$SCRIPT_DIR" \
    bash "$CLD_OBSERVE_ANY" --window "$win" \
    --max-cycles 2 --interval 1 2>"$STDERR_FILE"

# 検証1: auto-next-spawn.sh が呼ばれていないこと
if grep -q "auto-next-spawn UNEXPECTED CALL" "$CALL_LOG" 2>/dev/null; then
    echo "FAIL: _WAVE_CHECK_LIB 不在なのに auto-next-spawn.sh が呼ばれた"
    rm -rf "$TMPD"
    exit 1
fi

# 検証2: stderr に WARN が出力されていること
stderr_text=$(cat "$STDERR_FILE" 2>/dev/null || echo "")
if echo "$stderr_text" | grep -qi "warn\|not found\|skip"; then
    echo "PASS: _WAVE_CHECK_LIB 不在時に WARN が stderr に出力されスキップ"
    rm -rf "$TMPD"
    exit 0
else
    echo "FAIL: stderr に WARN が出力されていない（stderr=$stderr_text）"
    rm -rf "$TMPD"
    exit 1
fi
MOCKEOF

    # RED: 実装前は AUTO_KILL=0 経路が存在しないため fail
    [[ "$status" -eq 0 ]] && echo "$output" | grep -q "PASS: _WAVE_CHECK_LIB 不在時に WARN が stderr に出力されスキップ"
}
