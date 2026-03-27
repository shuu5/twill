#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: plugin-recognition.md
# Generated from: openspec/changes/b-2-bare-repo-depsyaml-v30-co-naming/specs/plugin-recognition.md
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

assert_dir_exists() {
  local dir="$1"
  [[ -d "${PROJECT_ROOT}/${dir}" ]]
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

assert_valid_json() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "import json; json.load(open('${PROJECT_ROOT}/${file}'))" 2>/dev/null
}

assert_json_has_key() {
  local file="$1"
  local key="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import json, sys
data = json.load(open('${PROJECT_ROOT}/${file}'))
sys.exit(0 if '${key}' in data else 1)
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

# =============================================================================
# Requirement: plugin.json によるプラグイン認識
# =============================================================================
echo ""
echo "--- Requirement: plugin.json によるプラグイン認識 ---"

# Scenario: Claude Code がプラグインを認識する (line 12)
# WHEN: Claude Code が main/ ディレクトリでセッションを開始する
# THEN: .claude-plugin/plugin.json が存在し、正しい JSON として読み込める
test_plugin_json_exists_and_valid() {
  assert_file_exists ".claude-plugin/plugin.json" || return 1
  assert_valid_json ".claude-plugin/plugin.json"
}
run_test "Claude Code がプラグインを認識する" test_plugin_json_exists_and_valid

# Edge case: plugin.json が空ファイルでない
test_plugin_json_not_empty() {
  local file=".claude-plugin/plugin.json"
  assert_file_exists "$file" || return 1
  local size
  size=$(wc -c < "${PROJECT_ROOT}/${file}")
  [[ $size -gt 2 ]]
}
run_test "Claude Code がプラグインを認識する [edge: 空ファイルでない]" test_plugin_json_not_empty

# Edge case: plugin.json が UTF-8 エンコーディング
test_plugin_json_utf8() {
  local file=".claude-plugin/plugin.json"
  assert_file_exists "$file" || return 1
  file "${PROJECT_ROOT}/${file}" | grep -qiP "ASCII|UTF-8|JSON"
}
run_test "Claude Code がプラグインを認識する [edge: UTF-8エンコーディング]" test_plugin_json_utf8

# Scenario: plugin.json の必須フィールド検証 (line 16)
# WHEN: .claude-plugin/plugin.json を読み込む
# THEN: name, version, description の3フィールドが全て存在する
test_plugin_json_required_fields() {
  local file=".claude-plugin/plugin.json"
  assert_file_exists "$file" || return 1
  assert_valid_json "$file" || return 1
  assert_json_has_key "$file" "name" || return 1
  assert_json_has_key "$file" "version" || return 1
  assert_json_has_key "$file" "description"
}
run_test "plugin.json の必須フィールド検証" test_plugin_json_required_fields

# Edge case: name が "dev" である
test_plugin_json_name_is_dev() {
  local file=".claude-plugin/plugin.json"
  assert_file_exists "$file" || return 1
  python3 -c "
import json, sys
data = json.load(open('${PROJECT_ROOT}/${file}'))
sys.exit(0 if data.get('name') == 'dev' else 1)
" 2>/dev/null
}
run_test "plugin.json [edge: name が 'dev']" test_plugin_json_name_is_dev

# Edge case: version がセマンティックバージョニング形式
test_plugin_json_version_format() {
  local file=".claude-plugin/plugin.json"
  assert_file_exists "$file" || return 1
  python3 -c "
import json, sys, re
data = json.load(open('${PROJECT_ROOT}/${file}'))
v = data.get('version', '')
sys.exit(0 if re.match(r'^[0-9]+\.[0-9]+', str(v)) else 1)
" 2>/dev/null
}
run_test "plugin.json [edge: version がバージョン形式]" test_plugin_json_version_format

# Edge case: description が空文字列でない
test_plugin_json_description_not_empty() {
  local file=".claude-plugin/plugin.json"
  assert_file_exists "$file" || return 1
  python3 -c "
import json, sys
data = json.load(open('${PROJECT_ROOT}/${file}'))
desc = data.get('description', '')
sys.exit(0 if desc and len(str(desc).strip()) > 0 else 1)
" 2>/dev/null
}
run_test "plugin.json [edge: description が空でない]" test_plugin_json_description_not_empty

# =============================================================================
# Requirement: プラグインディレクトリ構造
# =============================================================================
echo ""
echo "--- Requirement: プラグインディレクトリ構造 ---"

# Scenario: ディレクトリ構造の完備 (line 24)
# WHEN: main/ のディレクトリ構造を検査する
# THEN: skills/, commands/, agents/, refs/, scripts/ が全て存在する
test_directory_structure_complete() {
  assert_dir_exists "skills" || return 1
  assert_dir_exists "commands" || return 1
  assert_dir_exists "agents" || return 1
  assert_dir_exists "refs" || return 1
  assert_dir_exists "scripts"
}
run_test "ディレクトリ構造の完備" test_directory_structure_complete

# Edge case: ディレクトリが空でない（最低限 .gitkeep か何かがある）
test_directory_structure_not_all_empty() {
  local has_content=0
  for dir in skills commands agents refs scripts; do
    if [[ -d "${PROJECT_ROOT}/${dir}" ]]; then
      local count
      count=$(ls -A "${PROJECT_ROOT}/${dir}" | wc -l)
      if [[ $count -gt 0 ]]; then
        has_content=1
      fi
    fi
  done
  [[ $has_content -eq 1 ]]
}
run_test "ディレクトリ構造 [edge: 少なくとも1つのディレクトリに内容あり]" test_directory_structure_not_all_empty

# Scenario: controller ディレクトリの存在 (line 28)
# WHEN: skills/ 配下を検査する
# THEN: co-autopilot/, co-issue/, co-project/, co-architect/ の4ディレクトリが存在し、
#       各ディレクトリに SKILL.md が配置されている
test_controller_directories_exist() {
  for ctrl in co-autopilot co-issue co-project co-architect; do
    assert_dir_exists "skills/${ctrl}" || return 1
    assert_file_exists "skills/${ctrl}/SKILL.md" || return 1
  done
  return 0
}
run_test "controller ディレクトリの存在" test_controller_directories_exist

# Edge case: SKILL.md が空ファイルでない
test_controller_skill_not_empty() {
  for ctrl in co-autopilot co-issue co-project co-architect; do
    local file="skills/${ctrl}/SKILL.md"
    if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
      local size
      size=$(wc -c < "${PROJECT_ROOT}/${file}")
      if [[ $size -le 1 ]]; then
        return 1
      fi
    else
      return 1
    fi
  done
  return 0
}
run_test "controller ディレクトリ [edge: SKILL.md が空でない]" test_controller_skill_not_empty

# Edge case: skills/ 配下に controller 以外のサブディレクトリがあっても OK だが、
# controller 4つは必ず存在する（正確に4つが co-* プレフィックス）
test_controller_exactly_four_co_prefixed() {
  local co_count=0
  for dir in "${PROJECT_ROOT}"/skills/co-*/; do
    if [[ -d "$dir" ]]; then
      ((co_count++))
    fi
  done
  [[ $co_count -ge 4 ]]
}
run_test "controller ディレクトリ [edge: co-* プレフィックスが4つ以上]" test_controller_exactly_four_co_prefixed

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
