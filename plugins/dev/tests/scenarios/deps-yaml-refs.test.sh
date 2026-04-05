#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: deps-yaml-refs.md
# Generated from: openspec/changes/b-6-specialist-few-shot/specs/deps-yaml-refs.md
# Coverage level: edge-cases
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_get() {
  local file="$1"
  local expr="$2"
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = yaml.safe_load(f)
${expr}
" 2>/dev/null
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
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
  ((SKIP++))
}

DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: deps.yaml refs セクション
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml refs セクション ---"

# Scenario: refs セクションの存在 (line 12)
# WHEN: deps.yaml をパースする
# THEN: refs セクションが存在し、2 つのエントリが定義されている
test_refs_section_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', None)
if refs is None:
    sys.exit(1)
sys.exit(0)
"
}
run_test "refs セクションの存在" test_refs_section_exists

test_refs_section_two_entries() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
if not isinstance(refs, dict):
    sys.exit(1)
sys.exit(0 if len(refs) >= 2 else 1)
"
}
run_test "refs セクション - 2 つ以上のエントリ" test_refs_section_two_entries

test_refs_has_output_schema() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
found = any('specialist-output-schema' in str(k) for k in refs.keys())
sys.exit(0 if found else 1)
"
}
run_test "refs セクション - ref-specialist-output-schema エントリ" test_refs_has_output_schema

test_refs_has_few_shot() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
found = any('specialist-few-shot' in str(k) for k in refs.keys())
sys.exit(0 if found else 1)
"
}
run_test "refs セクション - ref-specialist-few-shot エントリ" test_refs_has_few_shot

# Edge case: refs セクションが dict 形式（リストではない）
test_refs_is_dict() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
sys.exit(0 if isinstance(refs, dict) else 1)
"
}
run_test "refs セクション [edge: dict 形式]" test_refs_is_dict

# Scenario: reference エントリの形式 (line 16)
# WHEN: refs セクションの各エントリを検査する
# THEN: 全エントリに type: reference, path, description が存在する
test_refs_entry_format_output_schema() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'specialist-output-schema' in str(key):
        if not isinstance(val, dict):
            sys.exit(1)
        if val.get('type') != 'reference':
            sys.exit(1)
        if 'path' not in val:
            sys.exit(1)
        if 'description' not in val:
            sys.exit(1)
        sys.exit(0)
sys.exit(1)
"
}
run_test "reference エントリ形式 - output-schema (type, path, description)" test_refs_entry_format_output_schema

test_refs_entry_format_few_shot() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'specialist-few-shot' in str(key):
        if not isinstance(val, dict):
            sys.exit(1)
        if val.get('type') != 'reference':
            sys.exit(1)
        if 'path' not in val:
            sys.exit(1)
        if 'description' not in val:
            sys.exit(1)
        sys.exit(0)
sys.exit(1)
"
}
run_test "reference エントリ形式 - few-shot (type, path, description)" test_refs_entry_format_few_shot

# Edge case: path が実際のファイルを指している
test_refs_path_output_schema_file_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  local ref_path
  ref_path=$(yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'specialist-output-schema' in str(key):
        print(val.get('path', ''))
        sys.exit(0)
sys.exit(1)
")
  [[ -n "$ref_path" ]] && assert_file_exists "$ref_path"
}
run_test "refs [edge: output-schema path が実ファイルを指す]" test_refs_path_output_schema_file_exists

test_refs_path_few_shot_file_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  local ref_path
  ref_path=$(yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'specialist-few-shot' in str(key):
        print(val.get('path', ''))
        sys.exit(0)
sys.exit(1)
")
  [[ -n "$ref_path" ]] && assert_file_exists "$ref_path"
}
run_test "refs [edge: few-shot path が実ファイルを指す]" test_refs_path_few_shot_file_exists

# Edge case: path が refs/ ディレクトリ配下を指している
test_refs_path_under_refs_dir() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    p = val.get('path', '')
    if not str(p).startswith('refs/'):
        sys.exit(1)
sys.exit(0)
"
}
run_test "refs [edge: 全 path が refs/ 配下]" test_refs_path_under_refs_dir

# Edge case: description が空文字列でない
test_refs_description_not_empty() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    desc = val.get('description', '')
    if not desc or not str(desc).strip():
        sys.exit(1)
sys.exit(0)
"
}
run_test "refs [edge: description が空でない]" test_refs_description_not_empty

# Edge case: deps.yaml 全体が有効な YAML
test_deps_yaml_valid() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML"
}
run_test "refs [edge: deps.yaml が有効な YAML]" test_deps_yaml_valid

# =============================================================================
# Requirement: twl check の通過
# =============================================================================
echo ""
echo "--- Requirement: twl check の通過 ---"

# Scenario: twl check が pass する (line 22)
# WHEN: deps.yaml 更新後に twl check を実行する
# THEN: exit code が 0 で、エラーが報告されない
test_twl_check_pass() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl check 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

if command -v twl &>/dev/null; then
  run_test "twl check が pass する" test_twl_check_pass
else
  run_test_skip "twl check が pass する" "twl command not found"
fi

# Edge case: twl check の出力に ERROR がない
test_twl_check_no_errors() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl check 2>&1)
  if echo "$output" | grep -qiP "^ERROR|:\s*ERROR"; then
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl check [edge: エラー出力なし]" test_twl_check_no_errors
else
  run_test_skip "twl check [edge: エラー出力なし]" "twl command not found"
fi

# =============================================================================
# Requirement: twl validate の通過
# =============================================================================
echo ""
echo "--- Requirement: twl validate の通過 ---"

# Scenario: twl validate が新規 violation なしで完了する (line 30)
# WHEN: twl validate を実行する
# THEN: 新規 violation が 0 件である
test_twl_validate_pass() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

if command -v twl &>/dev/null; then
  run_test "twl validate が新規 violation なしで完了する" test_twl_validate_pass
else
  run_test_skip "twl validate が新規 violation なしで完了する" "twl command not found"
fi

# Edge case: twl validate の出力に "violation" が 0 件
test_twl_validate_zero_violations() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  if echo "$output" | grep -qiP "violation"; then
    echo "$output" | grep -qiP "0.*violation|no.*violation|violation.*\b0\b" || return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl validate [edge: violation 0件表示]" test_twl_validate_zero_violations
else
  run_test_skip "twl validate [edge: violation 0件表示]" "twl command not found"
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
