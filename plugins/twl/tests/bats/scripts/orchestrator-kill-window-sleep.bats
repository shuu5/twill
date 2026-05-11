#!/usr/bin/env bats
# orchestrator-kill-window-sleep.bats
#
# AC-3d (Issue #1360): bats regression test
#   safe_kill_window ヘルパー内の sleep 挿入が tmux burst-kill を緩和することを検証。
#
# 実装方式: Issue #1385 のリファクタにより全 19 caller が
# `plugins/twl/scripts/lib/tmux-window-kill.sh::safe_kill_window` 経由になっているため、
# 行番号 hardcoded ではなく、ヘルパー本体と caller の関係を検証する。
#
# Issue: #1360 — P0 incident: tmux server protected scope crash

load '../helpers/common'

setup() {
  common_setup

  ORCHESTRATOR="${REPO_ROOT}/scripts/issue-lifecycle-orchestrator.sh"
  AUTOPILOT_ORCH="${REPO_ROOT}/scripts/autopilot-orchestrator.sh"
  SPEC_REVIEW_ORCH="${REPO_ROOT}/scripts/spec-review-orchestrator.sh"
  AUTO_MERGE="${REPO_ROOT}/scripts/auto-merge.sh"
  PILOT_FALLBACK="${REPO_ROOT}/scripts/pilot-fallback-monitor.sh"
  SAFE_KILL_HELPER="${REPO_ROOT}/scripts/lib/tmux-window-kill.sh"
  export ORCHESTRATOR AUTOPILOT_ORCH SPEC_REVIEW_ORCH AUTO_MERGE \
         PILOT_FALLBACK SAFE_KILL_HELPER
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# AC-3d-1: ヘルパー本体に sleep 挿入があることを検証
# ---------------------------------------------------------------------------

@test "ac3d-1: safe_kill_window ヘルパー内に tmux kill-window + sleep の組み合わせがある" {
  # kill-window 行と sleep 行が両方含まれていることを検証
  run grep -qE 'tmux[[:space:]]+kill-window' "${SAFE_KILL_HELPER}"
  [ "${status}" -eq 0 ]
  run grep -qE 'sleep[[:space:]]+("?\$\{?SAFE_KILL_WINDOW_SLEEP|[0-9])' "${SAFE_KILL_HELPER}"
  [ "${status}" -eq 0 ]
}

@test "ac3d-1: ヘルパーの sleep は SAFE_KILL_WINDOW_SLEEP env で override 可能" {
  run grep -qE 'SAFE_KILL_WINDOW_SLEEP:-1' "${SAFE_KILL_HELPER}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-3d-2: 集中化が保持されている（caller が safe_kill_window を呼ぶ）
# ---------------------------------------------------------------------------

@test "ac3d-2: issue-lifecycle-orchestrator.sh が safe_kill_window 経由で kill する" {
  # safe_kill_window 呼び出しが少なくとも 5 回以上あること（実際は 10 回）
  count=$(grep -cE '\bsafe_kill_window\b' "${ORCHESTRATOR}")
  [ "${count}" -ge 5 ]
}

@test "ac3d-2: autopilot-orchestrator.sh が safe_kill_window 経由で kill する" {
  count=$(grep -cE '\bsafe_kill_window\b' "${AUTOPILOT_ORCH}")
  [ "${count}" -ge 1 ]
}

@test "ac3d-2: spec-review-orchestrator.sh が safe_kill_window 経由で kill する" {
  count=$(grep -cE '\bsafe_kill_window\b' "${SPEC_REVIEW_ORCH}")
  [ "${count}" -ge 1 ]
}

# ---------------------------------------------------------------------------
# AC-3d-3: orchestrator 内に直接 tmux kill-window 呼び出しが残存しない
# ---------------------------------------------------------------------------

@test "ac3d-3: issue-lifecycle-orchestrator.sh に直接 tmux kill-window 呼び出しなし" {
  run grep -E '\btmux[[:space:]]+kill-window\b' "${ORCHESTRATOR}"
  [ "${status}" -ne 0 ]
}

@test "ac3d-3: autopilot-orchestrator.sh に直接 tmux kill-window 呼び出しなし" {
  run grep -E '\btmux[[:space:]]+kill-window\b' "${AUTOPILOT_ORCH}"
  [ "${status}" -ne 0 ]
}

@test "ac3d-3: spec-review-orchestrator.sh に直接 tmux kill-window 呼び出しなし" {
  run grep -E '\btmux[[:space:]]+kill-window\b' "${SPEC_REVIEW_ORCH}"
  [ "${status}" -ne 0 ]
}

@test "ac3d-3: auto-merge.sh に直接 tmux kill-window 呼び出しなし" {
  run grep -E '\btmux[[:space:]]+kill-window\b' "${AUTO_MERGE}"
  [ "${status}" -ne 0 ]
}

@test "ac3d-3: pilot-fallback-monitor.sh に直接 tmux kill-window 呼び出しなし" {
  run grep -E '\btmux[[:space:]]+kill-window\b' "${PILOT_FALLBACK}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC-3d-4: safe_kill_window のランタイム挙動確認
# ---------------------------------------------------------------------------

@test "ac3d-4-a: 存在しないウィンドウ名なら safe_kill_window は kill も sleep も実行しない" {
  # target が空文字列なら if [[ -n "$target" ]] が false で sleep がスキップされる。
  # SAFE_KILL_WINDOW_SLEEP=10 でも fast-return すべき。
  run bash -c "
    source '${SAFE_KILL_HELPER}'
    SAFE_KILL_WINDOW_SLEEP=10
    time_start=\$(date +%s%N)
    safe_kill_window '__nonexistent_window_for_test__' 2>/dev/null
    time_end=\$(date +%s%N)
    elapsed_ms=\$(( (time_end - time_start) / 1000000 ))
    [ \$elapsed_ms -lt 1000 ]
  "
  [ "${status}" -eq 0 ]
}

@test "ac3d-4-b: SAFE_KILL_WINDOW_SLEEP=0 + window 存在ならば sleep 0 が呼ばれる（kill 経路）" {
  # tmux をモックして必ず window が見つかる状態を作り、kill 経路に入った上で sleep 0 が走ることを確認。
  # mock tmux: list-windows は target を1つ返し、kill-window は no-op。
  # SAFE_KILL_WINDOW_SLEEP=0 で kill 経路に入っても 1 秒未満で返るはず。
  run bash -c "
    _stub_dir=\$(mktemp -d)
    cat > \"\$_stub_dir/tmux\" <<'EOF'
#!/usr/bin/env bash
case \"\$1\" in
  list-windows) echo 'sess:0 __mock_window__' ;;
  kill-window)  : ;;
  *)            : ;;
esac
EOF
    chmod +x \"\$_stub_dir/tmux\"
    PATH=\"\$_stub_dir:\$PATH\"
    source '${SAFE_KILL_HELPER}'
    SAFE_KILL_WINDOW_SLEEP=0
    time_start=\$(date +%s%N)
    safe_kill_window '__mock_window__'
    time_end=\$(date +%s%N)
    elapsed_ms=\$(( (time_end - time_start) / 1000000 ))
    rm -rf \"\$_stub_dir\"
    # SLEEP=0 なので kill 経路でも 1 秒未満で完了
    [ \$elapsed_ms -lt 1000 ]
  "
  [ "${status}" -eq 0 ]
}
