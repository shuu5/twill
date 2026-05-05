#!/usr/bin/env bats
# issue-1404-cmdinject-session-msg.bats
# Issue #1404: cmd_inject が TWILL_MSG_BACKEND を無視する — session_msg 経由への統一
# Spec: issue-1404
# Coverage: --type=structural,functional

# RED: cmd_inject がまだ直接 source backend-tmux.sh + _backend_tmux_send を呼んでいるため FAIL

setup() {
    PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    SCRIPT="$PLUGIN_ROOT/scripts/session-comm.sh"
    SANDBOX="$(mktemp -d)"
    BACKEND_MCP_BAK=""  # ac4 で設定。teardown が安全ネットとして復元
    export SANDBOX SCRIPT PLUGIN_ROOT BACKEND_MCP_BAK
}

teardown() {
    # ac4: 本番 backend-mcp.sh が上書きされた場合の安全ネット復元
    if [[ -n "${BACKEND_MCP_BAK:-}" && -f "$BACKEND_MCP_BAK" ]]; then
        local backend_mcp="$PLUGIN_ROOT/scripts/session-comm-backend-mcp.sh"
        mv "$BACKEND_MCP_BAK" "$backend_mcp"
    fi
    [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
}

# ===========================================================================
# helper: cmd_inject 関数本体のみ抽出（setup/teardown 外の grep 対象）
# ===========================================================================

_extract_cmd_inject_body() {
    # cmd_inject() { ... } の本体のみ抽出（次の空行 or 次の関数定義まで）
    awk '/^cmd_inject\(\) *\{/,/^\}/' "$SCRIPT" 2>/dev/null
}

# ===========================================================================
# AC-1: cmd_inject が session-comm-backend-tmux.sh を直接 source しない（構造確認）
#
# RED: 現状 cmd_inject 本体に source "${SCRIPT_DIR}/session-comm-backend-tmux.sh" があるため FAIL
# ===========================================================================

@test "ac1: cmd_inject 関数が session-comm-backend-tmux.sh を直接 source しない" {
    local body
    body=$(_extract_cmd_inject_body)

    if echo "$body" | grep -q 'source.*session-comm-backend-tmux\.sh'; then
        echo "FAIL: cmd_inject が session-comm-backend-tmux.sh を直接 source している" >&2
        echo "  session_msg send 経由に変更が必要" >&2
        echo "  発見行:" >&2
        echo "$body" | grep 'source.*session-comm-backend-tmux\.sh' | sed 's/^/    /' >&2
        return 1
    fi
}

# ===========================================================================
# AC-2: cmd_inject が _backend_tmux_send を直接呼び出さない（構造確認）
#
# RED: 現状 cmd_inject 本体に _backend_tmux_send 直呼び出しがあるため FAIL
# ===========================================================================

@test "ac2: cmd_inject 関数が _backend_tmux_send を直接呼び出さない" {
    local body
    body=$(_extract_cmd_inject_body)

    if echo "$body" | grep -q '_backend_tmux_send'; then
        echo "FAIL: cmd_inject が _backend_tmux_send を直接呼び出している" >&2
        echo "  session_msg send 経由に統一が必要（TWILL_MSG_BACKEND を尊重するため）" >&2
        echo "  発見行:" >&2
        echo "$body" | grep '_backend_tmux_send' | sed 's/^/    /' >&2
        return 1
    fi
}

# ===========================================================================
# AC-3: cmd_inject 関数が session_msg を呼び出す（構造確認）
#
# RED: 現状 cmd_inject 本体に session_msg 呼び出しがないため FAIL
# ===========================================================================

@test "ac3: cmd_inject 関数が session_msg send を経由する" {
    local body
    body=$(_extract_cmd_inject_body)

    if ! echo "$body" | grep -q 'session_msg'; then
        echo "FAIL: cmd_inject に session_msg 呼び出しが存在しない" >&2
        echo "  session_msg send <target> <text> [--no-enter] に変更が必要" >&2
        return 1
    fi
}

# ===========================================================================
# AC-4: TWILL_MSG_BACKEND=mcp 設定時、cmd_inject が mcp backend を呼ぶ（機能確認）
#
# RED: 現状 cmd_inject は TWILL_MSG_BACKEND を無視して tmux backend を直接呼ぶため FAIL
# ===========================================================================

@test "ac4: TWILL_MSG_BACKEND=mcp で cmd_inject が mcp backend に dispatch される" {
    mkdir -p "$SANDBOX/bin"

    # mock session-state.sh: always input-waiting
    cat > "$SANDBOX/bin/session-state.sh" <<'EOF'
#!/usr/bin/env bash
echo "input-waiting"
exit 0
EOF
    chmod +x "$SANDBOX/bin/session-state.sh"

    # mock tmux: list-windows -a -F で resolve_target が期待する形式を返す
    cat > "$SANDBOX/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    list-windows) echo "testsession:0 main" ;;
    has-session)  exit 0 ;;
    send-keys)
        echo "FAIL: tmux send-keys was called directly (should go through session_msg → mcp backend)" >&2
        exit 1
        ;;
    *) exit 0 ;;
esac
EOF
    chmod +x "$SANDBOX/bin/tmux"

    # mock session-comm-backend-mcp.sh: call を記録して成功
    local backend_mcp="$PLUGIN_ROOT/scripts/session-comm-backend-mcp.sh"
    local mock_mcp="$SANDBOX/mock-mcp-called"
    # teardown 安全ネット用バックアップ（bats kill 時でも復元される）
    BACKEND_MCP_BAK="$SANDBOX/session-comm-backend-mcp.sh.bak"
    [[ -f "$backend_mcp" ]] && cp "$backend_mcp" "$BACKEND_MCP_BAK"

    cat > "$backend_mcp" <<EOF
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

    # --force: state チェックをスキップ（session-state.sh は SCRIPT_DIR 絶対パス呼出のため PATH mock 非介入）
    PATH="$SANDBOX/bin:$PATH" \
    SESSION_COMM_LOCK_DIR="/tmp" \
    TWILL_MSG_BACKEND=mcp \
    bash "$SCRIPT" inject "main" "hello" --force 2>/dev/null || true

    # backend-mcp.sh を復元（teardown も安全ネットとして同じ復元を行う）
    if [[ -f "$BACKEND_MCP_BAK" ]]; then
        mv "$BACKEND_MCP_BAK" "$backend_mcp"
    else
        rm -f "$backend_mcp"
    fi
    BACKEND_MCP_BAK=""

    if [[ ! -f "$mock_mcp" ]]; then
        echo "FAIL: TWILL_MSG_BACKEND=mcp を設定しても mcp backend が呼ばれなかった" >&2
        echo "  cmd_inject が TWILL_MSG_BACKEND を無視して tmux backend を直呼びしている可能性" >&2
        return 1
    fi
}

# ===========================================================================
# AC-5: TWILL_MSG_BACKEND=tmux（デフォルト）で cmd_inject が tmux backend を呼ぶ（後退確認）
#
# RED: session_msg 経由の dispatch が未実装のため挙動変化で確認困難だが、
#      session_msg 関数定義後は tmux backend が呼ばれるはず
# ===========================================================================

@test "ac5: TWILL_MSG_BACKEND=tmux（デフォルト）で cmd_inject が tmux send-keys を実行する" {
    local sent_file="$SANDBOX/tmux-sent"

    mkdir -p "$SANDBOX/bin"

    # mock session-state.sh: always input-waiting
    cat > "$SANDBOX/bin/session-state.sh" <<'EOF'
#!/usr/bin/env bash
echo "input-waiting"
exit 0
EOF
    chmod +x "$SANDBOX/bin/session-state.sh"

    # mock tmux: list-windows -a -F で resolve_target が期待する形式 + send-keys 記録
    cat > "$SANDBOX/bin/tmux" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
    list-windows) echo "testsession:0 main" ;;
    has-session)  exit 0 ;;
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
    bash "$SCRIPT" inject "main" "hello" --force 2>/dev/null || true

    if [[ ! -f "$sent_file" ]]; then
        echo "FAIL: TWILL_MSG_BACKEND=tmux で tmux send-keys が呼ばれなかった" >&2
        echo "  後退: tmux backend 経由の基本動作が壊れている可能性" >&2
        return 1
    fi
}
