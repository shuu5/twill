#!/usr/bin/env bats
# cld-observe-any-test-mode-validate.bats
# AC1〜AC3 の regression guard (TDD RED フェーズ)
# これらのテストは実装変更前の現コードでは FAIL し、実装変更後に PASS する。

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../scripts" && pwd)"
CLD_OBSERVE_ANY="$SCRIPT_DIR/cld-observe-any"

setup() {
    TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
    [[ -n "${TMPDIR_TEST:-}" && -d "$TMPDIR_TEST" ]] && rm -rf "$TMPDIR_TEST"
    # AC3 guard が生成するテスト用 lock ファイルを削除
    rm -f /tmp/cld-observe-any-test-*.lock /tmp/cld-observe-any-test-*.lock.pid 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Scenario A (AC1 guard):
#   _TEST_MODE=1 かつ --window/--pattern 不在 → exit 1 + stderr にエラーメッセージ
#
# 現在の L144: [[ -z "${_DAEMON_LOAD_ONLY:-}" && -z "${_TEST_MODE:-}" ]]
# → _TEST_MODE=1 のとき条件が偽になり validation skip → exit 0 になるため RED
#
# 実装後 L144: [[ -z "${_DAEMON_LOAD_ONLY:-}" ]]
# → _TEST_MODE の有無によらず --window/--pattern 未指定で exit 1 → PASS
# ---------------------------------------------------------------------------
@test "AC1: _TEST_MODE=1 かつ --window/--pattern 未指定 → exit 1 と validation エラー" {
    local script_dir="$SCRIPT_DIR"
    local cld_observe_any="$CLD_OBSERVE_ANY"

    run bash <<EOF
_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$script_dir" \
    bash "$cld_observe_any" 2>&1
EOF

    # 実装前: exit 0 で FAIL、実装後: exit 1 で PASS
    [[ "$status" -eq 1 ]]
    echo "$output" | grep -q "Error: --window または --pattern を指定してください"
}

# ---------------------------------------------------------------------------
# Scenario B (AC3 guard):
#   _TEST_MODE=1 かつ --window <name> --once 実行 → /tmp/cld-observe-any-test-*.lock が存在
#
# 現在の L162: [[ -z "${_DAEMON_LOAD_ONLY:-}" && -z "${_TEST_MODE:-}" ]]
# → _TEST_MODE=1 のとき flock ブロック全体 skip → lock ファイルが作られない → RED
#
# 実装後 L162: _TEST_MODE set → LOCK_FILE="/tmp/cld-observe-any-test-$$.lock" にリダイレクト
# → lock ファイルが /tmp/cld-observe-any-test-*.lock に存在 → PASS
# ---------------------------------------------------------------------------
@test "AC3: _TEST_MODE=1 かつ --window 指定 → /tmp/cld-observe-any-test-*.lock が存在する" {
    local script_dir="$SCRIPT_DIR"
    local cld_observe_any="$CLD_OBSERVE_ANY"
    local tmpdir="$TMPDIR_TEST"
    local win="test-win-ac3-$$"

    run bash <<EOF
# tmux モック: window が存在し pane_dead=1 で即終了
tmux() {
    case "\$1" in
        list-windows)
            if [[ "\${2:-}" == "-a" ]]; then
                printf 'test-session:0\n'
                return
            fi
            echo "test-session:0 $win"
            ;;
        display-message)
            # pane_dead=1 → [PANE-DEAD] emit して --once 終了
            echo "1 bash"
            ;;
        capture-pane)
            echo ""
            ;;
        *)
            return 0 ;;
    esac
}
export -f tmux

_TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$script_dir" \
    bash "$cld_observe_any" --window "$win" --once 2>/dev/null
EOF

    # 終了コードの確認（PANE-DEAD 検出で exit 0）
    [[ "$status" -eq 0 ]]
    # 実装前: lock ファイルなし → FAIL、実装後: lock ファイルあり → PASS
    local lock_count
    lock_count=$(ls /tmp/cld-observe-any-test-*.lock 2>/dev/null | wc -l)
    [[ "$lock_count" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# Scenario C (AC2 guard):
#   _DAEMON_LOAD_ONLY=1 を env 経由でセットして実行
#   → unset _DAEMON_LOAD_ONLY により env 由来の値が破棄される
#   → flock と validation を通過して main loop に到達
#   → tmux モックで window なし → exit 0 かつ stdout が空
#
# 現在: unset 処理なし → env 由来 _DAEMON_LOAD_ONLY=1 が有効
#   → L144 で validation skip、L162 で flock skip → main loop に到達し exit 0 だが、
#     「unset しているか」の保証がない。
#
# 検証方法: _DAEMON_LOAD_ONLY=1 かつ --window 指定なし で実行。
#   実装前 (unset なし): _DAEMON_LOAD_ONLY=1 が live のため validation skip → exit 0
#                       だが、これは「env 由来の値で bypass された」状態であり不正。
#   実装後 (unset あり): 引数解析後に unset → _DAEMON_LOAD_ONLY は空
#                       → validation が発動して exit 1（--window/--pattern 未指定）
#
# RED 根拠: 実装前は exit 0（validation bypass）、実装後は exit 1（validation 発動）
# ---------------------------------------------------------------------------
@test "AC2: env 経由 _DAEMON_LOAD_ONLY=1 は unset され --window 未指定で exit 1 になる" {
    local script_dir="$SCRIPT_DIR"
    local cld_observe_any="$CLD_OBSERVE_ANY"

    run bash <<EOF
# env 経由で _DAEMON_LOAD_ONLY=1 をセット（引数ではなく環境変数として注入）
_DAEMON_LOAD_ONLY=1 _TEST_MODE=1 CLD_OBSERVE_ANY_SCRIPT_DIR="$script_dir" \
    bash "$cld_observe_any" 2>&1
EOF

    # 実装前: exit 0（env 由来 _DAEMON_LOAD_ONLY が live で validation skip）→ FAIL
    # 実装後: unset により _DAEMON_LOAD_ONLY が破棄 → validation 発動 → exit 1 → PASS
    [[ "$status" -eq 1 ]]
    echo "$output" | grep -q "Error: --window または --pattern を指定してください"
}
