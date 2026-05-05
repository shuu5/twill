#!/usr/bin/env bats
# issue-1032-session-comm-strategy.bats
# Requirement: session-comm Strategy pattern (Issue #1032)
#   refactor(session-comm) -- Strategy pattern で backend 切替可能化 [Tier B]
#
# Coverage: --type=integration --coverage=functional,structural
#
# RED テスト: 実装前の現在状態では全件 FAIL することを意図する

setup() {
    PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
    REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
    SESSION_COMM_SCRIPT="$PLUGIN_ROOT/scripts/session-comm.sh"
    SANDBOX="$(mktemp -d)"
    export PLUGIN_ROOT REPO_ROOT SESSION_COMM_SCRIPT SANDBOX
}

teardown() {
    [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]] && rm -rf "$SANDBOX"
}

# ===========================================================================
# AC-1: production caller 全件が session_msg API 経由に migrate 済
#   grep -rn "tmux send-keys" plugins/{twl,session}/{scripts,skills}/ --exclude-dir=tests
#   で whitelist 記載のみ
#
# Whitelist (実装後も残存が許可される):
#   - plugins/session/scripts/session-comm-backend-tmux.sh (backend 実装自体)
#   - budget-detect.sh の Escape/kill-window 系（セッション制御用途）
#   - observer-auto-inject.sh（メニュー選択UI用途）
#
# RED: session-comm.sh 本体にまだ tmux send-keys が存在するため FAIL
# ===========================================================================

@test "ac1: session-comm.sh に tmux send-keys の直呼び出しが存在しない（whitelist: backend-tmux.sh のみ）" {
    # 実装後は tmux send-keys は session-comm-backend-tmux.sh にのみ存在するはず
    # 実装前は session-comm.sh 本体 L304, L310, L433 に存在するため FAIL
    local found
    found=$(grep -n "tmux send-keys" "$SESSION_COMM_SCRIPT" 2>/dev/null || true)
    if [[ -n "$found" ]]; then
        echo "FAIL: session-comm.sh に tmux send-keys の直呼び出しが存在する（session_msg 経由への migrate が未完了）" >&2
        echo "  発見箇所:" >&2
        echo "$found" | sed 's/^/    /' >&2
        return 1
    fi
}

@test "ac1: session-comm-backend-tmux.sh が存在する（whitelist として）" {
    # 実装後は backend スクリプトが存在するはず
    # 実装前は未存在のため FAIL
    local backend_script="$PLUGIN_ROOT/scripts/session-comm-backend-tmux.sh"
    if [[ ! -f "$backend_script" ]]; then
        echo "FAIL: session-comm-backend-tmux.sh が存在しない（未実装）" >&2
        echo "  expected: $backend_script" >&2
        return 1
    fi
}

# ===========================================================================
# AC-2: bidirectional 通信が並列 100 msg で損失ゼロ
#   mailbox jsonl atomic append 検証、stress test
#
# RED: session_msg 関数が session-comm.sh に存在しないため FAIL
# ===========================================================================

@test "ac2: session-comm.sh に session_msg 関数が定義されている" {
    # 実装後は session_msg 関数が session-comm.sh に存在するはず
    # 実装前は存在しないため FAIL
    if ! grep -qE '^session_msg\(\)|^function session_msg' "$SESSION_COMM_SCRIPT"; then
        echo "FAIL: session-comm.sh に session_msg 関数が定義されていない（未実装）" >&2
        return 1
    fi
}

@test "ac2: session_msg が mailbox jsonl への atomic append をサポートしている（構造確認）" {
    # 実装後は mailbox jsonl への atomic append (flock + >>)が存在するはず
    # session_msg 関数内または session-comm-backend-mcp.sh に flock + jsonl append が必要
    local mailbox_backend="$PLUGIN_ROOT/scripts/session-comm-backend-mcp.sh"
    if [[ ! -f "$mailbox_backend" ]]; then
        echo "FAIL: session-comm-backend-mcp.sh が存在しない（mailbox backend 未実装）" >&2
        return 1
    fi
    if ! grep -q "flock" "$mailbox_backend" && ! grep -q "flock" "$SESSION_COMM_SCRIPT"; then
        echo "FAIL: mailbox jsonl への atomic append (flock) が見つからない" >&2
        return 1
    fi
}

# ===========================================================================
# AC-3: bats integration test PASS、CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 でも動作
#   AT 非依存性
#
# RED: session_msg 関数が未実装のため、AT=0 での動作確認が不可能
# ===========================================================================

@test "ac3: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 で session_msg が関数として呼び出し可能" {
    # 実装後は AT 非依存で session_msg が動作するはず
    # 実装前は session_msg が未定義のため FAIL
    local exit_code=0
    CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 bash -c "
        source \"$SESSION_COMM_SCRIPT\" 2>/dev/null
        if ! declare -f session_msg >/dev/null 2>&1; then
            echo 'session_msg not defined' >&2
            exit 1
        fi
        echo 'ok'
    " || exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        echo "FAIL: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 で session_msg が呼び出し可能でない（未実装）" >&2
        return 1
    fi
}

# ===========================================================================
# AC-4: backend 切替 (TWILL_MSG_BACKEND={tmux,mcp}) で同 test PASS
#
# RED: TWILL_MSG_BACKEND の dispatch logic が未実装のため FAIL
# ===========================================================================

@test "ac4: TWILL_MSG_BACKEND=tmux のとき session-comm-backend-tmux.sh が dispatch される（構造確認）" {
    # 実装後は session-comm.sh に TWILL_MSG_BACKEND に基づく dispatch logic が存在するはず
    # 実装前は TWILL_MSG_BACKEND の参照がないため FAIL
    if ! grep -q "TWILL_MSG_BACKEND" "$SESSION_COMM_SCRIPT"; then
        echo "FAIL: session-comm.sh に TWILL_MSG_BACKEND の参照がない（dispatch 未実装）" >&2
        return 1
    fi
}

@test "ac4: TWILL_MSG_BACKEND=mcp のとき session-comm-backend-mcp.sh が dispatch される（構造確認）" {
    # 実装後は session-comm-backend-mcp.sh が存在し dispatch される
    # 実装前は backend スクリプトが存在しないため FAIL
    local backend_mcp="$PLUGIN_ROOT/scripts/session-comm-backend-mcp.sh"
    if [[ ! -f "$backend_mcp" ]]; then
        echo "FAIL: session-comm-backend-mcp.sh が存在しない（mcp backend 未実装）" >&2
        return 1
    fi
}

@test "ac4: session-comm.sh の TWILL_MSG_BACKEND dispatch が tmux と mcp の両方を処理する" {
    # 実装後は case 文または if-elif で tmux/mcp の両方が dispatch されるはず
    # 実装前は dispatch logic 自体が未実装のため FAIL
    local has_tmux_dispatch=0
    local has_mcp_dispatch=0
    grep -q "tmux" "$SESSION_COMM_SCRIPT" && has_tmux_dispatch=1 || true
    grep -q "mcp" "$SESSION_COMM_SCRIPT" && has_mcp_dispatch=1 || true

    # TWILL_MSG_BACKEND コンテキスト内の dispatch である必要がある
    if ! grep -A5 "TWILL_MSG_BACKEND" "$SESSION_COMM_SCRIPT" 2>/dev/null | grep -q "tmux\|backend-tmux"; then
        echo "FAIL: TWILL_MSG_BACKEND=tmux の dispatch が session-comm.sh に存在しない" >&2
        return 1
    fi
    if ! grep -A5 "TWILL_MSG_BACKEND" "$SESSION_COMM_SCRIPT" 2>/dev/null | grep -q "mcp\|backend-mcp"; then
        echo "FAIL: TWILL_MSG_BACKEND=mcp の dispatch が session-comm.sh に存在しない" >&2
        return 1
    fi
}

# ===========================================================================
# AC-5: shadow mode で mismatch 0 件を 1 週間維持
#   mcp-shadow-compare.sh exit 0 を 7 日連続、判定基準: 出力に mismatch_count: 0 が含まれること
#
# RED: mcp-shadow-compare.sh が mismatch_count: 0 を出力しない（現在は MISMATCH_COUNT 変数のみ）
#      かつ mcp_with_fallback backend が未実装のため FAIL
# ===========================================================================

@test "ac5: mcp-shadow-compare.sh が存在する" {
    # 実装前後ともに存在するため PASS するが、出力フォーマット確認で FAIL する
    local shadow_script="$REPO_ROOT/plugins/twl/scripts/mcp-shadow-compare.sh"
    if [[ ! -f "$shadow_script" ]]; then
        echo "FAIL: mcp-shadow-compare.sh が存在しない" >&2
        return 1
    fi
}

@test "ac5: mcp-shadow-compare.sh が mismatch_count: 0 を出力する（判定基準形式）" {
    # AC-5 判定基準: 出力に mismatch_count: 0 が含まれること
    # 実装前は MISMATCH_COUNT 変数のみで mismatch_count: 0 形式の出力がないため FAIL
    local shadow_script="$REPO_ROOT/plugins/twl/scripts/mcp-shadow-compare.sh"
    local empty_log="$SANDBOX/empty-shadow.jsonl"
    touch "$empty_log"

    local output
    output=$("$shadow_script" --log-file "$empty_log" 2>&1 || true)
    if ! echo "$output" | grep -q "mismatch_count: 0"; then
        echo "FAIL: mcp-shadow-compare.sh の出力に 'mismatch_count: 0' が含まれない（フォーマット未実装）" >&2
        echo "  実際の出力: $output" >&2
        return 1
    fi
}

@test "ac5: session-comm-backend-mcp.sh に mcp_with_fallback backend が実装されている（構造確認）" {
    # 実装後は mcp_with_fallback backend が session-comm-backend-mcp.sh に存在するはず
    # 実装前は backend スクリプト自体が存在しないため FAIL
    local backend_mcp="$PLUGIN_ROOT/scripts/session-comm-backend-mcp.sh"
    if [[ ! -f "$backend_mcp" ]]; then
        echo "FAIL: session-comm-backend-mcp.sh が存在しない（mcp_with_fallback 未実装）" >&2
        return 1
    fi
    if ! grep -q "mcp_with_fallback\|fallback" "$backend_mcp"; then
        echo "FAIL: session-comm-backend-mcp.sh に mcp_with_fallback または fallback パスが存在しない" >&2
        return 1
    fi
}

# ===========================================================================
# AC-6: Phase 3 完遂時に #1033 close、Phase 3 完遂 + Tier B (#1032) merge AND で #1034 epic close
#       Phase 4 完了時に #1050 close
#   プロセス AC: session_msg の mcp backend が正常動作すること（Phase 3 移行の前提）
#
# RED: session_msg 関数 + mcp backend が未実装のため FAIL
# ===========================================================================

@test "ac6: session_msg が mcp backend で動作する（Phase 3 移行前提の構造確認）" {
    # 実装後は session_msg を TWILL_MSG_BACKEND=mcp で呼んだとき backend-mcp.sh が実行されるはず
    # 実装前は session_msg 自体が未定義のため FAIL
    local exit_code=0
    TWILL_MSG_BACKEND=mcp bash -c "
        source \"$SESSION_COMM_SCRIPT\" 2>/dev/null
        if ! declare -f session_msg >/dev/null 2>&1; then
            echo 'session_msg not defined with TWILL_MSG_BACKEND=mcp' >&2
            exit 1
        fi
        echo 'ok'
    " || exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        echo "FAIL: TWILL_MSG_BACKEND=mcp で session_msg が利用可能でない（Phase 3 移行前提未達）" >&2
        return 1
    fi
}

# ===========================================================================
# AC-7: 補助ドキュメントの存在確認と整合性確認
#   architecture/migrations/tier-2-caller/migration-strategy.md
#   architecture/migrations/tier-2-caller/rollback-plan.md
#
# RED: architecture/migrations/tier-2-caller/ ディレクトリが存在しないため FAIL
# ===========================================================================

@test "ac7: architecture/migrations/tier-2-caller/migration-strategy.md が存在する" {
    local doc="$REPO_ROOT/architecture/migrations/tier-2-caller/migration-strategy.md"
    if [[ ! -f "$doc" ]]; then
        echo "FAIL: $doc が存在しない（ドキュメント未作成）" >&2
        return 1
    fi
}

@test "ac7: architecture/migrations/tier-2-caller/rollback-plan.md が存在する" {
    local doc="$REPO_ROOT/architecture/migrations/tier-2-caller/rollback-plan.md"
    if [[ ! -f "$doc" ]]; then
        echo "FAIL: $doc が存在しない（ドキュメント未作成）" >&2
        return 1
    fi
}

@test "ac7: migration-strategy.md が Issue #1032 への言及を含む（整合性確認）" {
    local doc="$REPO_ROOT/architecture/migrations/tier-2-caller/migration-strategy.md"
    if [[ ! -f "$doc" ]]; then
        skip "migration-strategy.md が存在しないためスキップ"
    fi
    if ! grep -q "1032\|#1032" "$doc"; then
        echo "FAIL: migration-strategy.md に Issue #1032 への言及がない（整合性不足）" >&2
        return 1
    fi
}

# ===========================================================================
# AC-8: tools_comm.py の try/except ImportError gate と fallback パスの保持
#   cli/twl/src/twl/mcp_server/tools_comm.py の try/except ImportError gate (L311付近)
#   session-comm-backend-tmux.sh が Phase 3 後も保持される
#
# RED: session-comm-backend-tmux.sh が未存在のため FAIL（ImportError gate は既存のため部分的 PASS）
# ===========================================================================

@test "ac8: tools_comm.py に try/except ImportError gate が存在する" {
    local tools_comm="$REPO_ROOT/cli/twl/src/twl/mcp_server/tools_comm.py"
    if [[ ! -f "$tools_comm" ]]; then
        echo "FAIL: tools_comm.py が存在しない" >&2
        return 1
    fi
    if ! grep -q "except ImportError" "$tools_comm"; then
        echo "FAIL: tools_comm.py に except ImportError gate が存在しない（保持されていない）" >&2
        return 1
    fi
}

@test "ac8: session-comm-backend-tmux.sh が Phase 3 後も保持される（存在確認）" {
    # 実装後は session-comm-backend-tmux.sh が fallback path として存在するはず
    # 実装前は未存在のため FAIL
    local backend_tmux="$PLUGIN_ROOT/scripts/session-comm-backend-tmux.sh"
    if [[ ! -f "$backend_tmux" ]]; then
        echo "FAIL: session-comm-backend-tmux.sh が存在しない（fallback パス未実装）" >&2
        return 1
    fi
}

@test "ac8: session-comm-backend-tmux.sh が FastMCP 接続失敗時の fallback として機能する（構造確認）" {
    # 実装後は session-comm-backend-tmux.sh が tmux send-keys を使った fallback として動作するはず
    # 実装前はファイル自体が存在しないため FAIL
    local backend_tmux="$PLUGIN_ROOT/scripts/session-comm-backend-tmux.sh"
    if [[ ! -f "$backend_tmux" ]]; then
        echo "FAIL: session-comm-backend-tmux.sh が存在しない（未実装）" >&2
        return 1
    fi
    if ! grep -q "tmux send-keys" "$backend_tmux"; then
        echo "FAIL: session-comm-backend-tmux.sh に tmux send-keys が含まれていない（fallback として不完全）" >&2
        return 1
    fi
}

# ===========================================================================
# AC-9: 各 Phase の PR で twl check --deps-integrity PASS
#   chain SSoT との非干渉、ADR-022 整合
#
# RED: 実装が存在しない現時点では deps.yaml 更新が未完了のため FAIL の可能性
#      ただし twl コマンドの利用可否によって挙動が変わる
# ===========================================================================

@test "ac9: twl check --deps-integrity が PASS する（chain SSoT 非干渉確認）" {
    # twl CLI が利用可能な場合のみ実行
    local twl_bin="$REPO_ROOT/cli/twl/twl"
    if [[ ! -x "$twl_bin" ]]; then
        echo "FAIL: twl CLI が存在しない: $twl_bin" >&2
        return 1
    fi

    # deps-integrity チェック: chain SSoT 非干渉確認（plugins/twl で実行）
    # chain の deps-integrity は plugins/twl が SSoT（plugins/session は chain 定義なし）
    local exit_code=0
    (cd "$REPO_ROOT/plugins/twl" && "$twl_bin" check --deps-integrity) 2>&1 || exit_code=$?
    if [[ "$exit_code" -ne 0 ]]; then
        echo "FAIL: twl check --deps-integrity が失敗した（exit code: $exit_code）" >&2
        return 1
    fi
}
