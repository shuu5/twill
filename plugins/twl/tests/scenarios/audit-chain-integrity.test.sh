#!/usr/bin/env bash
# =============================================================================
# Scenario: twl --audit --section 9 (Chain Integrity)
# Verifies that Layer 0 audit detects known chain integrity drift in this plugin.
# =============================================================================
set -uo pipefail
# Note: twl --audit exits 1 when CRITICAL findings exist; we want to inspect
# its output without that exit propagating through pipefail.

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TWL="$(cd "$PLUGIN_ROOT/../../cli/twl" && pwd)/twl"

PASS=0
FAIL=0
ERRORS=()

run_test() {
  local name="$1"; shift
  if "$@"; then
    PASS=$((PASS + 1))
    echo "  PASS: $name"
  else
    FAIL=$((FAIL + 1))
    ERRORS+=("$name")
    echo "  FAIL: $name"
  fi
}

# Run audit Section 9 from plugin root (exit code ignored: critical findings expected)
audit_section9_output() {
  ( cd "$PLUGIN_ROOT" && "$TWL" --audit --section 9 2>&1 ) || true
}

# 1. Section 9 header is emitted
test_section9_header() {
  audit_section9_output | grep -qF "## 9. Chain Integrity"
}

# 2. Known dead code (ac-verify) is detected as orphan_call
test_ac_verify_detected() {
  audit_section9_output | grep -qE "workflow-pr-verify→ac-verify.*orphan_call.*WARNING"
}

# 3. Known dispatch gaps (e.g., workflow-plugin-create→plugin-interview) are CRITICAL
test_dispatch_gap_critical() {
  audit_section9_output | grep -qE "dispatch_gap.*CRITICAL"
}

# 4. Summary table shows non-zero CRITICAL count
test_summary_present() {
  audit_section9_output | grep -qE "^\| CRITICAL\s*\|\s*[1-9]"
}

# 5. Section 9 only mode does not include other sections
test_section9_only() {
  local out
  out=$(audit_section9_output)
  ! echo "$out" | grep -qF "## 1. Controller" && \
  ! echo "$out" | grep -qF "## 8. Prompt"
}

run_test "section_9_header"        test_section9_header
run_test "ac_verify_detected"      test_ac_verify_detected
run_test "dispatch_gap_critical"   test_dispatch_gap_critical
run_test "summary_present"         test_summary_present
run_test "section_9_only_mode"     test_section9_only

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -gt 0 ]]; then
  echo "Failures: ${ERRORS[*]}"
  exit 1
fi
exit 0
