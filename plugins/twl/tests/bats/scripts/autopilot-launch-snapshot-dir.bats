#!/usr/bin/env bats
# autopilot-launch-snapshot-dir.bats
# Spec: #1176 — SNAPSHOT_DIR auto-set in autopilot Worker
#
# Coverage:
#   AC1: tmux new-window env inject に SNAPSHOT_DIR= が含まれる
#   AC3: --worktree-dir 指定で LAUNCH_DIR が SNAPSHOT_DIR の base path になる
#   AC5: chain-runner.sh の export SNAPSHOT_DIR= が削除されていないこと（guard）
#   AC6: pitfalls-catalog.md §14.4 が追加されていること

load '../helpers/common'

setup() {
  common_setup

  TMUX_CMD_FILE="$SANDBOX/tmux-new-window.txt"
  export TMUX_CMD_FILE
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
case "\$1" in
  new-window)
    printf '%s\n' "\$*" >> "${TMUX_CMD_FILE}"
    exit 0 ;;
  set-option|set-hook|display-message|list-windows)
    exit 0 ;;
  *)
    exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  cat > "$STUB_BIN/cld" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_BIN/cld"

  stub_command "gh" '
    case "$*" in
      *"project item-list"*)
        echo "{\"items\":[{\"id\":\"I_1176\",\"content\":{\"number\":1176,\"type\":\"Issue\"},\"status\":\"In Progress\"},{\"id\":\"I_42\",\"content\":{\"number\":42,\"type\":\"Issue\"},\"status\":\"Refined\"},{\"id\":\"I_999\",\"content\":{\"number\":999,\"type\":\"Issue\"},\"status\":\"In Progress\"}]}" ;;
      *"repo view"*"--json owner"*)
        echo "shuu5" ;;
      *"issue view"*"--json labels"*)
        echo "" ;;
      *)
        echo "{}" ;;
    esac
  '

  stub_command "git" '
    case "$*" in
      *"rev-parse"*) echo "$SANDBOX" ;;
      *"worktree list"*) echo "" ;;
      *) exit 0 ;;
    esac
  '

  cat > "$STUB_BIN/python3" <<STUB
#!/usr/bin/env bash
case "\$*" in
  *"worktree create"*) exit 1 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/python3"

  mkdir -p "$SANDBOX/.autopilot/trace"
  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{"session_id": "test-session-1176", "started_at": "2026-04-30T00:00:00Z"}
JSON

  mkdir -p "$SANDBOX/project/.git"
  TEST_PROJECT_DIR="$SANDBOX/project"
  export TEST_PROJECT_DIR

  mkdir -p "$SANDBOX/wt/.git"
}

teardown() {
  common_teardown
}

_run_launch() {
  local issue="${1:-1176}"
  local extra_args="${2:-}"
  # shellcheck disable=SC2086
  run bash "$SANDBOX/scripts/autopilot-launch.sh" \
    --issue "$issue" \
    --project-dir "$TEST_PROJECT_DIR" \
    --autopilot-dir "$SANDBOX/.autopilot" \
    $extra_args
}

_get_tmux_cmd() {
  cat "$TMUX_CMD_FILE" 2>/dev/null || echo ""
}

_tmux_cmd_contains() {
  local keyword="$1"
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  echo "$tmux_cmd" | tr -d '\\' | grep -qF "$keyword"
}

# ---------------------------------------------------------------------------
# AC1: tmux new-window の env inject に SNAPSHOT_DIR= が含まれる
# ---------------------------------------------------------------------------

@test "snapshot-dir: SNAPSHOT_DIR= が tmux new-window の env inject に含まれる" {
  _run_launch 1176

  assert_success
  _tmux_cmd_contains "SNAPSHOT_DIR="
}

@test "snapshot-dir: SNAPSHOT_DIR に .dev-session/issue-1176 が含まれる" {
  _run_launch 1176

  assert_success
  _tmux_cmd_contains ".dev-session/issue-1176"
}

@test "snapshot-dir: Issue 番号が異なる場合も SNAPSHOT_DIR に正しい Issue 番号が含まれる" {
  _run_launch 42

  assert_success
  _tmux_cmd_contains ".dev-session/issue-42"
}

# ---------------------------------------------------------------------------
# AC3: --worktree-dir 指定で LAUNCH_DIR が SNAPSHOT_DIR の base path になる
# ---------------------------------------------------------------------------

@test "snapshot-dir: --worktree-dir 指定時に SNAPSHOT_DIR の base path が WORKTREE_DIR になる" {
  _run_launch 1176 "--worktree-dir $SANDBOX/wt"

  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  # SNAPSHOT_DIR=$SANDBOX/wt/.dev-session/issue-1176 相当が含まれること
  echo "$tmux_cmd" | tr -d '\\' | grep -qF "wt/.dev-session/issue-1176"
}

@test "snapshot-dir: --worktree-dir 指定時に SNAPSHOT_DIR が project-dir 配下にならない" {
  _run_launch 1176 "--worktree-dir $SANDBOX/wt"

  assert_success
  local tmux_cmd
  tmux_cmd=$(_get_tmux_cmd)
  # worktree-dir が指定された場合、wt/.dev-session になること（正）
  echo "$tmux_cmd" | tr -d '\\' | grep -qF "wt/.dev-session/issue-1176"
  # project/.dev-session ではないこと（負の検証）
  ! echo "$tmux_cmd" | tr -d '\\' | grep -qF "project/.dev-session"
}

# ---------------------------------------------------------------------------
# AC5: chain-runner.sh の export SNAPSHOT_DIR= が削除されていないこと（guard）
# ---------------------------------------------------------------------------

@test "snapshot-dir: chain-runner.sh L330 の export SNAPSHOT_DIR= が保持されている（SSOT 維持）" {
  local chain_runner
  chain_runner="$SANDBOX/scripts/chain-runner.sh"
  [[ -f "$chain_runner" ]] || skip "chain-runner.sh が sandbox にコピーされていない"

  grep -q 'export SNAPSHOT_DIR=' "$chain_runner"
}

# ---------------------------------------------------------------------------
# AC6: pitfalls-catalog.md §14.4 が追加されていること
# ---------------------------------------------------------------------------

@test "snapshot-dir: pitfalls-catalog.md に §14.4 エントリが存在する" {
  local catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  [[ -f "$catalog" ]] || skip "pitfalls-catalog.md が見つからない"

  grep -F '14.4' "$catalog"
}

@test "snapshot-dir: pitfalls-catalog.md §14.4 に #1176 への言及が含まれる" {
  local catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  [[ -f "$catalog" ]] || skip "pitfalls-catalog.md が見つからない"

  grep -A5 '14.4' "$catalog" | grep -qF '#1176'
}

@test "snapshot-dir: pitfalls-catalog.md §14.4 に defense in depth への言及が含まれる" {
  local catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"
  [[ -f "$catalog" ]] || skip "pitfalls-catalog.md が見つからない"

  grep -A5 '14.4' "$catalog" | grep -qF 'defense in depth'
}
