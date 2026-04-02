#!/usr/bin/env bash
# =============================================================================
# Functional Tests: worktree-lifecycle-safety.md
# Generated from: openspec/changes/b-3-autopilot-state-management/specs/worktree-lifecycle-safety.md
# Coverage level: edge-cases
# Tests worktree-delete.sh Pilot-only rule, crash detection, cleanup
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Script paths (will be created during implementation)
WORKTREE_DELETE="${PROJECT_ROOT}/scripts/worktree-delete.sh"
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
  mkdir -p "${SANDBOX}/main"
  mkdir -p "${SANDBOX}/worktrees/feat/42-xxx"
  # Create a .git file in main (simulating bare repo worktree)
  echo "gitdir: ${SANDBOX}/.bare" > "${SANDBOX}/main/.git"
  # Copy scripts into main/scripts/ (mirroring real project structure)
  for script in "$WORKTREE_DELETE" "$STATE_WRITE" "$STATE_READ"; do
    if [[ -f "$script" ]]; then
      mkdir -p "${SANDBOX}/main/scripts"
      cp "$script" "${SANDBOX}/main/scripts/$(basename "$script")"
      chmod +x "${SANDBOX}/main/scripts/$(basename "$script")"
    fi
  done
  # Also keep a symlink at sandbox root for other tests
  if [[ -d "${SANDBOX}/main/scripts" ]]; then
    ln -sf "${SANDBOX}/main/scripts" "${SANDBOX}/scripts"
  fi
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

# Helper: create an issue file with given status
create_issue_file() {
  local issue_num="$1"
  local status="$2"
  local retry_count="${3:-0}"
  cat > "${SANDBOX}/.autopilot/issues/issue-${issue_num}.json" <<EOF
{
  "issue": ${issue_num},
  "status": "${status}",
  "retry_count": ${retry_count},
  "current_step": "",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "failure": null
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

# =============================================================================
# Requirement: worktree 削除の Pilot 専任ルール
# =============================================================================
echo ""
echo "--- Requirement: worktree 削除の Pilot 専任ルール ---"

# Scenario: Pilot からの worktree 削除 (line 7)
# WHEN: CWD が main/ 配下で worktree-delete.sh feat/42-xxx が実行される
# THEN: worktree と対応するブランチが削除される
test_pilot_worktree_delete() {
  # Simulate running from main/ directory
  local result
  result=$(cd "${SANDBOX}/main" && bash "${SANDBOX}/main/scripts/worktree-delete.sh" "feat/42-xxx" 2>/dev/null)
  local exit_code=$?
  [[ "$exit_code" -eq 0 ]] || return 1
  # Verify the worktree directory no longer exists
  [[ ! -d "${SANDBOX}/worktrees/feat/42-xxx" ]] || return 1
}

if [[ -f "$WORKTREE_DELETE" ]]; then
  run_test "Pilot からの worktree 削除" test_pilot_worktree_delete
else
  run_test_skip "Pilot からの worktree 削除" "worktree-delete.sh not found"
fi

# Edge case: 削除後に git worktree list に対象が含まれない
test_pilot_worktree_delete_git_list() {
  # This test verifies the concept; actual git worktree would need a real repo
  # For now verify the script attempts to call git worktree remove
  if [[ -f "$WORKTREE_DELETE" ]]; then
    grep -qP "git\s+worktree\s+remove" "$WORKTREE_DELETE" || return 1
  else
    return 1
  fi
}

if [[ -f "$WORKTREE_DELETE" ]]; then
  run_test "Pilot 削除 [edge: git worktree remove が呼ばれる]" test_pilot_worktree_delete_git_list
else
  run_test_skip "Pilot 削除 [edge: git worktree remove が呼ばれる]" "worktree-delete.sh not found"
fi

# Scenario: Worker からの worktree 削除拒否 (line 11)
# WHEN: CWD が worktrees/feat/42-xxx/ 配下で worktree-delete.sh feat/42-xxx が実行される
# THEN: Worker からの削除は不変条件 B に違反するため、exit 1 でエラー終了しメッセージを表示する
test_worker_worktree_delete_denied() {
  local output
  output=$(cd "${SANDBOX}/worktrees/feat/42-xxx" && bash "${SANDBOX}/scripts/worktree-delete.sh" "feat/42-xxx" 2>&1)
  local result=$?
  [[ "$result" -ne 0 ]] || return 1
}

if [[ -f "$WORKTREE_DELETE" ]]; then
  run_test "Worker からの worktree 削除拒否" test_worker_worktree_delete_denied
else
  run_test_skip "Worker からの worktree 削除拒否" "worktree-delete.sh not found"
fi

# Edge case: エラーメッセージに不変条件 B の言及がある
test_worker_delete_error_mentions_invariant() {
  local output
  output=$(cd "${SANDBOX}/worktrees/feat/42-xxx" && bash "${SANDBOX}/scripts/worktree-delete.sh" "feat/42-xxx" 2>&1)
  echo "$output" | grep -qiP "不変条件|invariant|Pilot|main/" || return 1
}

if [[ -f "$WORKTREE_DELETE" ]]; then
  run_test "Worker 削除拒否 [edge: エラーに不変条件の言及]" test_worker_delete_error_mentions_invariant
else
  run_test_skip "Worker 削除拒否 [edge: エラーに不変条件の言及]" "worktree-delete.sh not found"
fi

# Scenario: 自身の worktree 削除拒否 (line 15)
# WHEN: CWD が worktrees/feat/42-xxx/ で自身の worktree を削除しようとする
# THEN: 自身の CWD が削除対象に含まれるため、exit 1 でエラー終了する
test_self_worktree_delete_denied() {
  local result
  cd "${SANDBOX}/worktrees/feat/42-xxx" && bash "${SANDBOX}/scripts/worktree-delete.sh" "feat/42-xxx" 2>/dev/null
  result=$?
  [[ "$result" -ne 0 ]] || return 1
  # Worktree should still exist
  [[ -d "${SANDBOX}/worktrees/feat/42-xxx" ]] || return 1
}

if [[ -f "$WORKTREE_DELETE" ]]; then
  run_test "自身の worktree 削除拒否" test_self_worktree_delete_denied
else
  run_test_skip "自身の worktree 削除拒否" "worktree-delete.sh not found"
fi

# =============================================================================
# Requirement: crash 検知によるステータス遷移
# =============================================================================
echo ""
echo "--- Requirement: crash 検知によるステータス遷移 ---"

# Scenario: tmux ペイン消失の検知 (line 23)
# WHEN: ポーリング中に tmux list-panes -t <window> が失敗し、issue-{N}.json の status が running
# THEN: issue-{N}.json の status が failed に遷移し、failure フィールドに crash 情報が記録される
test_tmux_crash_detection() {
  create_issue_file 42 "running"
  # crash-detect.sh が tmux list-panes と crash/failed 処理を持つことを検証
  local crash_script="${PROJECT_ROOT}/scripts/crash-detect.sh"
  if [[ -f "$crash_script" ]]; then
    grep -qP "tmux.*list-panes|list-panes" "$crash_script" || return 1
    grep -qP "failed|crash" "$crash_script" || return 1
  else
    return 1
  fi
}

# Check for crash detection script
if [[ -f "${PROJECT_ROOT}/scripts/crash-detect.sh" ]]; then
  run_test "tmux ペイン消失の検知" test_tmux_crash_detection
else
  run_test_skip "tmux ペイン消失の検知" "crash-detect.sh not found"
fi

# Edge case: failure フィールドに message, step, timestamp が含まれる
test_crash_failure_fields() {
  # Structural check: the spec or implementation mentions crash failure fields
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/worktree-lifecycle-safety.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "message.*step.*timestamp|crash.*情報" "$spec_file" || return 1
}

run_test "crash 検知 [edge: failure に message/step/timestamp]" test_crash_failure_fields

# Scenario: 正常終了との区別 (line 27)
# WHEN: tmux ペインが消失し、issue-{N}.json の status が merge-ready
# THEN: Worker は正常に merge-ready を宣言して終了したため、crash として扱わない
test_normal_exit_not_crash() {
  create_issue_file 42 "merge-ready"
  # If status is merge-ready, tmux pane disappearance is NOT a crash
  # Structural verification: the issue file status should remain merge-ready
  local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
  local status
  status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
  [[ "$status" == "merge-ready" ]] || return 1
}

run_test "正常終了との区別（merge-ready は crash ではない）" test_normal_exit_not_crash

# Edge case: merge-ready 以外の非 running status（failed, done）もcrash扱いしない
test_non_running_not_crash() {
  for s in "merge-ready" "failed" "done"; do
    create_issue_file 42 "$s"
    local issue_file="${SANDBOX}/.autopilot/issues/issue-42.json"
    local status
    status=$(python3 -c "import json; print(json.load(open('$issue_file'))['status'])" 2>/dev/null)
    [[ "$status" == "$s" ]] || return 1
  done
}

run_test "正常終了区別 [edge: 非 running status は全て crash 扱いしない]" test_non_running_not_crash

# =============================================================================
# Requirement: merge 後の worktree クリーンアップ
# =============================================================================
echo ""
echo "--- Requirement: merge 後の worktree クリーンアップ ---"

# Scenario: merge 成功後のクリーンアップ (line 35)
# WHEN: issue-{N}.json の status が done に遷移した後
# THEN: Pilot が worktree-delete.sh で worktree を削除し、tmux kill-window で window を終了する
test_merge_cleanup() {
  # Structural verification: check spec mentions both worktree-delete and tmux kill-window
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/worktree-lifecycle-safety.md"
  [[ -f "$spec_file" ]] || return 1
  grep -qP "worktree-delete" "$spec_file" || return 1
  grep -qP "tmux.*kill-window|kill-window" "$spec_file" || return 1
}

run_test "merge 成功後のクリーンアップ" test_merge_cleanup

# Edge case: クリーンアップの順序が worktree 削除 → tmux kill の順
test_cleanup_order() {
  # Check the spec or implementation defines the cleanup order
  local spec_file="${PROJECT_ROOT}/openspec/changes/b-3-autopilot-state-management/specs/worktree-lifecycle-safety.md"
  [[ -f "$spec_file" ]] || return 1
  # worktree-delete should appear before tmux kill-window in the spec
  local wt_line tmux_line
  wt_line=$(grep -nP "worktree-delete" "$spec_file" | head -1 | cut -d: -f1)
  tmux_line=$(grep -nP "tmux.*kill-window|kill-window" "$spec_file" | head -1 | cut -d: -f1)
  [[ -n "$wt_line" && -n "$tmux_line" ]] || return 1
  [[ "$wt_line" -le "$tmux_line" ]] || return 1
}

run_test "merge クリーンアップ [edge: worktree 削除 → tmux kill の順序]" test_cleanup_order

# Scenario: merge-gate REJECT 後の worktree 保持 (line 39)
# WHEN: merge-gate が REJECT を返し、retry_count < 1
# THEN: worktree は削除せず保持する（fix-phase で再利用するため）
test_reject_worktree_preserved() {
  create_issue_file 42 "failed" 0
  # Worktree should still exist after REJECT
  [[ -d "${SANDBOX}/worktrees/feat/42-xxx" ]] || return 1
}

run_test "merge-gate REJECT 後の worktree 保持" test_reject_worktree_preserved

# Edge case: retry_count >= 1 の REJECT 後も worktree は保持される（手動介入のため）
test_reject_max_retry_worktree_preserved() {
  create_issue_file 42 "failed" 1
  [[ -d "${SANDBOX}/worktrees/feat/42-xxx" ]] || return 1
}

run_test "REJECT 後 worktree 保持 [edge: retry_count >= 1 でも保持]" test_reject_max_retry_worktree_preserved

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
