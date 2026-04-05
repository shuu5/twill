#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: deps.yaml 新フィールド反映
# Generated from: openspec/changes/claude-code-v2185-feature-intake/specs/deps-yaml-sync/spec.md
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
    print(' '.join(str(v) for v in val))
else:
    print(val)
" 2>/dev/null
}

deps_yaml_get() {
  local component="$1"
  local field="$2"
  python3 -c "
import sys, yaml
data = yaml.safe_load(open('${PROJECT_ROOT}/deps.yaml'))
# deps.yaml uses separate top-level keys: skills, agents, commands, etc.
comp = None
for section in ['skills', 'agents', 'commands', 'scripts', 'refs']:
    section_data = data.get(section, {})
    if '${component}' in section_data:
        comp = section_data['${component}']
        break
if comp is None:
    print('COMPONENT_NOT_FOUND: ${component}', file=sys.stderr)
    sys.exit(1)
val = comp.get('${field}')
if val is None:
    print('FIELD_NOT_FOUND: ${field}', file=sys.stderr)
    sys.exit(1)
if isinstance(val, list):
    print(' '.join(str(v) for v in val))
else:
    print(val)
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
# Requirement: deps.yaml 新フィールド反映
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml 新フィールド反映 ---"

# ---------------------------------------------------------------------------
# Scenario: Controller の effort が deps.yaml に反映
# WHEN: skills/co-autopilot/SKILL.md に effort: high が設定される
# THEN: deps.yaml の co-autopilot コンポーネント定義にも effort: high が反映されている
# ---------------------------------------------------------------------------

test_co_autopilot_effort_in_deps() {
  local fm_val deps_val
  fm_val=$(yaml_frontmatter_get "skills/co-autopilot/SKILL.md" "effort") || return 1
  deps_val=$(deps_yaml_get "co-autopilot" "effort") || return 1
  [[ "$fm_val" == "$deps_val" ]]
}

if assert_file_exists "skills/co-autopilot/SKILL.md" 2>/dev/null; then
  run_test "co-autopilot effort が deps.yaml と一致" test_co_autopilot_effort_in_deps
else
  run_test_skip "co-autopilot effort が deps.yaml と一致" "SKILL.md not found"
fi

# [edge-case] 全 Controller の effort が deps.yaml と一致
test_all_controller_effort_sync() {
  python3 -c "
import sys, yaml, os

deps = yaml.safe_load(open('${PROJECT_ROOT}/deps.yaml'))
skills_data = deps.get('skills', {})
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
    fm_effort = fm.get('effort')
    if fm_effort is None:
        continue
    comp = skills_data.get(skill_name, {})
    deps_effort = comp.get('effort')
    if fm_effort != deps_effort:
        errors.append(f'{skill_name}: frontmatter={fm_effort!r}, deps.yaml={deps_effort!r}')

if errors:
    for e in errors:
        print(f'  MISMATCH: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "全 Controller effort が deps.yaml と同期 [edge]" test_all_controller_effort_sync

# ---------------------------------------------------------------------------
# Scenario: specialist の skills が deps.yaml に反映
# WHEN: agents/worker-code-reviewer.md に skills が設定される
# THEN: deps.yaml の worker-code-reviewer にも skills が反映されている
# ---------------------------------------------------------------------------

test_code_reviewer_skills_in_deps() {
  local fm_val deps_val
  fm_val=$(yaml_frontmatter_get "agents/worker-code-reviewer.md" "skills") || return 1
  deps_val=$(deps_yaml_get "worker-code-reviewer" "skills") || return 1
  [[ -n "$fm_val" && -n "$deps_val" ]]
}

if assert_file_exists "agents/worker-code-reviewer.md" 2>/dev/null; then
  run_test "worker-code-reviewer skills が deps.yaml に反映" test_code_reviewer_skills_in_deps
else
  run_test_skip "worker-code-reviewer skills が deps.yaml に反映" "agent not found"
fi

# ---------------------------------------------------------------------------
# Scenario: twl check が PASS
# ---------------------------------------------------------------------------

test_twl_check_pass() {
  local twl_bin
  twl_bin=$(which twl 2>/dev/null) || return 1
  cd "${PROJECT_ROOT}" && twl check > /dev/null 2>&1
}

if which twl > /dev/null 2>&1; then
  run_test "twl check が PASS" test_twl_check_pass
else
  run_test_skip "twl check が PASS" "twl CLI not found"
fi

# ---------------------------------------------------------------------------
# Scenario: twl validate が PASS
# ---------------------------------------------------------------------------

test_twl_validate_pass() {
  local twl_bin
  twl_bin=$(which twl 2>/dev/null) || return 1
  cd "${PROJECT_ROOT}" && twl validate > /dev/null 2>&1
}

if which twl > /dev/null 2>&1; then
  run_test "twl validate が PASS" test_twl_validate_pass
else
  run_test_skip "twl validate が PASS" "twl CLI not found"
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
