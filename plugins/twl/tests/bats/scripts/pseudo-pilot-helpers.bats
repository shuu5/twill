#!/usr/bin/env bats
# pseudo-pilot-helpers.bats - unit tests for scripts/pseudo-pilot/
#
# Spec: Issue #168 — Pseudo-Pilot helper の永続化: ad-hoc /tmp スクリプトの plugins/twl/scripts/ 移管
#
# Coverage:
#   1. 正常系: pr-wait.sh が gh stub で PR 番号を echo して exit 0
#   2. timeout: pr-wait.sh が PR 不在 stub + --timeout 1 で exit 1
#   3. 正常系: worker-done-wait.sh が session-state stub で exit 0
#   4. 状態判定: worker-done-wait.sh が processing→timeout で exit 1

load '../helpers/common'

setup() {
  common_setup

  # Copy pseudo-pilot scripts into sandbox
  mkdir -p "$SANDBOX/scripts/pseudo-pilot"
  cp "$REPO_ROOT/scripts/pseudo-pilot/pr-wait.sh" "$SANDBOX/scripts/pseudo-pilot/"
  cp "$REPO_ROOT/scripts/pseudo-pilot/worker-done-wait.sh" "$SANDBOX/scripts/pseudo-pilot/"
  chmod +x "$SANDBOX/scripts/pseudo-pilot/pr-wait.sh"
  chmod +x "$SANDBOX/scripts/pseudo-pilot/worker-done-wait.sh"

  # Create a stub session-state.sh at the relative path worker-done-wait.sh expects:
  # scripts/pseudo-pilot/../../session/scripts/session-state.sh
  mkdir -p "$SANDBOX/session/scripts"
  cat > "$SANDBOX/session/scripts/session-state.sh" <<'EOF'
#!/usr/bin/env bash
echo "${SESSION_STATE_STUB_OUTPUT:-unknown}"
EOF
  chmod +x "$SANDBOX/session/scripts/session-state.sh"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Test 1: 正常系 — pr-wait.sh が gh stub で PR 番号を echo して exit 0
# ---------------------------------------------------------------------------

@test "正常系: pr-wait.sh が gh stub で PR 番号を echo して exit 0" {
  stub_command "gh" 'echo "123"'

  run "$SANDBOX/scripts/pseudo-pilot/pr-wait.sh" "feat/123-test"

  assert_success
  assert_output "123"
}

# ---------------------------------------------------------------------------
# Test 2: timeout — pr-wait.sh が PR 不在 stub + --timeout 1 で exit 1
# ---------------------------------------------------------------------------

@test "timeout: pr-wait.sh が PR 不在時に --timeout 1 で exit 1" {
  stub_command "gh" 'exit 1'

  run "$SANDBOX/scripts/pseudo-pilot/pr-wait.sh" "feat/123-test" --timeout 1 --interval 1

  assert_failure 1
  assert_output --partial "timeout after 1s"
}

# ---------------------------------------------------------------------------
# Test 3: 正常系 — worker-done-wait.sh が session-state stub で exit 0
# ---------------------------------------------------------------------------

@test "正常系: worker-done-wait.sh が input-waiting 状態で exit 0" {
  export SESSION_STATE_STUB_OUTPUT="input-waiting"

  run "$SANDBOX/scripts/pseudo-pilot/worker-done-wait.sh" "worker-01"

  assert_success
}

# ---------------------------------------------------------------------------
# Test 4: 状態判定 — processing を返した場合は polling 継続し --timeout 1 で exit 1
# ---------------------------------------------------------------------------

@test "状態判定: worker-done-wait.sh が processing 返却時に --timeout 1 で exit 1" {
  export SESSION_STATE_STUB_OUTPUT="processing"

  run "$SANDBOX/scripts/pseudo-pilot/worker-done-wait.sh" "worker-01" --timeout 1 --interval 1

  assert_failure 1
  assert_output --partial "timeout after 1s"
}
