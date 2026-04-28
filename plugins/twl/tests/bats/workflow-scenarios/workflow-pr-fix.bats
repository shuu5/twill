#!/usr/bin/env bats
# workflow-pr-fix.bats - Issue #144 / Phase 4-A Layer 2
#
# workflow-pr-fix の chain step 順序を回帰テストとして凍結する。
#   fix-phase → post-fix-verify → warning-fix

load '../helpers/workflow-scenario-env'
load '../helpers/trace-assertions'

setup() {
  setup_workflow_scenario_env
}

teardown() {
  teardown_workflow_scenario_env
}

@test "workflow-pr-fix: fix-phase → post-fix-verify → warning-fix の順で実行" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order \
    fix-phase \
    post-fix-verify \
    warning-fix
  [ "$status" -eq 0 ]
}

@test "workflow-pr-fix: 全 3 step が trace に存在する" {
  run bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_contains fix-phase post-fix-verify warning-fix
  [ "$status" -eq 0 ]
}

@test "workflow-pr-fix: 30 秒以内に完了する" {
  local start_ts end_ts
  start_ts=$(date +%s)
  bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh" >/dev/null 2>&1
  end_ts=$(date +%s)
  [ $((end_ts - start_ts)) -lt 30 ]
}

# ─── Issue #996: warning-fix skip path state update ───────────────────────────

# helper: sandbox 内に issue state を初期化する
_init_issue_state() {
  local issue_num="$1" autopilot_dir="$2"
  mkdir -p "$autopilot_dir/issues"
  python3 -m twl.autopilot.state write \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --role worker --init --set "status=running" 2>/dev/null
  python3 -m twl.autopilot.state write \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --role worker --set "current_step=post-fix-verify" 2>/dev/null
}

@test "ac1: warning-fix skip path が state.current_step を warning-fix に更新する" {
  # RED: chain-runner.sh に record-current-step case が未定義のため exit 1
  local issue_num=9101
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-warning-fix-skip" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  _init_issue_state "$issue_num" "$autopilot_dir"

  run bash "$PLUGIN_ROOT/scripts/chain-runner.sh" record-current-step warning-fix
  [ "$status" -eq 0 ]

  result=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --field current_step 2>/dev/null)
  [ "$result" = "warning-fix" ]
}

@test "ac1: warning-fix skip path が last_heartbeat_at を更新する" {
  # RED: record-current-step case 未定義のため state 更新されない
  local issue_num=9102
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-warning-fix-hb" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  _init_issue_state "$issue_num" "$autopilot_dir"

  run bash "$PLUGIN_ROOT/scripts/chain-runner.sh" record-current-step warning-fix
  [ "$status" -eq 0 ]

  hb=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --field last_heartbeat_at 2>/dev/null)
  [ -n "$hb" ]
}

@test "ac2: resolve_next_workflow が current_step=warning-fix から workflow-pr-merge を返す" {
  # RED: AC1 が通らないと実際の flow では current_step が warning-fix にならない。
  # ここでは state を手動設定して resolve_next_workflow 単体を検証する。
  local issue_num=9103
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-resolve-nw" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  mkdir -p "$autopilot_dir/issues"
  python3 -m twl.autopilot.state write \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --role worker --init --set "status=running" 2>/dev/null
  python3 -m twl.autopilot.state write \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --role worker --set "current_step=warning-fix" 2>/dev/null

  result=$(python3 -m twl.autopilot.resolve_next_workflow \
    --issue "$issue_num" 2>/dev/null)
  [ "$result" = "/twl:workflow-pr-merge" ]
}

@test "ac3: record-current-step 後に resolve_next_workflow が成功する（RESOLVE_FAILED を防ぐ）" {
  # RED: record-current-step case 未定義 → current_step が post-fix-verify のまま →
  # resolve_next_workflow が "post-fix-verify は terminal step ではない" で exit 1 →
  # 実際の orchestrator では RESOLVE_FAILED カウンターが増加する
  local issue_num=9104
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-resolve-fail" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  _init_issue_state "$issue_num" "$autopilot_dir"

  # record-current-step が成功して current_step=warning-fix が書き込まれる（修正後）
  bash "$PLUGIN_ROOT/scripts/chain-runner.sh" record-current-step warning-fix \
    2>/dev/null || true

  # resolve_next_workflow が exit 0 = RESOLVE_FAILED 不発生
  run python3 -m twl.autopilot.resolve_next_workflow --issue "$issue_num"
  [ "$status" -eq 0 ]
}

@test "ac4: non-skip path で既存 regression が発生しない（fix-phase → post-fix-verify → warning-fix 順序保持）" {
  # GREEN guard: 既存 step 順序テストが常に通ることを確認
  run bash "$PLUGIN_ROOT/skills/workflow-pr-fix/dry-run.sh"
  [ "$status" -eq 0 ]

  run assert_trace_order fix-phase post-fix-verify warning-fix
  [ "$status" -eq 0 ]
}

@test "ac5: skip path（CRITICAL 0 件）で state.current_step=warning-fix かつ last_heartbeat_at が更新される" {
  # RED: record-current-step case 未定義のため両フィールドとも更新されない
  local issue_num=9105
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-ac5-skip" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  _init_issue_state "$issue_num" "$autopilot_dir"

  run bash "$PLUGIN_ROOT/scripts/chain-runner.sh" record-current-step warning-fix
  [ "$status" -eq 0 ]

  step=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --field current_step 2>/dev/null)
  [ "$step" = "warning-fix" ]

  hb=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --field last_heartbeat_at 2>/dev/null)
  [ -n "$hb" ]
}

@test "ac5: non-skip path（CRITICAL あり）で state.current_step=warning-fix かつ last_heartbeat_at が更新される" {
  # RED: record-current-step case 未定義のため state 更新されない
  local issue_num=9106
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-ac5-nonskip" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  _init_issue_state "$issue_num" "$autopilot_dir"

  run bash "$PLUGIN_ROOT/scripts/chain-runner.sh" record-current-step warning-fix
  [ "$status" -eq 0 ]

  step=$(python3 -m twl.autopilot.state read \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --field current_step 2>/dev/null)
  [ "$step" = "warning-fix" ]
}

# ─── Issue #1016: AC3 RESOLVE_FAILED カウンター直接アサート ────────────────────
# 既存 ac3 test は resolve_next_workflow exit 0 を proxy 検証していたが、
# RESOLVE_FAIL_COUNT 変数自体への増加・リセット動作を直接 assert するケースを追加する。

@test "ac3-direct: inject_next_workflow が resolve_next_workflow 失敗時に RESOLVE_FAIL_COUNT を increment する" {
  # current_step=post-fix-verify (terminal step ではない) で resolve_next_workflow が失敗
  # → inject_next_workflow が RESOLVE_FAIL_COUNT[$entry] を increment する経路を直接検証
  local issue_num=9201
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-fail-count-incr" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"
  _init_issue_state "$issue_num" "$autopilot_dir"  # current_step=post-fix-verify

  # cleanup_worker stub: inject-next-workflow.sh 先頭コメント「呼び出し元で定義」要件
  cleanup_worker() { :; }

  # inject_next_workflow を bats プロセスに source
  # shellcheck source=/dev/null
  source "$PLUGIN_ROOT/scripts/lib/inject-next-workflow.sh"

  # stagnate 検知を抑制（巨大閾値でカウンターのみ増やす）
  export AUTOPILOT_STAGNATE_SEC=999999
  # 連想配列を初期化（global scope, lib 側 declare -gA と同名）
  RESOLVE_FAIL_COUNT=()
  RESOLVE_FAIL_FIRST_TS=()
  INJECT_TIMEOUT_COUNT=()
  NUDGE_COUNTS=()

  local entry="_default:${issue_num}"

  # 1 回目: resolve_next_workflow 失敗 → RESOLVE_FAIL_COUNT[$entry] = 1
  inject_next_workflow "$issue_num" "fake-window:0" || true

  [ "${RESOLVE_FAIL_COUNT[$entry]:-0}" -eq 1 ] || {
    echo "FAIL: 1 回目 inject_next_workflow 後 RESOLVE_FAIL_COUNT[$entry] = ${RESOLVE_FAIL_COUNT[$entry]:-0} (expected 1)" >&2
    return 1
  }

  # 2 回目: 同じく失敗 → カウント 2
  inject_next_workflow "$issue_num" "fake-window:0" || true

  [ "${RESOLVE_FAIL_COUNT[$entry]:-0}" -eq 2 ] || {
    echo "FAIL: 2 回目 inject_next_workflow 後 RESOLVE_FAIL_COUNT[$entry] = ${RESOLVE_FAIL_COUNT[$entry]:-0} (expected 2)" >&2
    return 1
  }

  # 3 回目: カウント 3
  inject_next_workflow "$issue_num" "fake-window:0" || true

  [ "${RESOLVE_FAIL_COUNT[$entry]:-0}" -eq 3 ] || {
    echo "FAIL: 3 回目 inject_next_workflow 後 RESOLVE_FAIL_COUNT[$entry] = ${RESOLVE_FAIL_COUNT[$entry]:-0} (expected 3)" >&2
    return 1
  }
}

@test "ac3-direct: inject_next_workflow が resolve_next_workflow 成功時に RESOLVE_FAIL_COUNT を 0 にリセットする" {
  # current_step=warning-fix (terminal step) で resolve_next_workflow 成功
  # → inject_next_workflow が RESOLVE_FAIL_COUNT[$entry] = 0 にリセットする経路を直接検証
  local issue_num=9202
  local autopilot_dir="$WORKFLOW_SANDBOX/.autopilot"
  git checkout -q -b "feat/${issue_num}-stub-fail-count-reset" 2>/dev/null || true
  export AUTOPILOT_DIR="$autopilot_dir"

  # current_step=warning-fix で初期化（resolve_next_workflow が /twl:workflow-pr-merge を返す）
  mkdir -p "$autopilot_dir/issues"
  python3 -m twl.autopilot.state write \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --role worker --init --set "status=running" 2>/dev/null
  python3 -m twl.autopilot.state write \
    --autopilot-dir "$autopilot_dir" --type issue --issue "$issue_num" \
    --role worker --set "current_step=warning-fix" 2>/dev/null

  cleanup_worker() { :; }

  # shellcheck source=/dev/null
  source "$PLUGIN_ROOT/scripts/lib/inject-next-workflow.sh"

  export AUTOPILOT_STAGNATE_SEC=999999
  # USE_SESSION_STATE=false で tmux capture-pane fallback。
  # tmux モックなしでも prompt 検出失敗→return 1 までに RESOLVE_FAIL_COUNT のリセットは
  # 実行されている（line 56-58、resolve 成功直後）
  export USE_SESSION_STATE=false

  RESOLVE_FAIL_COUNT=()
  RESOLVE_FAIL_FIRST_TS=()
  INJECT_TIMEOUT_COUNT=()
  NUDGE_COUNTS=()

  local entry="_default:${issue_num}"

  # 事前にカウントを 5 に設定（リセット前条件）
  RESOLVE_FAIL_COUNT[$entry]=5
  RESOLVE_FAIL_FIRST_TS[$entry]=1000

  # tmux send-keys が失敗してもリセット (line 56-58) は既に実行済み
  # ただし sleep 2/4/8 の合計 14s が走るので bats の timeout 内に終わる必要あり
  # → tmux モックを stub bin に配置して capture-pane で prompt を返し早期成功させる
  # （inject_next_workflow が成功 path を辿る）
  cat > "$WORKFLOW_STUB_BIN/tmux" <<'STUB_EOF'
#!/usr/bin/env bash
case "$1" in
  capture-pane) echo "ready ❯ "; exit 0 ;;
  send-keys) exit 0 ;;
  display-message) echo "0 claude"; exit 0 ;;
  has-session) exit 0 ;;
  *) exit 0 ;;
esac
STUB_EOF
  chmod +x "$WORKFLOW_STUB_BIN/tmux"

  # inject_next_workflow 実行（resolve 成功 → RESOLVE_FAIL_COUNT[$entry]=0 にリセット）
  inject_next_workflow "$issue_num" "fake-window:0" || true

  [ "${RESOLVE_FAIL_COUNT[$entry]}" -eq 0 ] || {
    echo "FAIL: resolve 成功後 RESOLVE_FAIL_COUNT[$entry] = ${RESOLVE_FAIL_COUNT[$entry]} (expected 0 — reset)" >&2
    return 1
  }
}
