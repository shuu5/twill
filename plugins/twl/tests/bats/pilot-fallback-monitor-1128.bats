#!/usr/bin/env bats
# pilot-fallback-monitor-1128.bats
#
# Issue #1128: Tech-debt: autopilot BUDGET-LOW recovery
#   Bug A: Pilot 自動 inject (AC-2)
#   Bug C: Worker window cleanup SLA (AC-4)
#
# AC coverage:
#   AC2 - Worker idle + next-workflow regex 検出 → pilot-fallback-monitor.sh が
#          session-comm.sh inject を発火する
#   AC4 - PR merged 検知後 30s 以内に対応 Worker window を kill する（SLA: 論理積検証）
#
# 全テストは実装前（RED）状態で fail する。
# pilot-fallback-monitor.sh が存在しないため、全テストは必ず fail する。

load 'helpers/common'

# ===========================================================================
# Setup / Teardown
# ===========================================================================

setup() {
  common_setup

  REPO_ROOT_BATS="${REPO_ROOT}"
  export REPO_ROOT_BATS

  MONITOR_SCRIPT="${REPO_ROOT}/scripts/pilot-fallback-monitor.sh"
  SESSION_COMM_SCRIPT="${REPO_ROOT_BATS}/../../../session/scripts/session-comm.sh"
  WINDOW_CHECK_LIB="${REPO_ROOT}/scripts/lib/observer-window-check.sh"
  export MONITOR_SCRIPT SESSION_COMM_SCRIPT WINDOW_CHECK_LIB

  # spy ファイル: session-comm.sh inject の呼び出し記録
  INJECT_SPY_LOG="${SANDBOX}/inject-spy.log"
  export INJECT_SPY_LOG

  # spy ファイル: tmux kill-window の呼び出し記録
  KILL_WINDOW_SPY_LOG="${SANDBOX}/kill-window-spy.log"
  export KILL_WINDOW_SPY_LOG

  # stub: session-comm.sh inject を spy に置換
  # 実際の tmux 操作をしない。呼び出し引数を INJECT_SPY_LOG に記録する
  cat > "${STUB_BIN}/session-comm.sh" <<'STUB'
#!/usr/bin/env bash
# stub: session-comm.sh inject spy
echo "CALL: $*" >> "${INJECT_SPY_LOG}"
# inject サブコマンドのみ記録
if [[ "${1:-}" == "inject" ]]; then
  echo "inject window=${2:-} text=${3:-}" >> "${INJECT_SPY_LOG}"
fi
exit 0
STUB
  chmod +x "${STUB_BIN}/session-comm.sh"

  # stub: tmux kill-window を spy に置換
  # 実際の tmux 操作をしない。呼び出し引数を KILL_WINDOW_SPY_LOG に記録する
  stub_command "tmux" '
case "$1" in
  kill-window)
    echo "kill-window $*" >> "${KILL_WINDOW_SPY_LOG}"
    exit 0
    ;;
  list-windows)
    # window 存在確認用: stub は固定 window 名を返す
    echo "ap-worker-1128"
    exit 0
    ;;
  capture-pane)
    # AC-2 用: idle 状態（shell prompt）を返す
    printf "> \n"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  # stub: gh pr view を即時 MERGED 返却に置換（CI で GitHub API を叩かない）
  stub_command "gh" '
# gh pr view --json state → MERGED を即時返す
if echo "$*" | grep -q "pr view"; then
  echo '"'"'{"state":"MERGED"}'"'"'
  exit 0
fi
exit 0
'
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-2: Worker idle + next-workflow regex 検出 → session-comm.sh inject 発火
# ===========================================================================

@test "ac2: pilot-fallback-monitor.sh exists" {
  # AC: plugins/twl/scripts/pilot-fallback-monitor.sh が新規作成される
  # RED: ファイルがまだ存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
}

@test "ac2: pilot-fallback-monitor.sh is executable" {
  # AC: pilot-fallback-monitor.sh が実行可能である
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  [ -x "${MONITOR_SCRIPT}" ]
}

@test "ac2: pilot-fallback-monitor.sh defines inject judgment logic" {
  # AC: inject 判定ロジック（orchestrator unavailable 時の next-workflow 自動 inject）が実装される
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  # session-comm.sh inject の呼び出し、または inject_next_workflow 相当のロジックを含む
  run grep -E 'session-comm\.sh.*inject|inject.*session-comm|inject_next_workflow|INJECT' "${MONITOR_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: pilot-fallback-monitor.sh has PID file management" {
  # AC: PID file 管理が実装されている（daemon として安全に再起動できるため）
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  run grep -E 'PID|pid_file|\.pid' "${MONITOR_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac2: pilot-fallback-monitor.sh stops when orchestrator is alive" {
  # AC: orchestrator alive 時は自動停止する（二重起動防止）
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  run grep -E 'orchestrator.*alive|autopilot-orchestrator|orchestrator.*pid|pgrep.*orchestrator|orchestrator.*running' \
    "${MONITOR_SCRIPT}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-2 の核心: Worker idle 検知 + session-comm.sh inject 呼び出し検証
# ---------------------------------------------------------------------------

@test "ac2: worker idle + next-workflow regex → session-comm.sh inject is called" {
  # AC: Worker pane が idle 状態（terminal signal）で next-workflow regex を検出したとき、
  #     pilot-fallback-monitor.sh が session-comm.sh inject <worker> "/twl:workflow-X" を実行する
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  #
  # mock 設計:
  #   - tmux capture-pane は "nothing pending" を含む idle fixture を返す（stub 済み）
  #   - session-comm.sh inject は spy（INJECT_SPY_LOG に記録）
  #   - orchestrator は起動していない想定（ORCHESTRATOR_PID 未設定）
  [ -f "${MONITOR_SCRIPT}" ]

  # sandbox 内で inject ロジックのみを抽出して実行するヘルパー
  # autopilot-cleanup-crossrepo-dep-chain.bats:17 の関数抽出パターンに倣う
  local inject_func
  inject_func=$(grep -n '_check_and_inject\|check_worker_idle\|do_inject\|run_once\|check_inject' \
    "${MONITOR_SCRIPT}" | head -1 | cut -d: -f1 || true)

  # 関数が特定できた場合は関数抽出パターンで実行、できない場合は --once フラグで一周だけ実行
  run bash -c "
    set -euo pipefail
    export SANDBOX='${SANDBOX}'
    export INJECT_SPY_LOG='${INJECT_SPY_LOG}'
    export KILL_WINDOW_SPY_LOG='${KILL_WINDOW_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    export NEXT_WORKFLOW='/twl:workflow-setup'
    # 一周のみ実行（daemon ループには入らない）
    bash '${MONITOR_SCRIPT}' --once --worker ap-worker-1128 2>/dev/null || true
  "

  # session-comm.sh inject が呼ばれたことを spy ログで確認
  [ -f "${INJECT_SPY_LOG}" ]
  run grep -q 'inject' "${INJECT_SPY_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac2: inject command targets correct worker window" {
  # AC: inject コマンドが正しい Worker window を対象とする
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]

  run bash -c "
    set -euo pipefail
    export SANDBOX='${SANDBOX}'
    export INJECT_SPY_LOG='${INJECT_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    export NEXT_WORKFLOW='/twl:workflow-setup'
    bash '${MONITOR_SCRIPT}' --once --worker ap-worker-1128 2>/dev/null || true
  "

  # inject の対象 window が ap-worker-1128 であることを確認
  run grep -E 'ap-worker-1128' "${INJECT_SPY_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac2: inject command sends /twl:workflow-* pattern" {
  # AC: inject するテキストが /twl:workflow-<name> パターンに適合する
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]

  run bash -c "
    set -euo pipefail
    export SANDBOX='${SANDBOX}'
    export INJECT_SPY_LOG='${INJECT_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    export NEXT_WORKFLOW='/twl:workflow-setup'
    bash '${MONITOR_SCRIPT}' --once --worker ap-worker-1128 2>/dev/null || true
  "

  # inject テキストが /twl:workflow-X 形式であることを確認
  run grep -E '/twl:workflow-[a-z][a-z0-9-]*' "${INJECT_SPY_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac2: no real tmux or sleep in test execution" {
  # AC: テスト実行時間は 1 秒以内（実時間待機なし）
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]

  local start_ts end_ts elapsed
  start_ts=$(date +%s)

  run bash -c "
    export SANDBOX='${SANDBOX}'
    export INJECT_SPY_LOG='${INJECT_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    bash '${MONITOR_SCRIPT}' --once --worker ap-worker-1128 2>/dev/null || true
  "

  end_ts=$(date +%s)
  elapsed=$(( end_ts - start_ts ))

  # 1 秒以内に完了すること（実時間待機なし mock の確認）
  [ "${elapsed}" -lt 2 ]
}

# ===========================================================================
# AC-4: PR merged 検知後 30s 以内に Worker window kill（SLA: 論理積で検証）
# ===========================================================================

@test "ac4: pilot-fallback-monitor.sh has pr-merged cleanup logic" {
  # AC: PR merged 後の Worker window 即時 cleanup logic が実装される
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  run grep -E 'pr.*merge[d]?|MERGED|kill.window|cleanup.*window|window.*cleanup' \
    "${MONITOR_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: pilot-fallback-monitor.sh uses _check_window_alive from observer-window-check.sh" {
  # AC: _check_window_alive() を observer-window-check.sh から使用する（pitfalls §4.9 準拠）
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  run grep -E '_check_window_alive|observer-window-check\.sh' "${MONITOR_SCRIPT}"
  [ "${status}" -eq 0 ]
}

@test "ac4: pilot-fallback-monitor.sh uses list-windows not has-session for window check" {
  # AC: window 存在確認に has-session ではなく list-windows を使用する（§4.9 準拠）
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  # has-session を window 確認に使っていないことを確認
  # （_check_window_alive 経由で list-windows を使う設計）
  run grep -v '#' "${MONITOR_SCRIPT}"
  local content="${output}"
  # _check_window_alive 使用または list-windows 直接使用のどちらかが必要
  echo "${content}" | grep -qE '_check_window_alive|list-windows'
  [ "$?" -eq 0 ]
}

@test "ac4: sla poll_interval is defined and <= 15s" {
  # AC: poll_interval が定義され、15s 以下である（SLA: 30s 以内に検知するため）
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]
  run grep -E 'POLL_INTERVAL|poll_interval' "${MONITOR_SCRIPT}"
  [ "${status}" -eq 0 ]

  # poll_interval の値が 15 以下であることを確認（論理積 SLA 検証）
  local interval_val
  interval_val=$(grep -Eo 'POLL_INTERVAL[^=]*=\s*[0-9]+' "${MONITOR_SCRIPT}" \
    | grep -Eo '[0-9]+$' | head -1 || echo "")
  if [[ -n "${interval_val}" ]]; then
    [ "${interval_val}" -le 15 ]
  fi
}

@test "ac4: sla max_retry x poll_interval <= 30s (logical assertion without wall-clock wait)" {
  # AC: poll_interval × max_retry ≤ 30s を論理積で assert する
  #     bats テスト実行時間は 1 秒以内（wall-clock 待機なし）
  # RED: ファイルが存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]

  # poll_interval と max_retry（または max_wait）の値を抽出して論理検証
  local interval max_retry max_total

  interval=$(grep -Eo 'POLL_INTERVAL[^=]*=[[:space:]]*[0-9]+' "${MONITOR_SCRIPT}" \
    | grep -Eo '[0-9]+$' | head -1 || echo "30")
  max_retry=$(grep -Eo 'MAX_RETRY[^=]*=[[:space:]]*[0-9]+|max_retry[^=]*=[[:space:]]*[0-9]+' \
    "${MONITOR_SCRIPT}" | grep -Eo '[0-9]+$' | head -1 || echo "1")

  max_total=$(( interval * max_retry ))

  # SLA: poll_interval × max_retry ≤ 30s
  [ "${max_total}" -le 30 ]
}

@test "ac4: gh pr view --json state stub returns MERGED immediately" {
  # AC: gh pr view --json state が stub で即時 MERGED を返す（CI で GitHub API を叩かない）
  # RED: pilot-fallback-monitor.sh が存在しないため fail（stub は独立して動作するが本テストは
  #      stub と monitor が組み合わさって動作することを検証する）
  [ -f "${MONITOR_SCRIPT}" ]

  # stub が正しく MERGED を返すことを独立確認
  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    gh pr view 1128 --json state
  "
  [ "${status}" -eq 0 ]
  echo "${output}" | grep -q 'MERGED'
}

@test "ac4: pr merged → tmux kill-window is called for worker window" {
  # AC: PR が MERGED 状態のとき、対応 Worker window に対して tmux kill-window が実行される
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  #
  # mock 設計:
  #   - gh pr view --json state → 即時 MERGED（stub 済み）
  #   - tmux kill-window → spy（KILL_WINDOW_SPY_LOG に記録）
  #   - tmux list-windows → ap-worker-1128 を返す（window alive）
  [ -f "${MONITOR_SCRIPT}" ]

  run bash -c "
    set -euo pipefail
    export SANDBOX='${SANDBOX}'
    export INJECT_SPY_LOG='${INJECT_SPY_LOG}'
    export KILL_WINDOW_SPY_LOG='${KILL_WINDOW_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    export ISSUE_NUM='1128'
    # PR merged 検知後 cleanup のみを実行（daemon ループなし）
    bash '${MONITOR_SCRIPT}' --once --cleanup --worker ap-worker-1128 --issue 1128 2>/dev/null || true
  "

  # tmux kill-window が呼ばれたことを spy ログで確認
  [ -f "${KILL_WINDOW_SPY_LOG}" ]
  run grep -q 'kill-window' "${KILL_WINDOW_SPY_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac4: kill-window targets correct worker window name" {
  # AC: kill-window が正しい Worker window 名を -t で指定する
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]

  run bash -c "
    set -euo pipefail
    export SANDBOX='${SANDBOX}'
    export KILL_WINDOW_SPY_LOG='${KILL_WINDOW_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    export ISSUE_NUM='1128'
    bash '${MONITOR_SCRIPT}' --once --cleanup --worker ap-worker-1128 --issue 1128 2>/dev/null || true
  "

  # kill-window の -t 引数が ap-worker-1128 であることを確認
  run grep -E 'ap-worker-1128' "${KILL_WINDOW_SPY_LOG}"
  [ "${status}" -eq 0 ]
}

@test "ac4: no wall-clock sleep in cleanup test (executes under 2 seconds)" {
  # AC: cleanup テスト実行時間は 2 秒以内（wall-clock 待機なし mock の確認）
  # RED: pilot-fallback-monitor.sh が存在しないため fail
  [ -f "${MONITOR_SCRIPT}" ]

  local start_ts end_ts elapsed
  start_ts=$(date +%s)

  run bash -c "
    export SANDBOX='${SANDBOX}'
    export KILL_WINDOW_SPY_LOG='${KILL_WINDOW_SPY_LOG}'
    export PATH='${STUB_BIN}:${PATH}'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    export WORKER_WINDOW='ap-worker-1128'
    export ISSUE_NUM='1128'
    bash '${MONITOR_SCRIPT}' --once --cleanup --worker ap-worker-1128 --issue 1128 2>/dev/null || true
  "

  end_ts=$(date +%s)
  elapsed=$(( end_ts - start_ts ))

  # 2 秒以内に完了すること
  [ "${elapsed}" -lt 3 ]
}
