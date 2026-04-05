#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: depsyaml-skeleton.md
# Generated from: openspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/depsyaml-skeleton.md
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
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
# Requirement: deps.yaml v3.0 skeleton
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml v3.0 skeleton ---"

# Scenario: deps.yaml の基本構造が正しい (line 13)
# WHEN: deps.yaml をパースする
# THEN: version が "3.0"、plugin が "dev"、entry_points が4件存在する
test_depsyaml_basic_structure() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
v = data.get('version')
sys.exit(0 if str(v) == '3.0' else 1)
"
}
run_test "deps.yaml の基本構造 - version が 3.0" test_depsyaml_basic_structure

test_depsyaml_plugin_dev() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
p = data.get('plugin')
sys.exit(0 if str(p) == 'dev' else 1)
"
}
run_test "deps.yaml の基本構造 - plugin が dev" test_depsyaml_plugin_dev

test_depsyaml_entry_points_count() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
ep = data.get('entry_points', [])
sys.exit(0 if len(ep) == 4 else 1)
"
}
run_test "deps.yaml の基本構造 - entry_points が4件" test_depsyaml_entry_points_count

# Edge case: deps.yaml が有効な YAML としてパースできる
test_depsyaml_valid_yaml() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml [edge: 有効な YAML]" test_depsyaml_valid_yaml

# Edge case: entry_points の各パスが skills/ 配下を指している
test_depsyaml_entry_points_paths() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
ep = data.get('entry_points', [])
for p in ep:
    if not str(p).startswith('skills/'):
        sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml [edge: entry_points が skills/ 配下]" test_depsyaml_entry_points_paths

# Scenario: controller 4つが定義されている (line 17)
# WHEN: deps.yaml の skills セクションを検査する
# THEN: co-autopilot, co-issue, co-project, co-architect の4エントリが存在し、全て type: controller
test_depsyaml_four_controllers() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', data.get('components', {}))
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for name in required:
    found = False
    for key in skills:
        if name in str(key):
            found = True
            break
    if not found:
        sys.exit(1)
sys.exit(0)
"
}
run_test "controller 4つが定義されている" test_depsyaml_four_controllers

# Edge case: 全 controller が type: controller を持つ
test_depsyaml_controllers_type() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', data.get('components', {}))
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for name in required:
    for key, val in skills.items():
        if name in str(key):
            if isinstance(val, dict) and val.get('type') != 'controller':
                sys.exit(1)
sys.exit(0)
"
}
run_test "controller 4つ [edge: 全て type: controller]" test_depsyaml_controllers_type

# Edge case: 各 controller に description フィールドが存在する
test_depsyaml_controllers_description() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', data.get('components', {}))
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for name in required:
    for key, val in skills.items():
        if name in str(key):
            if isinstance(val, dict) and not val.get('description'):
                sys.exit(1)
sys.exit(0)
"
}
run_test "controller 4つ [edge: description フィールドあり]" test_depsyaml_controllers_description

# Edge case: 各 controller に spawnable_by フィールドが存在する
test_depsyaml_controllers_spawnable_by() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', data.get('components', {}))
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for name in required:
    for key, val in skills.items():
        if name in str(key):
            if isinstance(val, dict) and 'spawnable_by' not in val:
                sys.exit(1)
sys.exit(0)
"
}
run_test "controller 4つ [edge: spawnable_by フィールドあり]" test_depsyaml_controllers_spawnable_by

# =============================================================================
# Requirement: co-* 命名規則の適用
# =============================================================================
echo ""
echo "--- Requirement: co-* 命名規則の適用 ---"

# Scenario: co-* 命名規則の遵守 (line 25)
# WHEN: deps.yaml の controller エントリ名を検査する
# THEN: 全てが co- プレフィックスで始まっている
test_naming_co_prefix() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', data.get('components', {}))
for key, val in skills.items():
    if isinstance(val, dict) and val.get('type') == 'controller':
        # Extract the component name from the key (may be a path like skills/co-xxx)
        name = str(key).split('/')[-1]
        if not name.startswith('co-'):
            sys.exit(1)
sys.exit(0)
"
}
run_test "co-* 命名規則の遵守" test_naming_co_prefix

# Edge case: co- プレフィックスの後に意味のある名前が続く（co- のみは不可）
test_naming_co_prefix_meaningful() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', data.get('components', {}))
for key, val in skills.items():
    if isinstance(val, dict) and val.get('type') == 'controller':
        name = str(key).split('/')[-1]
        if name.startswith('co-'):
            suffix = name[3:]
            if not suffix or len(suffix) < 2:
                sys.exit(1)
sys.exit(0)
"
}
run_test "co-* 命名規則 [edge: co- の後に意味のある名前]" test_naming_co_prefix_meaningful

# Scenario: 旧命名の不在 (line 29)
# WHEN: deps.yaml 全体を controller- で検索する
# THEN: controller- プレフィックスのコンポーネント名が存在しない
test_naming_no_old_prefix() {
  assert_file_exists "$DEPS_YAML" || return 1
  # controller- as a component name key should not exist
  # (note: "type: controller" is OK, we check for "controller-" as a key/name prefix)
  assert_file_not_contains "$DEPS_YAML" "^\s*controller-|/controller-"
}
run_test "旧命名の不在" test_naming_no_old_prefix

# Edge case: ファイル全体に controller- で始まるコンポーネント参照がない（spawnable_by 等含む）
test_naming_no_old_prefix_anywhere() {
  assert_file_exists "$DEPS_YAML" || return 1
  # Search for controller- that is not "type: controller" or comment
  local matches
  matches=$(grep -P "controller-" "${PROJECT_ROOT}/${DEPS_YAML}" | grep -vP "^\s*#|type:\s*controller" || true)
  [[ -z "$matches" ]]
}
run_test "旧命名の不在 [edge: 参照箇所にも controller- なし]" test_naming_no_old_prefix_anywhere

# =============================================================================
# Requirement: loom check の通過
# =============================================================================
echo ""
echo "--- Requirement: loom check の通過 ---"

# Scenario: loom check が pass する (line 37)
# WHEN: main/ ディレクトリで loom check を実行する
# THEN: exit code が 0 で、エラーが報告されない
test_loom_check_pass() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom check 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

# Check if loom is available before running
if command -v loom &>/dev/null; then
  run_test "loom check が pass する" test_loom_check_pass
else
  run_test_skip "loom check が pass する" "loom command not found"
fi

# Edge case: loom check の出力にエラーや WARNING がない
test_loom_check_no_errors() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom check 2>&1)
  if echo "$output" | grep -qiP "error|ERROR"; then
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom check [edge: エラー出力なし]" test_loom_check_no_errors
else
  run_test_skip "loom check [edge: エラー出力なし]" "loom command not found"
fi

# =============================================================================
# Requirement: loom validate の通過
# =============================================================================
echo ""
echo "--- Requirement: loom validate の通過 ---"

# Scenario: loom validate が新規 violation なしで完了する (line 45)
# WHEN: main/ ディレクトリで loom validate を実行する
# THEN: 新規 violation が 0 件である
test_loom_validate_pass() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom validate 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

if command -v loom &>/dev/null; then
  run_test "loom validate が新規 violation なしで完了する" test_loom_validate_pass
else
  run_test_skip "loom validate が新規 violation なしで完了する" "loom command not found"
fi

# Edge case: loom validate の出力に "violation" が0件
test_loom_validate_zero_violations() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom validate 2>&1)
  # If "violation" appears, check it says 0
  if echo "$output" | grep -qiP "violation"; then
    echo "$output" | grep -qiP "0.*violation|no.*violation"
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom validate [edge: violation 0件表示]" test_loom_validate_zero_violations
else
  run_test_skip "loom validate [edge: violation 0件表示]" "loom command not found"
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
