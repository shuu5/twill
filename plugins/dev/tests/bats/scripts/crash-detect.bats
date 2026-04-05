#!/usr/bin/env bats
# crash-detect.bats - unit tests for scripts/crash-detect.sh

load '../helpers/common'

setup() {
  common_setup
  # stub tmux by default (no panes = crash)
  stub_command "tmux" 'exit 1'
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: crash-detect unit test (existing - compatibility maintained)
# ---------------------------------------------------------------------------

# Scenario: pane absent -> crash detection (exit 2, status -> failed)
@test "crash-detect detects crash when tmux pane is absent" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  # Verify status changed to failed
  local new_status
  new_status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$new_status" = "failed" ]

  # Verify failure info was written
  local failure_msg
  failure_msg=$(jq -r '.failure.message' "$SANDBOX/.autopilot/issues/issue-1.json")
  [[ "$failure_msg" == *"crash"* ]] || [[ "$failure_msg" == *"disappeared"* ]]
}

# Scenario: non-running status is skipped (exit 0)
@test "crash-detect skips non-running issue with exit 0" {
  create_issue_json 1 "done"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# ---------------------------------------------------------------------------
# Edge cases (existing - compatibility maintained)
# ---------------------------------------------------------------------------

@test "crash-detect exits 0 when tmux pane exists" {
  create_issue_json 1 "running"
  stub_command "tmux" 'exit 0'

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

@test "crash-detect skips merge-ready status" {
  create_issue_json 1 "merge-ready"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

@test "crash-detect skips failed status" {
  create_issue_json 1 "failed"

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

@test "crash-detect fails without --issue" {
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --window "ap-#1"

  assert_failure
  assert_output --partial "--issue"
}

@test "crash-detect fails without --window" {
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1

  assert_failure
  assert_output --partial "--window"
}

@test "crash-detect fails with non-numeric issue" {
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue abc --window "ap-#1"

  assert_failure
  assert_output --partial "正の整数"
}

@test "crash-detect with nonexistent issue file (state-read returns empty)" {
  # No issue json created -- state-read returns empty, status != running
  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 99 --window "ap-#99"

  # status would be empty string, which is != "running", so exit 0
  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: crash-detect 5状態検出 (session-state.sh integration)
# Spec: openspec/changes/autopilot-session-interop-phase-a/specs/crash-detect/spec.md
# ---------------------------------------------------------------------------

# Scenario: session-state.sh で exited 状態を検出
# WHEN session-state.sh が利用可能で state <window> が `exited` を返す
# THEN exit code 2、status=failed、failure.detected_state="exited"
@test "crash-detect detects crash via session-state.sh when state is exited" {
  create_issue_json 1 "running"

  # stub session-state.sh: `state <window>` returns "exited"
  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "exited"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local new_status detected_state
  new_status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  detected_state=$(jq -r '.failure.detected_state' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$new_status" = "failed" ]
  [ "$detected_state" = "exited" ]
}

# Scenario: session-state.sh で error 状態を検出
# WHEN session-state.sh が利用可能で state <window> が `error` を返す
# THEN exit code 2、status=failed、failure.detected_state="error"
@test "crash-detect detects crash via session-state.sh when state is error" {
  create_issue_json 1 "running"

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "error"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local detected_state
  detected_state=$(jq -r '.failure.detected_state' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$detected_state" = "error" ]
}

# Scenario: session-state.sh で processing 状態を検出
# WHEN session-state.sh が利用可能で state <window> が `processing` を返す
# THEN exit code 0（正常）
@test "crash-detect exits 0 via session-state.sh when state is processing" {
  create_issue_json 1 "running"

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "processing"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# Scenario: session-state.sh で idle 状態を検出
# WHEN session-state.sh が利用可能で state <window> が `idle` を返す
# THEN exit code 0（正常）
@test "crash-detect exits 0 via session-state.sh when state is idle" {
  create_issue_json 1 "running"

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "idle"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# Scenario: session-state.sh で input-waiting 状態を検出
# WHEN session-state.sh が利用可能で state <window> が `input-waiting` を返す
# THEN exit code 0（正常）
@test "crash-detect exits 0 via session-state.sh when state is input-waiting" {
  create_issue_json 1 "running"

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "input-waiting"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: crash-detect フォールバック
# Spec: openspec/changes/autopilot-session-interop-phase-a/specs/crash-detect/spec.md
# ---------------------------------------------------------------------------

# Scenario: session-state.sh 非存在時のフォールバック（ペイン消失 → crash）
# WHEN SESSION_STATE_CMD が存在しないパスを指す
# THEN tmux list-panes フォールバック: ペイン消失 → exit 2
@test "crash-detect falls back to tmux when SESSION_STATE_CMD path does not exist (pane absent)" {
  create_issue_json 1 "running"
  # tmux stub returns exit 1 = pane absent (set in global setup)

  SESSION_STATE_CMD="/nonexistent/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local new_status
  new_status=$(jq -r '.status' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$new_status" = "failed" ]
}

# Scenario: session-state.sh 非存在時のフォールバック（ペイン存在 → 正常）
# WHEN SESSION_STATE_CMD が存在しないパスを指し、tmux ペインが存在する
# THEN tmux list-panes フォールバック: ペイン存在 → exit 0
@test "crash-detect falls back to tmux when SESSION_STATE_CMD path does not exist (pane present)" {
  create_issue_json 1 "running"
  stub_command "tmux" 'exit 0'

  SESSION_STATE_CMD="/nonexistent/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# Scenario: session-state.sh が実行失敗した場合のフォールバック
# WHEN session-state.sh の実行がエラーを返す（window not found 等）
# THEN tmux list-panes フォールバックに切り替えて crash 検知（ペイン消失 → exit 2）
@test "crash-detect falls back to tmux when session-state.sh execution fails" {
  create_issue_json 1 "running"
  # tmux stub: pane absent (default setup)

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
# Simulate "window not found" error
echo "ERROR: window not found" >&2
exit 1
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]
}

# Scenario: session-state.sh 実行失敗後フォールバック（ペイン存在）
# WHEN session-state.sh の実行がエラーを返し、tmux ペインが存在する
# THEN フォールバックは exit 0 で正常終了する（エラー終了しない）
@test "crash-detect falls back to tmux pane-present when session-state.sh fails" {
  create_issue_json 1 "running"
  stub_command "tmux" 'exit 0'

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
echo "ERROR: window not found" >&2
exit 1
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: crash-detect failure 情報の拡張
# Spec: openspec/changes/autopilot-session-interop-phase-a/specs/crash-detect/spec.md
# ---------------------------------------------------------------------------

# Scenario: session-state.sh 経由の failure 情報
# WHEN session-state.sh で error 状態が検出されて crash と判定される
# THEN failure JSON に "detected_state": "error" が含まれる
@test "crash-detect failure JSON contains detected_state=error when session-state reports error" {
  create_issue_json 1 "running"

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "error"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local detected_state failure_ts
  detected_state=$(jq -r '.failure.detected_state' "$SANDBOX/.autopilot/issues/issue-1.json")
  failure_ts=$(jq -r '.failure.timestamp' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$detected_state" = "error" ]
  # timestamp must be a non-empty ISO8601 string
  [[ "$failure_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]
}

# Scenario: フォールバック経由の failure 情報
# WHEN tmux list-panes フォールバックでペイン消失が検出される
# THEN failure JSON に "detected_state": "pane_absent" が含まれる
@test "crash-detect failure JSON contains detected_state=pane_absent in fallback path" {
  create_issue_json 1 "running"
  # SESSION_STATE_CMD not set → uses fallback; tmux returns exit 1 = pane absent

  run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local detected_state
  detected_state=$(jq -r '.failure.detected_state' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$detected_state" = "pane_absent" ]
}

# ---------------------------------------------------------------------------
# Requirement: crash-detect 既存インターフェース互換
# Spec: openspec/changes/autopilot-session-interop-phase-a/specs/crash-detect/spec.md
# ---------------------------------------------------------------------------

# Scenario: 既存引数形式の維持
# WHEN `crash-detect.sh --issue 1 --window "ap-#1"` を実行する
# THEN 従来と同じ引数形式で動作し、exit code 体系が維持される (0=正常, 1=エラー, 2=crash)
@test "crash-detect maintains existing CLI interface and exit code contract" {
  # exit code 0: non-running issue
  create_issue_json 1 "done"
  run bash "$SANDBOX/scripts/crash-detect.sh" --issue 1 --window "ap-#1"
  assert_success
  [ "$status" -eq 0 ]

  # exit code 1: invalid argument
  run bash "$SANDBOX/scripts/crash-detect.sh" --window "ap-#1"
  assert_failure
  [ "$status" -eq 1 ]

  # exit code 2: crash (pane absent, running issue)
  create_issue_json 2 "running"
  run bash "$SANDBOX/scripts/crash-detect.sh" --issue 2 --window "ap-#2"
  assert_failure
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Edge cases: session-state.sh exited path - failure JSON completeness
# ---------------------------------------------------------------------------

# Scenario: exited 経由の failure JSON 全フィールド検証
# WHEN session-state.sh が exited を返す
# THEN failure JSON に message, step, timestamp, detected_state が全て含まれる
@test "crash-detect failure JSON is complete when session-state reports exited" {
  create_issue_json 1 "running" '.current_step = "implement"'

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "exited"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local failure
  failure=$(jq '.failure' "$SANDBOX/.autopilot/issues/issue-1.json")

  # All required fields must be present and non-null
  [ "$(echo "$failure" | jq -r '.message')" != "null" ]
  [ "$(echo "$failure" | jq -r '.timestamp')" != "null" ]
  [ "$(echo "$failure" | jq -r '.detected_state')" = "exited" ]
}

# Edge case: SESSION_STATE_CMD set to empty string → treated as not set (fallback)
@test "crash-detect treats empty SESSION_STATE_CMD as fallback path" {
  create_issue_json 1 "running"
  # tmux stub: pane absent (default)

  SESSION_STATE_CMD="" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  local detected_state
  detected_state=$(jq -r '.failure.detected_state' "$SANDBOX/.autopilot/issues/issue-1.json")
  [ "$detected_state" = "pane_absent" ]
}

# Edge case: session-state.sh が exited を返した場合、tmux は呼ばれない
@test "crash-detect does not invoke tmux when session-state.sh succeeds" {
  create_issue_json 1 "running"

  # tmux stub that logs invocations
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
echo "tmux-was-called" >> "$SANDBOX/tmux-calls.log"
exit 0
STUB
  chmod +x "$STUB_BIN/tmux"

  cat > "$STUB_BIN/session-state.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == "state" ]]; then
  echo "exited"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/session-state.sh"

  SESSION_STATE_CMD="$STUB_BIN/session-state.sh" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  assert_failure
  [ "$status" -eq 2 ]

  # tmux must NOT have been called (session-state.sh path is exclusive)
  [ ! -f "$SANDBOX/tmux-calls.log" ]
}
