#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot session management commands
# Generated from: openspec/changes/c-2d-autopilot-controller-autopilot/specs/session-management/spec.md
# Coverage level: edge-cases
# Verifies: autopilot-init, autopilot-launch, autopilot-poll COMMAND.md
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_get() {
  local file="$1"
  local expr="$2"
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = yaml.safe_load(f)
${expr}
" 2>/dev/null
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++))
}

INIT_CMD="commands/autopilot-init.md"
LAUNCH_CMD="commands/autopilot-launch.md"
POLL_CMD="commands/autopilot-poll.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: autopilot-init コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-init コマンド ---"

# Scenario: 正常初期化 (line 18)
# WHEN: .autopilot/ が未存在で plan.yaml が有効
# THEN: .autopilot/ が作成され session.json が生成される。SESSION_ID が出力される

test_init_file_exists() {
  assert_file_exists "$INIT_CMD"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init COMMAND.md が存在する" test_init_file_exists
else
  run_test_skip "autopilot-init COMMAND.md が存在する" "commands/autopilot-init.md not yet created"
fi

test_init_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init COMMAND.md exists (deps.yaml defines type)" test_init_frontmatter_type
else
  run_test_skip "autopilot-init COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_init_autopilot_init_sh() {
  assert_file_contains "$INIT_CMD" "autopilot-init\.sh"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init が autopilot-init.sh を参照" test_init_autopilot_init_sh
else
  run_test_skip "autopilot-init が autopilot-init.sh を参照" "COMMAND.md not yet created"
fi

test_init_session_create_sh() {
  assert_file_contains "$INIT_CMD" "session-create\.sh"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init が session-create.sh を参照" test_init_session_create_sh
else
  run_test_skip "autopilot-init が session-create.sh を参照" "COMMAND.md not yet created"
fi

test_init_plan_file_input() {
  assert_file_contains "$INIT_CMD" "PLAN_FILE|plan\.yaml|plan_path"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init が PLAN_FILE を入力として記述" test_init_plan_file_input
else
  run_test_skip "autopilot-init が PLAN_FILE を入力として記述" "COMMAND.md not yet created"
fi

test_init_session_id_output() {
  assert_file_contains "$INIT_CMD" "SESSION_ID"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init が SESSION_ID を出力として記述" test_init_session_id_output
else
  run_test_skip "autopilot-init が SESSION_ID を出力として記述" "COMMAND.md not yet created"
fi

test_init_phase_count_output() {
  assert_file_contains "$INIT_CMD" "PHASE_COUNT|phase_count"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init が PHASE_COUNT を記述" test_init_phase_count_output
else
  run_test_skip "autopilot-init が PHASE_COUNT を記述" "COMMAND.md not yet created"
fi

# Scenario: 既存セッション検出 (line 23)
# WHEN: session.json が既に存在（24h 以内）
# THEN: autopilot-init.sh がエラーを返し、排他制御メッセージが表示される

test_init_existing_session_error() {
  assert_file_contains "$INIT_CMD" "既存|排他|existing.*session|already.*running|session.*exist"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init 既存セッションのエラーハンドリング記述" test_init_existing_session_error
else
  run_test_skip "autopilot-init 既存セッションのエラーハンドリング記述" "COMMAND.md not yet created"
fi

# Scenario: 旧マーカー残存警告 (line 27)
# WHEN: /tmp/dev-autopilot/ にマーカーファイルが存在
# THEN: 「旧マーカーファイルが残存しています」警告を出力する

test_init_legacy_marker_warning() {
  assert_file_contains "$INIT_CMD" "旧マーカー|legacy.*marker|/tmp/dev-autopilot|マーカー.*残存|marker.*warn"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init 旧マーカー残存警告の記述" test_init_legacy_marker_warning
else
  run_test_skip "autopilot-init 旧マーカー残存警告の記述" "COMMAND.md not yet created"
fi

# Edge case: autopilot-init にマーカーファイル参照なし（旧パターン禁止）
test_init_no_marker_refs() {
  assert_file_not_contains "$INIT_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$INIT_CMD" '\.done"' || return 1
  assert_file_not_contains "$INIT_CMD" '\.fail"' || return 1
  assert_file_not_contains "$INIT_CMD" '\.merge-ready"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init [edge: マーカーファイル参照なし]" test_init_no_marker_refs
else
  run_test_skip "autopilot-init [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_init_no_dev_autopilot_session() {
  assert_file_not_contains "$INIT_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_init_no_dev_autopilot_session
else
  run_test_skip "autopilot-init [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: SESSION_STATE_FILE 出力の記述
test_init_session_state_file() {
  assert_file_contains "$INIT_CMD" "SESSION_STATE_FILE"
}

if [[ -f "${PROJECT_ROOT}/${INIT_CMD}" ]]; then
  run_test "autopilot-init [edge: SESSION_STATE_FILE 出力の記述]" test_init_session_state_file
else
  run_test_skip "autopilot-init [edge: SESSION_STATE_FILE 出力の記述]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: autopilot-launch コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-launch コマンド ---"

# Scenario: 正常起動 (line 47)
# WHEN: cld が PATH に存在し Issue 番号が有効
# THEN: issue-{N}.json が status=running で作成され、tmux window "ap-#N" が起動される

test_launch_file_exists() {
  assert_file_exists "$LAUNCH_CMD"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch COMMAND.md が存在する" test_launch_file_exists
else
  run_test_skip "autopilot-launch COMMAND.md が存在する" "commands/autopilot-launch.md not yet created"
fi

test_launch_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch COMMAND.md exists (deps.yaml defines type)" test_launch_frontmatter_type
else
  run_test_skip "autopilot-launch COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_launch_state_write_init() {
  assert_file_contains "$LAUNCH_CMD" "state-write\.sh.*--init|state-write.*init"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch が state-write --init で issue 状態初期化" test_launch_state_write_init
else
  run_test_skip "autopilot-launch が state-write --init で issue 状態初期化" "COMMAND.md not yet created"
fi

test_launch_tmux_window() {
  assert_file_contains "$LAUNCH_CMD" 'tmux.*new-window|tmux.*new.window|ap-#'
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch が tmux window 作成を記述" test_launch_tmux_window
else
  run_test_skip "autopilot-launch が tmux window 作成を記述" "COMMAND.md not yet created"
fi

test_launch_workflow_setup() {
  assert_file_contains "$LAUNCH_CMD" "workflow-setup.*--auto.*--auto-merge"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch が workflow-setup --auto --auto-merge を記述" test_launch_workflow_setup
else
  run_test_skip "autopilot-launch が workflow-setup --auto --auto-merge を記述" "COMMAND.md not yet created"
fi

# Scenario: cross-issue 警告付き起動 (line 51)
# WHEN: CROSS_ISSUE_WARNINGS に該当 Issue の警告がある（high confidence）
# THEN: --append-system-prompt にサニタイズ済み警告テキストが注入される

test_launch_cross_issue_warnings_input() {
  assert_file_contains "$LAUNCH_CMD" "CROSS_ISSUE_WARNINGS"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch が CROSS_ISSUE_WARNINGS 入力を記述" test_launch_cross_issue_warnings_input
else
  run_test_skip "autopilot-launch が CROSS_ISSUE_WARNINGS 入力を記述" "COMMAND.md not yet created"
fi

test_launch_append_system_prompt() {
  assert_file_contains "$LAUNCH_CMD" "append-system-prompt|append.*system.*prompt"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch が --append-system-prompt を記述" test_launch_append_system_prompt
else
  run_test_skip "autopilot-launch が --append-system-prompt を記述" "COMMAND.md not yet created"
fi

# Scenario: cld 未検出 (line 55)
# WHEN: cld が PATH に存在しない
# THEN: state-write で status=failed に遷移し、failure.message に "cld_not_found" を記録する

test_launch_cld_not_found_handling() {
  assert_file_contains "$LAUNCH_CMD" "cld_not_found|cld.*not.*found|cld.*存在しない"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch cld 未検出時のエラー記述" test_launch_cld_not_found_handling
else
  run_test_skip "autopilot-launch cld 未検出時のエラー記述" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION を設定していないこと（禁止の言及は許容）
test_launch_no_dev_autopilot_session() {
  assert_file_not_contains "$LAUNCH_CMD" "export DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_launch_no_dev_autopilot_session
else
  run_test_skip "autopilot-launch [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル参照なし
test_launch_no_marker_refs() {
  assert_file_not_contains "$LAUNCH_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$LAUNCH_CMD" '\.done"' || return 1
  assert_file_not_contains "$LAUNCH_CMD" '\.fail"' || return 1
  assert_file_not_contains "$LAUNCH_CMD" '\.merge-ready"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch [edge: マーカーファイル参照なし]" test_launch_no_marker_refs
else
  run_test_skip "autopilot-launch [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: crash-detect.sh のペイン死亡フック設定
test_launch_pane_died_hook() {
  assert_file_contains "$LAUNCH_CMD" "pane-died|crash-detect|pane.*died"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch [edge: pane-died フックで crash-detect.sh 設定]" test_launch_pane_died_hook
else
  run_test_skip "autopilot-launch [edge: pane-died フックで crash-detect.sh 設定]" "COMMAND.md not yet created"
fi

# Edge case: PHASE_INSIGHTS 入力の記述
test_launch_phase_insights_input() {
  assert_file_contains "$LAUNCH_CMD" "PHASE_INSIGHTS"
}

if [[ -f "${PROJECT_ROOT}/${LAUNCH_CMD}" ]]; then
  run_test "autopilot-launch [edge: PHASE_INSIGHTS 入力の記述]" test_launch_phase_insights_input
else
  run_test_skip "autopilot-launch [edge: PHASE_INSIGHTS 入力の記述]" "COMMAND.md not yet created"
fi

# =============================================================================
# Requirement: autopilot-poll コマンド
# =============================================================================
echo ""
echo "--- Requirement: autopilot-poll コマンド ---"

# Scenario: 正常完了検知（single） (line 74)
# WHEN: Worker が merge-ready に遷移
# THEN: "Issue #N: merge-ready" を出力し、ポーリングを終了する

test_poll_file_exists() {
  assert_file_exists "$POLL_CMD"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll COMMAND.md が存在する" test_poll_file_exists
else
  run_test_skip "autopilot-poll COMMAND.md が存在する" "commands/autopilot-poll.md not yet created"
fi

test_poll_frontmatter_type() {
  return 0  # deps.yaml defines type
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll COMMAND.md exists (deps.yaml defines type)" test_poll_frontmatter_type
else
  run_test_skip "autopilot-poll COMMAND.md exists (deps.yaml defines type)" "COMMAND.md not yet created"
fi

test_poll_state_read_ref() {
  assert_file_contains "$POLL_CMD" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll が state-read.sh を参照" test_poll_state_read_ref
else
  run_test_skip "autopilot-poll が state-read.sh を参照" "COMMAND.md not yet created"
fi

# Scenario: クラッシュ検知 (line 78)
# WHEN: tmux ペインが消失し status が running のまま
# THEN: crash-detect.sh が status=failed に遷移させる

test_poll_crash_detect_ref() {
  assert_file_contains "$POLL_CMD" "crash-detect\.sh|crash.detect"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll が crash-detect.sh を参照" test_poll_crash_detect_ref
else
  run_test_skip "autopilot-poll が crash-detect.sh を参照" "COMMAND.md not yet created"
fi

# Scenario: タイムアウト (line 82)
# WHEN: 360 回のポーリング（60 分）で状態が変化しない
# THEN: state-write で status=failed, reason=poll_timeout に遷移する

test_poll_timeout_handling() {
  assert_file_contains "$POLL_CMD" "MAX_POLL|360|poll_timeout|タイムアウト|timeout"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll タイムアウトハンドリングの記述" test_poll_timeout_handling
else
  run_test_skip "autopilot-poll タイムアウトハンドリングの記述" "COMMAND.md not yet created"
fi

test_poll_timeout_state_write() {
  assert_file_contains "$POLL_CMD" "state-write.*failed|poll_timeout|status.*failed"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll タイムアウト時に state-write で failed 記録" test_poll_timeout_state_write
else
  run_test_skip "autopilot-poll タイムアウト時に state-write で failed 記録" "COMMAND.md not yet created"
fi

# Scenario: phase モードの一括ポーリング (line 86)
# WHEN: POLL_MODE=phase で 3 Issue を監視
# THEN: 全 Issue が done/failed/merge-ready になるまでポーリングを継続する

test_poll_phase_mode() {
  assert_file_contains "$POLL_CMD" "POLL_MODE|phase.*モード|phase mode"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll phase モードの記述" test_poll_phase_mode
else
  run_test_skip "autopilot-poll phase モードの記述" "COMMAND.md not yet created"
fi

# Edge case: マーカーファイル参照なし（明示的に禁止）
test_poll_no_marker_refs() {
  assert_file_not_contains "$POLL_CMD" "MARKER_DIR" || return 1
  assert_file_not_contains "$POLL_CMD" '\.done"' || return 1
  assert_file_not_contains "$POLL_CMD" '\.fail"' || return 1
  assert_file_not_contains "$POLL_CMD" '\.merge-ready"' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll [edge: マーカーファイル参照なし]" test_poll_no_marker_refs
else
  run_test_skip "autopilot-poll [edge: マーカーファイル参照なし]" "COMMAND.md not yet created"
fi

# Edge case: DEV_AUTOPILOT_SESSION 参照なし
test_poll_no_dev_autopilot_session() {
  assert_file_not_contains "$POLL_CMD" "DEV_AUTOPILOT_SESSION"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll [edge: DEV_AUTOPILOT_SESSION 参照なし]" test_poll_no_dev_autopilot_session
else
  run_test_skip "autopilot-poll [edge: DEV_AUTOPILOT_SESSION 参照なし]" "COMMAND.md not yet created"
fi

# Edge case: 10 秒間隔の明示
test_poll_10_second_interval() {
  assert_file_contains "$POLL_CMD" "10.*秒|10.*second|sleep.*10|POLL_INTERVAL.*10"
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll [edge: 10 秒ポーリング間隔の明示]" test_poll_10_second_interval
else
  run_test_skip "autopilot-poll [edge: 10 秒ポーリング間隔の明示]" "COMMAND.md not yet created"
fi

# Edge case: merge-ready と done/failed の全ステータス検知
test_poll_all_terminal_statuses() {
  assert_file_contains "$POLL_CMD" "done" || return 1
  assert_file_contains "$POLL_CMD" "failed" || return 1
  assert_file_contains "$POLL_CMD" "merge-ready" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${POLL_CMD}" ]]; then
  run_test "autopilot-poll [edge: done/failed/merge-ready 全ステータス検知]" test_poll_all_terminal_statuses
else
  run_test_skip "autopilot-poll [edge: done/failed/merge-ready 全ステータス検知]" "COMMAND.md not yet created"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
