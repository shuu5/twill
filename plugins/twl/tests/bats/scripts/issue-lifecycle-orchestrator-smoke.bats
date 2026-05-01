#!/usr/bin/env bats
# issue-lifecycle-orchestrator-smoke.bats
# Issue #1218: tech-debt: tmux kill-window / set-option
# AC5 — issue-lifecycle-orchestrator.sh が dry-run で正常完了（exit 0）
#
# 設計:
#   - --per-issue-dir に OUT/report.json 済み（status: done）の subdir を 1 つ含む
#     ディレクトリを渡す → spawn_session がスキップ → batch 末の kill-window → exit 0
#   - この smoke テストは kill-window callsite リファクタ後も exit 0 を維持することを確認する
#   - kill-window が session:index 形式（"coi-xxx:0" 等）で呼ばれても exit 0 を維持すること
#
# 複数 callsite をカバーする理由:
#   orchestrator.sh には kill-window callsite が多数存在（L372, L411, L562, L589, L595,
#   L641, L681, L690, L715, L754）。いずれかのリファクタが orchestrator 全体の
#   exit code に影響しないことを integration smoke で確認する。
#
# GREEN 化条件:
#   - lib/tmux-resolve.sh が実装される
#   - orchestrator の kill-window callsite が _kill_window_safe / _resolve_window_target
#     を使うようにリファクタされる
#   - set-option callsite (L368) も同様にリファクタされる
#   - それらの変更後も orchestrator が exit 0 で完了すること

load '../../bats/helpers/common'

SCRIPT_SRC=""
PER_ISSUE_DIR_TEST=""

setup() {
    common_setup
    SCRIPT_SRC="$REPO_ROOT/scripts/issue-lifecycle-orchestrator.sh"
}

teardown() {
    [[ -n "${PER_ISSUE_DIR_TEST:-}" ]] && rm -rf "$PER_ISSUE_DIR_TEST"
    common_teardown
}

# ---------------------------------------------------------------------------
# AC5-smoke-exit0:
#   --per-issue-dir に done 済み subdir を 1 つ渡して exit 0 を確認
#   RED: orchestrator の kill-window リファクタ後にリグレッションがない限り GREEN
#        （ただし lib/tmux-resolve.sh が未実装の場合、source エラーで exit != 0 になりうる）
# ---------------------------------------------------------------------------
@test "AC5-smoke: done 済み subdir 1 件で orchestrator が exit 0 で完了する (smoke)" {
    # RED → GREEN 条件: lib/tmux-resolve.sh 実装 + orchestrator kill-window callsite リファクタ
    # 実装前（tmux-resolve.sh 不在）でも orchestrator は既存の直接 kill-window を使うため
    # このテストはスクリプト全体の統合 smoke として機能する。

    PER_ISSUE_DIR_TEST="$(mktemp -d)"

    # done 済み subdir を作成（spawn_session は report.json 存在でスキップ）
    local subdir="$PER_ISSUE_DIR_TEST/issue-smoke-001"
    mkdir -p "$subdir/IN" "$subdir/OUT"
    printf 'dummy draft for smoke test\n' > "$subdir/IN/draft.md"
    printf '{"status":"done","issue_num":1218}\n' > "$subdir/OUT/report.json"

    run bash <<EOF
# PATH に stub_bin を追加（cld / tmux / session-comm.sh を mock）
STUB_BIN="\$(mktemp -d)"
trap 'rm -rf "\$STUB_BIN"' EXIT

# cld stub（session 起動を skip）
cat > "\$STUB_BIN/cld" <<'STUBEOF'
#!/usr/bin/env bash
exit 0
STUBEOF
chmod +x "\$STUB_BIN/cld"

# tmux stub（kill-window / set-option / list-windows を absorb）
cat > "\$STUB_BIN/tmux" <<'STUBEOF'
#!/usr/bin/env bash
case "\$1" in
    kill-window|set-option|has-session|new-window) exit 0 ;;
    list-windows)
        # spawn_session skip のため呼ばれないが念のため
        printf ''
        exit 0
        ;;
    *) exit 0 ;;
esac
STUBEOF
chmod +x "\$STUB_BIN/tmux"

# flock stub（ロック操作を pass-through）
cat > "\$STUB_BIN/flock" <<'STUBEOF'
#!/usr/bin/env bash
# "-n fd" を読み飛ばして残りのコマンドを実行
shift; shift
exec "\$@"
STUBEOF
chmod +x "\$STUB_BIN/flock"

export PATH="\$STUB_BIN:\$PATH"

bash "$SCRIPT_SRC" --per-issue-dir "$PER_ISSUE_DIR_TEST" 2>/dev/null
EOF

    # smoke: exit 0 で完了すること
    [[ "$status" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# AC5-smoke-empty-dir-exit1:
#   --per-issue-dir が空ディレクトリ（IN/draft.md なし）の場合 exit 1
#   これは orchestrator の引数バリデーション確認（リファクタで壊れないこと）
# ---------------------------------------------------------------------------
@test "AC5-smoke: 空ディレクトリ（IN/draft.md なし）で exit 1（バリデーション回帰ガード）" {
    PER_ISSUE_DIR_TEST="$(mktemp -d)"

    run bash <<EOF
STUB_BIN="\$(mktemp -d)"
trap 'rm -rf "\$STUB_BIN"' EXIT

cat > "\$STUB_BIN/cld" <<'STUBEOF'
#!/usr/bin/env bash
exit 0
STUBEOF
chmod +x "\$STUB_BIN/cld"

cat > "\$STUB_BIN/tmux" <<'STUBEOF'
#!/usr/bin/env bash
exit 0
STUBEOF
chmod +x "\$STUB_BIN/tmux"

export PATH="\$STUB_BIN:\$PATH"

bash "$SCRIPT_SRC" --per-issue-dir "$PER_ISSUE_DIR_TEST" 2>/dev/null
EOF

    # 空ディレクトリは IN/draft.md が存在しないため exit 1
    [[ "$status" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# AC5-smoke-kill-window-callsite-count:
#   orchestrator.sh に tmux kill-window callsite が存在することを確認
#   リファクタ後も kill-window は残る（_kill_window_safe 経由で呼ぶため）
# ---------------------------------------------------------------------------
@test "AC5-smoke: orchestrator.sh に kill-window callsite が存在する（リファクタ後も維持）" {
    [ -f "$SCRIPT_SRC" ]
    # kill-window または _kill_window_safe が存在すること
    grep -qE "kill-window|_kill_window_safe" "$SCRIPT_SRC"
}
