#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: su-observer SKILL.md リファクタリング (issue-814)
# Generated from: Issue #814 AC (Option C + Phase 分割)
# Coverage level: edge-cases
# Type: unit (document-verification)
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

SKILL_MD="skills/su-observer/SKILL.md"
DEPS_YAML="deps.yaml"

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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -q -- "$pattern" "${PROJECT_ROOT}/${file}"
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
  ((SKIP++)) || true
}

# =============================================================================
# Scenario: su-observer SKILL.md body line count under 200
# =============================================================================
echo ""
echo "--- Scenario: su-observer SKILL.md 本文行数の削減 ---"

test_skill_md_body_line_count_under_200() {
  assert_file_exists "$SKILL_MD" || return 1
  python3 -c "
import sys
with open('${PROJECT_ROOT}/${SKILL_MD}') as f:
    lines = f.readlines()

# Strip frontmatter: skip from first '---' to closing '---'
in_frontmatter = False
body_lines = []
fm_closed = False
for i, line in enumerate(lines):
    stripped = line.rstrip()
    if i == 0 and stripped == '---':
        in_frontmatter = True
        continue
    if in_frontmatter and stripped == '---':
        in_frontmatter = False
        fm_closed = True
        continue
    if fm_closed or not in_frontmatter:
        body_lines.append(line)

count = len(body_lines)
if count >= 200:
    print(f'Body line count is {count}, expected < 200', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

run_test "SKILL.md 本文行数が 200 未満である" test_skill_md_body_line_count_under_200

# Edge case: frontmatter が --- で正しく囲まれている
test_skill_md_has_valid_frontmatter() {
  assert_file_exists "$SKILL_MD" || return 1
  python3 -c "
import sys
with open('${PROJECT_ROOT}/${SKILL_MD}') as f:
    lines = [l.rstrip() for l in f.readlines()]
if lines[0] != '---':
    print('No opening --- found at line 1', file=sys.stderr)
    sys.exit(1)
closing = next((i for i in range(1, len(lines)) if lines[i] == '---'), None)
if closing is None:
    print('No closing --- found for frontmatter', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

run_test "SKILL.md [edge: frontmatter が --- で正しく囲まれている]" test_skill_md_has_valid_frontmatter

# =============================================================================
# Scenario: su-observer 主要 refs/commands への参照が維持されている
# =============================================================================
echo ""
echo "--- Scenario: 参照文字列の維持 ---"

test_skill_md_contains_intervention_catalog() {
  assert_file_contains "$SKILL_MD" "intervention-catalog"
}
run_test "SKILL.md に intervention-catalog 参照が存在する" test_skill_md_contains_intervention_catalog

test_skill_md_contains_pitfalls_catalog() {
  assert_file_contains "$SKILL_MD" "pitfalls-catalog"
}
run_test "SKILL.md に pitfalls-catalog 参照が存在する" test_skill_md_contains_pitfalls_catalog

test_skill_md_contains_monitor_channel_catalog() {
  assert_file_contains "$SKILL_MD" "monitor-channel-catalog"
}
run_test "SKILL.md に monitor-channel-catalog 参照が存在する" test_skill_md_contains_monitor_channel_catalog

test_skill_md_contains_proxy_dialog_playbook() {
  assert_file_contains "$SKILL_MD" "proxy-dialog-playbook"
}
run_test "SKILL.md に proxy-dialog-playbook 参照が存在する" test_skill_md_contains_proxy_dialog_playbook

test_skill_md_contains_wave_collect() {
  assert_file_contains "$SKILL_MD" "commands/wave-collect.md"
}
run_test "SKILL.md に commands/wave-collect.md 参照が存在する" test_skill_md_contains_wave_collect

test_skill_md_contains_externalize_state() {
  assert_file_contains "$SKILL_MD" "commands/externalize-state.md"
}
run_test "SKILL.md に commands/externalize-state.md 参照が存在する" test_skill_md_contains_externalize_state

# =============================================================================
# Scenario: 新規 script と reference が deps.yaml に登録されている
# =============================================================================
echo ""
echo "--- Scenario: deps.yaml の su-observer.calls 配列検証 ---"

test_deps_yaml_calls_budget_detect() {
  assert_file_contains "$DEPS_YAML" "script: budget-detect"
}
run_test "deps.yaml su-observer.calls に budget-detect エントリが含まれる" test_deps_yaml_calls_budget_detect

test_deps_yaml_calls_budget_monitor_watcher() {
  assert_file_contains "$DEPS_YAML" "script: budget-monitor-watcher"
}
run_test "deps.yaml su-observer.calls に budget-monitor-watcher エントリが含まれる" test_deps_yaml_calls_budget_monitor_watcher

test_deps_yaml_calls_session_init() {
  assert_file_contains "$DEPS_YAML" "script: session-init"
}
run_test "deps.yaml su-observer.calls に session-init エントリが含まれる" test_deps_yaml_calls_session_init

test_deps_yaml_calls_proxy_dialog_playbook() {
  assert_file_contains "$DEPS_YAML" "reference: proxy-dialog-playbook"
}
run_test "deps.yaml su-observer.calls に proxy-dialog-playbook エントリが含まれる" test_deps_yaml_calls_proxy_dialog_playbook

# =============================================================================
# Scenario: 新規 script ファイルが実在する
# =============================================================================
echo ""
echo "--- Scenario: 新規 script ファイルの実在確認 ---"

test_budget_detect_script_exists() {
  assert_file_exists "skills/su-observer/scripts/budget-detect.sh"
}
run_test "skills/su-observer/scripts/budget-detect.sh が存在する" test_budget_detect_script_exists

test_budget_monitor_watcher_script_exists() {
  assert_file_exists "skills/su-observer/scripts/budget-monitor-watcher.sh"
}
run_test "skills/su-observer/scripts/budget-monitor-watcher.sh が存在する" test_budget_monitor_watcher_script_exists

test_session_init_script_exists() {
  assert_file_exists "skills/su-observer/scripts/session-init.sh"
}
run_test "skills/su-observer/scripts/session-init.sh が存在する" test_session_init_script_exists

test_proxy_dialog_playbook_exists() {
  assert_file_exists "skills/su-observer/refs/proxy-dialog-playbook.md"
}
run_test "skills/su-observer/refs/proxy-dialog-playbook.md が存在する" test_proxy_dialog_playbook_exists

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
