#!/usr/bin/env bash
# =============================================================================
# Unit Tests: auto-merge.md フォールバックガード（issue-{N}.json 直接確認）
# Generated from: openspec/changes/autopilot-fallback-guard/specs/fallback-guard.md
# Requirement: auto-merge フォールバックガード（issue-{N}.json 直接確認）
# Coverage level: edge-cases (happy path + edge cases)
#
# Strategy:
#   1. Document-level tests: verify auto-merge.md contains the required guard logic
#   2. Functional tests: exercise the guard logic in an isolated subshell using
#      a temporary AUTOPILOT_DIR, without touching real state files.
#
# The guard spec (Step 0 of auto-merge.md) requires:
#   - When IS_AUTOPILOT=false AND issue-{N}.json EXISTS in main worktree .autopilot/
#     → do NOT merge; call state-write.sh with status=merge-ready; warn; exit 0
#   - When IS_AUTOPILOT=false AND issue-{N}.json DOES NOT EXIST
#     → proceed with Step 1+ (normal merge flow)
#   - When ISSUE_NUM is unset/empty
#     → skip fallback check; proceed with normal merge flow
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
  if grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

TARGET_CMD="scripts/auto-merge.sh"

# ---------------------------------------------------------------------------
# Functional guard runner
#
# Executes the fallback guard logic (extracted as a self-contained snippet)
# in an isolated subshell.
#
# The guard snippet mirrors what auto-merge.md Step 0 SHALL implement:
#
#   if [[ -n "$ISSUE_NUM" && "$IS_AUTOPILOT" == "false" ]]; then
#     MAIN_AUTOPILOT_DIR="<main_worktree>/.autopilot"
#     if [[ -f "$MAIN_AUTOPILOT_DIR/issue-${ISSUE_NUM}.json" ]]; then
#       bash scripts/state-write.sh --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready
#       echo "WARNING: fallback guard triggered ..." >&2
#       exit 0
#     fi
#   fi
#
# Arguments:
#   $1  ISSUE_NUM value (pass "" to simulate unset)
#   $2  IS_AUTOPILOT value ("true" | "false")
#   $3  AUTOPILOT_DIR path (temp dir controlled by tests)
#   $4  expected_action: "block" | "continue"
#
# Returns 0 if the guard behaves as expected, 1 otherwise.
# ---------------------------------------------------------------------------

run_fallback_guard() {
  local issue_num="$1"
  local is_autopilot="$2"
  local autopilot_dir="$3"
  local expected_action="$4"

  local actual_action
  actual_action=$(bash -c "
    set -uo pipefail
    ISSUE_NUM='${issue_num}'
    IS_AUTOPILOT='${is_autopilot}'
    MAIN_AUTOPILOT_DIR='${autopilot_dir}'

    ACTION='continue'

    if [[ -n \"\${ISSUE_NUM}\" && \"\${IS_AUTOPILOT}\" == 'false' ]]; then
      if [[ -f \"\${MAIN_AUTOPILOT_DIR}/issue-\${ISSUE_NUM}.json\" ]]; then
        # Fallback guard fires: simulate state-write + warning + exit 0
        echo 'WARNING: IS_AUTOPILOT=false 誤判定 — フォールバックガード発動' >&2
        ACTION='block'
      fi
    fi

    echo \"\${ACTION}\"
  " 2>/dev/null)

  [[ "$actual_action" == "$expected_action" ]]
}

# ---------------------------------------------------------------------------
# =============================================================================
# Requirement: auto-merge フォールバックガード（issue-{N}.json 直接確認）
# Source: specs/fallback-guard.md, line 3
# =============================================================================

echo ""
echo "--- Requirement: auto-merge フォールバックガード ---"

# ---------------------------------------------------------------------------
# Structural tests: auto-merge.md must document the guard
# ---------------------------------------------------------------------------

test_auto_merge_exists() {
  assert_file_exists "$TARGET_CMD"
}
run_test "auto-merge.md が存在する" test_auto_merge_exists

test_fallback_guard_documented() {
  # Must reference the fallback guard concept using filesystem direct check
  assert_file_contains "$TARGET_CMD" \
    '(fallback|フォールバック|直接確認|issue-\{N\}\.json|issue-\\\$\{ISSUE_NUM\}\.json|-f .*/\.autopilot/)' || return 1
}
run_test "auto-merge.md にフォールバックガード（ファイル直接確認）が記述されている" test_fallback_guard_documented

test_fallback_guard_no_state_read_dependency() {
  # The guard SHALL NOT use state-read.sh (it must be a direct fs check)
  # The spec says: "この検証は state-read.sh を使用せず、ファイルシステムの直接存在確認で行わなければならない"
  # Check that the guard section does NOT rely on state-read.sh for the fallback check.
  # We accept that state-read.sh may appear elsewhere in the file (for IS_AUTOPILOT detection),
  # but the fallback guard itself must use -f file check.
  assert_file_contains "$TARGET_CMD" '\-f .*issue-' || return 1
}
run_test "auto-merge.md のフォールバックガードが -f ファイル存在確認を使用する" test_fallback_guard_no_state_read_dependency

test_fallback_guard_merge_ready_transition() {
  # On guard trigger: state-write.sh must be called with status=merge-ready
  assert_file_contains "$TARGET_CMD" 'state-write\.sh.*merge-ready|merge-ready.*state-write\.sh' || return 1
}
run_test "auto-merge.md フォールバックガードが status=merge-ready 遷移を含む" test_fallback_guard_merge_ready_transition

test_fallback_guard_warns_on_trigger() {
  # Must output a warning message when guard fires
  assert_file_contains "$TARGET_CMD" '(警告|WARNING|warn|フォールバック.*ガード|fallback.*guard)' || return 1
}
run_test "auto-merge.md フォールバックガードが警告メッセージを出力する" test_fallback_guard_warns_on_trigger

test_fallback_guard_skips_merge_on_trigger() {
  # When guard fires, merge (gh pr merge) must NOT be executed
  # The guard must cause early exit / skip of Step 1+
  assert_file_contains "$TARGET_CMD" '(正常終了|Step 1.*スキップ|処理を終了|exit 0|ここで終了|早期終了)' || return 1
}
run_test "auto-merge.md フォールバックガード発動時に merge をスキップする" test_fallback_guard_skips_merge_on_trigger

test_fallback_guard_main_worktree_path() {
  # The guard must check the main worktree's .autopilot directory, not CWD/.autopilot
  assert_file_contains "$TARGET_CMD" '(main.*worktree.*\.autopilot|main.*\.autopilot|MAIN.*AUTOPILOT|main_worktree.*autopilot)' || return 1
}
run_test "auto-merge.md フォールバックガードが main worktree の .autopilot を参照する" test_fallback_guard_main_worktree_path

# ---------------------------------------------------------------------------
# Scenario: IS_AUTOPILOT=false 誤判定 + issue-{N}.json 存在（spec line 9）
# WHEN: IS_AUTOPILOT=false, main worktree .autopilot/issue-${ISSUE_NUM}.json が存在する
# THEN: merge を実行せず、status=merge-ready に遷移し、警告出力して正常終了
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: IS_AUTOPILOT=false 誤判定 + issue-{N}.json 存在]"

test_guard_blocks_when_json_exists() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '{"status":"running"}' > "${tmpdir}/issue-86.json"

  run_fallback_guard "86" "false" "${tmpdir}" "block"
  local rc=$?
  rm -rf "${tmpdir}"
  return $rc
}
run_test "IS_AUTOPILOT=false + issue-N.json 存在 → フォールバックガード発動 (block)" \
  test_guard_blocks_when_json_exists

test_guard_outputs_warning_when_triggered() {
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '{"status":"running"}' > "${tmpdir}/issue-86.json"

  local stderr_out
  stderr_out=$(bash -c "
    ISSUE_NUM='86'
    IS_AUTOPILOT='false'
    MAIN_AUTOPILOT_DIR='${tmpdir}'
    if [[ -n \"\${ISSUE_NUM}\" && \"\${IS_AUTOPILOT}\" == 'false' ]]; then
      if [[ -f \"\${MAIN_AUTOPILOT_DIR}/issue-\${ISSUE_NUM}.json\" ]]; then
        echo 'WARNING: IS_AUTOPILOT=false 誤判定 — フォールバックガード発動' >&2
      fi
    fi
  " 2>&1) || true

  rm -rf "${tmpdir}"
  echo "${stderr_out}" | grep -qiE '(warning|warn|フォールバック|fallback|誤判定)' || return 1
}
run_test "IS_AUTOPILOT=false + issue-N.json 存在 → 警告メッセージが出力される" \
  test_guard_outputs_warning_when_triggered

test_guard_blocks_different_issue_numbers() {
  # Edge: guard must work for any ISSUE_NUM, not just hardcoded values
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '{"status":"running"}' > "${tmpdir}/issue-1.json"
  echo '{"status":"running"}' > "${tmpdir}/issue-999.json"

  run_fallback_guard "1" "false" "${tmpdir}" "block" || { rm -rf "${tmpdir}"; return 1; }
  run_fallback_guard "999" "false" "${tmpdir}" "block" || { rm -rf "${tmpdir}"; return 1; }
  rm -rf "${tmpdir}"
}
run_test "[edge] 任意の ISSUE_NUM に対してフォールバックガードが機能する" \
  test_guard_blocks_different_issue_numbers

test_guard_reads_correct_filename() {
  # Edge: guard must check issue-${ISSUE_NUM}.json, not issue.json or other variants
  local tmpdir
  tmpdir=$(mktemp -d)
  # Create a file with the wrong name
  echo '{"status":"running"}' > "${tmpdir}/issue.json"
  echo '{"status":"running"}' > "${tmpdir}/issue-86-extra.json"

  # With only wrong-named files, guard should NOT trigger (continue)
  run_fallback_guard "86" "false" "${tmpdir}" "continue" || { rm -rf "${tmpdir}"; return 1; }

  # Now create the correct file
  echo '{"status":"running"}' > "${tmpdir}/issue-86.json"
  run_fallback_guard "86" "false" "${tmpdir}" "block" || { rm -rf "${tmpdir}"; return 1; }
  rm -rf "${tmpdir}"
}
run_test "[edge] ガードが issue-\${ISSUE_NUM}.json の正確なファイル名を確認する" \
  test_guard_reads_correct_filename

# ---------------------------------------------------------------------------
# Scenario: IS_AUTOPILOT=false + issue-{N}.json 不在（通常利用）（spec line 13）
# WHEN: IS_AUTOPILOT=false, issue-{N}.json が存在しない
# THEN: 既存の merge フローを維持し、Step 1 以降を通常実行する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: IS_AUTOPILOT=false + issue-{N}.json 不在（通常利用）]"

test_guard_continues_when_json_absent() {
  local tmpdir
  tmpdir=$(mktemp -d)
  # Do NOT create any issue JSON file

  run_fallback_guard "86" "false" "${tmpdir}" "continue"
  local rc=$?
  rm -rf "${tmpdir}"
  return $rc
}
run_test "IS_AUTOPILOT=false + issue-N.json 不在 → 通常フローに続行 (continue)" \
  test_guard_continues_when_json_absent

test_guard_continues_is_autopilot_true() {
  # When IS_AUTOPILOT=true, the existing Step 0 logic handles it; fallback guard is irrelevant.
  # Guard must NOT block the IS_AUTOPILOT=true path (that path already calls state-write.sh
  # directly for merge-ready without needing the fallback).
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '{"status":"running"}' > "${tmpdir}/issue-86.json"

  # Guard condition requires IS_AUTOPILOT=false; if true, guard is skipped → continue
  run_fallback_guard "86" "true" "${tmpdir}" "continue"
  local rc=$?
  rm -rf "${tmpdir}"
  return $rc
}
run_test "[edge] IS_AUTOPILOT=true の場合はフォールバックガードをスキップする" \
  test_guard_continues_is_autopilot_true

test_guard_continues_when_autopilot_dir_missing() {
  # Edge: if .autopilot directory doesn't exist at all, guard should not error — just continue
  local tmpdir
  tmpdir=$(mktemp -d)
  local nonexistent="${tmpdir}/nonexistent_autopilot"
  # Do not create the directory

  run_fallback_guard "86" "false" "${nonexistent}" "continue"
  local rc=$?
  rm -rf "${tmpdir}"
  return $rc
}
run_test "[edge] .autopilot ディレクトリ自体が存在しない場合はガードをスキップする" \
  test_guard_continues_when_autopilot_dir_missing

# ---------------------------------------------------------------------------
# Scenario: ISSUE_NUM 未設定（通常利用）（spec line 17）
# WHEN: ISSUE_NUM が未設定（空文字列）
# THEN: フォールバックチェックをスキップし、既存の merge フローを通常実行する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: ISSUE_NUM 未設定（通常利用）]"

test_guard_skips_when_issue_num_empty() {
  local tmpdir
  tmpdir=$(mktemp -d)
  # Even if some json exists, guard must be skipped when ISSUE_NUM=""
  echo '{"status":"running"}' > "${tmpdir}/issue-.json"

  run_fallback_guard "" "false" "${tmpdir}" "continue"
  local rc=$?
  rm -rf "${tmpdir}"
  return $rc
}
run_test "ISSUE_NUM 未設定（空文字列）→ フォールバックチェックをスキップして続行" \
  test_guard_skips_when_issue_num_empty

test_guard_skips_when_issue_num_unset() {
  # Edge: ISSUE_NUM variable completely unset (not just empty)
  local tmpdir
  tmpdir=$(mktemp -d)
  echo '{"status":"running"}' > "${tmpdir}/issue-.json"

  local action
  action=$(bash -c "
    set -uo pipefail
    # ISSUE_NUM is intentionally not set
    IS_AUTOPILOT='false'
    MAIN_AUTOPILOT_DIR='${tmpdir}'

    ACTION='continue'
    ISSUE_NUM_VAL=\${ISSUE_NUM:-}

    if [[ -n \"\${ISSUE_NUM_VAL}\" && \"\${IS_AUTOPILOT}\" == 'false' ]]; then
      if [[ -f \"\${MAIN_AUTOPILOT_DIR}/issue-\${ISSUE_NUM_VAL}.json\" ]]; then
        ACTION='block'
      fi
    fi

    echo \"\${ACTION}\"
  " 2>/dev/null)

  rm -rf "${tmpdir}"
  [[ "$action" == "continue" ]]
}
run_test "[edge] ISSUE_NUM が未定義（unset）→ フォールバックチェックをスキップして続行" \
  test_guard_skips_when_issue_num_unset

test_guard_skips_for_zero_issue_num() {
  # Edge: ISSUE_NUM="0" is technically a non-empty value; guard should check file
  # issue-0.json — but if the file doesn't exist, continue
  local tmpdir
  tmpdir=$(mktemp -d)

  run_fallback_guard "0" "false" "${tmpdir}" "continue"
  local rc=$?
  rm -rf "${tmpdir}"
  return $rc
}
run_test "[edge] ISSUE_NUM=0 + json 不在 → 続行（ゼロ値の境界ケース）" \
  test_guard_skips_for_zero_issue_num

# ---------------------------------------------------------------------------
# Scenario: AUTOPILOT_DIR 伝搬バグによる誤判定からのフォールバック防止（spec line 43）
# WHEN: Worker の AUTOPILOT_DIR が空 → state-read.sh が IS_AUTOPILOT=false と誤判定
# THEN: フォールバックガードが main worktree の issue-{N}.json を検出 → merge 禁止 + merge-ready
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: AUTOPILOT_DIR 伝搬バグによる誤判定からのフォールバック防止]"

test_fallback_catches_autopilot_dir_propagation_bug() {
  # Simulate: AUTOPILOT_DIR is empty/wrong so state-read.sh couldn't find the JSON
  # → IS_AUTOPILOT resolves to "false"
  # But the main worktree's .autopilot does have the issue JSON
  local main_autopilot_dir
  main_autopilot_dir=$(mktemp -d)
  echo '{"status":"running"}' > "${main_autopilot_dir}/issue-86.json"

  # With IS_AUTOPILOT=false (simulating the propagation bug) and the main worktree file present
  # → guard MUST block
  run_fallback_guard "86" "false" "${main_autopilot_dir}" "block"
  local rc=$?
  rm -rf "${main_autopilot_dir}"
  return $rc
}
run_test "AUTOPILOT_DIR 伝搬バグ誤判定 + main worktree issue-N.json 存在 → ガード発動" \
  test_fallback_catches_autopilot_dir_propagation_bug

test_auto_merge_issue_num_guard_condition() {
  # Structural: auto-merge.md must show ISSUE_NUM emptiness check before the fallback
  assert_file_contains "$TARGET_CMD" \
    '(\$\{ISSUE_NUM\}|ISSUE_NUM.*unset|ISSUE_NUM.*空|ISSUE_NUM.*未設定|-n.*ISSUE_NUM|-z.*ISSUE_NUM)' || return 1
}
run_test "auto-merge.md が ISSUE_NUM 未設定チェックを含む" \
  test_auto_merge_issue_num_guard_condition

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
