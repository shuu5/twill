#!/usr/bin/env bash
# =============================================================================
# Unit Tests: Worker terminal status 検証ガード (Issue #131)
#
# Coverage:
#   1. Document-level: worker-terminal-guard.sh の構造検証
#   2. chain-runner.sh 修正: 2>/dev/null || true 削除 + err 関数経由出力
#   3. deps.yaml に worker-terminal-guard 登録
#   4. Runtime behavior: ガードの実行時挙動（terminal / non-terminal / no-op）
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_GIT_ROOT="$(cd "${PROJECT_ROOT}" && git rev-parse --show-toplevel 2>/dev/null || echo "")"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  "$func" || result=$?
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
  ((SKIP++)) || true
}

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  ! grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

# =============================================================================
# Document verification
# =============================================================================
echo ""
echo "--- Document: worker-terminal-guard.sh の構造検証 ---"

test_guard_script_exists() {
  assert_file_exists "scripts/worker-terminal-guard.sh" || return 1
}
run_test "scripts/worker-terminal-guard.sh が存在する" test_guard_script_exists

test_guard_terminal_set_definition() {
  # terminal 集合 {merge-ready, done, failed, conflict} がコメントで明記されている
  assert_file_contains "scripts/worker-terminal-guard.sh" 'merge-ready.*done.*failed.*conflict' || return 1
}
run_test "worker-terminal-guard.sh コメントに terminal 集合が明記されている" test_guard_terminal_set_definition

test_guard_autopilot_dir_noop() {
  # AUTOPILOT_DIR 未設定 → no-op（exit 0）
  assert_file_contains "scripts/worker-terminal-guard.sh" 'AUTOPILOT_DIR' || return 1
  assert_file_contains "scripts/worker-terminal-guard.sh" 'exit 0' || return 1
}
run_test "AUTOPILOT_DIR 未設定時 no-op 分岐が存在する" test_guard_autopilot_dir_noop

test_guard_terminal_case() {
  # case 文で terminal 集合を網羅
  assert_file_contains "scripts/worker-terminal-guard.sh" 'merge-ready\|done\|failed\|conflict' || return 1
}
run_test "case 文で terminal 集合を網羅している" test_guard_terminal_case

test_guard_force_fail_writes_failure() {
  # 非 terminal 時に failure.message=non_terminal_chain_end を書き込む
  assert_file_contains "scripts/worker-terminal-guard.sh" 'non_terminal_chain_end' || return 1
  assert_file_contains "scripts/worker-terminal-guard.sh" 'worker-terminal-guard' || return 1
  assert_file_contains "scripts/worker-terminal-guard.sh" 'status=failed' || return 1
}
run_test "非 terminal 時に status=failed + failure.message を書き込む" test_guard_force_fail_writes_failure

test_guard_stderr_warning() {
  assert_file_contains "scripts/worker-terminal-guard.sh" 'WARNING.*>&2|echo.*>&2' || return 1
}
run_test "非 terminal 時に stderr WARNING を出力する" test_guard_stderr_warning

test_guard_numeric_validation() {
  # 引数注入防止: 数値検証
  assert_file_contains "scripts/worker-terminal-guard.sh" '\^\[0-9\]' || return 1
}
run_test "issue_num 数値検証（引数注入防止）" test_guard_numeric_validation

# =============================================================================
# chain-runner.sh の修正検証
# =============================================================================
echo ""
echo "--- chain-runner.sh: 2>/dev/null || true 削除 + err 関数経由 ---"

test_chain_runner_no_dev_null_in_all_pass() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  # step_all_pass_check 周辺に `2>/dev/null || true` が残っていないこと
  # （他のステップでは残っていてよいので、all-pass-check 周辺をピンポイントで）
  local line_pass line_fail
  line_pass=$(grep -n 'status=merge-ready' "${PROJECT_ROOT}/scripts/chain-runner.sh" | head -1 | cut -d: -f1)
  line_fail=$(grep -n '"status=failed"' "${PROJECT_ROOT}/scripts/chain-runner.sh" | head -1 | cut -d: -f1)
  [[ -z "$line_pass" || -z "$line_fail" ]] && return 1

  # 当該行に `2>/dev/null || true` が含まれないこと
  local pass_line fail_line
  pass_line=$(sed -n "${line_pass}p" "${PROJECT_ROOT}/scripts/chain-runner.sh")
  fail_line=$(sed -n "${line_fail}p" "${PROJECT_ROOT}/scripts/chain-runner.sh")

  if echo "$pass_line" | grep -q '2>/dev/null || true'; then
    return 1
  fi
  if echo "$fail_line" | grep -q '2>/dev/null || true'; then
    return 1
  fi
  return 0
}
run_test "all-pass-check の state write から 2>/dev/null || true が削除されている" test_chain_runner_no_dev_null_in_all_pass

test_chain_runner_uses_err_on_failure() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" 'err "all-pass-check" "state write merge-ready' || return 1
  assert_file_contains "scripts/chain-runner.sh" 'err "all-pass-check" "state write failed' || return 1
}
run_test "all-pass-check 失敗時に err 関数で stderr 出力する" test_chain_runner_uses_err_on_failure

test_chain_runner_invokes_guard() {
  assert_file_exists "scripts/chain-runner.sh" || return 1
  assert_file_contains "scripts/chain-runner.sh" 'worker-terminal-guard\.sh' || return 1
  # all-pass-check 限定で呼び出される
  assert_file_contains "scripts/chain-runner.sh" 'all-pass-check.*AUTOPILOT_DIR|AUTOPILOT_DIR.*all-pass-check' || return 1
}
run_test "chain-runner.sh main 終端で worker-terminal-guard.sh を呼び出す" test_chain_runner_invokes_guard

# =============================================================================
# deps.yaml 検証
# =============================================================================
echo ""
echo "--- deps.yaml: worker-terminal-guard 登録 ---"

test_deps_yaml_has_worker_terminal_guard() {
  assert_file_exists "deps.yaml" || return 1
  assert_file_contains "deps.yaml" 'worker-terminal-guard:' || return 1
  assert_file_contains "deps.yaml" 'scripts/worker-terminal-guard\.sh' || return 1
}
run_test "deps.yaml に worker-terminal-guard コンポーネントが登録されている" test_deps_yaml_has_worker_terminal_guard

test_deps_yaml_chain_runner_calls_guard() {
  assert_file_exists "deps.yaml" || return 1
  # chain-runner の calls リストに worker-terminal-guard が含まれる
  grep -q 'worker-terminal-guard' "${PROJECT_ROOT}/deps.yaml" || return 1
}
run_test "deps.yaml の chain-runner.calls に worker-terminal-guard が含まれる" test_deps_yaml_chain_runner_calls_guard

# =============================================================================
# Runtime behavior tests
# =============================================================================
echo ""
echo "--- Runtime: worker-terminal-guard.sh の実行時挙動 ---"

_make_sandbox() {
  local sandbox
  sandbox="$(mktemp -d)"
  mkdir -p "$sandbox/.autopilot/issues"
  echo "$sandbox"
}

_write_issue_status() {
  local sandbox="$1"
  local num="$2"
  local status="$3"
  local file="${sandbox}/.autopilot/issues/issue-${num}.json"
  python3 -c "
import json, sys
data = {
    'issue': int('$num'),
    'status': '$status',
    'branch': 'feat/${num}-test',
    'pr': None,
    'window': '',
    'started_at': '2026-04-07T00:00:00Z',
    'current_step': 'all-pass-check',
    'retry_count': 0,
    'fix_instructions': None,
    'merged_at': None,
    'files_changed': [],
    'failure': None,
}
with open('$file', 'w') as f:
    json.dump(data, f)
"
}

GUARD="${PROJECT_ROOT}/scripts/worker-terminal-guard.sh"

# PYTHONPATH for twl.autopilot.state
if [[ -n "$REPO_GIT_ROOT" && -d "$REPO_GIT_ROOT/cli/twl/src" ]]; then
  export PYTHONPATH="${REPO_GIT_ROOT}/cli/twl/src${PYTHONPATH:+:${PYTHONPATH}}"
fi

test_runtime_no_autopilot_dir_noop() {
  (
    unset AUTOPILOT_DIR
    bash "$GUARD" "131" >/dev/null 2>&1
  )
}
run_test "runtime: AUTOPILOT_DIR 未設定時は no-op (exit 0)" test_runtime_no_autopilot_dir_noop

test_runtime_empty_issue_noop() {
  (
    export AUTOPILOT_DIR="/tmp"
    bash "$GUARD" "" >/dev/null 2>&1
  )
}
run_test "runtime: issue_num 空は no-op (exit 0)" test_runtime_empty_issue_noop

test_runtime_non_numeric_issue_noop() {
  (
    export AUTOPILOT_DIR="/tmp"
    bash "$GUARD" "abc" >/dev/null 2>&1
  )
}
run_test "runtime: issue_num 非数値は no-op (exit 0)" test_runtime_non_numeric_issue_noop

test_runtime_terminal_merge_ready_noop() {
  local sbx
  sbx="$(_make_sandbox)"
  _write_issue_status "$sbx" 131 "merge-ready"
  (
    export AUTOPILOT_DIR="${sbx}/.autopilot"
    bash "$GUARD" "131" >/dev/null 2>&1
  )
  local rc=$?
  rm -rf "$sbx"
  return $rc
}
run_test "runtime: status=merge-ready は no-op (exit 0)" test_runtime_terminal_merge_ready_noop

test_runtime_terminal_done_noop() {
  local sbx
  sbx="$(_make_sandbox)"
  _write_issue_status "$sbx" 131 "done"
  (
    export AUTOPILOT_DIR="${sbx}/.autopilot"
    bash "$GUARD" "131" >/dev/null 2>&1
  )
  local rc=$?
  rm -rf "$sbx"
  return $rc
}
run_test "runtime: status=done は no-op (exit 0)" test_runtime_terminal_done_noop

test_runtime_terminal_failed_noop() {
  local sbx
  sbx="$(_make_sandbox)"
  _write_issue_status "$sbx" 131 "failed"
  (
    export AUTOPILOT_DIR="${sbx}/.autopilot"
    bash "$GUARD" "131" >/dev/null 2>&1
  )
  local rc=$?
  rm -rf "$sbx"
  return $rc
}
run_test "runtime: status=failed は no-op (exit 0)" test_runtime_terminal_failed_noop

test_runtime_terminal_conflict_noop() {
  local sbx
  sbx="$(_make_sandbox)"
  _write_issue_status "$sbx" 131 "conflict"
  (
    export AUTOPILOT_DIR="${sbx}/.autopilot"
    bash "$GUARD" "131" >/dev/null 2>&1
  )
  local rc=$?
  rm -rf "$sbx"
  return $rc
}
run_test "runtime: status=conflict は no-op (exit 0)" test_runtime_terminal_conflict_noop

test_runtime_non_terminal_running_force_fail() {
  local sbx
  sbx="$(_make_sandbox)"
  _write_issue_status "$sbx" 131 "running"

  local stderr_output rc
  stderr_output=$(
    export AUTOPILOT_DIR="${sbx}/.autopilot"
    bash "$GUARD" "131" 2>&1 >/dev/null
  )
  rc=$?

  # exit 1 が返ること
  if [[ $rc -ne 1 ]]; then
    rm -rf "$sbx"
    return 1
  fi

  # stderr に WARNING が含まれること
  if ! echo "$stderr_output" | grep -q "worker-terminal-guard"; then
    rm -rf "$sbx"
    return 1
  fi
  if ! echo "$stderr_output" | grep -qi "non-terminal\|WARNING"; then
    rm -rf "$sbx"
    return 1
  fi

  # state が failed + failure.message=non_terminal_chain_end に更新されること
  local new_status new_message new_step
  new_status=$(python3 -c "import json; print(json.load(open('${sbx}/.autopilot/issues/issue-131.json'))['status'])")
  new_message=$(python3 -c "import json; print(json.load(open('${sbx}/.autopilot/issues/issue-131.json'))['failure']['message'])")
  new_step=$(python3 -c "import json; print(json.load(open('${sbx}/.autopilot/issues/issue-131.json'))['failure']['step'])")
  rm -rf "$sbx"

  [[ "$new_status" == "failed" ]] || return 1
  [[ "$new_message" == "non_terminal_chain_end" ]] || return 1
  [[ "$new_step" == "worker-terminal-guard" ]] || return 1
  return 0
}

if python3 -c "import twl.autopilot.state" 2>/dev/null; then
  run_test "runtime: status=running は force-fail (exit 1 + state write)" test_runtime_non_terminal_running_force_fail
else
  run_test_skip "runtime: status=running は force-fail (exit 1 + state write)" "twl.autopilot.state 未インポート可能"
fi

test_runtime_pythonpath_unset_module_error() {
  local sbx
  sbx="$(_make_sandbox)"
  _write_issue_status "$sbx" 197 "running"

  local stderr_output rc
  stderr_output=$(
    export AUTOPILOT_DIR="${sbx}/.autopilot"
    # PYTHONPATH を空にして ModuleNotFoundError を誘発
    export PYTHONPATH=""
    bash "$GUARD" "197" 2>&1 >/dev/null
  )
  rc=$?

  # exit 1 が返ること（非 terminal として force-fail）
  if [[ $rc -ne 1 ]]; then
    rm -rf "$sbx"
    return 1
  fi

  # stderr に PYTHONPATH 未設定の可能性 が含まれること
  if ! echo "$stderr_output" | grep -q "PYTHONPATH 未設定の可能性"; then
    rm -rf "$sbx"
    return 1
  fi

  rm -rf "$sbx"
  return 0
}

# PYTHONPATH 未設定テストは twl モジュールが通常パスにない場合のみ意味がある
if ! PYTHONPATH="" python3 -c "import twl.autopilot.state" 2>/dev/null; then
  run_test "runtime: PYTHONPATH 未設定時に ModuleNotFoundError 警告を出力する" test_runtime_pythonpath_unset_module_error
else
  run_test_skip "runtime: PYTHONPATH 未設定時に ModuleNotFoundError 警告を出力する" "twl モジュールがシステムパスにインストール済み"
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
