#!/usr/bin/env bats
# test_1395_cmd_inject_file_cleanup.bats
# Issue #1395: tech-debt: session-comm cmd_inject_file EXIT trap → inline cleanup
#
# AC1: 各 exit 経路の直前に tmux delete-buffer -b "$_buf_name" 2>/dev/null || true が
#      明示的に呼ばれる（inline cleanup ブロック採用）
# AC2: trap "..." EXIT および trap - EXIT の対が削除されている
#      (cmd_inject_file の行番号範囲内に trap.*EXIT が残っていないこと)
# AC3: load-buffer 失敗時・paste-buffer 各 error path（-p 分岐と fallback 分岐）の
#      直前に cleanup ブロックが呼ばれる
# AC5: inject-file 実行後に tmux buffer に session-comm-* という残留 buffer が無い
#      (tmux list-buffers | grep session-comm- で 0 件)
#
# NOTE: AC4 は既存テスト session-comm-robustness.test.sh でカバー済み（スキップ）
# NOTE: source guard 確認:
#       session-comm.sh L539 に `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard が存在する。
#       このファイルは bash "$SCRIPT" で実行（source ではない）ため問題なし。

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
# helper: mock tmux（バッファ追跡付き）
# delete-buffer 呼び出しを call log に記録し、残留バッファを検出できる
# NOTE: 非クォート heredoc で外部変数 $SANDBOX を展開する
# ===========================================================================

_create_mock_tmux_with_buffer_tracking() {
    local mock="$SANDBOX/bin/tmux"
    mkdir -p "$SANDBOX/bin" "$SANDBOX/buffers" "$SANDBOX/targets"
    local call_log="$SANDBOX/tmux_calls.log"
    # 存在する buffer 一覧を $SANDBOX/active_buffers ファイルで管理
    local active_buffers="$SANDBOX/active_buffers"
    touch "$active_buffers"

    # NOTE: 非クォート heredoc — $SANDBOX, $call_log, $active_buffers は parent shell で展開
    cat > "$mock" << MOCK
#!/bin/bash
# すべての呼び出しをログに記録
echo "\$*" >> "${call_log}"

case "\$1" in
    -V)
        echo "tmux 3.4"
        ;;
    has-session)
        exit 0
        ;;
    list-windows)
        echo "session:0 mock-window"
        ;;
    list-buffers)
        # active_buffers ファイル内の各バッファ名を "session-comm-NNN-NNN: N bytes" 形式で出力
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
        shift  # skip "load-buffer"
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                -b) buf_name="\$2"; shift 2 ;;
                *)  file_arg="\$1"; shift ;;
            esac
        done
        if [[ -n "\$buf_name" && -n "\$file_arg" && -f "\$file_arg" ]]; then
            cp "\$file_arg" "${SANDBOX}/buffers/\${buf_name}"
            # アクティブバッファ一覧に追加
            echo "\${buf_name}" >> "${active_buffers}"
        fi
        exit 0
        ;;
    paste-buffer)
        buf_name=""
        target=""
        shift  # skip "paste-buffer"
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
        shift  # skip "delete-buffer"
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                -b) buf_name="\$2"; shift 2 ;;
                *)  shift ;;
            esac
        done
        if [[ -n "\$buf_name" ]]; then
            rm -f "${SANDBOX}/buffers/\${buf_name}"
            # アクティブバッファ一覧から削除
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
    echo "$call_log"
}

# load-buffer を意図的に失敗させる mock
_create_mock_tmux_load_buffer_fail() {
    local mock="$SANDBOX/bin/tmux"
    mkdir -p "$SANDBOX/bin"
    local call_log="$SANDBOX/tmux_calls.log"
    local active_buffers="$SANDBOX/active_buffers"
    touch "$active_buffers"

    cat > "$mock" << MOCK
#!/bin/bash
echo "\$*" >> "${call_log}"
case "\$1" in
    -V)
        echo "tmux 3.4"
        ;;
    has-session)
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
        if [[ -n "\$buf_name" ]]; then
            # バッファを「残留」させる（delete されなければ list-buffers で見える）
            echo "\${buf_name}" >> "${active_buffers}"
        fi
        # load-buffer を失敗させる
        echo "tmux: error: load-buffer failed" >&2
        exit 1
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
            grep -v "^\${buf_name}$" "${active_buffers}" > "${active_buffers}.tmp" 2>/dev/null || true
            mv "${active_buffers}.tmp" "${active_buffers}" 2>/dev/null || true
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK
    chmod +x "$mock"
    echo "$call_log"
}

# paste-buffer を意図的に失敗させる mock（load-buffer は成功、paste-buffer は失敗）
_create_mock_tmux_paste_buffer_fail() {
    local mock="$SANDBOX/bin/tmux"
    mkdir -p "$SANDBOX/bin"
    local call_log="$SANDBOX/tmux_calls.log"
    local active_buffers="$SANDBOX/active_buffers"
    touch "$active_buffers"

    cat > "$mock" << MOCK
#!/bin/bash
echo "\$*" >> "${call_log}"
case "\$1" in
    -V)
        echo "tmux 3.4"
        ;;
    has-session)
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
        exit 0
        ;;
    paste-buffer)
        buf_name=""
        shift
        while [[ \$# -gt 0 ]]; do
            case "\$1" in
                -b) buf_name="\$2"; shift 2 ;;
                *)  shift ;;
            esac
        done
        # paste-buffer を失敗させる（バッファは残留する）
        echo "tmux: error: paste-buffer failed" >&2
        exit 1
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
            grep -v "^\${buf_name}$" "${active_buffers}" > "${active_buffers}.tmp" 2>/dev/null || true
            mv "${active_buffers}.tmp" "${active_buffers}" 2>/dev/null || true
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK
    chmod +x "$mock"
    echo "$call_log"
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
# AC1: inline cleanup — 各 exit 経路直前に delete-buffer が明示的に呼ばれること
# RED: 現在の実装は trap ベースのため、exit 直前に inline delete-buffer がない
# ===========================================================================

@test "ac1[structural][RED]: load-buffer error path 直前に inline delete-buffer コードが存在する" {
    # AC1: load-buffer 失敗 exit 1 の直前に delete-buffer 呼び出しが inline で存在する
    # 現在の実装（trap ベース）は exit 1 の直前に delete-buffer を明示しない → FAIL
    #
    # 検証方法: cmd_inject_file 関数内の load-buffer error block を抽出し、
    # そのブロック内に delete-buffer が inline で存在することを確認する
    #
    # 現在の実装（trap ベース）では以下のパターン:
    #   tmux load-buffer ... || {
    #       echo "Error: ..." >&2
    #       exit 1          ← delete-buffer なし（trap に委任）
    #   }
    #
    # 期待する inline cleanup パターン:
    #   tmux load-buffer ... || {
    #       tmux delete-buffer -b "$_buf_name" 2>/dev/null || true   ← inline cleanup
    #       echo "Error: ..." >&2
    #       exit 1
    #   }

    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    if [[ -z "$start_line" ]]; then
        echo "FAIL: cmd_inject_file() 関数が見つからない" >&2
        return 1
    fi

    # cmd_inject_file 範囲内の load-buffer error ブロックを抽出
    # "tmux load-buffer" 行から最初の閉じ中括弧 "}" まで（error ブロック）
    local load_buffer_block
    load_buffer_block=$(awk "
        NR >= $start_line && NR <= ${end_line:-99999} {
            if (/tmux load-buffer/) { in_block=1 }
            if (in_block) { print }
            if (in_block && /^\s*\}/) { in_block=0 }
        }
    " "$SCRIPT" | head -15)

    # inline cleanup は load-buffer error ブロック内（exit 1 の前）に delete-buffer があること
    # 現在の実装: ブロック内に delete-buffer は存在せず trap に委任 → FAIL
    local has_inline_cleanup
    has_inline_cleanup=$(echo "$load_buffer_block" | awk '
        /delete-buffer/ { has_delete=1 }
        /exit 1/ && has_delete { found=1 }
        END { print found+0 }
    ')

    if [[ "$has_inline_cleanup" -ne 1 ]]; then
        echo "FAIL: cmd_inject_file の load-buffer error block に inline delete-buffer が存在しない" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        echo "  block content:" >&2
        echo "$load_buffer_block" >&2
        return 1
    fi
}

@test "ac1[structural][RED]: paste-buffer (-p) error path 直前に inline delete-buffer コードが存在する" {
    # AC1: paste-buffer -p 分岐の失敗 exit 1 の直前に delete-buffer が inline で存在する
    # 現在の実装では paste-buffer -p の失敗時も trap に委ねる → FAIL

    # paste-buffer -p の error block を抽出（"paste-buffer -b" + "-p" 行から "exit 1" まで）
    local paste_p_block
    paste_p_block=$(awk '/paste-buffer.*-p/{found=1} found && /exit 1/{print; found=0; next} found{print}' "$SCRIPT" | head -20)

    echo "$paste_p_block" | grep -q 'delete-buffer' || {
        echo "FAIL: paste-buffer -p error path に inline delete-buffer が存在しない" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        return 1
    }
}

@test "ac1[structural][RED]: paste-buffer fallback error path 直前に inline delete-buffer コードが存在する" {
    # AC1: paste-buffer fallback 分岐（-p なし）の失敗 exit 1 直前に delete-buffer が存在する
    # 現在の実装では fallback 分岐の失敗時も trap に委ねる → FAIL

    # fallback paste-buffer の error block を探す
    # "-p" を含まない paste-buffer の失敗 exit 1 ブロック
    local fallback_block
    fallback_block=$(awk '
        /paste-buffer -b/ && !/paste-buffer -b.*-p/ { in_fallback=1 }
        in_fallback && /exit 1/ { print; in_fallback=0; next }
        in_fallback { print }
    ' "$SCRIPT" | head -20)

    echo "$fallback_block" | grep -q 'delete-buffer' || {
        echo "FAIL: paste-buffer fallback error path に inline delete-buffer が存在しない" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        return 1
    }
}

# ===========================================================================
# AC2: trap EXIT 対が削除されていること
# RED: 現在の実装に trap "..." EXIT と trap - EXIT が存在する → 以下のテストが FAIL
# ===========================================================================

@test "ac2[structural][RED]: cmd_inject_file の行番号範囲内に 'trap.*EXIT' が存在しない" {
    # AC2: trap "..." EXIT および trap - EXIT の対が削除されていること
    # grep -n "trap.*EXIT" で cmd_inject_file の範囲（L323-L470 付近）に該当行がないこと
    #
    # 現在の実装（L410: trap set, L432: trap reset）があるため FAIL する

    # cmd_inject_file の開始行と終了行を特定
    local start_line end_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)
    # cmd_inject_file の次の関数定義行を終了行とする
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/" "$SCRIPT" | head -1)
    # awk で行番号を取得
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    if [[ -z "$start_line" ]]; then
        echo "FAIL: cmd_inject_file() 関数が見つからない" >&2
        return 1
    fi

    # cmd_inject_file 範囲内の trap.*EXIT 行を抽出
    local trap_lines
    trap_lines=$(awk "NR >= $start_line && NR <= ${end_line:-99999} && /trap.*EXIT/" "$SCRIPT")

    if [[ -n "$trap_lines" ]]; then
        echo "FAIL: cmd_inject_file 範囲内に trap.*EXIT が存在する（削除が必要）" >&2
        echo "  該当行:" >&2
        echo "$trap_lines" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        return 1
    fi
}

@test "ac2[structural][RED]: session-comm.sh 全体で 'trap.*EXIT' が cmd_inject_file 範囲にない（行番号確認）" {
    # AC2 詳細確認: grep -n "trap.*EXIT" の結果が cmd_inject_file (L323-L470 付近) に含まれない
    #
    # 現在の状態:
    #   L410: trap "tmux delete-buffer -b $_buf_name 2>/dev/null || true" EXIT  ← 存在する
    #   L432: trap - EXIT  ← 存在する
    # → このテストは FAIL する

    local trap_in_range
    trap_in_range=$(grep -n 'trap.*EXIT' "$SCRIPT" | awk -F: '$1 >= 323 && $1 <= 470')

    if [[ -n "$trap_in_range" ]]; then
        echo "FAIL: L323-L470 範囲内に trap.*EXIT が存在する" >&2
        echo "  該当行:" >&2
        echo "$trap_in_range" >&2
        echo "  AC2 達成には trap 対を削除し inline cleanup に移行する必要があります" >&2
        return 1
    fi
}

# ===========================================================================
# AC3: 各 error path の直前に cleanup ブロックが呼ばれること
# (load-buffer 失敗時、paste-buffer -p 分岐失敗時、fallback 分岐失敗時)
# RED: 現在の実装では error path で inline cleanup されずに exit する
# ===========================================================================

@test "ac3[functional][RED]: load-buffer 失敗時に buffer が残留しない（inline cleanup 確認）" {
    # AC3: load-buffer 失敗時の error path で buffer が削除されること
    # 現在の実装（trap ベース）では bash -e 環境で trap が発火しない場合がある
    # また、このテストは mock で load-buffer の後 active_buffers に追加 → exit 1 →
    # delete-buffer が呼ばれれば active_buffers から消える仕組み
    #
    # 現在の trap ベース実装は bash "$SCRIPT" として subshell で実行されるため
    # EXIT trap は subshell 内で発火する。このテストでは mock の active_buffers を
    # 確認してバッファ残留を検証する。
    #
    # RED の理由: trap ベース実装では mock の active_buffers に load-buffer 登録時点で
    # バッファが記録されるが、現在の mock では load-buffer が exit 1 する前に
    # buf_name を active_buffers に追加するため、trap が発火しても mock の
    # delete-buffer が呼ばれるかを確認できる。
    # → 実際には trap は機能するが、inline cleanup への移行確認として:
    #   delete-buffer が exit 1 の「直前」（inline）で呼ばれているかをログで確認

    _create_mock_tmux_load_buffer_fail
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    echo -e "line1\nline2\nline3" > "$test_file"

    local exit_code=0
    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null \
        || exit_code=$?

    # load-buffer 失敗なので非ゼロ exit を期待
    [[ "$exit_code" -ne 0 ]] || {
        echo "FAIL: load-buffer 失敗時に exit 0 が返った（テスト設定エラー）" >&2
        return 1
    }

    # inline cleanup の検証: call log に delete-buffer が記録されているか
    local call_log="$SANDBOX/tmux_calls.log"
    [[ -f "$call_log" ]] || {
        echo "FAIL: tmux call log が存在しない（tmux が呼ばれなかった）" >&2
        return 1
    }

    # load-buffer の後、delete-buffer が呼ばれているか（inline cleanup の証拠）
    # 現在の trap ベース実装では: EXIT trap が subshell exit 時に発火するため
    # delete-buffer は「終了後」に呼ばれる可能性がある（inline ではない）
    # inline cleanup なら: load-buffer 呼び出し行の「直後のブロック内」で delete-buffer が記録される
    #
    # このテストの RED 根拠: inline cleanup への移行が完了しているか
    # を load-buffer コードの構造（AC1 の構造テスト）と合わせて確認する。
    # 本テストは「delete-buffer が呼ばれたか」ではなく
    # 「load-buffer 失敗の exit ブロック内に delete-buffer コードが存在するか」で判定
    local load_error_block
    load_error_block=$(awk '/tmux load-buffer/,/^\s*\}/' "$SCRIPT" | head -10)
    echo "$load_error_block" | grep -q 'delete-buffer' || {
        echo "FAIL: load-buffer error block に inline delete-buffer コードが存在しない" >&2
        echo "  block content:" >&2
        echo "$load_error_block" >&2
        return 1
    }
}

@test "ac3[functional][RED]: paste-buffer (-p) 失敗時に buffer が残留しない（inline cleanup 確認）" {
    # AC3: paste-buffer -p 分岐の失敗時に buffer が削除されること
    # 現在の trap ベース実装では、paste-buffer 失敗時の exit 1 直前に inline delete-buffer がない

    _create_mock_tmux_paste_buffer_fail
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    echo -e "line1\nline2\nline3" > "$test_file"

    local exit_code=0
    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null \
        || exit_code=$?

    # paste-buffer 失敗なので非ゼロ exit を期待
    [[ "$exit_code" -ne 0 ]] || {
        echo "FAIL: paste-buffer 失敗時に exit 0 が返った（テスト設定エラー）" >&2
        return 1
    }

    # inline cleanup の構造確認: paste-buffer -p の error block に delete-buffer があるか
    local paste_p_error_block
    paste_p_error_block=$(awk '
        /paste-buffer.*-p.*-t/ { in_block=1 }
        in_block && /exit 1/ { print; in_block=0; next }
        in_block { print }
    ' "$SCRIPT" | head -10)

    echo "$paste_p_error_block" | grep -q 'delete-buffer' || {
        echo "FAIL: paste-buffer -p error block に inline delete-buffer コードが存在しない" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        return 1
    }
}

@test "ac3[functional][RED]: paste-buffer fallback 失敗時に buffer が残留しない（inline cleanup 確認）" {
    # AC3: paste-buffer fallback 分岐（-p なし、tmux < 3.2）の失敗時に buffer が削除されること
    # 現在の trap ベース実装では、fallback 分岐の exit 1 直前に inline delete-buffer がない

    _create_mock_tmux_paste_buffer_fail
    _create_mock_session_state_input_waiting

    # tmux 3.1 を返すよう mock を更新（fallback 分岐を通すため）
    local mock="$SANDBOX/bin/tmux"
    cat > "$mock" << MOCK_FALLBACK
#!/bin/bash
echo "\$*" >> "${SANDBOX}/tmux_calls.log"
case "\$1" in
    -V)
        echo "tmux 3.1"
        ;;
    has-session)
        exit 0
        ;;
    list-windows)
        echo "session:0 mock-window"
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
            echo "\${buf_name}" >> "${SANDBOX}/active_buffers"
        fi
        exit 0
        ;;
    paste-buffer)
        # fallback 分岐（-p なし）も失敗させる
        echo "tmux: error: paste-buffer failed" >&2
        exit 1
        ;;
    delete-buffer)
        buf_name=""
        shift
        while [[ \$# -gt 0 ]]; do
            case "\$1" in -b) buf_name="\$2"; shift 2 ;; *) shift ;; esac
        done
        if [[ -n "\$buf_name" ]]; then
            grep -v "^\${buf_name}$" "${SANDBOX}/active_buffers" > "${SANDBOX}/active_buffers.tmp" 2>/dev/null || true
            mv "${SANDBOX}/active_buffers.tmp" "${SANDBOX}/active_buffers" 2>/dev/null || true
        fi
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
MOCK_FALLBACK
    chmod +x "$mock"
    mkdir -p "$SANDBOX/buffers"
    touch "$SANDBOX/active_buffers"

    local test_file="$SANDBOX/test_content.txt"
    echo -e "line1\nline2\nline3" > "$test_file"

    local exit_code=0
    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null \
        || exit_code=$?

    # paste-buffer 失敗なので非ゼロ exit を期待
    [[ "$exit_code" -ne 0 ]] || {
        echo "FAIL: paste-buffer fallback 失敗時に exit 0 が返った（テスト設定エラー）" >&2
        return 1
    }

    # inline cleanup の構造確認: fallback paste-buffer の error block に delete-buffer があるか
    # fallback 分岐（-p なし）の error ブロックを抽出
    local fallback_error_block
    fallback_error_block=$(awk '
        /paste-buffer -b/ && !/paste-buffer -b.*-p/ && /-t/ { in_block=1 }
        in_block && /exit 1/ { print; in_block=0; next }
        in_block { print }
    ' "$SCRIPT" | head -10)

    echo "$fallback_error_block" | grep -q 'delete-buffer' || {
        echo "FAIL: paste-buffer fallback error block に inline delete-buffer コードが存在しない" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        return 1
    }
}

# ===========================================================================
# AC5: 正常完了後 tmux buffer に session-comm-* 残留バッファがないこと
# RED: 現在の実装は正常完了時に delete-buffer を呼ぶが、
#      trap - EXIT の後に追加クリーンアップが確実でない場合のリグレッションを防ぐ
# このテストは実際の tmux を使わずに mock で検証する
# ===========================================================================

@test "ac5[functional][RED]: 正常完了後に session-comm-* 残留バッファが mock で 0 件" {
    # AC5: inject-file 正常完了後に session-comm-* buffer が残留しないこと
    # mock の active_buffers ファイルで残留バッファを検証
    #
    # 現在の実装（正常パス）:
    #   L431: tmux delete-buffer -b "$_buf_name" 2>/dev/null || true
    #   L432: trap - EXIT
    # これは正常パスでは動作する可能性があるが、
    # inline cleanup への移行確認として active_buffers が空であることを検証する

    local call_log
    call_log=$(_create_mock_tmux_with_buffer_tracking)
    _create_mock_session_state_input_waiting

    local test_file="$SANDBOX/test_content.txt"
    printf 'line1\nline2\nline3\n' > "$test_file"

    PATH="$SANDBOX/bin:$PATH" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/mock_scripts" \
        bash "$SCRIPT" inject-file --no-enter --force "session:0" "$test_file" 2>/dev/null || true

    # mock の active_buffers を確認（残留バッファがないこと）
    local active_buffers="$SANDBOX/active_buffers"
    local remaining_count
    remaining_count=$(grep -c 'session-comm-' "$active_buffers" 2>/dev/null || echo 0)

    if [[ "$remaining_count" -gt 0 ]]; then
        echo "FAIL: inject-file 完了後に session-comm-* 残留バッファが $remaining_count 件存在する" >&2
        echo "  残留バッファ:" >&2
        grep 'session-comm-' "$active_buffers" >&2
        return 1
    fi

    # call log に delete-buffer が記録されていること（cleanup が呼ばれた証拠）
    grep -qF 'delete-buffer' "$call_log" || {
        echo "FAIL: tmux call log に delete-buffer が記録されていない（cleanup が呼ばれなかった）" >&2
        echo "  actual calls:" >&2
        cat "$call_log" >&2
        return 1
    }
}

@test "ac5[structural][RED]: inline cleanup パターンが cmd_inject_file の各 exit 前に揃っている（コード構造確認）" {
    # AC5 補完: 構造チェック
    # cmd_inject_file 関数内の exit 1 の前に delete-buffer 呼び出しがあること
    # 現在の実装では:
    #   - exit 1（load-buffer 失敗）→ delete-buffer なし（trap に委任）
    #   - exit 1（paste-buffer -p 失敗）→ delete-buffer なし（trap に委任）
    #   - exit 1（paste-buffer fallback 失敗）→ delete-buffer なし（trap に委任）
    # inline cleanup 実装後: 全 exit 1 の直前に delete-buffer が存在する
    #
    # テスト方法: cmd_inject_file 関数内の exit 1 の数と、
    # その直前行グループに delete-buffer がある数を比較する

    local start_line
    start_line=$(grep -n '^cmd_inject_file()' "$SCRIPT" | head -1 | cut -d: -f1)

    local end_line
    end_line=$(awk "NR > $start_line && /^[a-z_]+\(\)/ {print NR; exit}" "$SCRIPT")

    local func_body
    func_body=$(awk "NR >= $start_line && NR <= ${end_line:-99999}" "$SCRIPT")

    # error path の exit 1 数（_buf_name 定義後のもの）
    local exit1_count
    exit1_count=$(echo "$func_body" | grep -c 'exit 1' || true)

    # delete-buffer を含む exit ブロック数
    # awk: "delete-buffer" の後に "exit 1" が出現するブロック数
    local cleanup_exit_count
    cleanup_exit_count=$(echo "$func_body" | awk '
        /delete-buffer/ { has_delete=1 }
        /exit 1/ && has_delete { count++; has_delete=0 }
        /^\s*\}/ { has_delete=0 }
        END { print count+0 }
    ')

    if [[ "$cleanup_exit_count" -lt "$exit1_count" ]]; then
        echo "FAIL: exit 1 の数($exit1_count) と inline cleanup 付き exit 1 の数($cleanup_exit_count) が一致しない" >&2
        echo "  inline cleanup が不足している exit 1 が存在します" >&2
        echo "  現在の実装（trap ベース）ではこのテストは FAIL します" >&2
        return 1
    fi
}
