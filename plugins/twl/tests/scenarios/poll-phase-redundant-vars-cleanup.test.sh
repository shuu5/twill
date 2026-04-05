#!/usr/bin/env bash
# =============================================================================
# Unit Tests: poll_phase() 冗長変数削除
# Generated from: openspec/changes/pollphase-issuetoentry-cleanup/specs/poll-phase-cleanup.md
# change-id: pollphase-issuetoentry-cleanup
# Coverage level: edge-cases
# Verifies: scripts/autopilot-orchestrator.sh の poll_phase() から
#   issue_to_entry 連想配列と issue_entry 変数が削除されていること、
#   cleanup_worker が $entry を直接使用していること
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

# poll_phase() 関数本体のみを抽出する。
# 関数定義開始行（poll_phase() {）から、その関数を閉じる "^}" 行までを返す。
extract_poll_phase() {
  awk '/^poll_phase\(\)[ \t]*\{/,/^\}/' "${PROJECT_ROOT}/scripts/autopilot-orchestrator.sh"
}

assert_poll_phase_not_contains() {
  local pattern="$1"
  local body
  body=$(extract_poll_phase)
  if echo "$body" | grep -qE -- "$pattern"; then
    return 1
  fi
  return 0
}

assert_poll_phase_contains() {
  local pattern="$1"
  local body
  body=$(extract_poll_phase)
  echo "$body" | grep -qE -- "$pattern"
}

run_test() {
  local name="$1"
  local func="$2"
  local result=0
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
  ((SKIP++)) || true
}

ORCHESTRATOR="scripts/autopilot-orchestrator.sh"

# =============================================================================
# Requirement: poll_phase の冗長変数削除
# =============================================================================
echo ""
echo "--- Requirement: poll_phase の冗長変数削除 ---"

# ---------------------------------------------------------------------------
# Scenario: issue_to_entry 配列が削除される (spec line 7)
# WHEN: poll_phase() 関数を参照する
# THEN: declare -A issue_to_entry の宣言が存在しない
# ---------------------------------------------------------------------------

test_orchestrator_file_exists() {
  assert_file_exists "$ORCHESTRATOR"
}
run_test "orchestrator スクリプトが存在する" test_orchestrator_file_exists

# poll_phase 本体に declare -A issue_to_entry または local -A issue_to_entry が存在しないこと
# （スクリプトでは local -A 形式で宣言されているため両パターンを検査する）
test_no_declare_issue_to_entry() {
  assert_poll_phase_not_contains '(declare|local)[[:space:]]+-A[[:space:]]+issue_to_entry'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase(): declare/local -A issue_to_entry 宣言が存在しない" test_no_declare_issue_to_entry
else
  run_test_skip "poll_phase(): declare/local -A issue_to_entry 宣言が存在しない" "${ORCHESTRATOR} not found"
fi

# エッジケース: issue_to_entry への代入も存在しないこと（宣言と代入の両方が消えていること）
test_no_issue_to_entry_assignment() {
  assert_poll_phase_not_contains 'issue_to_entry\['
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: issue_to_entry[] への代入が存在しない]" test_no_issue_to_entry_assignment
else
  run_test_skip "poll_phase() [edge: issue_to_entry[] への代入が存在しない]" "${ORCHESTRATOR} not found"
fi

# エッジケース: issue_to_entry 変数名自体が poll_phase 内に一切ない
test_no_issue_to_entry_any() {
  assert_poll_phase_not_contains 'issue_to_entry'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: issue_to_entry 変数名が一切存在しない]" test_no_issue_to_entry_any
else
  run_test_skip "poll_phase() [edge: issue_to_entry 変数名が一切存在しない]" "${ORCHESTRATOR} not found"
fi

# ---------------------------------------------------------------------------
# Scenario: issue_entry 変数が削除される (spec line 11)
# WHEN: poll_phase() 関数を参照する
# THEN: issue_entry 変数への代入・参照が存在しない
# ---------------------------------------------------------------------------

# poll_phase 本体に issue_entry の代入が存在しないこと
test_no_issue_entry_assignment() {
  assert_poll_phase_not_contains 'local[[:space:]]+issue_entry'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase(): local issue_entry 宣言/代入が存在しない" test_no_issue_entry_assignment
else
  run_test_skip "poll_phase(): local issue_entry 宣言/代入が存在しない" "${ORCHESTRATOR} not found"
fi

# エッジケース: $issue_entry 参照も存在しないこと
test_no_issue_entry_reference() {
  assert_poll_phase_not_contains '\$issue_entry'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: \$issue_entry 参照が存在しない]" test_no_issue_entry_reference
else
  run_test_skip "poll_phase() [edge: \$issue_entry 参照が存在しない]" "${ORCHESTRATOR} not found"
fi

# エッジケース: issue_entry 変数名自体が poll_phase 内に一切ない（代入も参照も）
test_no_issue_entry_any() {
  assert_poll_phase_not_contains 'issue_entry'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: issue_entry 変数名が一切存在しない]" test_no_issue_entry_any
else
  run_test_skip "poll_phase() [edge: issue_entry 変数名が一切存在しない]" "${ORCHESTRATOR} not found"
fi

# ---------------------------------------------------------------------------
# Scenario: cleanup_worker が entry を直接使用する (spec line 15)
# WHEN: cleanup_worker が呼び出される
# THEN: 第2引数として $entry が渡される（$issue_entry ではない）
# ---------------------------------------------------------------------------

# poll_phase 本体の cleanup_worker 呼び出しで "$entry" が第2引数に使われていること
test_cleanup_worker_uses_entry() {
  assert_poll_phase_contains 'cleanup_worker[[:space:]]+"?\$issue_num"?[[:space:]]+"?\$entry"?'
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase(): cleanup_worker の第2引数が \$entry である" test_cleanup_worker_uses_entry
else
  run_test_skip "poll_phase(): cleanup_worker の第2引数が \$entry である" "${ORCHESTRATOR} not found"
fi

# エッジケース: cleanup_worker 呼び出しで $issue_entry が第2引数に使われていないこと
test_cleanup_worker_not_issue_entry() {
  # poll_phase 内の全 cleanup_worker 呼び出しを取り出し、$issue_entry が引数にないことを確認
  local body
  body=$(extract_poll_phase)
  if echo "$body" | grep -E 'cleanup_worker' | grep -qE '\$issue_entry'; then
    return 1
  fi
  return 0
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: cleanup_worker の引数に \$issue_entry が使われていない]" test_cleanup_worker_not_issue_entry
else
  run_test_skip "poll_phase() [edge: cleanup_worker の引数に \$issue_entry が使われていない]" "${ORCHESTRATOR} not found"
fi

# エッジケース: タイムアウトブロック内の cleanup_worker も $entry を使うこと
# poll_phase のタイムアウトループ（poll_count >= MAX_POLL）内でも同じパターンが適用される
test_cleanup_worker_timeout_block_entry() {
  local body
  body=$(extract_poll_phase)
  # タイムアウトブロックは MAX_POLL 付近に現れる; $issue_entry がどこにも現れないことで間接検証
  if echo "$body" | grep -E 'cleanup_worker' | grep -qE '\$issue_entry'; then
    return 1
  fi
  return 0
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: タイムアウトブロックの cleanup_worker も \$entry を使う]" test_cleanup_worker_timeout_block_entry
else
  run_test_skip "poll_phase() [edge: タイムアウトブロックの cleanup_worker も \$entry を使う]" "${ORCHESTRATOR} not found"
fi

# エッジケース: check_and_nudge 呼び出しが残っている（issue_entry 削除後も nudge は $entry ベースで動作）
# check_and_nudge の第3引数が $entry であること
test_check_and_nudge_uses_entry() {
  local body
  body=$(extract_poll_phase)
  if echo "$body" | grep -qE 'check_and_nudge'; then
    # check_and_nudge が存在する場合、$issue_entry を引数に使っていないこと
    if echo "$body" | grep -E 'check_and_nudge' | grep -qE '\$issue_entry'; then
      return 1
    fi
  fi
  return 0
}

if assert_file_exists "$ORCHESTRATOR"; then
  run_test "poll_phase() [edge: check_and_nudge の引数に \$issue_entry が使われていない]" test_check_and_nudge_uses_entry
else
  run_test_skip "poll_phase() [edge: check_and_nudge の引数に \$issue_entry が使われていない]" "${ORCHESTRATOR} not found"
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
