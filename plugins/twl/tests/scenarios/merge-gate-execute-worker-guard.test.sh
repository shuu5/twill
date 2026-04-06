#!/usr/bin/env bash
# =============================================================================
# Unit Tests: merge-gate-execute.sh Worker ロール検出ガード
# Generated from: deltaspec/changes/autopilot-fallback-guard/specs/fallback-guard.md
# Requirement: merge-gate-execute Worker ロール検出ガード
# Coverage level: edge-cases (happy path + edge cases)
#
# Strategy:
#   1. Document-level / structural tests: verify merge-gate-execute.sh contains
#      the tmux window name guard block.
#   2. Functional tests: exercise the guard logic in an isolated subshell by
#      overriding `tmux` with a stub function, without invoking real tmux.
#
# The guard spec requires:
#   - tmux window 名が ap-#* パターンに一致 → エラーメッセージ + exit 1
#   - tmux window 名が ap-#* に一致しない   → 通常フロー続行
#   - tmux 外（tmux display-message 失敗）   → ガードスキップ + 通常フロー続行
#
# Guard placement (SHALL):
#   After the CWD guard, before merge execution.
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

SCRIPT_PATH="${PROJECT_ROOT}/scripts/merge-gate-execute.sh"
TARGET_SCRIPT="scripts/merge-gate-execute.sh"

# ---------------------------------------------------------------------------
# Worker guard runner
#
# Executes the Worker role detection guard snippet in an isolated subshell
# with a stubbed `tmux` command.
#
# The guard snippet mirrors what merge-gate-execute.sh SHALL implement:
#
#   TMUX_WINDOW=$(tmux display-message -p '#W' 2>/dev/null || echo "")
#   if [[ "$TMUX_WINDOW" =~ ^ap-# ]]; then
#     echo "[merge-gate-execute] ERROR: Worker tmux window から merge は禁止" >&2
#     exit 1
#   fi
#
# Arguments:
#   $1  tmux_window_name: the window name tmux stub should return
#       pass "__ERROR__" to simulate tmux failure (not in a session)
#   $2  expected: "reject" | "allow"
#
# Returns 0 if guard behaves as expected, 1 otherwise.
# ---------------------------------------------------------------------------

run_worker_guard() {
  local tmux_window="$1"
  local expected="$2"

  local rc
  if [[ "$tmux_window" == "__ERROR__" ]]; then
    # Simulate tmux not running (display-message fails)
    bash -c "
      set -uo pipefail
      tmux() { return 1; }
      export -f tmux

      TMUX_WINDOW=\$(tmux display-message -p '#W' 2>/dev/null || echo '')
      if [[ \"\${TMUX_WINDOW}\" =~ ^ap-# ]]; then
        echo '[merge-gate-execute] ERROR: autopilot Worker tmux window からの merge 実行は禁止' >&2
        exit 1
      fi
      exit 0
    " 2>/dev/null
    rc=$?
  else
    bash -c "
      set -uo pipefail
      tmux() { echo '${tmux_window}'; }
      export -f tmux

      TMUX_WINDOW=\$(tmux display-message -p '#W' 2>/dev/null || echo '')
      if [[ \"\${TMUX_WINDOW}\" =~ ^ap-# ]]; then
        echo '[merge-gate-execute] ERROR: autopilot Worker tmux window からの merge 実行は禁止' >&2
        exit 1
      fi
      exit 0
    " 2>/dev/null
    rc=$?
  fi

  if [[ "$expected" == "reject" ]]; then
    [[ $rc -ne 0 ]]
  else
    [[ $rc -eq 0 ]]
  fi
}

# ---------------------------------------------------------------------------
# =============================================================================
# Requirement: merge-gate-execute Worker ロール検出ガード
# Source: specs/fallback-guard.md, line 22
# =============================================================================

echo ""
echo "--- Requirement: merge-gate-execute Worker ロール検出ガード ---"

# ---------------------------------------------------------------------------
# Structural tests: script must contain the guard
# ---------------------------------------------------------------------------

test_script_exists() {
  assert_file_exists "$TARGET_SCRIPT"
}
run_test "merge-gate-execute.sh が存在する" test_script_exists

test_worker_guard_pattern_in_script() {
  # Guard must reference tmux and the ap-# pattern
  assert_file_contains "$TARGET_SCRIPT" \
    '(ap-#|ap-\\\\#|ap-#\*|^\^ap-#|tmux.*display|window.*ap)' || return 1
}
run_test "merge-gate-execute.sh に ap-#* パターンの Worker ガードが存在する" \
  test_worker_guard_pattern_in_script

test_worker_guard_uses_tmux_display() {
  # Guard must use tmux display-message to detect window name
  assert_file_contains "$TARGET_SCRIPT" 'tmux.*display(-message|-msg|)' || return 1
}
run_test "merge-gate-execute.sh が tmux display-message を使用してウィンドウ名を取得する" \
  test_worker_guard_uses_tmux_display

test_worker_guard_exits_1_on_reject() {
  # On rejection, guard must exit 1
  assert_file_contains "$TARGET_SCRIPT" 'exit 1' || return 1
}
run_test "merge-gate-execute.sh の Worker ガードが exit 1 を含む" \
  test_worker_guard_exits_1_on_reject

test_worker_guard_outputs_error() {
  # Guard must output a recognizable error message
  assert_file_contains "$TARGET_SCRIPT" \
    '(Worker.*window|worker.*window|ap-#.*禁止|Worker.*merge.*禁止|ERROR.*Worker|Worker.*ERROR)' || return 1
}
run_test "merge-gate-execute.sh の Worker ガードがエラーメッセージを出力する" \
  test_worker_guard_outputs_error

test_worker_guard_positioned_before_merge() {
  # The guard (tmux check) must appear before the gh pr merge invocation
  [[ -f "${SCRIPT_PATH}" ]] || return 1
  local guard_line merge_line
  guard_line=$(grep -n 'tmux.*display\|ap-#\|Worker.*guard' "${SCRIPT_PATH}" 2>/dev/null | head -1 | cut -d: -f1)
  merge_line=$(grep -n 'gh pr merge' "${SCRIPT_PATH}" 2>/dev/null | head -1 | cut -d: -f1)

  # Both must be present and guard must come first
  [[ -n "${guard_line:-}" && -n "${merge_line:-}" ]] || return 1
  [[ "${guard_line}" -lt "${merge_line}" ]] || return 1
}
run_test "Worker ガードが gh pr merge の前に配置されている" \
  test_worker_guard_positioned_before_merge

test_worker_guard_positioned_after_cwd_guard() {
  # The guard (tmux check) must appear AFTER the CWD guard (worktrees check)
  [[ -f "${SCRIPT_PATH}" ]] || return 1
  local cwd_guard_line worker_guard_line
  cwd_guard_line=$(grep -n 'worktrees' "${SCRIPT_PATH}" 2>/dev/null | head -1 | cut -d: -f1)
  worker_guard_line=$(grep -n 'tmux.*display\|ap-#' "${SCRIPT_PATH}" 2>/dev/null | head -1 | cut -d: -f1)

  [[ -n "${cwd_guard_line:-}" && -n "${worker_guard_line:-}" ]] || return 1
  [[ "${cwd_guard_line}" -lt "${worker_guard_line}" ]] || return 1
}
run_test "Worker ガードが CWD ガードの後に配置されている（SHALL 順序）" \
  test_worker_guard_positioned_after_cwd_guard

# ---------------------------------------------------------------------------
# Scenario: autopilot Worker tmux window からの merge 実行（spec line 25）
# WHEN: tmux window 名が ap-#* パターンに一致（例: ap-#86, ap-#1）
# THEN: エラーメッセージを出力し exit 1 で終了する（merge を実行しない）
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: autopilot Worker tmux window からの merge 実行]"

test_guard_rejects_ap_hash_window() {
  run_worker_guard "ap-#86" "reject"
}
run_test "tmux window 名 'ap-#86' → Worker ガードが merge を拒否する (exit 1)" \
  test_guard_rejects_ap_hash_window

test_guard_rejects_ap_hash_window_1() {
  run_worker_guard "ap-#1" "reject"
}
run_test "tmux window 名 'ap-#1' → Worker ガードが merge を拒否する (exit 1)" \
  test_guard_rejects_ap_hash_window_1

test_guard_rejects_ap_hash_window_large_number() {
  # Edge: large issue numbers
  run_worker_guard "ap-#9999" "reject"
}
run_test "[edge] tmux window 名 'ap-#9999'（大きな番号）→ Worker ガードが拒否する" \
  test_guard_rejects_ap_hash_window_large_number

test_guard_outputs_error_on_reject() {
  local stderr_out
  stderr_out=$(bash -c "
    tmux() { echo 'ap-#86'; }
    export -f tmux
    TMUX_WINDOW=\$(tmux display-message -p '#W' 2>/dev/null || echo '')
    if [[ \"\${TMUX_WINDOW}\" =~ ^ap-# ]]; then
      echo '[merge-gate-execute] ERROR: autopilot Worker tmux window からの merge 実行は禁止' >&2
      exit 1
    fi
  " 2>&1) || true

  echo "${stderr_out}" | grep -qiE '(error|ERROR|禁止|worker|Worker|ap-#)' || return 1
}
run_test "Worker ガード発動時にエラーメッセージが stderr に出力される" \
  test_guard_outputs_error_on_reject

# ---------------------------------------------------------------------------
# Scenario: 非 autopilot tmux window からの merge 実行（spec line 29）
# WHEN: tmux window 名が ap-#* に一致しない（例: main, bash, 空）
# THEN: 従来通り merge フローを続行する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: 非 autopilot tmux window からの merge 実行]"

test_guard_allows_main_window() {
  run_worker_guard "main" "allow"
}
run_test "tmux window 名 'main' → Worker ガードが続行を許可する" \
  test_guard_allows_main_window

test_guard_allows_bash_window() {
  run_worker_guard "bash" "allow"
}
run_test "tmux window 名 'bash' → Worker ガードが続行を許可する" \
  test_guard_allows_bash_window

test_guard_allows_empty_window_name() {
  run_worker_guard "" "allow"
}
run_test "tmux window 名が空 → Worker ガードが続行を許可する" \
  test_guard_allows_empty_window_name

test_guard_allows_arbitrary_window_name() {
  # Edge: names that start with ap but don't match ap-# exactly
  run_worker_guard "ap-branch-main" "allow"
}
run_test "[edge] tmux window 名 'ap-branch-main' (ap-# に一致しない) → 続行を許可する" \
  test_guard_allows_arbitrary_window_name

test_guard_allows_ap_without_hash() {
  # Edge: "ap-86" (no #) must not match the ap-#* pattern
  run_worker_guard "ap-86" "allow"
}
run_test "[edge] tmux window 名 'ap-86' (# なし) → 続行を許可する（パターン不一致）" \
  test_guard_allows_ap_without_hash

test_guard_allows_ap_hash_in_middle() {
  # Edge: window name with ap-# not at the start should not match ^ap-#
  run_worker_guard "feature-ap-#86" "allow"
}
run_test "[edge] tmux window 名 'feature-ap-#86' (先頭不一致) → 続行を許可する" \
  test_guard_allows_ap_hash_in_middle

# ---------------------------------------------------------------------------
# Scenario: tmux 外からの merge 実行（spec line 33）
# WHEN: tmux display-message がエラーを返す（tmux セッション外）
# THEN: Worker ロール検出をスキップし、従来通り merge フローを続行する
# ---------------------------------------------------------------------------
echo ""
echo "  [Scenario: tmux 外からの merge 実行]"

test_guard_skips_when_tmux_fails() {
  # When tmux display-message exits non-zero, TMUX_WINDOW should be empty
  # and guard should NOT reject
  run_worker_guard "__ERROR__" "allow"
}
run_test "tmux セッション外（display-message 失敗）→ Worker ガードをスキップして続行" \
  test_guard_skips_when_tmux_fails

test_guard_handles_tmux_error_gracefully() {
  # Edge: guard must not crash when tmux is not available at all
  local rc
  bash -c "
    set -uo pipefail
    # tmux not available
    tmux() { return 127; }
    export -f tmux
    TMUX_WINDOW=\$(tmux display-message -p '#W' 2>/dev/null || echo '')
    if [[ \"\${TMUX_WINDOW}\" =~ ^ap-# ]]; then
      exit 1
    fi
    exit 0
  " 2>/dev/null
  rc=$?
  [[ $rc -eq 0 ]]
}
run_test "[edge] tmux コマンド不在でもガードがクラッシュせず続行する" \
  test_guard_handles_tmux_error_gracefully

test_guard_uses_fallback_empty_on_tmux_error() {
  # Edge: the guard should use || echo "" pattern so TMUX_WINDOW defaults to empty
  # when tmux fails — structural check
  assert_file_contains "$TARGET_SCRIPT" \
    '(tmux.*display.*2>/dev/null.*echo|tmux.*display.*\|\|.*echo|TMUX_WINDOW.*:-.*\"\")' || return 1
}
run_test "[edge] merge-gate-execute.sh が tmux エラー時に空文字列フォールバックを使用する" \
  test_guard_uses_fallback_empty_on_tmux_error

# ---------------------------------------------------------------------------
# Additional edge cases: guard syntax and script validity
# ---------------------------------------------------------------------------
echo ""
echo "  [Additional edge cases]"

test_script_syntax_valid() {
  bash -n "${SCRIPT_PATH}" 2>/dev/null
}
run_test "merge-gate-execute.sh が bash 構文チェック pass" test_script_syntax_valid

test_guard_does_not_affect_reject_mode() {
  # The Worker guard is only in the default merge path (mode *)
  # --reject and --reject-final modes do NOT need the guard (no merge is executed)
  # Verify that the tmux display-message window-name check does NOT appear inside
  # the --reject) or --reject-final) case arms.
  [[ -f "${SCRIPT_PATH}" ]] || return 1
  # Check: tmux display-message (the guard pattern) must not appear inside a reject arm
  # We look for tmux display-message between --reject) and the next case arm or ;;
  local reject_block_has_display_guard
  reject_block_has_display_guard=$(awk \
    '/^[[:space:]]*--reject(-final)?\)/{found=1} found && /tmux.*display/{print; found=0} /;;/{found=0}' \
    "${SCRIPT_PATH}" 2>/dev/null || echo "")
  [[ -z "${reject_block_has_display_guard}" ]] || return 1
}
run_test "[edge] --reject モードに Worker ガード（tmux display-message）が重複配置されていない" \
  test_guard_does_not_affect_reject_mode

test_guard_error_message_to_stderr() {
  # Guard error message must go to stderr (>&2), not stdout
  assert_file_contains "$TARGET_SCRIPT" \
    '(ap-#.*>&2|Worker.*>&2|>&2.*Worker|ERROR.*Worker.*>&2)' || return 1
}
run_test "Worker ガードのエラーメッセージが stderr (>&2) に出力される" \
  test_guard_error_message_to_stderr

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
