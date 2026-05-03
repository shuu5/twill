#!/usr/bin/env bash
# =============================================================================
# AC Verification Tests: Issue #1221
# reference-migration.test.sh pre-existing failures
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PASS=0
FAIL=0
ERRORS=()

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

# --- AC-1: 対象 file/script の修正実施 ---
# RED: reference-migration.test.sh に誤ったサブコマンド構文 "twl validate" が残っている間は FAIL
test_ac1_wrong_subcommand_syntax_removed() {
  local test_file="${PROJECT_ROOT}/tests/scenarios/reference-migration.test.sh"
  [[ -f "$test_file" ]] || return 1
  # コメント行を除いて "twl validate" (without --) が残っていないことを確認
  if grep -v '^\s*#' "$test_file" | grep -q 'twl validate\b' 2>/dev/null; then
    echo "ERROR: 'twl validate' (wrong syntax, should be 'twl --validate') found in non-comment line" >&2
    return 1
  fi
  # コメント行を除いて "twl sync-docs --check" が残っていないことを確認
  if grep -v '^\s*#' "$test_file" | grep -q 'twl sync-docs --check' 2>/dev/null; then
    echo "ERROR: 'twl sync-docs --check' found in non-comment line (should be 'twl --check')" >&2
    return 1
  fi
  return 0
}
echo ""
echo "--- AC-1: 対象 file/script の修正実施 ---"
run_test "AC-1: reference-migration.test.sh に誤ったサブコマンド構文が残っていない" test_ac1_wrong_subcommand_syntax_removed

# --- AC-2: 該当 bats / pytest test の green 化 ---
# RED: reference-migration.test.sh が現在 4 failures を持つ間は FAIL
test_ac2_reference_migration_all_pass() {
  local test_file="${PROJECT_ROOT}/tests/scenarios/reference-migration.test.sh"
  [[ -f "$test_file" ]] || return 1
  local output exit_code
  output=$(cd "${PROJECT_ROOT}" && bash "$test_file" 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" | grep "FAIL:" >&2
    echo "reference-migration.test.sh exited with $exit_code" >&2
    return 1
  fi
  return 0
}
echo ""
echo "--- AC-2: 該当テストの green 化 ---"
run_test "AC-2: reference-migration.test.sh が 0 failures で通過" test_ac2_reference_migration_all_pass

# --- AC-3: 修正後 twl validate で WARNING 解消確認 ---
# RED: twl がサブコマンド "validate" を認識しない間（または --validate が失敗する間）は FAIL
test_ac3_twl_validate_passes() {
  if ! command -v twl &>/dev/null; then
    echo "ERROR: twl command not found" >&2
    return 1
  fi
  local output exit_code
  output=$(cd "${PROJECT_ROOT}" && twl --validate 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  # validate 出力に Violations があれば失敗
  if echo "$output" | grep -q 'Violations: [^0]'; then
    echo "Type constraint violations found:" >&2
    echo "$output" >&2
    return 1
  fi
  return 0
}
echo ""
echo "--- AC-3: twl --validate で WARNING 解消 ---"
run_test "AC-3: twl --validate がエラー・Violations なしで通過" test_ac3_twl_validate_passes

# --- AC-4: regression test で修正の persistence 確認 ---
# RED: deps.yaml の refs path 整合性が修正されるまで FAIL
test_ac4_deps_refs_path_consistency() {
  local deps_yaml="${PROJECT_ROOT}/deps.yaml"
  [[ -f "$deps_yaml" ]] || return 1
  local errors
  errors=$(python3 -c "
import yaml, sys
with open('${deps_yaml}') as f:
    data = yaml.safe_load(f)
refs = data.get('refs', {})
errors = []
for name, entry in refs.items():
    if not isinstance(entry, dict):
        continue
    path = entry.get('path', '')
    # 許容パターン: refs/<name>.md OR skills/**/refs/<name>.md
    expected_flat = f'refs/{name}.md'
    import re
    if path != expected_flat and not re.match(r'^skills/[^/]+/refs/' + re.escape(name) + r'\.md\$', path):
        errors.append(f'{name}: path={path}, expected refs/{name}.md or skills/*/refs/{name}.md')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>&1)
  local ec=$?
  if [[ $ec -ne 0 ]]; then
    echo "$errors" >&2
    return 1
  fi
  return 0
}
test_ac4_reference_migration_idempotent() {
  local test_file="${PROJECT_ROOT}/tests/scenarios/reference-migration.test.sh"
  [[ -f "$test_file" ]] || return 1
  # 2回実行してどちらも 0 failures
  local exit1 exit2
  cd "${PROJECT_ROOT}" && bash "$test_file" &>/dev/null; exit1=$?
  cd "${PROJECT_ROOT}" && bash "$test_file" &>/dev/null; exit2=$?
  if [[ $exit1 -ne 0 || $exit2 -ne 0 ]]; then
    echo "Test not idempotent: first=$exit1, second=$exit2" >&2
    return 1
  fi
  return 0
}
echo ""
echo "--- AC-4: regression test で persistence 確認 ---"
run_test "AC-4a: deps.yaml refs の path 整合性（refs/ or skills/*/refs/ パターン）" test_ac4_deps_refs_path_consistency
run_test "AC-4b: reference-migration.test.sh が 2 回連続で 0 failures（冪等性）" test_ac4_reference_migration_idempotent

# =============================================================================
echo ""
echo "==========================================="
echo "AC Results: ${PASS} passed, ${FAIL} failed"
echo "==========================================="
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed ACs:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
exit $FAIL
