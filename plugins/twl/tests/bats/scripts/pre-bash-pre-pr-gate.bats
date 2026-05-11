#!/usr/bin/env bats
# pre-bash-pre-pr-gate.bats — Issue #1633 / ADR-039 AC5
#
# AC3 / AC5 シナリオ:
#   S1: test-only diff + gh pr create → deny
#   S2: impl + test diff + gh pr create → allow (実装ファイルあり)
#   S3: test-only diff + tdd-followup label → allow (allowlist)
#   S4: test-only diff + SKIP_PRE_PR_GATE=1 + REASON='...' → allow + bypass log 記録
#   S5: test-only diff + SKIP_PRE_PR_GATE=1 (REASON 不在) → deny (REASON 必須)
#   S6: gh pr create 以外のコマンド → 素通り (matcher 外)
#
# Hook interface (公式仕様 https://code.claude.com/docs/en/hooks):
#   - JSON payload via stdin: {tool_name:"Bash", tool_input:{command:"<cmd>"}}
#   - Deny: stdout に {hookSpecificOutput:{permissionDecision:"deny",...}} を出力 + exit 0
#   - Allow: stdout 空 (or non-deny) + exit 0

load '../helpers/common'

GATE_SCRIPT="scripts/hooks/pre-bash-pre-pr-gate.sh"
GATE_PATH=""
REPO_DIR=""

skip_if_gate_missing() {
  [[ -f "$GATE_PATH" ]] || skip "gate script not found: $GATE_PATH"
}

setup() {
  common_setup
  GATE_PATH="$REPO_ROOT/$GATE_SCRIPT"
  REPO_DIR="$SANDBOX/repo"
  _setup_git_fixture
}

teardown() {
  common_teardown
}

# Build minimal git fixture: main branch with base commit + feat branch
_setup_git_fixture() {
  mkdir -p "$REPO_DIR"
  (
    cd "$REPO_DIR" || exit 1
    git init -q -b main 2>/dev/null
    git config user.email "test@example.com"
    git config user.name "test"
    mkdir -p src tests
    echo "base" > src/base.sh
    echo "@test 'base' { :; }" > tests/base.bats
    git add .
    git commit -q -m "base commit"
    # Create feat branch (pretend this is the PR branch)
    git checkout -q -b feat/1633-test
    # origin/main を local main にエイリアス (gh pr create シナリオを模倣)
    git update-ref refs/remotes/origin/main main
  )
}

_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Run hook with cwd in fixture repo
_run_hook() {
  local payload="$1"
  echo "$payload" | (cd "$REPO_DIR" && bash "$GATE_PATH")
}

_is_deny() {
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

# Add test-only changes (no impl file)
_make_test_only_diff() {
  (
    cd "$REPO_DIR" || exit 1
    echo "@test 'new' { false; }" > tests/new.bats
    git add tests/new.bats
    git commit -q -m "RED test"
  )
}

# Add impl + test changes (mixed diff)
_make_mixed_diff() {
  (
    cd "$REPO_DIR" || exit 1
    echo "@test 'new' { true; }" > tests/new.bats
    echo "echo new" > src/new.sh
    git add tests/new.bats src/new.sh
    git commit -q -m "GREEN impl + test"
  )
}

# Stub gh CLI to return specific label names (newline-separated, mimics --jq '.labels[].name')
_stub_gh_with_labels() {
  local labels_newline_sep="$1"
  stub_command "gh" "
if [[ \"\$1\" == \"issue\" && \"\$2\" == \"view\" ]]; then
  printf '%s\\n' '$labels_newline_sep'
  exit 0
fi
exit 1
"
}

# ---------------------------------------------------------------------------
# S1: test-only diff + gh pr create → deny
# ---------------------------------------------------------------------------

@test "S1: test-only diff + gh pr create → deny" {
  skip_if_gate_missing
  _make_test_only_diff
  _stub_gh_with_labels "enhancement"

  run _run_hook "$(_payload "gh pr create --title 't' --body 'b'")"

  assert_success
  _is_deny || fail "expected deny but got allow. output: $output"
  echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q "test-only diff" \
    || fail "deny message should mention 'test-only diff'"
}

# ---------------------------------------------------------------------------
# S2: impl + test diff + gh pr create → allow
# ---------------------------------------------------------------------------

@test "S2: impl + test diff + gh pr create → allow" {
  skip_if_gate_missing
  _make_mixed_diff
  _stub_gh_with_labels ""

  run _run_hook "$(_payload "gh pr create --title 't' --body 'b'")"

  assert_success
  _is_deny && fail "expected allow but got deny. output: $output"
  true
}

# ---------------------------------------------------------------------------
# S3: test-only diff + tdd-followup label → allow (allowlist)
# ---------------------------------------------------------------------------

@test "S3: test-only diff + tdd-followup label → allow" {
  skip_if_gate_missing
  _make_test_only_diff
  _stub_gh_with_labels "tdd-followup"

  run _run_hook "$(_payload "gh pr create --title 't' --body 'b'")"

  assert_success
  _is_deny && fail "expected allow but got deny. output: $output"
  true
}

# ---------------------------------------------------------------------------
# S4: test-only diff + SKIP_PRE_PR_GATE=1 + REASON → allow + audit log 記録
# ---------------------------------------------------------------------------

@test "S4: test-only diff + SKIP_PRE_PR_GATE=1 + REASON → allow" {
  skip_if_gate_missing
  _make_test_only_diff
  _stub_gh_with_labels ""

  # bypass log は /tmp/pre-pr-gate-bypass.log (実装通り、副作用 OK だが test 後に確認)
  local before_size=0
  [[ -f /tmp/pre-pr-gate-bypass.log ]] && before_size=$(wc -c < /tmp/pre-pr-gate-bypass.log)

  run _run_hook "$(_payload "SKIP_PRE_PR_GATE=1 SKIP_PRE_PR_GATE_REASON='manual TDD followup' gh pr create --title 't'")"

  assert_success
  _is_deny && fail "expected allow but got deny. output: $output"

  # bypass log にエントリが追加されていることを確認
  [[ -f /tmp/pre-pr-gate-bypass.log ]] || fail "bypass log not created"
  local after_size
  after_size=$(wc -c < /tmp/pre-pr-gate-bypass.log)
  [[ "$after_size" -gt "$before_size" ]] || fail "bypass log not appended"
  grep -q "manual TDD followup" /tmp/pre-pr-gate-bypass.log || fail "REASON not in bypass log"
}

# ---------------------------------------------------------------------------
# S5: test-only diff + SKIP_PRE_PR_GATE=1 (REASON 不在) → deny
# ---------------------------------------------------------------------------

@test "S5: SKIP_PRE_PR_GATE=1 without REASON → deny (REASON 必須)" {
  skip_if_gate_missing
  _make_test_only_diff
  _stub_gh_with_labels ""

  run _run_hook "$(_payload "SKIP_PRE_PR_GATE=1 gh pr create --title 't'")"

  assert_success
  _is_deny || fail "expected deny but got allow. output: $output"
  echo "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason' | grep -q "REASON" \
    || fail "deny message should mention REASON requirement"
}

# ---------------------------------------------------------------------------
# S6: gh pr create 以外のコマンド → 素通り (matcher 外)
# ---------------------------------------------------------------------------

@test "S6: gh issue create → allow (matcher 外)" {
  skip_if_gate_missing
  _make_test_only_diff

  run _run_hook "$(_payload "gh issue create --title 't' --body 'b'")"

  assert_success
  _is_deny && fail "expected allow but got deny. output: $output"
  true
}

@test "S6b: git commit → allow (matcher 外)" {
  skip_if_gate_missing
  _make_test_only_diff

  run _run_hook "$(_payload "git commit -m 'wip'")"

  assert_success
  _is_deny && fail "expected allow but got deny. output: $output"
  true
}

@test "S6c: gh pr merge → allow (本 hook の matcher 外、merge は別 hook 担当)" {
  skip_if_gate_missing
  _make_test_only_diff

  run _run_hook "$(_payload "gh pr merge --squash")"

  assert_success
  _is_deny && fail "expected allow but got deny. output: $output"
  true
}
