#!/usr/bin/env bats
# health-check.bats - unit tests for scripts/health-check.sh
#
# Spec: openspec/changes/autopilot-proactive-monitoring/specs/health-check.md

load '../helpers/common'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Write a fake issue JSON with updated_at set to N minutes ago
_create_issue_with_age_minutes() {
  local issue_num="$1"
  local age_minutes="$2"
  local past_ts
  past_ts=$(date -u -d "${age_minutes} minutes ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v-"${age_minutes}"M +"%Y-%m-%dT%H:%M:%SZ")

  create_issue_json "$issue_num" "running" \
    ".updated_at = \"$past_ts\""
}

# Stub tmux capture-pane to output given text
_stub_tmux_capture() {
  local output="$1"
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
if echo "\$*" | grep -q "capture-pane"; then
  printf '%s\n' "$output"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/tmux"
}

# Stub tmux capture-pane to output nothing (empty)
_stub_tmux_capture_empty() {
  cat > "$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
if echo "$*" | grep -q "capture-pane"; then
  printf ''
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/tmux"
}

# Stub session-state.sh to return a given state and optionally minutes-waiting
_stub_session_state() {
  local window_state="$1"
  local waiting_minutes="${2:-0}"
  cat > "$STUB_BIN/session-state.sh" <<STUB
#!/usr/bin/env bash
cmd="\$1"; shift
case "\$cmd" in
  state)
    echo "$window_state"
    exit 0
    ;;
  get)
    if command -v date &>/dev/null; then
      since_epoch=\$(date -u -d "${waiting_minutes} minutes ago" +%s 2>/dev/null \
        || date -u -v-"${waiting_minutes}"M +%s)
    else
      since_epoch=0
    fi
    echo "{\"state\":\"$window_state\",\"since\":\$since_epoch}"
    exit 0
    ;;
  waiting-since)
    # Return epoch seconds for N minutes ago
    if command -v date &>/dev/null; then
      date -u -d "${waiting_minutes} minutes ago" +%s 2>/dev/null \
        || date -u -v-"${waiting_minutes}"M +%s
    fi
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$STUB_BIN/session-state.sh"
}

setup() {
  common_setup
  # Default: tmux capture-pane returns clean output
  _stub_tmux_capture_empty
  # Default: session-state.sh not present (fallback path)
  # (do not create stub → health-check falls back)
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: health-check スクリプト
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: chain 停止検知
# ---------------------------------------------------------------------------

@test "health-check detects chain_stall when updated_at exceeds default threshold (10 min)" {
  # WHEN updated_at is 11 minutes ago (exceeds default 10 min threshold)
  _create_issue_with_age_minutes 1 11

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  # THEN exit code 1, stdout contains chain_stall and elapsed minutes
  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
  # Elapsed minutes should be present (numeric)
  echo "$output" | grep -qE 'chain_stall.*[0-9]+'
}

@test "health-check does NOT detect chain_stall when updated_at is exactly at threshold (10 min boundary)" {
  # WHEN updated_at is exactly 10 minutes ago (boundary: not exceeded)
  _create_issue_with_age_minutes 1 10
  # No errors in tmux pane → should be clean
  _stub_tmux_capture_empty

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  # THEN exit code 0 (threshold is exclusive: > not >=)
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check does NOT detect chain_stall when updated_at is 9 min ago (threshold-1)" {
  # WHEN updated_at is 9 minutes ago (below default 10 min threshold)
  _create_issue_with_age_minutes 1 9
  _stub_tmux_capture_empty

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check detects chain_stall when updated_at is threshold+1 (11 min)" {
  # WHEN updated_at is 11 minutes ago (threshold+1)
  _create_issue_with_age_minutes 1 11

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
}

@test "health-check outputs elapsed minutes in chain_stall detection" {
  _create_issue_with_age_minutes 1 15

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  # Output must contain chain_stall and an elapsed number close to 15
  echo "$output" | grep -qE 'chain_stall.*(1[45]|16)'
}

# ---------------------------------------------------------------------------
# Scenario: エラー出力検知
# ---------------------------------------------------------------------------

@test "health-check detects error_output when tmux capture contains 'Error'" {
  create_issue_json 1 "running"
  _stub_tmux_capture "some line
Error: something went wrong
another line"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]
}

@test "health-check detects error_output when tmux capture contains 'FATAL'" {
  create_issue_json 1 "running"
  _stub_tmux_capture "line1
FATAL: out of memory
line2"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]
}

@test "health-check detects error_output when tmux capture contains 'panic'" {
  create_issue_json 1 "running"
  _stub_tmux_capture "goroutine 1 [running]:
panic: runtime error: index out of range
stack trace..."

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]
}

@test "health-check detects error_output when tmux capture contains 'Traceback'" {
  create_issue_json 1 "running"
  _stub_tmux_capture "Traceback (most recent call last):
  File 'app.py', line 10
AttributeError: 'NoneType' object"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]
}

@test "health-check does NOT detect error_output for clean tmux output" {
  create_issue_json 1 "running"
  _stub_tmux_capture "Step 1 complete
Step 2 running
All good"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check does NOT detect error_output for empty tmux capture-pane output" {
  # Edge case: empty capture-pane output
  create_issue_json 1 "running"
  _stub_tmux_capture_empty

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check includes matching line in error_output detection" {
  create_issue_json 1 "running"
  _stub_tmux_capture "clean line
Error: disk full
another clean line"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]
  # Matched line should be present in output
  [[ "$output" == *"Error: disk full"* ]]
}

# ---------------------------------------------------------------------------
# Scenario: input-waiting 長時間検知
# ---------------------------------------------------------------------------

@test "health-check detects input_waiting when session-state reports input-waiting >= default threshold (5 min)" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 6

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}

@test "health-check does NOT detect input_waiting when state is input-waiting but duration is below threshold (4 min)" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 4
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check does NOT detect input_waiting when state is input-waiting at exactly threshold boundary (5 min)" {
  # WHEN exactly 5 minutes (boundary: not exceeded)
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 5
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check detects input_waiting at threshold+1 (6 min)" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 6

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}

@test "health-check does NOT detect input_waiting when session-state returns non-waiting state" {
  create_issue_json 1 "running"
  _stub_session_state "processing" 0
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check outputs elapsed minutes in input_waiting detection" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 8

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  echo "$output" | grep -qE 'input_waiting.*[0-9]+'
}

# ---------------------------------------------------------------------------
# Scenario: session-state.sh 非存在時のフォールバック
# ---------------------------------------------------------------------------

@test "health-check skips input_waiting check when SESSION_STATE_CMD is not set" {
  # WHEN SESSION_STATE_CMD is not set (default fallback)
  create_issue_json 1 "running"
  _stub_tmux_capture_empty

  # Unset to simulate no session-state.sh
  run bash -c "unset SESSION_STATE_CMD; bash '$SANDBOX/scripts/health-check.sh' --issue 1 --window 'ap-#1'"

  [ "$status" -eq 0 ]
  # Output must NOT contain input_waiting
  [[ "$output" != *"input_waiting"* ]]
}

@test "health-check skips input_waiting but still runs chain_stall check when session-state.sh absent" {
  # WHEN session-state.sh is unavailable, chain_stall must still fire
  _create_issue_with_age_minutes 1 11

  SESSION_STATE_CMD="/nonexistent/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
  [[ "$output" != *"input_waiting"* ]]
}

@test "health-check skips input_waiting but still runs error_output check when session-state.sh absent" {
  create_issue_json 1 "running"
  _stub_tmux_capture "FATAL: out of memory"

  SESSION_STATE_CMD="/nonexistent/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]
  [[ "$output" != *"input_waiting"* ]]
}

@test "health-check skips input_waiting when SESSION_STATE_CMD points to nonexistent path" {
  create_issue_json 1 "running"
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="/nonexistent/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [[ "$output" != *"input_waiting"* ]]
}

# ---------------------------------------------------------------------------
# Scenario: 異常なし
# ---------------------------------------------------------------------------

@test "health-check exits 0 with no output when all three checks pass" {
  create_issue_json 1 "running"
  _stub_tmux_capture_empty
  # updated_at is fresh (default in create_issue_json)

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  assert_success
  [ -z "$output" ]
}

# ===========================================================================
# Requirement: 閾値の設定可能性
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 環境変数による閾値カスタマイズ
# ---------------------------------------------------------------------------

@test "health-check uses custom DEV_HEALTH_CHAIN_STALL_MIN=20 threshold" {
  # WHEN DEV_HEALTH_CHAIN_STALL_MIN=20 is set and updated_at is 15 min ago
  # THEN chain_stall should NOT fire (15 < 20)
  _create_issue_with_age_minutes 1 15
  _stub_tmux_capture_empty

  DEV_HEALTH_CHAIN_STALL_MIN=20 \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "health-check fires chain_stall with custom DEV_HEALTH_CHAIN_STALL_MIN=20 when 21 min elapsed" {
  # WHEN DEV_HEALTH_CHAIN_STALL_MIN=20 and updated_at is 21 min ago
  _create_issue_with_age_minutes 1 21

  DEV_HEALTH_CHAIN_STALL_MIN=20 \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
}

@test "health-check uses custom DEV_HEALTH_INPUT_WAIT_MIN=3 threshold" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 4  # 4 > 3 → should fire
  _stub_tmux_capture_empty

  DEV_HEALTH_INPUT_WAIT_MIN=3 \
    SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}

@test "health-check does NOT fire input_waiting with custom DEV_HEALTH_INPUT_WAIT_MIN=3 when 2 min elapsed" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 2  # 2 < 3 → should not fire
  _stub_tmux_capture_empty

  DEV_HEALTH_INPUT_WAIT_MIN=3 \
    SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario: 環境変数未設定時のデフォルト
# ---------------------------------------------------------------------------

@test "health-check uses default chain_stall threshold of 10 minutes when env var is unset" {
  # 9 min → no stall, 11 min → stall
  _create_issue_with_age_minutes 1 9
  _stub_tmux_capture_empty

  run bash -c "unset DEV_HEALTH_CHAIN_STALL_MIN; bash '$SANDBOX/scripts/health-check.sh' --issue 1 --window 'ap-#1'"
  [ "$status" -eq 0 ]

  _create_issue_with_age_minutes 1 11
  run bash -c "unset DEV_HEALTH_CHAIN_STALL_MIN; bash '$SANDBOX/scripts/health-check.sh' --issue 1 --window 'ap-#1'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
}

@test "health-check uses default input_waiting threshold of 5 minutes when env var is unset" {
  create_issue_json 1 "running"
  _stub_session_state "input-waiting" 4
  _stub_tmux_capture_empty

  run bash -c "unset DEV_HEALTH_INPUT_WAIT_MIN; SESSION_STATE_CMD='$STUB_BIN/session-state.sh' bash '$SANDBOX/scripts/health-check.sh' --issue 1 --window 'ap-#1'"
  [ "$status" -eq 0 ]

  _stub_session_state "input-waiting" 6
  run bash -c "unset DEV_HEALTH_INPUT_WAIT_MIN; SESSION_STATE_CMD='$STUB_BIN/session-state.sh' bash '$SANDBOX/scripts/health-check.sh' --issue 1 --window 'ap-#1'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "health-check detects multiple patterns simultaneously (chain_stall + error_output)" {
  # WHEN both chain is stalled and error pattern is in tmux output
  _create_issue_with_age_minutes 1 11
  _stub_tmux_capture "Error: connection refused"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
  [[ "$output" == *"error_output"* ]]
}

@test "health-check detects multiple patterns simultaneously (chain_stall + input_waiting)" {
  _create_issue_with_age_minutes 1 11
  _stub_session_state "input-waiting" 6
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
  [[ "$output" == *"input_waiting"* ]]
}

@test "health-check detects all three patterns simultaneously" {
  _create_issue_with_age_minutes 1 11
  _stub_tmux_capture "FATAL: out of memory"
  _stub_session_state "input-waiting" 6

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"chain_stall"* ]]
  [[ "$output" == *"error_output"* ]]
  [[ "$output" == *"input_waiting"* ]]
}

@test "health-check exits with error when --issue is missing" {
  run bash "$SANDBOX/scripts/health-check.sh" \
    --window "ap-#1"

  assert_failure
  assert_output --partial "--issue"
}

@test "health-check exits with error when --window is missing" {
  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1

  assert_failure
  assert_output --partial "--window"
}

@test "health-check exits with error for non-numeric --issue" {
  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue abc --window "ap-#1"

  assert_failure
}

@test "health-check handles missing issue JSON gracefully (no updated_at)" {
  # No issue-1.json created → state-read returns empty → no chain_stall
  _stub_tmux_capture_empty

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 99 --window "ap-#99"

  # Should not crash; no anomaly detectable without valid updated_at
  assert_success
}

# ===========================================================================
# Requirement: 多行エラー出力の1行正規化
# Spec: openspec/changes/fix-health-check-erroroutput/specs/health-check-erroroutput.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 複数行エラー出力時のパース維持
# WHEN tmux capture-pane の出力に複数行のエラーメッセージが含まれる
# THEN check_error_output は error_output:line1; line2; ... の形式で1行のみ出力しなければならない
# ---------------------------------------------------------------------------

_stub_session_state_with_state() {
  local window_state="$1"
  local waiting_minutes="${2:-0}"
  # Compute the "since" epoch for N minutes ago (used in the JSON get response)
  local since_epoch
  since_epoch=$(date -u -d "${waiting_minutes} minutes ago" +%s 2>/dev/null \
    || date -u -v-"${waiting_minutes}"M +%s)
  cat > "$STUB_BIN/session-state.sh" <<STUB
#!/usr/bin/env bash
cmd="\$1"; shift
case "\$cmd" in
  state)
    # health-check.sh L139: "\$SESSION_STATE_CMD" state "\$window"
    echo "$window_state"
    exit 0
    ;;
  get)
    # health-check.sh L146: "\$SESSION_STATE_CMD" get "\$window"
    # Returns JSON with .since (epoch seconds) so jq can extract it
    echo '{"state":"'"$window_state"'","since":'"$since_epoch"'}'
    exit 0
    ;;
  waiting-since)
    echo "$since_epoch"
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
STUB
  chmod +x "$STUB_BIN/session-state.sh"
}

@test "error_output with multiline tmux capture is normalized to a single output line" {
  # WHEN tmux capture contains multiple error-matching lines
  create_issue_json 1 "running"
  _stub_tmux_capture "Error: connection refused
FATAL: out of memory
panic: nil pointer"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"error_output"* ]]

  # THEN the output must contain exactly one line starting with "error_output:"
  local error_line_count
  error_line_count=$(echo "$output" | grep -c '^error_output:')
  [ "$error_line_count" -eq 1 ]
}

@test "error_output single line with multiline capture contains semicolon-joined lines" {
  # WHEN multiple error lines are captured
  create_issue_json 1 "running"
  _stub_tmux_capture "Error: disk full
FATAL: write failed"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]

  # THEN the single error_output line must join errors with '; '
  local error_line
  error_line=$(echo "$output" | grep '^error_output:')
  [[ "$error_line" == *";"* ]]
  # Must not contain a literal newline within the error_output value
  [ "$(echo "$error_line" | wc -l)" -eq 1 ]
}

@test "error_output with three error lines produces single colon-prefixed output line" {
  # Boundary: 3 error lines — all must be on one line, none spill to additional lines
  create_issue_json 1 "running"
  _stub_tmux_capture "Error: step 1 failed
FATAL: unrecoverable
Traceback (most recent call last):"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]

  local error_line_count
  error_line_count=$(echo "$output" | grep -c '^error_output:')
  [ "$error_line_count" -eq 1 ]
}

@test "chain_stall and error_output are still on separate lines when both detected" {
  # Regression: multiline normalization must not merge chain_stall and error_output into one line
  _create_issue_with_age_minutes 1 11
  _stub_tmux_capture "Error: timeout
FATAL: give up"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]

  # Each pattern must appear on its own output line
  local chain_lines error_lines
  chain_lines=$(echo "$output" | grep -c '^chain_stall:')
  error_lines=$(echo "$output" | grep -c '^error_output:')
  [ "$chain_lines" -eq 1 ]
  [ "$error_lines" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Scenario: 単一行エラー出力時の動作維持
# WHEN エラーが1行のみの場合
# THEN 既存の error_output:detail 形式がそのまま維持されなければならない
# ---------------------------------------------------------------------------

@test "error_output with single error line preserves existing format without extra semicolons" {
  create_issue_json 1 "running"
  _stub_tmux_capture "clean line
Error: something specific
another clean line"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]

  local error_line
  error_line=$(echo "$output" | grep '^error_output:')
  # Single error line — value must match the original line (no trailing semicolons)
  [[ "$error_line" == *"Error: something specific"* ]]
  [ "$(echo "$error_line" | wc -l)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Scenario: エラーなしの場合
# WHEN tmux capture-pane の出力にエラーパターンが含まれない
# THEN check_error_output は何も出力しない
# ---------------------------------------------------------------------------

@test "error_output check produces no output when tmux capture has no error keywords" {
  create_issue_json 1 "running"
  _stub_tmux_capture "step 1 done
step 2 running
all systems operational"

  run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  # No error_output line whatsoever
  ! echo "$output" | grep -q '^error_output:'
}

# ===========================================================================
# Requirement: テストスタブ state サブコマンド対応
# Spec: openspec/changes/fix-health-check-erroroutput/specs/health-check-erroroutput.md
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: state サブコマンドで状態取得
# WHEN session-state.sh が state <window> で呼び出される
# THEN 設定された window_state 文字列を返さなければならない
# ---------------------------------------------------------------------------

@test "session-state stub returns configured state when called with 'state' subcommand" {
  # Verify the stub itself handles the 'state' subcommand correctly
  _stub_session_state_with_state "input-waiting" 0

  run bash "$STUB_BIN/session-state.sh" state "ap-#1"

  [ "$status" -eq 0 ]
  [ "$output" = "input-waiting" ]
}

@test "session-state stub with state=processing returns processing for state subcommand" {
  _stub_session_state_with_state "processing" 0

  run bash "$STUB_BIN/session-state.sh" state "ap-#1"

  [ "$status" -eq 0 ]
  [ "$output" = "processing" ]
}

# ---------------------------------------------------------------------------
# Scenario: input_waiting 系テストの正常動作
# WHEN _stub_session_state_with_state "input-waiting" N でスタブが構成される
# THEN state サブコマンドは input-waiting を返し、get サブコマンドは状態文字列を返さなければならない
# ---------------------------------------------------------------------------

@test "health-check detects input_waiting with state-subcommand-aware stub (6 min over threshold)" {
  # WHEN stub supports 'state' subcommand and returns input-waiting with 6-min elapsed
  create_issue_json 1 "running"
  _stub_session_state_with_state "input-waiting" 6

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}

@test "health-check does NOT detect input_waiting with state-subcommand-aware stub when state is not input-waiting" {
  create_issue_json 1 "running"
  _stub_session_state_with_state "processing" 0
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [[ "$output" != *"input_waiting"* ]]
}

@test "health-check does NOT detect input_waiting at boundary (5 min) with state-subcommand-aware stub" {
  create_issue_json 1 "running"
  _stub_session_state_with_state "input-waiting" 5
  _stub_tmux_capture_empty

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 0 ]
  [[ "$output" != *"input_waiting"* ]]
}

@test "health-check detects input_waiting at threshold+1 (6 min) with state-subcommand-aware stub" {
  create_issue_json 1 "running"
  _stub_session_state_with_state "input-waiting" 6

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}

@test "stub get subcommand returns JSON with .state and .since fields" {
  # THEN get subcommand returns JSON so health-check.sh can extract .since via jq
  _stub_session_state_with_state "input-waiting" 0

  run bash "$STUB_BIN/session-state.sh" get "ap-#1"

  [ "$status" -eq 0 ]
  # Output must be valid JSON containing state and since
  echo "$output" | grep -q '"state"'
  echo "$output" | grep -q '"since"'
}
