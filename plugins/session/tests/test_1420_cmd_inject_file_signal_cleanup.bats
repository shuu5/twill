#!/usr/bin/env bats
# test_1420_cmd_inject_file_signal_cleanup.bats
# Issue #1420: tech-debt: session-comm cmd_inject_file シグナルハンドラによる buffer cleanup
#
# AC1: cmd_inject_file 内に trap '<cleanup>' TERM HUP INT ハンドラを追加し、
#      各シグナル受信時に tmux delete-buffer -b "$_buf_name" 2>/dev/null || true が実行される
# AC2: handler は _buf_name 代入直後（= tmux load-buffer 呼び出し直前）に設定する
# AC3: handler 実行後、信号別の signal-conventional 終了コードで終了する
#      SIGTERM=143, SIGHUP=129, SIGINT=130
# AC4: 既存 inline cleanup（normal path / 3 つの error path）は温存する
#      handler との重複呼び出しは冪等であることを delete-buffer ... 2>/dev/null || true で保証
# AC5: 各 exit 経路の exit 直前で trap - TERM HUP INT で trap を解除する
# AC6: 新規 bats テスト（本ファイル）で signal 送信・終了コード・バッファ残留を検証
# AC7: 既存テスト issue-1050-inject-file-named-buffer.bats / session-comm-robustness.test.sh が PASS する
#
# NOTE: source guard 確認:
#       session-comm.sh L534 に `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard が存在する。
#       このファイルは bash "$SCRIPT" で実行（source ではない）ため問題なし。
#
# NOTE: shellcheck disable=SC2064 について:
#       trap "$cleanup_cmd" TERM の形式（変数展開を trap 登録時に評価）を使う場合は
#       SC2064 を disable する必要がある。実装者は Issue body の技術メモを参照。

# ===========================================================================
# setup / teardown
# ===========================================================================

setup() {
    PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SCRIPT="$PLUGIN_ROOT/scripts/session-comm.sh"
    SANDBOX="$(mktemp -d)"
    export SANDBOX SCRIPT PLUGIN_ROOT
}

teardown() {
    [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
}

# ===========================================================================
# helper: mock tmux（シグナルテスト用 — load-buffer を sleep で遅延）
# load-buffer の間に kill を送り、シグナルハンドラ発火を待つパターン
# active_buffers ファイルでバッファ残留を追跡する
# NOTE: 非クォート heredoc で外部変数 $SANDBOX を展開する
# ===========================================================================

_create_mock_tmux_signal_test() {
    local delay="${1:-0.5}"  # load-buffer の遅延秒数
    local mock="$SANDBOX/bin/tmux"
    mkdir -p "$SANDBOX/bin" "$SANDBOX/buffers" "$SANDBOX/targets"
    local active_buffers="$SANDBOX/active_buffers"
    touch "$active_buffers"

    # 非クォート heredoc: $SANDBOX, $active_buffers, $delay は parent shell で展開
    cat > "$mock" << MOCK
#!/bin/bash
echo "\$*" >> "${SANDBOX}/tmux_calls.log"

case "\$1" in
    -V)
        echo "tmux 3.4"
        ;;
    has-session)
        exit 0
        ;;
    list-sessions)
        exit 0
        ;;
    list-windows)
        echo "session:0 mock-window"
        ;;
    list-buffers)
        if [[ -s "${active_buffers}" ]]; then
            while IFS= read -r buf; do
                echo "\${buf}: 10 bytes"
            done < "${active_buffers}"
        fi
        exit 0
        ;;
    load-buffer)
        buf_name=""
        file_arg=""
        shift
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                -b) buf_name="\$2"; shift 2 ;;
                *)  file_arg="\$1"; shift ;;
            esac
        done
        if [[ -n "\$buf_name" && -n "\$file_arg" && -f "\$file_arg" ]]; then
            cp "\$file_arg" "${SANDBOX}/buffers/\${buf_name}"
            echo "\${buf_name}" >> "${active_buffers}"
        fi
        # 遅延: この間に親プロセスがシグナルを送れる
        sleep ${delay}
        exit 0
        ;;
    paste-buffer)
        buf_name=""
        target=""
        shift
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                -b) buf_name="\$2"; shift 2 ;;
                -t) target="\$2"; shift 2 ;;
                -p) shift ;;
                *)  shift ;;
            esac
        done
        if [[ -n "\$buf_name" && -n "\$target" ]]; then
            buf_file="${SANDBOX}/buffers/\${buf_name}"
            if [[ -f "\$buf_file" ]]; then
                cat "\$buf_file" >> "${SANDBOX}/targets/\${target}"
            fi
        fi
        exit 0
        ;;
    delete-buffer)
        buf_name=""
        shift
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                -b) buf_name="\$2"; shift 2 ;;
                *)  shift ;;
            esac
        done
        if [[ -n "\$buf_name" ]]; then
            rm -f "${SANDBOX}/buffers/\${buf_name}"
            grep -v "^\${buf_name}$" "${active_buffers}" > "${active_buffers}.tmp" 2>/dev/null || true
            mv "${active_buffers}.tmp" "${active_buffers}" 2>/dev/null || true
        fi
        exit 0
        ;;
    send-keys)
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK
    chmod +x "$mock"
}

_create_mock_session_state_input_waiting() {
    mkdir -p "$SANDBOX/mock_scripts"
    cat > "$SANDBOX/mock_scripts/session-state.sh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "state" ]]; then echo "input-waiting"; exit 0; fi
if [[ "$1" == "wait" ]]; then exit 0; fi
exit 0
MOCK
    chmod +x "$SANDBOX/mock_scripts/session-state.sh"
}

# ===========================================================================
# AC1[structural][RED]: trap 'cleanup' TERM HUP INT が cmd_inject_file に存在する
# 現在の実装には trap ... TERM HUP INT が一切ない → FAIL
# ===========================================================================

@test "ac1[structural][RED]: cmd_inject_file に 'trap.*TERM.*HUP.*INT' または 'trap.*TERM' が存在する" {
    # AC1: _buf_name 代入後に trap handler が TERM HUP INT に設定されていること
    # 現在の実装には trap ... TERM が存在しない → FAIL

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    if [[ -z "$start_line" ]]; then
        echo "FAIL: cmd_inject_file() 関数が見つからない" >&2
        return 1
    fi

    # cmd_inject_file 範囲内に trap.*TERM が存在するか
    local trap_term_lines
    trap_term_lines=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /trap.*TERM/" "$SCRIPT")

    if [[ -z "$trap_term_lines" ]]; then
        echo "FAIL: cmd_inject_file 範囲内に 'trap.*TERM' が存在しない" >&2
        echo "  AC1 実装が必要: trap '<cleanup>' TERM HUP INT ハンドラを追加" >&2
        return 1
    fi
}

@test "ac1[structural][RED]: cmd_inject_file の trap handler に delete-buffer が含まれる" {
    # AC1: trap handler の中身に tmux delete-buffer -b "\$_buf_name" が含まれること
    # 現在の実装には trap ... TERM が存在しない → この検証自体が到達できず FAIL

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    # trap ... TERM 行が存在するか
    local trap_line
    trap_line=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /trap.*TERM/ {print NR; exit}" "$SCRIPT")

    if [[ -z "$trap_line" ]]; then
        echo "FAIL: cmd_inject_file 範囲内に 'trap.*TERM' が存在しない（AC1 未実装）" >&2
        return 1
    fi

    # trap handler の内容に delete-buffer が含まれるか
    local trap_content
    trap_content=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /trap.*TERM/" "$SCRIPT")

    echo "$trap_content" | grep -q 'delete-buffer' || {
        echo "FAIL: trap handler に delete-buffer が含まれない" >&2
        echo "  現在の trap 行: $trap_content" >&2
        return 1
    }
}

# ===========================================================================
# AC2[structural][RED]: trap handler は _buf_name 代入直後・load-buffer 直前に設定される
# 現在の実装には trap がない → FAIL
# ===========================================================================

@test "ac2[structural][RED]: trap handler は _buf_name 代入後・load-buffer 呼び出し前の行に存在する" {
    # AC2: _buf_name 代入行より後、tmux load-buffer -b 呼び出し行より前に
    #      trap ... TERM の設定が存在すること
    # 現在の実装には trap ... TERM が存在しない → FAIL

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    local buf_name_line load_buffer_line trap_term_line
    buf_name_line=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /local _buf_name=/ {print NR; exit}" "$SCRIPT")
    load_buffer_line=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /tmux load-buffer -b/ {print NR; exit}" "$SCRIPT")
    trap_term_line=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /trap.*TERM/ {print NR; exit}" "$SCRIPT")

    if [[ -z "$trap_term_line" ]]; then
        echo "FAIL: cmd_inject_file 範囲内に 'trap.*TERM' が存在しない（AC1/AC2 未実装）" >&2
        echo "  _buf_name 代入行: ${buf_name_line:-未検出}" >&2
        echo "  load-buffer 呼び出し行: ${load_buffer_line:-未検出}" >&2
        return 1
    fi

    # trap が _buf_name 代入より後に存在するか
    if [[ "$trap_term_line" -le "$buf_name_line" ]]; then
        echo "FAIL: trap handler が _buf_name 代入（L${buf_name_line}）より前（L${trap_term_line}）に設定されている" >&2
        echo "  AC2 違反: _buf_name 未設定時に trap を仕込んでいる（未設定変数参照リスク）" >&2
        return 1
    fi

    # trap が load-buffer より前に存在するか
    if [[ "$trap_term_line" -ge "$load_buffer_line" ]]; then
        echo "FAIL: trap handler（L${trap_term_line}）が load-buffer 呼び出し（L${load_buffer_line}）より後に設定されている" >&2
        echo "  AC2 違反: load-buffer 中のシグナルを捕捉できない" >&2
        return 1
    fi

    echo "OK: trap handler は L${trap_term_line}（_buf_name L${buf_name_line} 後、load-buffer L${load_buffer_line} 前）に設定されている"
}

# ===========================================================================
# AC3[functional][RED]: SIGTERM 受信時に終了コード 143 で終了する
# 現在の実装には trap TERM ハンドラがなく、SIGTERM でデフォルト終了（コードは不定）→ FAIL
# ===========================================================================

@test "ac3[functional][RED]: SIGTERM 送信時に終了コード 143 (128+15) で終了する" {
    # AC3: SIGTERM 受信時に終了コード 143 で終了すること
    # 現在の実装: trap TERM ハンドラなし → kill -TERM で SIG デフォルト動作（コード 143 に
    # ならないか、またはバッファ cleanup がされない）→ FAIL
    #
    # タイミング制御:
    # 1. mock tmux の load-buffer を 0.5s sleep で遅延
    # 2. subshell を background で起動
    # 3. mock が active_buffers に buf_name を書いた後（0.1s 待機）に kill -TERM を送る
    # 4. wait で終了コードを捕捉

    _create_mock_tmux_signal_test 0.5
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    local active_buffers="$SANDBOX/active_buffers"

    # subshell を background で起動
    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null &
    local subshell_pid=$!

    # mock の load-buffer が active_buffers に書き込むまで待機（最大 2s）
    local waited=0
    while [[ ! -s "$active_buffers" ]] && [[ $waited -lt 20 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    # SIGTERM を送信
    kill -TERM "$subshell_pid" 2>/dev/null || true

    local exit_code=0
    wait "$subshell_pid" 2>/dev/null || exit_code=$?

    # 終了コードが 143 であること
    if [[ "$exit_code" -ne 143 ]]; then
        echo "FAIL: SIGTERM 受信時の終了コードが 143 ではない（実際: $exit_code）" >&2
        echo "  AC3 実装が必要: handler 内で 'exit 143' を実行する" >&2
        echo "  現在の実装には SIGTERM handler がないため終了コードが不定" >&2
        return 1
    fi
}

@test "ac3[functional][RED]: SIGHUP 送信時に終了コード 129 (128+1) で終了する" {
    # AC3: SIGHUP 受信時に終了コード 129 で終了すること

    _create_mock_tmux_signal_test 0.5
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    local active_buffers="$SANDBOX/active_buffers"

    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null &
    local subshell_pid=$!

    local waited=0
    while [[ ! -s "$active_buffers" ]] && [[ $waited -lt 20 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    kill -HUP "$subshell_pid" 2>/dev/null || true

    local exit_code=0
    wait "$subshell_pid" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -ne 129 ]]; then
        echo "FAIL: SIGHUP 受信時の終了コードが 129 ではない（実際: $exit_code）" >&2
        echo "  AC3 実装が必要: handler 内で 'exit 129' を実行する" >&2
        return 1
    fi
}

@test "ac3[functional][RED]: SIGINT 送信時に終了コード 130 (128+2) で終了する" {
    # AC3: SIGINT 受信時に終了コード 130 で終了すること

    _create_mock_tmux_signal_test 0.5
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    local active_buffers="$SANDBOX/active_buffers"

    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null &
    local subshell_pid=$!

    local waited=0
    while [[ ! -s "$active_buffers" ]] && [[ $waited -lt 20 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    kill -INT "$subshell_pid" 2>/dev/null || true

    local exit_code=0
    wait "$subshell_pid" 2>/dev/null || exit_code=$?

    if [[ "$exit_code" -ne 130 ]]; then
        echo "FAIL: SIGINT 受信時の終了コードが 130 ではない（実際: $exit_code）" >&2
        echo "  AC3 実装が必要: handler 内で 'exit 130' を実行する" >&2
        return 1
    fi
}

# ===========================================================================
# AC4[structural][RED]: 既存 inline cleanup（error path の delete-buffer）が温存されている
# 現在の実装は既に inline cleanup 済みなので、このテストは GREEN（regression ガード）
# ただし、AC1 実装後に error path の cleanup が消えていないことを検証する重要性あり
# ===========================================================================

@test "ac4[structural][GREEN-regression]: load-buffer error path の inline delete-buffer が温存されている" {
    # AC4: 既存 inline cleanup は温存されること（実装前から PASS する regression ガード）
    # 現在の実装: load-buffer 失敗時に tmux delete-buffer -b "$_buf_name" 2>/dev/null || true
    # がすでに存在するため GREEN

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    local load_buffer_block
    load_buffer_block=$(awk "
        NR >= $start_line && NR <= ${end_line:-99999} {
            if (/tmux load-buffer -b/) { in_block=1 }
            if (in_block) { print }
            if (in_block && /^\s*\}/) { in_block=0 }
        }
    " "$SCRIPT" | head -15)

    echo "$load_buffer_block" | grep -q 'delete-buffer' || {
        echo "FAIL: load-buffer error block の inline delete-buffer が消えている（regression）" >&2
        echo "  AC4 違反: 既存 inline cleanup を削除してはならない" >&2
        return 1
    }
}

@test "ac4[structural][GREEN-regression]: paste-buffer error path の inline delete-buffer が温存されている" {
    # AC4: paste-buffer error path（-p 分岐・fallback 分岐）の inline cleanup も温存されること

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    # paste-buffer error block（-p 分岐）に delete-buffer が存在するか
    local paste_p_block
    paste_p_block=$(awk "
        NR >= $start_line && NR <= ${end_line:-99999} {
            if (/paste-buffer.*-p.*-t/) { in_block=1 }
            if (in_block) { print }
            if (in_block && /^\s*\}/) { in_block=0 }
        }
    " "$SCRIPT" | head -15)

    echo "$paste_p_block" | grep -q 'delete-buffer' || {
        echo "FAIL: paste-buffer -p error block の inline delete-buffer が消えている（regression）" >&2
        return 1
    }
}

# ===========================================================================
# AC5[structural][RED]: 各 exit 経路の直前で trap - TERM HUP INT が呼ばれる
# 現在の実装には trap - TERM HUP INT が存在しない → FAIL
# ===========================================================================

@test "ac5[structural][RED]: cmd_inject_file 内に 'trap - TERM HUP INT' が存在する" {
    # AC5: 各 exit 経路（正常終了・error path）の直前で trap - TERM HUP INT で解除すること
    # 現在の実装には trap - TERM HUP INT が存在しない → FAIL

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    local trap_reset_lines
    trap_reset_lines=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /trap - TERM/" "$SCRIPT")

    if [[ -z "$trap_reset_lines" ]]; then
        echo "FAIL: cmd_inject_file 範囲内に 'trap - TERM' が存在しない" >&2
        echo "  AC5 実装が必要: 各 exit 直前で 'trap - TERM HUP INT' を追加" >&2
        return 1
    fi
}

@test "ac5[structural][RED]: 正常終了 exit 前（delete-buffer 後）に trap - TERM HUP INT がある" {
    # AC5: 正常終了では delete-buffer 後に trap - TERM HUP INT が呼ばれること
    # 現在の実装には trap - TERM が存在しない → FAIL

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    # 正常終了付近（最後の delete-buffer の後）に trap - TERM があるか
    local last_delete_buf_line trap_reset_line
    last_delete_buf_line=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /tmux delete-buffer -b/ {last=NR} END {print last+0}" "$SCRIPT")
    trap_reset_line=$(awk "NR >= $last_delete_buf_line && NR <= ${end_line:-99999} && /trap - TERM/ {print NR; exit}" "$SCRIPT")

    if [[ -z "$trap_reset_line" || "$trap_reset_line" -le "$last_delete_buf_line" ]]; then
        echo "FAIL: 正常終了の最後の delete-buffer（L${last_delete_buf_line}）の後に 'trap - TERM' がない" >&2
        echo "  AC5 実装が必要: 正常終了では delete-buffer 後に trap を解除" >&2
        return 1
    fi

    echo "OK: trap - TERM は L${trap_reset_line}（最後の delete-buffer L${last_delete_buf_line} 後）に存在する"
}

# ===========================================================================
# AC6[functional][RED]: SIGTERM 受信時にバッファが残留しない
# 現在の実装には trap TERM ハンドラがない → kill 時にバッファが残留する → FAIL
# ===========================================================================

@test "ac6[functional][RED]: SIGTERM 受信後に session-comm-\$\$- プレフィックスのバッファが残留しない" {
    # AC6: SIGTERM を cmd_inject_file 実行中の subprocess に送信し、
    #      tmux list-buffers に session-comm-$$- プレフィックスのバッファが残っていないこと
    # 現在の実装: SIGTERM ハンドラがないため、kill 時に load-buffer が中断され
    # active_buffers ファイルにバッファが残る → FAIL

    _create_mock_tmux_signal_test 0.5
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    local active_buffers="$SANDBOX/active_buffers"

    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null &
    local subshell_pid=$!

    # mock が active_buffers に書き込むまで待機
    local waited=0
    while [[ ! -s "$active_buffers" ]] && [[ $waited -lt 20 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    # SIGTERM を送信してバッファが load された状態で中断させる
    kill -TERM "$subshell_pid" 2>/dev/null || true

    # subshell 終了を待つ
    wait "$subshell_pid" 2>/dev/null || true

    # シグナルハンドラが delete-buffer を呼ぶ時間を少し待つ
    sleep 0.2

    # active_buffers に session-comm-* が残っていないか確認
    local remaining_count=0
    if [[ -f "$active_buffers" ]]; then
        remaining_count=$(grep -c 'session-comm-' "$active_buffers" 2>/dev/null || echo 0)
    fi

    if [[ "$remaining_count" -gt 0 ]]; then
        echo "FAIL: SIGTERM 後に session-comm-* バッファが ${remaining_count} 件残留している" >&2
        echo "  残留バッファ:" >&2
        grep 'session-comm-' "$active_buffers" >&2
        echo "  AC1 実装が必要: SIGTERM handler で delete-buffer を実行" >&2
        return 1
    fi
}

@test "ac6[functional][RED]: SIGHUP 受信後に session-comm-\$\$- プレフィックスのバッファが残留しない" {
    # AC6: SIGHUP 受信後にバッファが残留しないこと

    _create_mock_tmux_signal_test 0.5
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    local active_buffers="$SANDBOX/active_buffers"

    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null &
    local subshell_pid=$!

    local waited=0
    while [[ ! -s "$active_buffers" ]] && [[ $waited -lt 20 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    kill -HUP "$subshell_pid" 2>/dev/null || true
    wait "$subshell_pid" 2>/dev/null || true
    sleep 0.2

    local remaining_count=0
    if [[ -f "$active_buffers" ]]; then
        remaining_count=$(grep -c 'session-comm-' "$active_buffers" 2>/dev/null || echo 0)
    fi

    if [[ "$remaining_count" -gt 0 ]]; then
        echo "FAIL: SIGHUP 後に session-comm-* バッファが ${remaining_count} 件残留している" >&2
        grep 'session-comm-' "$active_buffers" >&2
        echo "  AC1 実装が必要: SIGHUP handler で delete-buffer を実行" >&2
        return 1
    fi
}

@test "ac6[functional][RED]: SIGINT 受信後に session-comm-\$\$- プレフィックスのバッファが残留しない" {
    # AC6: SIGINT 受信後にバッファが残留しないこと

    _create_mock_tmux_signal_test 0.5
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    local active_buffers="$SANDBOX/active_buffers"

    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null &
    local subshell_pid=$!

    local waited=0
    while [[ ! -s "$active_buffers" ]] && [[ $waited -lt 20 ]]; do
        sleep 0.1
        waited=$((waited + 1))
    done

    kill -INT "$subshell_pid" 2>/dev/null || true
    wait "$subshell_pid" 2>/dev/null || true
    sleep 0.2

    local remaining_count=0
    if [[ -f "$active_buffers" ]]; then
        remaining_count=$(grep -c 'session-comm-' "$active_buffers" 2>/dev/null || echo 0)
    fi

    if [[ "$remaining_count" -gt 0 ]]; then
        echo "FAIL: SIGINT 後に session-comm-* バッファが ${remaining_count} 件残留している" >&2
        grep 'session-comm-' "$active_buffers" >&2
        echo "  AC1 実装が必要: SIGINT handler で delete-buffer を実行" >&2
        return 1
    fi
}

# ===========================================================================
# AC7[structural][GREEN]: 既存テストファイルが存在すること（regression ガード）
# これは現時点でも PASS する（ファイルの存在確認のみ）
# 実際の既存テストの PASS は make test / bats 実行で確認する
# ===========================================================================

@test "ac7: 既存テスト issue-1050-inject-file-named-buffer.bats が存在する（regression ガード）" {
    # AC7: 既存テスト issue-1050-inject-file-named-buffer.bats が PASS する前提として
    #      ファイルが存在し、削除・移動されていないことを確認する
    # これは現時点でも PASS する構造チェック（ファイル存在確認）
    local test_file="$PLUGIN_ROOT/tests/issue-1050-inject-file-named-buffer.bats"
    [[ -f "$test_file" ]] || {
        echo "FAIL: $test_file が存在しない（削除 or 移動された可能性）" >&2
        return 1
    }
}

@test "ac7: 既存テスト session-comm-robustness.test.sh が存在する（regression ガード）" {
    # AC7: 既存テスト session-comm-robustness.test.sh が PASS する前提として
    #      ファイルが存在し、削除・移動されていないことを確認する
    local test_file="$PLUGIN_ROOT/tests/session-comm-robustness.test.sh"
    [[ -f "$test_file" ]] || {
        echo "FAIL: $test_file が存在しない（削除 or 移動された可能性）" >&2
        return 1
    }
}
