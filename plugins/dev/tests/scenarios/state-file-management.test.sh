#!/usr/bin/env bash
# =============================================================================
# Functional Tests: state-file-management.md
# Generated from: openspec/changes/b-3-autopilot-state-management/specs/state-file-management.md
# Coverage level: edge-cases
# Tests state-write.sh / state-read.sh behavior, role-based access, transition validation
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Script paths (will be created during implementation)
STATE_WRITE="${PROJECT_ROOT}/scripts/state-write.sh"
STATE_READ="${PROJECT_ROOT}/scripts/state-read.sh"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Sandbox Setup ---

SANDBOX=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "${SANDBOX}/.autopilot/issues"
  # Copy scripts if they exist
  if [[ -f "$STATE_WRITE" ]]; then
    mkdir -p "${SANDBOX}/scripts"
    cp "$STATE_WRITE" "${SANDBOX}/scripts/state-write.sh"
    chmod +x "${SANDBOX}/scripts/state-write.sh"
  fi
  if [[ -f "$STATE_READ" ]]; then
    mkdir -p "${SANDBOX}/scripts"
    cp "$STATE_READ" "${SANDBOX}/scripts/state-read.sh"
    chmod +x "${SANDBOX}/scripts/state-read.sh"
  fi
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

# Run state-write.sh in the sandbox context
# Subshell で SANDBOX に cd することで worktrees/ CWD ガード（不変条件C）を回避し、
# Pilot ロールのテストがワークツリー配下から実行されても正常動作させる。
run_state_write() {
  ( cd "$SANDBOX" && AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "${SANDBOX}/scripts/state-write.sh" "$@" 2>/dev/null )
}

# Run state-read.sh in the sandbox context
run_state_read() {
  AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "${SANDBOX}/scripts/state-read.sh" "$@" 2>/dev/null
}

# Helper: create an issue file with given status and optional fields
create_issue_file() {
  local issue_num="$1"
  local status="$2"
  local retry_count="${3:-0}"
  local issue_file="${SANDBOX}/.autopilot/issues/issue-${issue_num}.json"
  cat > "$issue_file" <<EOF
{
  "issue": ${issue_num},
  "status": "${status}",
  "retry_count": ${retry_count},
  "current_step": "",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "merged_at": null
}
EOF
}

# --- Test Helpers ---

run_test() {
  local name="$1"
  local func="$2"
  local result
  setup_sandbox
  result=0
  $func || result=$?
  teardown_sandbox
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

scripts_available() {
  [[ -f "$STATE_WRITE" && -f "$STATE_READ" ]]
}

# =============================================================================
# Requirement: state-write.sh による状態ファイル書き込み
# =============================================================================
echo ""
echo "--- Requirement: state-write.sh による状態ファイル書き込み ---"

# Scenario: issue-{N}.json の新規作成 (line 7)
# WHEN: state-write.sh --type issue --issue 42 --init --role worker が実行される
# THEN: .autopilot/issues/issue-42.json が作成され、status が running に設定される
test_issue_init() {
  # Remove any pre-existing file
  rm -f "${SANDBOX}/.autopilot/issues/issue-42.json"
  run_state_write --type issue --issue 42 --init --role worker || return 1
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  [[ -f "$issue_file" ]] || return 1
  local status
  status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
  [[ "$status" == "running" ]] || return 1
}

if scripts_available; then
  run_test "issue-{N}.json の新規作成" test_issue_init
else
  run_test_skip "issue-{N}.json の新規作成" "state-write.sh not found"
fi

# Edge case: --init で作成されたファイルに必須フィールドが全て存在する
test_issue_init_required_fields() {
  rm -f "${SANDBOX}/.autopilot/issues/issue-42.json"
  run_state_write --type issue --issue 42 --init --role worker || return 1
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  python3 -c "
import json, sys
data = json.load(open('$issue_file'))
for field in ['status', 'issue', 'retry_count', 'started_at']:
    assert field in data, f'missing field: {field}'
" 2>/dev/null || return 1
}

if scripts_available; then
  run_test "issue 新規作成 [edge: 必須フィールド存在]" test_issue_init_required_fields
else
  run_test_skip "issue 新規作成 [edge: 必須フィールド存在]" "state-write.sh not found"
fi

# Scenario: status の正常遷移（running → merge-ready） (line 11)
# WHEN: state-write.sh --type issue --issue 42 --set status=merge-ready --role worker が実行される
# THEN: issue-42.json の status が merge-ready に更新される
test_status_transition_running_to_merge_ready() {
  create_issue_file 42 "running"
  run_state_write --type issue --issue 42 --set status=merge-ready --role worker || return 1
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local status
  status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
  [[ "$status" == "merge-ready" ]] || return 1
}

if scripts_available; then
  run_test "status の正常遷移（running → merge-ready）" test_status_transition_running_to_merge_ready
else
  run_test_skip "status の正常遷移（running → merge-ready）" "state-write.sh not found"
fi

# Edge case: 遷移前後で他フィールドが保持される
test_status_transition_preserves_fields() {
  create_issue_file 42 "running"
  # Set a custom field value first
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local original_started_at
  original_started_at=$(python3 -c "import json; print(json.load(open('$issue_file'))['started_at'])" 2>/dev/null)
  run_state_write --type issue --issue 42 --set status=merge-ready --role worker || return 1
  local new_started_at
  new_started_at=$(python3 -c "import json; print(json.load(open('$issue_file'))['started_at'])" 2>/dev/null)
  [[ "$original_started_at" == "$new_started_at" ]] || return 1
}

if scripts_available; then
  run_test "status 遷移 [edge: 他フィールド保持]" test_status_transition_preserves_fields
else
  run_test_skip "status 遷移 [edge: 他フィールド保持]" "state-write.sh not found"
fi

# Scenario: 不正な状態遷移の拒否 (line 15)
# WHEN: state-write.sh --type issue --issue 42 --set status=done --role worker が実行され、現在の status が running
# THEN: running → done は許可された遷移パスに含まれないため、exit 1 でエラー終了する
test_invalid_transition_running_to_done() {
  create_issue_file 42 "running"
  run_state_write --type issue --issue 42 --set status=done --role worker
  local result=$?
  [[ "$result" -ne 0 ]] || return 1
  # status should remain running
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local status
  status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
  [[ "$status" == "running" ]] || return 1
}

if scripts_available; then
  run_test "不正な状態遷移の拒否（running → done）" test_invalid_transition_running_to_done
else
  run_test_skip "不正な状態遷移の拒否（running → done）" "state-write.sh not found"
fi

# Edge case: エラーメッセージに現在のstatusと要求されたstatusが含まれる
test_invalid_transition_error_message() {
  create_issue_file 42 "running"
  local stderr_output
  stderr_output=$(AUTOPILOT_DIR="${SANDBOX}/.autopilot" bash "${SANDBOX}/scripts/state-write.sh" --type issue --issue 42 --set status=done --role worker 2>&1)
  local result=$?
  [[ "$result" -ne 0 ]] || return 1
  echo "$stderr_output" | grep -qi "running" || return 1
  echo "$stderr_output" | grep -qi "done" || return 1
}

if scripts_available; then
  run_test "不正遷移拒否 [edge: エラーメッセージに遷移情報]" test_invalid_transition_error_message
else
  run_test_skip "不正遷移拒否 [edge: エラーメッセージに遷移情報]" "state-write.sh not found"
fi

# Scenario: retry_count 超過時の failed → running 拒否 (line 19)
# WHEN: state-write.sh --type issue --issue 42 --set status=running --role worker が実行され、
#       現在の status が failed かつ retry_count が 1 以上
# THEN: リトライ上限（不変条件E）により exit 1 でエラー終了する
test_retry_count_exceeded_rejection() {
  create_issue_file 42 "failed" 1
  run_state_write --type issue --issue 42 --set status=running --role worker
  local result=$?
  [[ "$result" -ne 0 ]] || return 1
}

if scripts_available; then
  run_test "retry_count 超過時の failed → running 拒否" test_retry_count_exceeded_rejection
else
  run_test_skip "retry_count 超過時の failed → running 拒否" "state-write.sh not found"
fi

# Edge case: retry_count=0 なら failed → running は許可される
test_retry_count_zero_allows_retry() {
  create_issue_file 42 "failed" 0
  run_state_write --type issue --issue 42 --set status=running --role worker || return 1
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local status
  status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
  [[ "$status" == "running" ]] || return 1
}

if scripts_available; then
  run_test "retry_count 超過 [edge: retry_count=0 なら許可]" test_retry_count_zero_allows_retry
else
  run_test_skip "retry_count 超過 [edge: retry_count=0 なら許可]" "state-write.sh not found"
fi

# =============================================================================
# Requirement: state-read.sh による状態ファイル読み取り
# =============================================================================
echo ""
echo "--- Requirement: state-read.sh による状態ファイル読み取り ---"

# Scenario: 特定フィールドの読み取り (line 27)
# WHEN: state-read.sh --type issue --issue 42 --field status が実行される
# THEN: issue-42.json の status フィールドの値が標準出力に出力される
test_read_specific_field() {
  create_issue_file 42 "merge-ready"
  local output
  output=$(run_state_read --type issue --issue 42 --field status)
  [[ "$output" == "merge-ready" ]] || return 1
}

if [[ -f "$STATE_READ" ]]; then
  run_test "特定フィールドの読み取り" test_read_specific_field
else
  run_test_skip "特定フィールドの読み取り" "state-read.sh not found"
fi

# Edge case: ネストしたフィールドや数値フィールドの読み取り
test_read_numeric_field() {
  create_issue_file 42 "running" 1
  local output
  output=$(run_state_read --type issue --issue 42 --field retry_count)
  [[ "$output" == "1" ]] || return 1
}

if [[ -f "$STATE_READ" ]]; then
  run_test "フィールド読み取り [edge: 数値フィールド]" test_read_numeric_field
else
  run_test_skip "フィールド読み取り [edge: 数値フィールド]" "state-read.sh not found"
fi

# Scenario: 全フィールドの読み取り (line 31)
# WHEN: state-read.sh --type issue --issue 42 が実行される（--field 省略）
# THEN: issue-42.json の全内容が JSON 形式で標準出力に出力される
test_read_all_fields() {
  create_issue_file 42 "running"
  local output
  output=$(run_state_read --type issue --issue 42)
  # Output should be valid JSON
  echo "$output" | python3 -c "import json,sys; data=json.load(sys.stdin); assert 'status' in data" 2>/dev/null || return 1
}

if [[ -f "$STATE_READ" ]]; then
  run_test "全フィールドの読み取り" test_read_all_fields
else
  run_test_skip "全フィールドの読み取り" "state-read.sh not found"
fi

# Edge case: 出力が有効なJSONであること
test_read_all_valid_json() {
  create_issue_file 42 "running"
  local output
  output=$(run_state_read --type issue --issue 42)
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || return 1
}

if [[ -f "$STATE_READ" ]]; then
  run_test "全フィールド読み取り [edge: 有効な JSON 出力]" test_read_all_valid_json
else
  run_test_skip "全フィールド読み取り [edge: 有効な JSON 出力]" "state-read.sh not found"
fi

# Scenario: 存在しないファイルへのアクセス (line 35)
# WHEN: state-read.sh --type issue --issue 999 --field status が実行され、issue-999.json が存在しない
# THEN: 空文字列が標準出力に出力され、exit 0 で正常終了する
test_read_nonexistent_file() {
  local output
  output=$(run_state_read --type issue --issue 999 --field status)
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
  [[ -z "$output" ]] || return 1
}

if [[ -f "$STATE_READ" ]]; then
  run_test "存在しないファイルへのアクセス" test_read_nonexistent_file
else
  run_test_skip "存在しないファイルへのアクセス" "state-read.sh not found"
fi

# Edge case: 存在しないファイルの全フィールド読み取りも空文字列を返す
test_read_nonexistent_all_fields() {
  local output
  output=$(run_state_read --type issue --issue 999)
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
  [[ -z "$output" ]] || return 1
}

if [[ -f "$STATE_READ" ]]; then
  run_test "存在しないファイル [edge: 全フィールドも空文字列]" test_read_nonexistent_all_fields
else
  run_test_skip "存在しないファイル [edge: 全フィールドも空文字列]" "state-read.sh not found"
fi

# =============================================================================
# Requirement: Pilot/Worker ロールベースアクセス制御
# =============================================================================
echo ""
echo "--- Requirement: Pilot/Worker ロールベースアクセス制御 ---"

# Scenario: Worker が session.json に書き込みを試みる (line 43)
# WHEN: state-write.sh --type session --set current_phase=2 --role worker が実行される
# THEN: Worker は session.json への書き込み権限がないため、exit 1 でエラー終了する
test_worker_session_write_denied() {
  run_state_write --type session --set current_phase=2 --role worker
  local result=$?
  [[ "$result" -ne 0 ]] || return 1
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "Worker が session.json に書き込みを試みる" test_worker_session_write_denied
else
  run_test_skip "Worker が session.json に書き込みを試みる" "state-write.sh not found"
fi

# Edge case: Pilot は session.json に書き込み可能
test_pilot_session_write_allowed() {
  # Create a session.json first
  cat > "${SANDBOX}/.autopilot/session.json" <<EOF
{
  "session_id": "test-session-001",
  "plan_path": "plan.yaml",
  "current_phase": 1,
  "phase_count": 3,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  run_state_write --type session --set current_phase=2 --role pilot || return 1
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "Worker session 書き込み拒否 [edge: Pilot は許可]" test_pilot_session_write_allowed
else
  run_test_skip "Worker session 書き込み拒否 [edge: Pilot は許可]" "state-write.sh not found"
fi

# Scenario: Pilot が issue-{N}.json に書き込みを試みる (line 47)
# WHEN: state-write.sh --type issue --issue 42 --set status=done --role pilot が実行される
# THEN: status=done への遷移は Pilot に許可される
test_pilot_issue_status_done() {
  create_issue_file 42 "merge-ready"
  run_state_write --type issue --issue 42 --set status=done --role pilot || return 1
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local status
  status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
  [[ "$status" == "done" ]] || return 1
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "Pilot が issue status=done に書き込み" test_pilot_issue_status_done
else
  run_test_skip "Pilot が issue status=done に書き込み" "state-write.sh not found"
fi

# Scenario: Pilot が issue-{N}.json の status 以外のフィールドに書き込みを試みる (line 51)
# WHEN: state-write.sh --type issue --issue 42 --set current_step=review --role pilot が実行される
# THEN: Pilot は issue-{N}.json の status と merged_at 以外のフィールドへの書き込み権限がないため、exit 1
test_pilot_issue_non_status_field_denied() {
  create_issue_file 42 "running"
  run_state_write --type issue --issue 42 --set current_step=review --role pilot
  local result=$?
  [[ "$result" -ne 0 ]] || return 1
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "Pilot が issue の status 以外フィールド書き込み拒否" test_pilot_issue_non_status_field_denied
else
  run_test_skip "Pilot が issue の status 以外フィールド書き込み拒否" "state-write.sh not found"
fi

# Edge case: Pilot は merged_at フィールドには書き込み可能
test_pilot_issue_merged_at_allowed() {
  create_issue_file 42 "merge-ready"
  run_state_write --type issue --issue 42 --set "merged_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" --role pilot || return 1
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "Pilot issue フィールド制限 [edge: merged_at は許可]" test_pilot_issue_merged_at_allowed
else
  run_test_skip "Pilot issue フィールド制限 [edge: merged_at は許可]" "state-write.sh not found"
fi

# =============================================================================
# Requirement: 状態遷移テーブルの機械的検証
# =============================================================================
echo ""
echo "--- Requirement: 状態遷移テーブルの機械的検証 ---"

# Scenario: 全許可遷移の受理 (line 67)
# WHEN: 許可遷移リストに含まれる遷移が要求される
# THEN: 遷移が実行され、exit 0 で正常終了する
test_all_valid_transitions() {
  # running -> merge-ready
  create_issue_file 42 "running"
  run_state_write --type issue --issue 42 --set status=merge-ready --role worker || return 1

  # running -> failed
  create_issue_file 43 "running"
  run_state_write --type issue --issue 43 --set status=failed --role worker || return 1

  # merge-ready -> done (pilot only)
  create_issue_file 44 "merge-ready"
  run_state_write --type issue --issue 44 --set status=done --role pilot || return 1

  # merge-ready -> failed
  create_issue_file 45 "merge-ready"
  run_state_write --type issue --issue 45 --set status=failed --role worker || return 1

  # failed -> running (retry_count < 1)
  create_issue_file 46 "failed" 0
  run_state_write --type issue --issue 46 --set status=running --role worker || return 1
}

if scripts_available; then
  run_test "全許可遷移の受理" test_all_valid_transitions
else
  run_test_skip "全許可遷移の受理" "state-write.sh not found"
fi

# Edge case: 各遷移後に正しいstatusが保存されている
test_valid_transitions_verify_status() {
  create_issue_file 42 "running"
  run_state_write --type issue --issue 42 --set status=merge-ready --role worker || return 1
  local status
  status=$(python3 -c "import json; print(json.load(open('${SANDBOX}/.autopilot/issues/issue-42.json'))['status'])" 2>/dev/null)
  [[ "$status" == "merge-ready" ]] || return 1

  create_issue_file 43 "running"
  run_state_write --type issue --issue 43 --set status=failed --role worker || return 1
  status=$(python3 -c "import json; print(json.load(open('${SANDBOX}/.autopilot/issues/issue-43.json'))['status'])" 2>/dev/null)
  [[ "$status" == "failed" ]] || return 1
}

if scripts_available; then
  run_test "全許可遷移 [edge: 各遷移後の status 検証]" test_valid_transitions_verify_status
else
  run_test_skip "全許可遷移 [edge: 各遷移後の status 検証]" "state-write.sh not found"
fi

# Scenario: done からの遷移拒否 (line 71)
# WHEN: status が done の issue-{N}.json に対して任意の status 更新が要求される
# THEN: done は終端状態であるため、exit 1 でエラー終了する
test_done_is_terminal() {
  create_issue_file 42 "done"
  # Try every possible target status
  for target in running merge-ready failed done; do
    run_state_write --type issue --issue 42 --set "status=${target}" --role pilot
    local result=$?
    [[ "$result" -ne 0 ]] || return 1
  done
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "done からの遷移拒否" test_done_is_terminal
else
  run_test_skip "done からの遷移拒否" "state-write.sh not found"
fi

# Edge case: done 状態の issue ファイルが変更されていないことを確認
test_done_file_unchanged() {
  create_issue_file 42 "done"
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local before_hash
  before_hash=$(md5sum "$issue_file" | cut -d' ' -f1)
  run_state_write --type issue --issue 42 --set status=running --role pilot 2>/dev/null || true
  local after_hash
  after_hash=$(md5sum "$issue_file" | cut -d' ' -f1)
  [[ "$before_hash" == "$after_hash" ]] || return 1
}

if [[ -f "$STATE_WRITE" ]]; then
  run_test "done 遷移拒否 [edge: ファイル内容未変更]" test_done_file_unchanged
else
  run_test_skip "done 遷移拒否 [edge: ファイル内容未変更]" "state-write.sh not found"
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
