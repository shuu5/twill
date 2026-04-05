#!/usr/bin/env bash
# =============================================================================
# Test Runner: Run bats tests and legacy scenario tests
# Usage: bash tests/run-tests.sh [--bats-only] [--scenarios-only]
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BATS_BIN="$SCRIPT_DIR/lib/bats-core/bin/bats"
EXIT_CODE=0

BATS_ONLY=false
SCENARIOS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --bats-only) BATS_ONLY=true ;;
    --scenarios-only) SCENARIOS_ONLY=true ;;
  esac
done

echo "============================================="
echo "loom-plugin-dev Test Suite"
echo "============================================="

# -----------------------------------------------
# 1. bats tests
# -----------------------------------------------
BATS_PASS=0
BATS_FAIL=0

if [[ "$SCENARIOS_ONLY" != "true" ]]; then
  echo ""
  echo ">>> [1/2] bats tests"
  echo "---------------------------------------------"

  if [[ ! -x "$BATS_BIN" ]]; then
    echo "ERROR: bats not found at $BATS_BIN"
    echo "Run: git submodule update --init --recursive"
    EXIT_CODE=1
  else
    bats_files=()
    while IFS= read -r -d '' f; do
      bats_files+=("$f")
    done < <(find "$SCRIPT_DIR/bats" -name "*.bats" -print0 2>/dev/null | sort -z)

    if [[ ${#bats_files[@]} -eq 0 ]]; then
      echo "No .bats files found in tests/bats/"
    else
      echo "Found ${#bats_files[@]} bats test files"
      echo ""

      set +e
      "$BATS_BIN" --tap "${bats_files[@]}" 2>&1
      bats_exit=$?
      set -e

      if [[ $bats_exit -ne 0 ]]; then
        BATS_FAIL=1
        EXIT_CODE=1
      else
        BATS_PASS=1
      fi
    fi
  fi
fi

# -----------------------------------------------
# 2. Legacy scenario tests
# -----------------------------------------------
SCENARIO_TOTAL_PASS=0
SCENARIO_TOTAL_FAIL=0
SCENARIO_TOTAL_SKIP=0

if [[ "$BATS_ONLY" != "true" ]]; then
  echo ""
  echo ">>> [2/2] Scenario tests (legacy)"
  echo "---------------------------------------------"

  scenario_files=()
  while IFS= read -r -d '' f; do
    scenario_files+=("$f")
  done < <(find "$SCRIPT_DIR/scenarios" -name "*.test.sh" -print0 2>/dev/null | sort -z)

  if [[ ${#scenario_files[@]} -eq 0 ]]; then
    echo "No .test.sh files found in tests/scenarios/"
  else
    echo "Found ${#scenario_files[@]} scenario test files"

    for test_file in "${scenario_files[@]}"; do
      echo ""
      echo ">>> Running: $(basename "$test_file")"
      echo "---------------------------------------------"

      set +e
      output=$(bash "$test_file" 2>&1)
      test_exit=$?
      set -e

      echo "$output"

      if results_line=$(echo "$output" | grep -oP 'Results: \K[0-9]+ passed, [0-9]+ failed, [0-9]+ skipped'); then
        pass=$(echo "$results_line" | grep -oP '^[0-9]+')
        fail=$(echo "$results_line" | grep -oP '[0-9]+(?= failed)')
        skip=$(echo "$results_line" | grep -oP '[0-9]+(?= skipped)')
        SCENARIO_TOTAL_PASS=$((SCENARIO_TOTAL_PASS + pass))
        SCENARIO_TOTAL_FAIL=$((SCENARIO_TOTAL_FAIL + fail))
        SCENARIO_TOTAL_SKIP=$((SCENARIO_TOTAL_SKIP + skip))
      fi

      if [[ $test_exit -ne 0 ]]; then
        EXIT_CODE=1
      fi
    done
  fi
fi

# -----------------------------------------------
# Summary
# -----------------------------------------------
echo ""
echo "============================================="
echo "SUMMARY"
echo "============================================="

if [[ "$SCENARIOS_ONLY" != "true" ]]; then
  if [[ $BATS_FAIL -eq 0 && $BATS_PASS -eq 1 ]]; then
    echo "  bats:      PASS"
  elif [[ $BATS_FAIL -eq 1 ]]; then
    echo "  bats:      FAIL"
  else
    echo "  bats:      SKIP"
  fi
fi

if [[ "$BATS_ONLY" != "true" ]]; then
  echo "  scenarios: ${SCENARIO_TOTAL_PASS} passed, ${SCENARIO_TOTAL_FAIL} failed, ${SCENARIO_TOTAL_SKIP} skipped"
fi

echo "============================================="

exit $EXIT_CODE
