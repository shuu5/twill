#!/usr/bin/env bash
# =============================================================================
# Scenario: chain-runner.sh --trace + TWL_CHAIN_TRACE
# Verifies Phase 3 / Layer 1 trace event recording.
# =============================================================================
set -uo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHAIN_RUNNER="$PLUGIN_ROOT/scripts/chain-runner.sh"

PASS=0
FAIL=0
ERRORS=()

run_test() {
  local name="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$name")
    echo "  FAIL: $name"
  fi
}

# Use a per-test temp dir to avoid leaking state.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Invoking init without an issue number runs the no-op-style branch and exits 0.
# We use the env-var form (no flag) for the first test.
test_trace_via_env_var_records_start_and_end() {
  local trace_file="$TMP_DIR/env.jsonl"
  ( cd "$PLUGIN_ROOT" && \
    TWL_CHAIN_TRACE="$trace_file" bash "$CHAIN_RUNNER" check >/dev/null 2>&1 ) || true
  [[ -s "$trace_file" ]] || return 1
  grep -q '"step":"check"' "$trace_file" || return 1
  grep -q '"phase":"start"' "$trace_file" || return 1
  grep -q '"phase":"end"' "$trace_file" || return 1
}

# --trace <path> flag form
test_trace_via_flag_records_event() {
  local trace_file="$TMP_DIR/flag.jsonl"
  ( cd "$PLUGIN_ROOT" && \
    bash "$CHAIN_RUNNER" --trace "$trace_file" check >/dev/null 2>&1 ) || true
  [[ -s "$trace_file" ]] || return 1
  grep -q '"step":"check"' "$trace_file" || return 1
}

# --trace=<path> form (single argument)
test_trace_via_equals_form() {
  local trace_file="$TMP_DIR/equals.jsonl"
  ( cd "$PLUGIN_ROOT" && \
    bash "$CHAIN_RUNNER" --trace="$trace_file" check >/dev/null 2>&1 ) || true
  [[ -s "$trace_file" ]] || return 1
  grep -q '"step":"check"' "$trace_file" || return 1
}

# Without the env var or flag, no trace file is created and behaviour is unchanged.
test_no_trace_no_file() {
  local trace_file="$TMP_DIR/should-not-exist.jsonl"
  unset TWL_CHAIN_TRACE
  ( cd "$PLUGIN_ROOT" && \
    bash "$CHAIN_RUNNER" check >/dev/null 2>&1 ) || true
  [[ ! -e "$trace_file" ]] || return 1
}

# Each invocation appends events; multiple runs accumulate lines.
test_trace_appends_events() {
  local trace_file="$TMP_DIR/append.jsonl"
  ( cd "$PLUGIN_ROOT" && \
    TWL_CHAIN_TRACE="$trace_file" bash "$CHAIN_RUNNER" check >/dev/null 2>&1 ) || true
  ( cd "$PLUGIN_ROOT" && \
    TWL_CHAIN_TRACE="$trace_file" bash "$CHAIN_RUNNER" check >/dev/null 2>&1 ) || true
  local line_count
  line_count=$(wc -l < "$trace_file")
  [[ "$line_count" -ge 4 ]] || return 1
}

# Trace events are valid JSON Lines (each line parses).
test_trace_lines_are_valid_json() {
  local trace_file="$TMP_DIR/json.jsonl"
  ( cd "$PLUGIN_ROOT" && \
    TWL_CHAIN_TRACE="$trace_file" bash "$CHAIN_RUNNER" check >/dev/null 2>&1 ) || true
  [[ -s "$trace_file" ]] || return 1
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    echo "$line" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' || return 1
  done < "$trace_file"
}

# Path traversal is rejected (no file should be created when path contains ..).
test_path_traversal_rejected() {
  local trace_file="$TMP_DIR/../etc-evil.jsonl"
  ( cd "$PLUGIN_ROOT" && \
    bash "$CHAIN_RUNNER" --trace "$trace_file" check >/dev/null 2>&1 ) || true
  [[ ! -e "$trace_file" ]] || return 1
}

run_test "trace_via_env_var_records_start_and_end" test_trace_via_env_var_records_start_and_end
run_test "trace_via_flag_records_event"            test_trace_via_flag_records_event
run_test "trace_via_equals_form"                   test_trace_via_equals_form
run_test "no_trace_no_file"                        test_no_trace_no_file
run_test "trace_appends_events"                    test_trace_appends_events
run_test "trace_lines_are_valid_json"              test_trace_lines_are_valid_json
run_test "path_traversal_rejected"                 test_path_traversal_rejected

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  echo "Failures: ${ERRORS[*]}"
  exit 1
fi
exit 0
