#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: Controller tools フィールドによる Agent スポーン制限
# Generated from: openspec/changes/claude-code-v2185-feature-intake/specs/controller-tools-restriction/spec.md
# change-id: claude-code-v2185-feature-intake
# Coverage level: edge-cases
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

yaml_frontmatter_get() {
  local file="$1"
  local key="$2"
  python3 -c "
import sys, yaml
content = open('${PROJECT_ROOT}/${file}').read()
if not content.startswith('---'):
    print('NO_FRONTMATTER', file=sys.stderr)
    sys.exit(1)
end = content.find('---', 3)
fm = yaml.safe_load(content[3:end]) or {}
val = fm.get('${key}')
if val is None:
    print('KEY_NOT_FOUND: ${key}', file=sys.stderr)
    sys.exit(1)
if isinstance(val, list):
    for v in val:
        print(v)
else:
    print(val)
" 2>/dev/null
}

yaml_frontmatter_get_list() {
  local file="$1"
  local key="$2"
  python3 -c "
import sys, yaml
content = open('${PROJECT_ROOT}/${file}').read()
if not content.startswith('---'):
    sys.exit(1)
end = content.find('---', 3)
fm = yaml.safe_load(content[3:end]) or {}
val = fm.get('${key}')
if val is None or not isinstance(val, list):
    sys.exit(1)
for v in val:
    print(v)
" 2>/dev/null
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

# =============================================================================
# Requirement: Controller tools フィールドによる Agent スポーン制限
# =============================================================================
echo ""
echo "--- Requirement: Controller tools フィールドによる Agent スポーン制限 ---"

# ---------------------------------------------------------------------------
# Scenario: co-autopilot のスポーン制限
# WHEN: skills/co-autopilot/SKILL.md の frontmatter を確認する
# THEN: tools フィールドに Worker 系・e2e 系エージェントのスポーン許可が宣言されている
# ---------------------------------------------------------------------------

CO_AUTOPILOT="skills/co-autopilot/SKILL.md"

test_co_autopilot_has_tools() {
  assert_file_exists "$CO_AUTOPILOT" || return 1
  yaml_frontmatter_get "$CO_AUTOPILOT" "tools" > /dev/null
}

if assert_file_exists "$CO_AUTOPILOT" 2>/dev/null; then
  run_test "co-autopilot に tools フィールドが存在する" test_co_autopilot_has_tools
else
  run_test_skip "co-autopilot に tools フィールドが存在する" "SKILL.md not found"
fi

test_co_autopilot_tools_has_agent_patterns() {
  assert_file_exists "$CO_AUTOPILOT" || return 1
  local tools
  tools=$(yaml_frontmatter_get_list "$CO_AUTOPILOT" "tools") || return 1
  # Should contain Agent(...) patterns
  echo "$tools" | grep -q "Agent(" || return 1
}

if assert_file_exists "$CO_AUTOPILOT" 2>/dev/null; then
  run_test "co-autopilot tools に Agent() パターンが含まれる" test_co_autopilot_tools_has_agent_patterns
else
  run_test_skip "co-autopilot tools に Agent() パターンが含まれる" "SKILL.md not found"
fi

# [edge-case] co-autopilot の Agent スポーン制限に worker-* パターンを含む
test_co_autopilot_allows_workers() {
  assert_file_exists "$CO_AUTOPILOT" || return 1
  local tools
  tools=$(yaml_frontmatter_get_list "$CO_AUTOPILOT" "tools") || return 1
  echo "$tools" | grep -q "worker-\|worker\*" || return 1
}

if assert_file_exists "$CO_AUTOPILOT" 2>/dev/null; then
  run_test "co-autopilot tools に worker 系パターン [edge]" test_co_autopilot_allows_workers
else
  run_test_skip "co-autopilot tools に worker 系パターン [edge]" "SKILL.md not found"
fi

# ---------------------------------------------------------------------------
# Scenario: co-issue のスポーン制限
# WHEN: skills/co-issue/SKILL.md の frontmatter を確認する
# THEN: tools に issue-critic, issue-feasibility, context-checker, template-validator が含まれる
# ---------------------------------------------------------------------------

CO_ISSUE="skills/co-issue/SKILL.md"

test_co_issue_has_tools() {
  assert_file_exists "$CO_ISSUE" || return 1
  yaml_frontmatter_get "$CO_ISSUE" "tools" > /dev/null
}

if assert_file_exists "$CO_ISSUE" 2>/dev/null; then
  run_test "co-issue に tools フィールドが存在する" test_co_issue_has_tools
else
  run_test_skip "co-issue に tools フィールドが存在する" "SKILL.md not found"
fi

test_co_issue_tools_contains_expected_agents() {
  assert_file_exists "$CO_ISSUE" || return 1
  local tools
  tools=$(yaml_frontmatter_get_list "$CO_ISSUE" "tools") || return 1
  local expected=("issue-critic" "issue-feasibility" "context-checker" "template-validator")
  for agent in "${expected[@]}"; do
    echo "$tools" | grep -q "$agent" || {
      echo "  Missing: $agent" >&2
      return 1
    }
  done
}

if assert_file_exists "$CO_ISSUE" 2>/dev/null; then
  run_test "co-issue tools に期待される 4 agent が含まれる" test_co_issue_tools_contains_expected_agents
else
  run_test_skip "co-issue tools に期待される 4 agent が含まれる" "SKILL.md not found"
fi

# ---------------------------------------------------------------------------
# Scenario: スポーン制限外のエージェント呼び出し（構造検証のみ）
# WHEN: Controller が tools フィールドに宣言されていないエージェントをスポーンしようとする
# THEN: Claude Code が当該スポーンを制限する（MUST）
# Note: 実行時制限は Claude Code 側の動作。ここでは tools フィールドの存在と形式のみ検証
# ---------------------------------------------------------------------------

# [edge-case] tools フィールドがリスト形式
test_tools_is_list_format() {
  python3 -c "
import sys, yaml, os

skills_dir = '${PROJECT_ROOT}/skills'
errors = []

for skill_name in os.listdir(skills_dir):
    skill_path = os.path.join(skills_dir, skill_name, 'SKILL.md')
    if not os.path.isfile(skill_path):
        continue
    content = open(skill_path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    tools = fm.get('tools')
    if tools is not None and not isinstance(tools, list):
        errors.append(f'{skill_name}: tools is {type(tools).__name__}, expected list')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "tools フィールドはリスト形式 [edge]" test_tools_is_list_format

# [edge-case] tools 内の Agent() パターンが正しい構文
test_agent_pattern_syntax() {
  python3 -c "
import sys, yaml, os, re

skills_dir = '${PROJECT_ROOT}/skills'
errors = []
pattern = re.compile(r'^Agent\([a-zA-Z0-9_,\s*-]+\)$')

for skill_name in os.listdir(skills_dir):
    skill_path = os.path.join(skills_dir, skill_name, 'SKILL.md')
    if not os.path.isfile(skill_path):
        continue
    content = open(skill_path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    tools = fm.get('tools')
    if not isinstance(tools, list):
        continue
    for t in tools:
        if isinstance(t, str) and t.startswith('Agent('):
            if not pattern.match(t):
                errors.append(f'{skill_name}: invalid Agent pattern: {t!r}')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "Agent() パターンの構文が正しい [edge]" test_agent_pattern_syntax

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
