#!/usr/bin/env bats
# pre-bash-issue-create-gate.bats — AC2 GREEN テスト
#
# Issue #1578: feat(supervisor): Issue 起票前 co-explore 強制 enforcement
# AC2: pre-bash-issue-create-gate.sh 実装 + bats 12 シナリオ (S1-S12 全 PASS)
#
# Hook interface: JSON payload via stdin
#   {tool_name:"Bash", tool_input:{command:"<cmd>"}}
# Deny: hook outputs {hookSpecificOutput:{permissionDecision:"deny",...}}, exits 0
# Allow: hook outputs nothing (or non-deny), exits 0
#
# Scenarios:
#   S1:  gh issue create + no allow path → deny
#   S2:  gh issue create + SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON='trivial config' → allow
#   S3:  gh issue create + TWL_CALLER_AUTHZ=co-issue-phase4-create + summary file → allow
#   S4:  gh issue create --template + no allow path → deny
#   S5:  gh issue create + SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON='...' + --repo → allow (cross-repo)
#   S6:  gh pr create → allow（gate 対象外コマンド）
#   S7:  gh issue list → allow（gate 対象外コマンド）
#   S8:  git commit → allow（gh issue create でないため対象外）
#   S9:  SKIP_ISSUE_GATE=1 のみ (SKIP_ISSUE_REASON 欠落) → deny
#   S10: gh issue create (先頭空白あり) + no allow path → deny
#   S11: gh issue create → deny + "co-explore" を含む actionable message
#   S12: TWL_CALLER_AUTHZ=co-explore-bootstrap + state file なし → deny (state file 必須)

load '../helpers/common'

GATE_SCRIPT="scripts/hooks/pre-bash-issue-create-gate.sh"
GATE_PATH=""
TMP_DIR=""

setup() {
  common_setup
  GATE_PATH="$REPO_ROOT/$GATE_SCRIPT"
  TMP_DIR="$SANDBOX/tmp-session"
  mkdir -p "$TMP_DIR"
}

teardown() {
  common_teardown
}

# Build Bash tool JSON payload
_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Run hook with JSON payload on stdin; SESSION_TMP_DIR and CONTROLLER_ISSUE_DIR isolated
_run_hook() {
  local payload="$1"
  echo "$payload" | SESSION_TMP_DIR="$TMP_DIR" CONTROLLER_ISSUE_DIR="$SANDBOX/.controller-issue" bash "$GATE_PATH"
}

# Check if hook output is a deny decision
_is_deny() {
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# S1: gh issue create + no allow path → deny
# ---------------------------------------------------------------------------

@test "S1: gh issue create + no allow path → deny" {
  skip_if_gate_missing

  run _run_hook "$(_payload "gh issue create --title 'test' --body 'body'")"

  assert_success  # hook always exits 0
  _is_deny || fail "expected deny but got allow"
}

# ---------------------------------------------------------------------------
# S2: gh issue create + SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON → allow
# ---------------------------------------------------------------------------

@test "S2: gh issue create + SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON → allow" {
  skip_if_gate_missing

  run _run_hook "$(_payload "SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='trivial config: label rename' gh issue create --title 'test'")"

  assert_success
  _is_deny && fail "expected allow but got deny"
  true
}

# ---------------------------------------------------------------------------
# S3: gh issue create + TWL_CALLER_AUTHZ=co-issue-phase4-create + summary file → allow
# ---------------------------------------------------------------------------

@test "S3: gh issue create + TWL_CALLER_AUTHZ=co-issue-phase4-create + summary → allow" {
  skip_if_gate_missing

  # create explore-summary.md in controller-issue session dir
  mkdir -p "$SANDBOX/.controller-issue/test-session"
  echo "# explore summary" > "$SANDBOX/.controller-issue/test-session/explore-summary.md"

  run _run_hook "$(_payload "TWL_CALLER_AUTHZ=co-issue-phase4-create gh issue create --title 'issue' --body 'b'")"

  assert_success
  _is_deny && fail "expected allow but got deny"
  true
}

# ---------------------------------------------------------------------------
# S4: gh issue create --template + no allow path → deny
# ---------------------------------------------------------------------------

@test "S4: gh issue create --template + no allow path → deny" {
  skip_if_gate_missing

  run _run_hook "$(_payload "gh issue create --template bug_report.md --title 'bug'")"

  assert_success
  _is_deny || fail "expected deny but got allow"
}

# ---------------------------------------------------------------------------
# S5: gh issue create + SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON + --repo → allow (cross-repo)
# ---------------------------------------------------------------------------

@test "S5: gh issue create + SKIP_ISSUE_GATE + SKIP_REASON + --repo → allow (cross-repo)" {
  skip_if_gate_missing

  run _run_hook "$(_payload "SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='trivial config' gh issue create --repo shuu5/other --title 'x'")"

  assert_success
  _is_deny && fail "expected allow but got deny"
  true
}

# ---------------------------------------------------------------------------
# S6: gh pr create → allow (gate 対象外)
# ---------------------------------------------------------------------------

@test "S6: gh pr create → allow (gate 対象外)" {
  skip_if_gate_missing

  run _run_hook "$(_payload "gh pr create --title 'feat' --body 'desc'")"

  assert_success
  _is_deny && fail "expected allow but got deny"
  true
}

# ---------------------------------------------------------------------------
# S7: gh issue list → allow (gate 対象外)
# ---------------------------------------------------------------------------

@test "S7: gh issue list → allow (gate 対象外)" {
  skip_if_gate_missing

  run _run_hook "$(_payload "gh issue list --state open")"

  assert_success
  _is_deny && fail "expected allow but got deny"
  true
}

# ---------------------------------------------------------------------------
# S8: git commit → allow (gh issue create でない)
# ---------------------------------------------------------------------------

@test "S8: git commit → allow (gh issue create でない)" {
  skip_if_gate_missing

  run _run_hook "$(_payload "git commit -m 'feat: add feature'")"

  assert_success
  _is_deny && fail "expected allow but got deny"
  true
}

# ---------------------------------------------------------------------------
# S9: SKIP_ISSUE_GATE=1 のみ (SKIP_ISSUE_REASON 欠落) → deny
# ---------------------------------------------------------------------------

@test "S9: SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON 欠落 → deny" {
  skip_if_gate_missing

  run _run_hook "$(_payload "SKIP_ISSUE_GATE=1 gh issue create --title 'no reason'")"

  assert_success
  _is_deny || fail "expected deny (SKIP_ISSUE_REASON missing) but got allow"
}

# ---------------------------------------------------------------------------
# S10: gh issue create (先頭空白あり) + no allow path → deny
# ---------------------------------------------------------------------------

@test "S10: '  gh issue create' (先頭空白) + no allow path → deny" {
  skip_if_gate_missing

  run _run_hook "$(_payload "  gh issue create --title 'trimmed'")"

  assert_success
  _is_deny || fail "expected deny but got allow"
}

# ---------------------------------------------------------------------------
# S11: gh issue create → deny + actionable message に "co-explore" を含む
# ---------------------------------------------------------------------------

@test "S11: gh issue create → deny + actionable message に co-explore 案内" {
  skip_if_gate_missing

  run _run_hook "$(_payload "gh issue create --title 'new feat' --body 'feature description'")"

  assert_success
  _is_deny || fail "expected deny but got allow"
  echo "$output" | grep -q "co-explore" || fail "expected 'co-explore' in deny message"
}

# ---------------------------------------------------------------------------
# S12: TWL_CALLER_AUTHZ=co-explore-bootstrap + state file なし → deny
# ---------------------------------------------------------------------------

@test "S12: TWL_CALLER_AUTHZ=co-explore-bootstrap + state file なし → deny" {
  skip_if_gate_missing

  # ensure no bootstrap state files exist in isolated TMP_DIR
  rm -f "$TMP_DIR"/.co-explore-bootstrap-*.json 2>/dev/null || true

  run _run_hook "$(_payload "TWL_CALLER_AUTHZ=co-explore-bootstrap gh issue create --title 'spoof attempt'")"

  assert_success
  _is_deny || fail "expected deny (state file missing) but got allow"
}

# ---------------------------------------------------------------------------
# helper: skip if gate script not found
# ---------------------------------------------------------------------------

skip_if_gate_missing() {
  [[ -f "$GATE_PATH" ]] || skip "gate script not found: $GATE_PATH"
}
