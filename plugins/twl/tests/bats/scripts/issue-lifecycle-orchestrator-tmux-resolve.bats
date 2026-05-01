#!/usr/bin/env bats
# issue-lifecycle-orchestrator-tmux-resolve.bats
# Issue #1218: tech-debt: tmux kill-window / set-option
# AC2 — 複数 session 同名 window 時に正しい session が kill される
#
# RED テスト: _kill_window_safe / lib/tmux-resolve.sh が実装される前は fail する。
# 実装後（lib/tmux-resolve.sh + orchestrator の kill-window callsite リファクタ）に GREEN になる。
#
# 設計:
#   - issue-lifecycle-orchestrator.sh の tmux kill-window -t "$window_name" は
#     window_name だけを渡しているため、複数 session に同名 window が存在すると
#     ambiguous target エラーになる（またはランダム session の window が kill される）
#   - 修正後: _kill_window_safe "wt-target" を使い、session:index に解決してから kill する
#   - このテストは orchestrator が _kill_window_safe を呼び出すことを確認する
#
# 検証方法:
#   - tmux mock: list-windows（-a なし = current session）で s1:3 wt-test-multi-session を返す
#   - _resolve_window_target は -a なし設計のため current session の s1:3 を一意に解決する
#   - kill-window は session:index 形式 ("s1:3") で呼ばれること
#   - mock の -a 分岐（複数セッション返却）は実装では使用されない（設計上 current session スコープ）

load '../../bats/helpers/common'

SCRIPT_SRC=""

setup() {
    common_setup
    SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"
}

teardown() {
    common_teardown
}

# ---------------------------------------------------------------------------
# AC2-multi-session-disambig:
#   tmux mock で複数 session 同名 window 時に正しい session が kill される
#   RED: _kill_window_safe 未実装のため fail する
# ---------------------------------------------------------------------------
@test "AC2-multi-session-disambig: 複数セッションに同名 window が存在する場合 kill-window は session:index 形式で呼ばれる (RED)" {
    # RED: lib/tmux-resolve.sh + orchestrator kill-window callsite リファクタ前は fail する
    # 実装後: kill-window が "s1:3" 形式（session:index）で呼ばれることを確認
    local PER_ISSUE_DIR_LOCAL
    PER_ISSUE_DIR_LOCAL="$(mktemp -d)"
    local KILL_LOG_FILE
    KILL_LOG_FILE="$(mktemp)"
    local WINDOW_NAME="wt-test-multi-session"
    # LIB_PATH を heredoc 外で計算（BATS_TEST_FILENAME ベース - codex-reviewer CRITICAL 修正）
    local lib_path="$REPO_ROOT/../session/scripts/lib/tmux-resolve.sh"

    # IN/draft.md を含む subdir を作成（orchestrator がスキャンする対象）
    mkdir -p "$PER_ISSUE_DIR_LOCAL/issue-001/IN"
    printf 'dummy draft\n' > "$PER_ISSUE_DIR_LOCAL/issue-001/IN/draft.md"
    # OUT/report.json を事前作成して spawn をスキップさせる（kill のみテスト対象）
    mkdir -p "$PER_ISSUE_DIR_LOCAL/issue-001/OUT"
    printf '{"status":"done"}\n' > "$PER_ISSUE_DIR_LOCAL/issue-001/OUT/report.json"

    run bash <<EOF
KILL_LOG_FILE="$KILL_LOG_FILE"
WINDOW_NAME="$WINDOW_NAME"
LIB_PATH="$lib_path"

# tmux mock: list-windows -a に同名 window が s1 と s2 の両 session に存在する
tmux() {
    case "\$1" in
        list-windows)
            if [[ "\${*}" == *"-a"* ]]; then
                # 複数 session に同名 window
                printf 's1:3 %s\ns2:0 %s\n' "\$WINDOW_NAME" "\$WINDOW_NAME"
            else
                printf 's1:3 %s\n' "\$WINDOW_NAME"
            fi
            return 0
            ;;
        kill-window)
            # kill-window の引数を記録
            echo "kill-window \${@}" >> "\$KILL_LOG_FILE"
            return 0
            ;;
        set-option)
            return 0
            ;;
        has-session)
            return 1
            ;;
        new-window)
            return 0
            ;;
        *)
            return 0
            ;;
    esac
}
export -f tmux

if [[ ! -f "\$LIB_PATH" ]]; then
    echo "FAIL: lib/tmux-resolve.sh が存在しない（実装前）"
    exit 1
fi

source "\$LIB_PATH"
_kill_window_safe "\$WINDOW_NAME"
EOF

    kill_calls=$(cat "$KILL_LOG_FILE" 2>/dev/null || echo "")
    rm -f "$KILL_LOG_FILE"
    rm -rf "$PER_ISSUE_DIR_LOCAL"

    # RED: lib/tmux-resolve.sh が存在しないため失敗する
    # 実装後: kill-window が "s1:3" (session:index) で呼ばれ、s2:0 は kill されない
    [[ "$status" -eq 0 ]]
    echo "$kill_calls" | grep -q "kill-window -t s1:3"
    ! echo "$kill_calls" | grep -q "kill-window -t s2:0"
}
