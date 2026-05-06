#!/usr/bin/env bats
# issue-1410-cmdinject-file-session-msg.bats
# Issue #1410: cmd_inject_file が TWILL_MSG_BACKEND を無視（session_msg 未経由）
# Spec: issue-1410
# Coverage: --type=structural,functional

# RED: cmd_inject_file がまだ直接 source backend-tmux.sh + _backend_tmux_send を呼んでいるため FAIL

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
# helper: cmd_inject_file 関数本体のみ抽出（grep 対象）
# ===========================================================================

_extract_cmd_inject_file_body() {
    # NOTE: /^\}/ は行頭の } でマッチするため、cmd_inject_file 内に行頭 } が
    # 追加されると抽出が早期終了し AC1-AC3 が偽陰性になる（issue-1410 時点では非該当）。
    awk '/^cmd_inject_file\(\) *\{/,/^\}/' "$SCRIPT" 2>/dev/null
}

# ===========================================================================
# AC-1: cmd_inject_file が session-comm-backend-tmux.sh を直接 source しない（構造確認）
#
# RED: 現状 cmd_inject_file 本体に source "${SCRIPT_DIR}/session-comm-backend-tmux.sh" があるため FAIL
# ===========================================================================

@test "ac1: cmd_inject_file 関数が session-comm-backend-tmux.sh を直接 source しない" {
    local body
    body=$(_extract_cmd_inject_file_body)

    if echo "$body" | grep -q 'source.*session-comm-backend-tmux\.sh'; then
        echo "FAIL: cmd_inject_file が session-comm-backend-tmux.sh を直接 source している" >&2
        echo "  session_msg send 経由に変更が必要" >&2
        echo "  発見行:" >&2
        echo "$body" | grep 'source.*session-comm-backend-tmux\.sh' | sed 's/^/    /' >&2
        return 1
    fi
}

# ===========================================================================
# AC-2: cmd_inject_file が _backend_tmux_send を直接呼び出さない（構造確認）
#
# RED: 現状 cmd_inject_file 本体に _backend_tmux_send 直呼び出しがあるため FAIL
# ===========================================================================

@test "ac2: cmd_inject_file 関数が _backend_tmux_send を直接呼び出さない" {
    local body
    body=$(_extract_cmd_inject_file_body)

    if echo "$body" | grep -q '_backend_tmux_send'; then
        echo "FAIL: cmd_inject_file が _backend_tmux_send を直接呼び出している" >&2
        echo "  session_msg send 経由に統一が必要（TWILL_MSG_BACKEND を尊重するため）" >&2
        echo "  発見行:" >&2
        echo "$body" | grep '_backend_tmux_send' | sed 's/^/    /' >&2
        return 1
    fi
}

# ===========================================================================
# AC-3: cmd_inject_file 関数の Enter 送出が session_msg send "$target" "" --enter-only 経由（構造確認）
#
# RED: 現状 cmd_inject_file 本体に session_msg 呼び出しがないため FAIL
# ===========================================================================

@test "ac3: cmd_inject_file 関数の Enter 送出が session_msg send --enter-only 経由である" {
    local body
    body=$(_extract_cmd_inject_file_body)

    if ! echo "$body" | grep -q 'session_msg'; then
        echo "FAIL: cmd_inject_file に session_msg 呼び出しが存在しない" >&2
        echo "  session_msg send \"\$target\" \"\" --enter-only に変更が必要" >&2
        return 1
    fi

    # --enter-only フラグが渡されているかも確認
    if ! echo "$body" | grep 'session_msg' | grep -q '\-\-enter-only'; then
        echo "FAIL: cmd_inject_file の session_msg 呼び出しに --enter-only が含まれていない" >&2
        echo "  Enter 送出は session_msg send \"\$target\" \"\" --enter-only で行う必要がある" >&2
        echo "  発見した session_msg 行:" >&2
        echo "$body" | grep 'session_msg' | sed 's/^/    /' >&2
        return 1
    fi
}

# ===========================================================================
# AC-4: TWILL_MSG_BACKEND=mcp 設定時、cmd_inject_file が mcp backend に dispatch される（機能確認）
#
# RED: 現状 cmd_inject_file は TWILL_MSG_BACKEND を無視して tmux backend を直接呼ぶため FAIL
# ===========================================================================

@test "ac4: TWILL_MSG_BACKEND=mcp で cmd_inject_file が mcp backend に dispatch される" {
    local mock_mcp="$SANDBOX/mock-mcp-called"
    local test_file="$SANDBOX/test-input.txt"
    echo "hello from file" > "$test_file"

    # sandbox: SANDBOX/scripts/ に必要ファイルを配置（本番ファイルに一切触れない）
    mkdir -p "$SANDBOX/scripts" "$SANDBOX/bin"
    cp "$PLUGIN_ROOT/scripts/session-comm-backend-tmux.sh" "$SANDBOX/scripts/"

    # mock session-state.sh: always input-waiting
    cat > "$SANDBOX/scripts/session-state.sh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then echo "input-waiting"; fi
exit 0
EOF
    chmod +x "$SANDBOX/scripts/session-state.sh"

    # mock mcp backend を SANDBOX/scripts/ に配置（本番には一切触れない）
    local sandbox_mcp="$SANDBOX/scripts/session-comm-backend-mcp.sh"
    cat > "$sandbox_mcp" <<EOF
#!/usr/bin/env bash
_backend_mcp_send() {
    echo "mcp-backend-called" > "${mock_mcp}"
    return 0
}
_backend_shadow_send() {
    echo "shadow-backend-called" > "${mock_mcp}"
    return 0
}
EOF
    chmod +x "$sandbox_mcp"

    # mock tmux: list-windows + load-buffer/paste-buffer
    # send-keys が呼ばれたら FAIL（mcp backend 経由になるべき）
    cat > "$SANDBOX/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    list-windows) echo "testsession:0 main" ;;
    has-session)  exit 0 ;;
    load-buffer)  exit 0 ;;
    paste-buffer) exit 0 ;;
    delete-buffer) exit 0 ;;
    -V) echo "tmux 3.3" ;;
    send-keys)
        echo "FAIL: tmux send-keys was called directly (should go through session_msg -> mcp backend)" >&2
        exit 1
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$SANDBOX/bin/tmux"

    # _TEST_MODE + SESSION_COMM_SCRIPT_DIR で sandbox を参照（本番ファイルに触れない）
    PATH="$SANDBOX/bin:$PATH" \
    SESSION_COMM_LOCK_DIR="/tmp" \
    _TEST_MODE=1 \
    SESSION_COMM_SCRIPT_DIR="$SANDBOX/scripts" \
    TWILL_MSG_BACKEND=mcp \
    bash "$SCRIPT" inject-file "main" "$test_file" --force 2>/dev/null || true

    if [[ ! -f "$mock_mcp" ]]; then
        echo "FAIL: TWILL_MSG_BACKEND=mcp を設定しても mcp backend が呼ばれなかった" >&2
        echo "  cmd_inject_file が TWILL_MSG_BACKEND を無視して tmux backend を直呼びしている可能性" >&2
        return 1
    fi
}

# ===========================================================================
# AC-5: TWILL_MSG_BACKEND=tmux（デフォルト）で cmd_inject_file が tmux backend を呼ぶ（後退確認）
#
# RED: session_msg 経由の dispatch が未実装のため、tmux send-keys（Enter 送出）が到達しない
# ===========================================================================

@test "ac5: TWILL_MSG_BACKEND=tmux（デフォルト）で cmd_inject_file が tmux send-keys を実行する" {
    local sent_file="$SANDBOX/tmux-sent"

    mkdir -p "$SANDBOX/bin"

    # テスト対象ファイルを作成（inject-file には実ファイルが必要）
    local test_file="$SANDBOX/test-input.txt"
    echo "hello from file" > "$test_file"

    # mock session-state.sh: always input-waiting
    cat > "$SANDBOX/bin/session-state.sh" <<'EOF'
#!/usr/bin/env bash
echo "input-waiting"
exit 0
EOF
    chmod +x "$SANDBOX/bin/session-state.sh"

    # mock tmux: list-windows で resolve_target が期待する形式
    # load-buffer/paste-buffer（AC6: paste-buffer フロー維持）+ send-keys 記録
    cat > "$SANDBOX/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    list-windows) echo "testsession:0 main" ;;
    has-session)  exit 0 ;;
    load-buffer)  exit 0 ;;
    paste-buffer) exit 0 ;;
    delete-buffer) exit 0 ;;
    -V) echo "tmux 3.3" ;;
    send-keys)
        echo "\$@" > "${sent_file}"
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$SANDBOX/bin/tmux"

    PATH="$SANDBOX/bin:$PATH" \
    SESSION_COMM_LOCK_DIR="/tmp" \
    TWILL_MSG_BACKEND=tmux \
    bash "$SCRIPT" inject-file "main" "$test_file" --force 2>/dev/null || true

    if [[ ! -f "$sent_file" ]]; then
        echo "FAIL: TWILL_MSG_BACKEND=tmux で tmux send-keys が呼ばれなかった" >&2
        echo "  後退: tmux backend 経由の基本動作（Enter 送出）が壊れている可能性" >&2
        return 1
    fi
}

# ===========================================================================
# AC-6: paste-buffer によるファイル内容送出フローが維持されている（非回帰確認）
#
# paste-buffer 経由のファイル送達 + Enter 送出の二段階フローが維持されていること
# ===========================================================================

@test "ac6: paste-buffer によるファイル内容送出フローが維持されている" {
    local paste_called="$SANDBOX/paste-buffer-called"
    local send_keys_called="$SANDBOX/send-keys-called"

    mkdir -p "$SANDBOX/bin"

    # テスト対象ファイルを作成
    local test_file="$SANDBOX/test-input.txt"
    printf "line1\nline2\nline3\n" > "$test_file"

    # mock session-state.sh: always input-waiting
    cat > "$SANDBOX/bin/session-state.sh" <<'EOF'
#!/usr/bin/env bash
echo "input-waiting"
exit 0
EOF
    chmod +x "$SANDBOX/bin/session-state.sh"

    # mock tmux: paste-buffer 呼び出しを記録
    # load-buffer と paste-buffer が両方呼ばれることを確認（二段階フロー）
    cat > "$SANDBOX/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    list-windows) echo "testsession:0 main" ;;
    has-session)  exit 0 ;;
    load-buffer)  exit 0 ;;
    paste-buffer)
        echo "\$@" > "${paste_called}"
        exit 0
        ;;
    delete-buffer) exit 0 ;;
    -V) echo "tmux 3.3" ;;
    send-keys)
        echo "\$@" > "${send_keys_called}"
        exit 0
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$SANDBOX/bin/tmux"

    PATH="$SANDBOX/bin:$PATH" \
    SESSION_COMM_LOCK_DIR="/tmp" \
    TWILL_MSG_BACKEND=tmux \
    bash "$SCRIPT" inject-file "main" "$test_file" --force 2>/dev/null || true

    # paste-buffer が呼ばれたこと（ファイル内容送達フロー）
    if [[ ! -f "$paste_called" ]]; then
        echo "FAIL: paste-buffer が呼ばれなかった" >&2
        echo "  AC6 違反: paste-buffer によるファイル内容送出フローが維持されていない" >&2
        return 1
    fi

    # send-keys が呼ばれたこと（Enter 送出フロー）
    if [[ ! -f "$send_keys_called" ]]; then
        echo "FAIL: paste-buffer 後に Enter 送出（tmux send-keys）が呼ばれなかった" >&2
        echo "  AC6 違反: paste-buffer 経由のファイル送達 + Enter 送出の二段階フローが壊れている" >&2
        return 1
    fi
}
