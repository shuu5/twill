#!/usr/bin/env bash
# git-fixture.bash - git repository fixture helpers for co-self-improve e2e tests
#
# 5 helper functions:
#   init_temp_repo    - create temporary git repo with initial commit
#   cleanup_temp_repo - remove temporary git repo
#   mock_tmux_window  - stub tmux command to simulate a window
#   mock_agent_call   - stub agent (cld) command and record calls to log
#   verify_orphan_branch - assert two branches share no common ancestor

# init_temp_repo [dir]
# Creates a temporary git repo with an initial empty commit.
# Sets TMP_REPO to the created directory.
# Returns: absolute path to the created repo.
init_temp_repo() {
  local dir="${1:-$(mktemp -d)}"
  TMP_REPO="$dir"
  export TMP_REPO

  (
    cd "$TMP_REPO"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test User"
    git commit --allow-empty -m "initial" -q
  )

  echo "$TMP_REPO"
}

# cleanup_temp_repo [dir]
# Removes the temporary git repo.
# Uses TMP_REPO if dir is not provided.
cleanup_temp_repo() {
  local dir="${1:-${TMP_REPO:-}}"
  if [[ -n "$dir" && -d "$dir" ]]; then
    rm -rf "$dir"
  fi
  unset TMP_REPO
}

# mock_tmux_window <window_name> [stub_output]
# Creates a STUB_BIN/tmux stub that returns stub_output for capture-pane
# and window_name for list-windows.
# Requires common_setup to have been called (STUB_BIN must be set).
mock_tmux_window() {
  local window_name="$1"
  local stub_output="${2:-}"

  if [[ -z "${STUB_BIN:-}" ]]; then
    echo "mock_tmux_window: STUB_BIN not set; call common_setup first" >&2
    return 1
  fi

  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
# stub tmux: window=${window_name}
case "\$1" in
  capture-pane)
    echo "${stub_output}"
    exit 0
    ;;
  list-windows)
    echo "${window_name}"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"
}

# mock_agent_call <log_file>
# Creates a STUB_BIN/cld stub that records all invocation args to log_file.
# Sets AGENT_CALL_LOG to log_file.
# Requires common_setup to have been called (STUB_BIN must be set).
mock_agent_call() {
  local log_file="${1:-/tmp/agent-calls.log}"
  : > "$log_file"
  export AGENT_CALL_LOG="$log_file"

  if [[ -z "${STUB_BIN:-}" ]]; then
    echo "mock_agent_call: STUB_BIN not set; call common_setup first" >&2
    return 1
  fi

  cat > "$STUB_BIN/cld" <<STUB
#!/usr/bin/env bash
# stub cld: records invocations to ${log_file}
echo "\$(date -u +%FT%TZ) \$*" >> "${log_file}"
echo '{"status":"ok","specialist":"mock","output":"stub"}'
exit 0
STUB
  chmod +x "$STUB_BIN/cld"
}

# verify_orphan_branch <branch_a> <branch_b> [repo_dir]
# Asserts that branch_a and branch_b share no common ancestor (orphan branch).
# Returns 0 if orphan (no common commit), 1 if they share history.
verify_orphan_branch() {
  local branch_a="$1"
  local branch_b="$2"
  local repo_dir="${3:-${TMP_REPO:-$(pwd)}}"

  local common
  common=$(cd "$repo_dir" && git merge-base "$branch_a" "$branch_b" 2>/dev/null || echo "")
  [[ -z "$common" ]]
}
