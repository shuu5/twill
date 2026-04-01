#!/usr/bin/env bats
# health-report.bats - unit tests for health-report generation
#
# Spec: openspec/changes/autopilot-proactive-monitoring/specs/health-report.md
#
# These tests verify that when health-check.sh detects an anomaly,
# the caller (autopilot-phase-execute) generates a structured report file.
# The report generator is tested as scripts/health-report.sh or via
# health-check.sh --report-dir flag (whichever the implementation provides).

load '../helpers/common'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Simulate health-check output for report generation
_stub_health_check_anomaly() {
  local issue_num="$1"
  local pattern="$2"          # chain_stall | error_output | input_waiting
  local elapsed="${3:-11}"

  cat > "$STUB_BIN/health-check.sh" <<STUB
#!/usr/bin/env bash
echo "${pattern} ${elapsed}"
exit 1
STUB
  chmod +x "$STUB_BIN/health-check.sh"
}

_stub_tmux_capture() {
  local output_text="$1"
  cat > "$STUB_BIN/tmux" <<STUB
#!/usr/bin/env bash
if echo "\$*" | grep -q "capture-pane"; then
  printf '%s\n' "$output_text"
  exit 0
fi
exit 0
STUB
  chmod +x "$STUB_BIN/tmux"
}

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

setup() {
  common_setup
  mkdir -p "$SANDBOX/.autopilot/health-reports"
  _stub_tmux_capture_empty
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: health-report 出力
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: レポートファイル生成
# ---------------------------------------------------------------------------

@test "health-report generates report file at correct path when chain_stall detected" {
  # WHEN health-check detects chain_stall (exit 1)
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  # THEN a report file matching the pattern must exist
  local report_count
  report_count=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | wc -l)
  [ "$report_count" -ge 1 ]
}

@test "health-report filename matches pattern issue-{N}-{YYYYMMDD-HHMMSS}.md" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "error_output" --elapsed 0 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  # Filename must match issue-1-YYYYMMDD-HHMMSS.md
  local found
  found=$(find "$SANDBOX/.autopilot/health-reports" \
    -name "issue-1-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].md" \
    | head -1)
  [ -n "$found" ]
}

# ---------------------------------------------------------------------------
# Scenario: レポート内容
# ---------------------------------------------------------------------------

@test "health-report file contains detection pattern type" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  [ -n "$report_file" ]
  grep -q "chain_stall" "$report_file"
}

@test "health-report file contains detection timestamp" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  # Timestamp section must be present (ISO8601 or date string)
  grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}' "$report_file"
}

@test "health-report file contains tmux capture-pane output section" {
  create_issue_json 1 "running"
  _stub_tmux_capture "Step 1 running
chain blocked here"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  # tmux capture-pane section must be present
  grep -q "capture" "$report_file" || grep -q "tmux" "$report_file"
}

@test "health-report file contains Issue Draft section" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  grep -q "Issue Draft" "$report_file"
}

# ---------------------------------------------------------------------------
# Scenario: Issue Draft テンプレート形式
# ---------------------------------------------------------------------------

@test "health-report Issue Draft contains required Title field" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  grep -q "Title" "$report_file"
  grep -q "\[autopilot\]" "$report_file"
  grep -q "Worker #1" "$report_file"
}

@test "health-report Issue Draft contains 概要 section" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  grep -q "概要" "$report_file"
}

@test "health-report Issue Draft contains 再現状況 section" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  grep -q "再現状況" "$report_file"
}

@test "health-report Issue Draft contains 対応候補 section" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | head -1)
  grep -q "対応候補" "$report_file"
}

@test "health-report Issue Draft Title includes detection pattern for error_output" {
  create_issue_json 2 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 2 --window "ap-#2" \
    --pattern "error_output" --elapsed 0 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-2-*.md" | head -1)
  grep -q "error_output" "$report_file"
  grep -q "Worker #2" "$report_file"
}

@test "health-report Issue Draft Title includes detection pattern for input_waiting" {
  create_issue_json 3 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 3 --window "ap-#3" \
    --pattern "input_waiting" --elapsed 7 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  local report_file
  report_file=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-3-*.md" | head -1)
  grep -q "input_waiting" "$report_file"
  grep -q "Worker #3" "$report_file"
}

# ---------------------------------------------------------------------------
# Scenario: ディレクトリ自動作成
# ---------------------------------------------------------------------------

@test "health-report auto-creates .autopilot/health-reports/ when directory does not exist" {
  create_issue_json 1 "running"
  # Remove the health-reports dir to test auto-creation
  rm -rf "$SANDBOX/.autopilot/health-reports"
  [ ! -d "$SANDBOX/.autopilot/health-reports" ]

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success
  [ -d "$SANDBOX/.autopilot/health-reports" ]
  local report_count
  report_count=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | wc -l)
  [ "$report_count" -ge 1 ]
}

@test "health-report auto-creates nested directory structure with mkdir -p" {
  create_issue_json 1 "running"
  rm -rf "$SANDBOX/.autopilot"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success
  [ -d "$SANDBOX/.autopilot/health-reports" ]
}

# ===========================================================================
# Requirement: gh issue create の禁止
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: Issue 自動作成の防止
# ---------------------------------------------------------------------------

@test "health-report does NOT call gh issue create" {
  create_issue_json 1 "running"

  # Stub gh to log any invocations
  cat > "$STUB_BIN/gh" <<STUB
#!/usr/bin/env bash
echo "gh-was-called: \$*" >> "$SANDBOX/gh-calls.log"
exit 0
STUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  # gh must not have been invoked with "issue create"
  if [ -f "$SANDBOX/gh-calls.log" ]; then
    ! grep -q "issue create" "$SANDBOX/gh-calls.log"
  else
    # gh was never called — pass
    true
  fi
}

@test "health-report does not call any GitHub API even for error_output pattern" {
  create_issue_json 1 "running"

  cat > "$STUB_BIN/gh" <<STUB
#!/usr/bin/env bash
echo "gh-called: \$*" >> "$SANDBOX/gh-calls.log"
exit 0
STUB
  chmod +x "$STUB_BIN/gh"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "error_output" --elapsed 0 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_success

  if [ -f "$SANDBOX/gh-calls.log" ]; then
    ! grep -q "issue" "$SANDBOX/gh-calls.log"
  else
    true
  fi
}

# ===========================================================================
# Edge cases
# ===========================================================================

@test "health-report generates separate files for multiple issues" {
  create_issue_json 1 "running"
  create_issue_json 2 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"
  assert_success

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 2 --window "ap-#2" \
    --pattern "error_output" --elapsed 0 \
    --report-dir "$SANDBOX/.autopilot/health-reports"
  assert_success

  local count_1 count_2
  count_1=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-1-*.md" | wc -l)
  count_2=$(find "$SANDBOX/.autopilot/health-reports" -name "issue-2-*.md" | wc -l)
  [ "$count_1" -ge 1 ]
  [ "$count_2" -ge 1 ]
}

@test "health-report exits with error when --issue is missing" {
  run bash "$SANDBOX/scripts/health-report.sh" \
    --window "ap-#1" \
    --pattern "chain_stall" --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_failure
  assert_output --partial "--issue"
}

@test "health-report exits with error when --pattern is missing" {
  create_issue_json 1 "running"

  run bash "$SANDBOX/scripts/health-report.sh" \
    --issue 1 --window "ap-#1" \
    --elapsed 11 \
    --report-dir "$SANDBOX/.autopilot/health-reports"

  assert_failure
}
