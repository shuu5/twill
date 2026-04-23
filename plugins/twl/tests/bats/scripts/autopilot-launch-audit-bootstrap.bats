#!/usr/bin/env bats
# autopilot-launch-audit-bootstrap.bats - #897-A + #897-B
#
# Spec: Issue #897 — autopilot-launch.sh で Worker 起動時に cross-repo audit + pipe-pane を自動 bootstrap
#
# Coverage:
#   (A1) Worker cwd で audit 非 active → bootstrap で audit on --run-id auto-<parent>-issue-<N>
#   (A2) Worker cwd で既に audit active → bootstrap skip (既存セッション継続)
#   (B1) audit active → tmux pipe-pane で pane log 永続化
#   (B2) audit bootstrap 失敗 → pipe-pane skip (regression 防止)
#
# pattern: autopilot-launch-merge-context.bats と同じ standard repo setup

load '../helpers/common'

setup() {
  common_setup

  # tmux stub: new-window / pipe-pane / set-option / set-hook / display-message / list-windows を記録
  TMUX_LOG="$SANDBOX/tmux-calls.log"
  export TMUX_LOG
  : > "$TMUX_LOG"

  cat > "$STUB_BIN/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_LOG"
case "$1" in
  display-message) echo "main" ;;
  list-windows) echo "" ;;
  *) exit 0 ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"

  # cld stub
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_BIN/cld"
  chmod +x "$STUB_BIN/cld"

  # gh stub: quick label なし
  stub_command "gh" '
    case "$*" in
      *"issue view"*"--json labels"*) echo "" ;;
      *) echo "{}" ;;
    esac
  '

  # git stub
  stub_command "git" '
    case "$*" in
      *"rev-parse"*) echo "$SANDBOX" ;;
      *"worktree list"*) echo "" ;;
      *) exit 0 ;;
    esac
  '

  # python3 stub: audit status / audit on / state write / worktree create を制御
  AUDIT_BOOTSTRAP_LOG="$SANDBOX/audit-bootstrap.log"
  export AUDIT_BOOTSTRAP_LOG
  : > "$AUDIT_BOOTSTRAP_LOG"

  AUDIT_BOOTSTRAPPED_FLAG="$SANDBOX/audit-bootstrapped.flag"
  export AUDIT_BOOTSTRAPPED_FLAG

  # シナリオ制御変数 (テスト毎に export で override)
  AUDIT_WORKER_ACTIVE="${AUDIT_WORKER_ACTIVE:-false}"
  AUDIT_PARENT_ACTIVE="${AUDIT_PARENT_ACTIVE:-true}"
  AUDIT_BOOTSTRAP_SUCCESS="${AUDIT_BOOTSTRAP_SUCCESS:-true}"
  AUDIT_DIR_AFTER_BOOTSTRAP="${AUDIT_DIR_AFTER_BOOTSTRAP:-$SANDBOX/.audit/auto-parent-run-issue-897}"
  AUDIT_WORKER_DIR="${AUDIT_WORKER_DIR:-$SANDBOX/.audit/existing-worker-run}"
  export AUDIT_WORKER_ACTIVE AUDIT_PARENT_ACTIVE AUDIT_BOOTSTRAP_SUCCESS AUDIT_DIR_AFTER_BOOTSTRAP AUDIT_WORKER_DIR

  cat > "$STUB_BIN/python3" <<'PYSTUB'
#!/usr/bin/env bash
case "$*" in
  *"twl.autopilot.worktree create"*) exit 1 ;;
  *"twl.autopilot.audit status"*)
    _CWD=$(pwd)
    # SCRIPTS_ROOT (git toplevel = SANDBOX/scripts) からの呼出 → parent
    # TEST_PROJECT_DIR (SANDBOX/project) からの呼出 → Worker
    if [[ "$_CWD" == *"/project"* ]]; then
      # Worker cwd audit status
      if [[ -f "${AUDIT_BOOTSTRAPPED_FLAG:-/nonexistent}" ]]; then
        echo "active: true"
        echo "run_id: auto-parent-run-issue-897"
        echo "audit_dir: ${AUDIT_DIR_AFTER_BOOTSTRAP}"
      elif [[ "${AUDIT_WORKER_ACTIVE:-false}" == "true" ]]; then
        echo "active: true"
        echo "run_id: existing-worker-run"
        echo "audit_dir: ${AUDIT_WORKER_DIR}"
      else
        echo "active: false"
      fi
    else
      # parent (SCRIPTS_ROOT) audit status
      if [[ "${AUDIT_PARENT_ACTIVE:-true}" == "true" ]]; then
        echo "active: true"
        echo "run_id: parent-run"
        echo "audit_dir: $SANDBOX/parent-audit-dir"
      else
        echo "active: false"
      fi
    fi
    exit 0 ;;
  *"twl.autopilot.audit on"*)
    _RUN_ID=""
    _NEXT=false
    for _ARG in "$@"; do
      if [[ "$_NEXT" == "true" ]]; then _RUN_ID="$_ARG"; break; fi
      if [[ "$_ARG" == "--run-id" ]]; then _NEXT=true; fi
    done
    echo "audit on run_id=$_RUN_ID cwd=$(pwd)" >> "$AUDIT_BOOTSTRAP_LOG"
    if [[ "${AUDIT_BOOTSTRAP_SUCCESS:-true}" == "true" ]]; then
      touch "${AUDIT_BOOTSTRAPPED_FLAG}" 2>/dev/null || true
      exit 0
    fi
    exit 1 ;;
  *"twl.autopilot.state"*) exit 0 ;;
  *) exit 0 ;;
esac
PYSTUB
  chmod +x "$STUB_BIN/python3"

  # test project: standard repo (not bare)
  mkdir -p "$SANDBOX/project/.git"
  mkdir -p "$SANDBOX/.autopilot/trace"
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "test-897-session", "started_at": "2026-04-23T00:00:00Z"}
JSON
  TEST_PROJECT_DIR="$SANDBOX/project"
  export TEST_PROJECT_DIR

  # 既存 audit dir を用意
  mkdir -p "$AUDIT_WORKER_DIR"
  mkdir -p "$AUDIT_DIR_AFTER_BOOTSTRAP"
}

teardown() {
  common_teardown
}

_run_launch() {
  local issue="${1:-897}"
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue" \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "$SANDBOX/.autopilot" \
    --context "test context"
}

# ---------------------------------------------------------------------------
# Scenario (A1): Worker cwd audit 非 active → bootstrap で audit on 発火
# ---------------------------------------------------------------------------

@test "#897-A (A1): Worker cwd audit 非 active で parent run 引継ぎ audit on" {
  export AUDIT_WORKER_ACTIVE="false"
  export AUDIT_PARENT_ACTIVE="true"

  _run_launch 897
  assert_success

  # audit bootstrap 呼出記録を確認
  [ -f "$AUDIT_BOOTSTRAP_LOG" ]
  grep -qE "run_id=auto-parent-run-issue-897" "$AUDIT_BOOTSTRAP_LOG"
}

# ---------------------------------------------------------------------------
# Scenario (A2): Worker cwd 既に audit active → bootstrap skip
# ---------------------------------------------------------------------------

@test "#897-A (A2): Worker cwd 既に audit active なら bootstrap skip" {
  export AUDIT_WORKER_ACTIVE="true"

  _run_launch 897
  assert_success

  # audit on は呼ばれていない
  if [[ -s "$AUDIT_BOOTSTRAP_LOG" ]]; then
    ! grep -qE "run_id=auto-" "$AUDIT_BOOTSTRAP_LOG"
  fi
}

# ---------------------------------------------------------------------------
# Scenario (B1): audit bootstrap 成功 → pipe-pane 実行
# ---------------------------------------------------------------------------

@test "#897-B (B1): audit bootstrap 成功後 tmux pipe-pane で pane log 永続化" {
  export AUDIT_WORKER_ACTIVE="false"
  export AUDIT_PARENT_ACTIVE="true"
  export AUDIT_BOOTSTRAP_SUCCESS="true"

  _run_launch 897
  assert_success

  # tmux pipe-pane が呼ばれた
  [ -f "$TMUX_LOG" ]
  grep -qE "^pipe-pane" "$TMUX_LOG"
  # pane log path に audit dir が含まれる
  grep -qF "$AUDIT_DIR_AFTER_BOOTSTRAP" "$TMUX_LOG"
}

# ---------------------------------------------------------------------------
# Scenario (B2): bootstrap 失敗で audit dir 解決できない → pipe-pane skip
# ---------------------------------------------------------------------------

@test "#897-B (B2): bootstrap 失敗時は pipe-pane skip (regression 防止)" {
  export AUDIT_WORKER_ACTIVE="false"
  export AUDIT_PARENT_ACTIVE="false"
  export AUDIT_BOOTSTRAP_SUCCESS="false"

  _run_launch 897
  assert_success

  # pipe-pane は呼ばれていない
  if [[ -s "$TMUX_LOG" ]]; then
    ! grep -qE "^pipe-pane" "$TMUX_LOG"
  fi
}
