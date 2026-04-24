#!/usr/bin/env bash
# =============================================================================
# Test Runner: Run all document verification tests
# Usage: bash tests/run-all.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_SKIP=0
EXIT_CODE=0

echo "============================================="
echo "Document Verification Test Suite"
echo "Change: c-2d-autopilot-controller-autopilot"
echo "============================================="

for test_file in "${SCRIPT_DIR}"/scenarios/*.test.sh; do
  if [[ -f "$test_file" ]]; then
    echo ""
    echo ">>> Running: $(basename "$test_file")"
    echo "---------------------------------------------"

    set +e
    output=$(bash "$test_file" 2>&1)
    test_exit=$?
    set -e

    echo "$output"

    # Parse results from output
    if results_line=$(echo "$output" | grep -oP 'Results: \K[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped'); then
      pass=$(echo "$results_line" | grep -oP '^[0-9]+')
      fail=$(echo "$results_line" | grep -oP '[0-9]+(?= failed)')
      skip=$(echo "$results_line" | grep -oP '[0-9]+(?= skipped)')
      TOTAL_PASS=$((TOTAL_PASS + pass))
      TOTAL_FAIL=$((TOTAL_FAIL + fail))
      TOTAL_SKIP=$((TOTAL_SKIP + skip))
    fi

    if [[ $test_exit -ne 0 ]]; then
      EXIT_CODE=1
    fi
  fi
done

# ---------------------------------------------------------------------------
# bats tests: plugins/twl/tests/bats/scripts/*.bats
# ---------------------------------------------------------------------------
BATS_DIR="${SCRIPT_DIR}/bats/scripts"
if [[ -d "$BATS_DIR" ]] && command -v bats &>/dev/null; then
  echo ""
  echo ">>> Running: bats scripts"
  echo "---------------------------------------------"

  set +e
  bats_output=$(bats "$BATS_DIR" 2>&1)
  bats_exit=$?
  set -e

  echo "$bats_output"

  bats_pass=$(echo "$bats_output" | grep -oP '^\d+(?= tests passed)' | head -1 || echo "0")
  bats_fail=$(echo "$bats_output" | grep -c '^not ok ' || echo "0")
  bats_ok=$(echo "$bats_output" | grep -c '^ok ' || echo "0")
  if [[ -z "$bats_pass" ]]; then
    bats_pass="$bats_ok"
  fi
  TOTAL_PASS=$((TOTAL_PASS + bats_pass))
  TOTAL_FAIL=$((TOTAL_FAIL + bats_fail))

  if [[ $bats_exit -ne 0 ]]; then
    EXIT_CODE=1
  fi
elif [[ -d "$BATS_DIR" ]]; then
  echo "WARN: bats not found in PATH — skipping bats tests in $BATS_DIR" >&2
fi

echo ""
echo "============================================="
echo "TOTAL: ${TOTAL_PASS} passed, ${TOTAL_FAIL} failed, ${TOTAL_SKIP} skipped"
echo "============================================="

exit $EXIT_CODE
