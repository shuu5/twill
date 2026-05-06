#!/usr/bin/env bats
# test_1424_bats_ac4_sandbox.bats
# Issue #1424: tech-debt(test): bats AC4 で session-comm-backend-mcp.sh を直接上書き
#              — SIGKILL 時モック残留リスク
#
# 修正方針: session-comm.sh の _TEST_MODE + SESSION_COMM_SCRIPT_DIR 機構で sandbox 化し、
#           本番ファイル plugins/session/scripts/session-comm-backend-mcp.sh に一切触れない。
#
# AC1: issue-1410 bats ファイルに git grep -nE '(cp|cat>).*session-comm-backend-mcp.sh' がマッチしない
# AC2: issue-1404 bats ファイルについて AC1 同様
# AC3: 両 bats 実行で全 11 ケース PASS すること（issue-1410: 6件, issue-1404: 5件）
# AC4: 両 bats 実行前後で sha256sum plugins/session/scripts/session-comm-backend-mcp.sh が一致
# AC5: grep -n BACKEND_MCP_BAK が両ファイルでマッチしないこと

# ===========================================================================
# setup / teardown
# ===========================================================================

setup() {
    PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    BATS_1410="$PLUGIN_ROOT/tests/issue-1410-cmdinject-file-session-msg.bats"
    BATS_1404="$PLUGIN_ROOT/tests/issue-1404-cmdinject-session-msg.bats"
    BACKEND_MCP="$PLUGIN_ROOT/scripts/session-comm-backend-mcp.sh"
    export PLUGIN_ROOT BATS_1410 BATS_1404 BACKEND_MCP
}

teardown() {
    : # no-op: このテストファイル自体は本番ファイルに触れない
}

# ===========================================================================
# AC1: issue-1410 bats ファイルに本番 mcp backend への直接 cp/cat> がないこと
#
# guardrail テスト: 現在は変数 $backend_mcp 経由のため NO MATCH（PASS）
# Fix 後も sandbox 化により本番ファイルへの cp/cat> が存在しないことを継続確認する
#
# 注意: この AC は "現在も PASS" だが Fix 前後で意味が変わる。
# Fix 前: 変数経由のため grep がマッチしないだけで実態は本番ファイルに触れている
# Fix 後: sandbox 化により本当に本番ファイルに触れない設計になっているはずで PASS 維持
# ===========================================================================

@test "ac1: issue-1410 bats に本番 mcp backend への直接 cp/cat> がないこと（guardrail）" {
    # git grep パターン: 引用符付き・なし両パターンを検出
    if git -C "$PLUGIN_ROOT" grep -nE \
        '(cp[[:space:]]|cat[[:space:]]+>[[:space:]]*)"?[^"]*/?session-comm-backend-mcp\.sh' \
        "tests/issue-1410-cmdinject-file-session-msg.bats" 2>/dev/null; then
        echo "FAIL: issue-1410 bats に本番 session-comm-backend-mcp.sh への直接 cp/cat> が存在する" >&2
        echo "  Fix: SESSION_COMM_SCRIPT_DIR sandbox 経由に変更が必要" >&2
        return 1
    fi
}

# ===========================================================================
# AC2: issue-1404 bats ファイルに本番 mcp backend への直接 cp/cat> がないこと
#
# AC1 同様の guardrail テスト
# ===========================================================================

@test "ac2: issue-1404 bats に本番 mcp backend への直接 cp/cat> がないこと（guardrail）" {
    if git -C "$PLUGIN_ROOT" grep -nE \
        '(cp[[:space:]]|cat[[:space:]]+>[[:space:]]*)"?[^"]*/?session-comm-backend-mcp\.sh' \
        "tests/issue-1404-cmdinject-session-msg.bats" 2>/dev/null; then
        echo "FAIL: issue-1404 bats に本番 session-comm-backend-mcp.sh への直接 cp/cat> が存在する" >&2
        echo "  Fix: SESSION_COMM_SCRIPT_DIR sandbox 経由に変更が必要" >&2
        return 1
    fi
}

# ===========================================================================
# AC3: 両 bats 実行で全 11 ケース PASS すること
#
# RED: 現状 issue-1410 ac4 / issue-1404 ac4 が SESSION_COMM_SCRIPT_DIR sandbox を
#      使っていないため FAIL（本番ファイルに触れない sandbox 未実装）
# Fix 後: SESSION_COMM_SCRIPT_DIR sandbox 化で全 11 ケース GREEN になるはず
# ===========================================================================

@test "ac3: 両 bats 実行で全 11 ケース PASS すること（issue-1410: 6件, issue-1404: 5件）" {
    # RED: sandbox 未実装のため issue-1410 ac4 / issue-1404 ac4 が FAIL する
    # Fix 後は SESSION_COMM_SCRIPT_DIR sandbox を使い全ケース PASS となるはず

    local bats_bin
    bats_bin="$(command -v bats 2>/dev/null || true)"
    if [[ -z "$bats_bin" ]]; then
        echo "SKIP: bats コマンドが見つからない" >&2
        return 1
    fi

    local output_file
    output_file="$(mktemp)"

    # 両ファイルをまとめて実行し exit code を確認
    if ! "$bats_bin" "$BATS_1410" "$BATS_1404" > "$output_file" 2>&1; then
        echo "FAIL: 両 bats を実行した結果、FAIL したケースが存在する" >&2
        echo "--- bats output ---" >&2
        cat "$output_file" >&2
        echo "-------------------" >&2
        rm -f "$output_file"
        return 1
    fi

    local pass_count
    pass_count=$(grep -c '^ok ' "$output_file" 2>/dev/null || echo 0)

    rm -f "$output_file"

    if [[ "$pass_count" -lt 11 ]]; then
        echo "FAIL: PASS ケース数が 11 未満（actual: $pass_count）" >&2
        echo "  issue-1410: 6 ケース（ac1〜ac6）, issue-1404: 5 ケース（ac1〜ac5）が全て PASS 必要" >&2
        return 1
    fi
}

# ===========================================================================
# AC4: 両 bats 実行前後で session-comm-backend-mcp.sh の sha256sum が一致すること
#
# RED: 現状 ac4 テスト（1404/1410 両ファイル）が BACKEND_MCP_BAK パターンで
#      本番ファイルを cp・cat > で上書きする。SIGKILL 時に teardown が呼ばれず
#      モック状態のまま残る = sha256sum が変わる可能性がある。
# Fix 後: SESSION_COMM_SCRIPT_DIR sandbox で本番ファイルに触れないため sha256sum 一致
# ===========================================================================

@test "ac4: 両 bats 実行前後で session-comm-backend-mcp.sh の sha256sum が一致すること" {
    # RED: 現状は BACKEND_MCP_BAK パターンで本番ファイルを上書きするリスクがある
    # この自体のテストは「正常終了時でも sha256sum が変わっていないか」を確認する

    local bats_bin
    bats_bin="$(command -v bats 2>/dev/null || true)"
    if [[ -z "$bats_bin" ]]; then
        echo "SKIP: bats コマンドが見つからない" >&2
        return 1
    fi

    if [[ ! -f "$BACKEND_MCP" ]]; then
        echo "FAIL: session-comm-backend-mcp.sh が見つからない: $BACKEND_MCP" >&2
        return 1
    fi

    # 実行前のハッシュ
    local hash_before
    hash_before=$(sha256sum "$BACKEND_MCP" | awk '{print $1}')

    # 両 bats を実行（exit code は無視 - テスト失敗は別 AC3 で確認）
    "$bats_bin" "$BATS_1410" "$BATS_1404" > /dev/null 2>&1 || true

    # 実行後のハッシュ
    local hash_after
    hash_after=$(sha256sum "$BACKEND_MCP" | awk '{print $1}')

    if [[ "$hash_before" != "$hash_after" ]]; then
        echo "FAIL: bats 実行後に session-comm-backend-mcp.sh の sha256sum が変化した" >&2
        echo "  before: $hash_before" >&2
        echo "  after:  $hash_after" >&2
        echo "  BACKEND_MCP_BAK パターンの teardown が正常に復元できなかった可能性" >&2
        echo "  Fix: SESSION_COMM_SCRIPT_DIR sandbox 化で本番ファイルに触れないようにする" >&2
        # sha256sum が変化した場合は本番ファイルが壊れているため即時 FAIL
        return 1
    fi
}

# ===========================================================================
# AC5: 両 bats ファイルに BACKEND_MCP_BAK ハンドリングが残っていないこと
#
# RED: 現状 grep -n BACKEND_MCP_BAK が両ファイルでマッチする（各 9 箇所）
# Fix 後: SESSION_COMM_SCRIPT_DIR sandbox 化により BACKEND_MCP_BAK が不要になり削除される
# ===========================================================================

@test "ac5: issue-1410 bats に BACKEND_MCP_BAK ハンドリングが残っていないこと" {
    # RED: 現在 BACKEND_MCP_BAK が存在するため FAIL
    local matches
    matches=$(grep -n 'BACKEND_MCP_BAK' "$BATS_1410" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        echo "FAIL: issue-1410 bats に BACKEND_MCP_BAK が残存している" >&2
        echo "$matches" | sed 's/^/  /' >&2
        echo "  Fix: setup()/teardown() の BACKEND_MCP_BAK ハンドリングを削除し" >&2
        echo "       SESSION_COMM_SCRIPT_DIR sandbox 化に移行する" >&2
        return 1
    fi
}

@test "ac5: issue-1404 bats に BACKEND_MCP_BAK ハンドリングが残っていないこと" {
    # RED: 現在 BACKEND_MCP_BAK が存在するため FAIL
    local matches
    matches=$(grep -n 'BACKEND_MCP_BAK' "$BATS_1404" 2>/dev/null || true)
    if [[ -n "$matches" ]]; then
        echo "FAIL: issue-1404 bats に BACKEND_MCP_BAK が残存している" >&2
        echo "$matches" | sed 's/^/  /' >&2
        echo "  Fix: setup()/teardown() の BACKEND_MCP_BAK ハンドリングを削除し" >&2
        echo "       SESSION_COMM_SCRIPT_DIR sandbox 化に移行する" >&2
        return 1
    fi
}
