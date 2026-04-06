#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: Controller effort フィールド追加
# Generated from: deltaspec/changes/claude-code-v2185-feature-intake/specs/controller-effort/spec.md
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
# Requirement: Controller effort フィールド追加
# =============================================================================
echo ""
echo "--- Requirement: Controller effort フィールド追加 ---"

# ---------------------------------------------------------------------------
# Scenario: co-autopilot に effort: high を設定 (spec.md line 7)
# WHEN: skills/co-autopilot/SKILL.md の frontmatter を確認する
# THEN: effort: high が宣言されていなければならない（MUST）
# ---------------------------------------------------------------------------

CO_AUTOPILOT="skills/co-autopilot/SKILL.md"

test_co_autopilot_effort_exists() {
  assert_file_exists "$CO_AUTOPILOT" || return 1
  yaml_frontmatter_get "$CO_AUTOPILOT" "effort" > /dev/null
}

if assert_file_exists "$CO_AUTOPILOT" 2>/dev/null; then
  run_test "co-autopilot に effort フィールドが存在する" test_co_autopilot_effort_exists
else
  run_test_skip "co-autopilot に effort フィールドが存在する" "skills/co-autopilot/SKILL.md not found"
fi

test_co_autopilot_effort_is_high() {
  assert_file_exists "$CO_AUTOPILOT" || return 1
  local val
  val=$(yaml_frontmatter_get "$CO_AUTOPILOT" "effort") || return 1
  [[ "$val" == "high" ]]
}

if assert_file_exists "$CO_AUTOPILOT" 2>/dev/null; then
  run_test "co-autopilot effort: high が設定されている" test_co_autopilot_effort_is_high
else
  run_test_skip "co-autopilot effort: high が設定されている" "skills/co-autopilot/SKILL.md not found"
fi

# [edge-case] effort の値が文字列型
test_co_autopilot_effort_is_string() {
  assert_file_exists "$CO_AUTOPILOT" || return 1
  python3 -c "
import sys, yaml
content = open('${PROJECT_ROOT}/${CO_AUTOPILOT}').read()
if not content.startswith('---'):
    sys.exit(1)
end = content.find('---', 3)
fm = yaml.safe_load(content[3:end]) or {}
effort = fm.get('effort')
if not isinstance(effort, str):
    print(f'effort is {type(effort).__name__}, expected str', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}

if assert_file_exists "$CO_AUTOPILOT" 2>/dev/null; then
  run_test "co-autopilot effort [edge: 文字列型]" test_co_autopilot_effort_is_string
else
  run_test_skip "co-autopilot effort [edge: 文字列型]" "skills/co-autopilot/SKILL.md not found"
fi

# ---------------------------------------------------------------------------
# Scenario: workflow-dead-cleanup に effort: low を設定 (spec.md line 11)
# WHEN: skills/workflow-dead-cleanup/SKILL.md の frontmatter を確認する
# THEN: effort: low が宣言されていなければならない（MUST）
# ---------------------------------------------------------------------------

DEAD_CLEANUP="skills/workflow-dead-cleanup/SKILL.md"

test_dead_cleanup_effort_is_low() {
  assert_file_exists "$DEAD_CLEANUP" || return 1
  local val
  val=$(yaml_frontmatter_get "$DEAD_CLEANUP" "effort") || return 1
  [[ "$val" == "low" ]]
}

if assert_file_exists "$DEAD_CLEANUP" 2>/dev/null; then
  run_test "workflow-dead-cleanup effort: low が設定されている" test_dead_cleanup_effort_is_low
else
  run_test_skip "workflow-dead-cleanup effort: low が設定されている" "skills/workflow-dead-cleanup/SKILL.md not found"
fi

# [edge-case] workflow-dead-cleanup のファイルが存在する（frontmatter 付き）
test_dead_cleanup_has_frontmatter() {
  assert_file_exists "$DEAD_CLEANUP" || return 1
  python3 -c "
import sys
content = open('${PROJECT_ROOT}/${DEAD_CLEANUP}').read()
if not content.startswith('---'):
    print('No frontmatter', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}

if assert_file_exists "$DEAD_CLEANUP" 2>/dev/null; then
  run_test "workflow-dead-cleanup [edge: frontmatter が存在する]" test_dead_cleanup_has_frontmatter
else
  run_test_skip "workflow-dead-cleanup [edge: frontmatter が存在する]" "skills/workflow-dead-cleanup/SKILL.md not found"
fi

# ---------------------------------------------------------------------------
# Scenario: 全 Controller に effort が存在する (spec.md line 15)
# WHEN: skills/ 配下の全 SKILL.md を走査する
# THEN: 全ファイルの frontmatter に effort フィールドが存在しなければならない（MUST）
# ---------------------------------------------------------------------------

# 期待される Controller と effort 値（design.md D2 のマッピング）
declare -A EXPECTED_EFFORTS=(
  ["co-autopilot"]="high"
  ["co-issue"]="high"
  ["co-project"]="medium"
  ["co-architect"]="high"
  ["workflow-setup"]="medium"
  ["workflow-test-ready"]="medium"
  ["workflow-pr-cycle"]="medium"
  ["workflow-dead-cleanup"]="low"
  ["workflow-tech-debt-triage"]="medium"
)

test_all_controllers_have_effort() {
  local missing=()
  for controller in "${!EXPECTED_EFFORTS[@]}"; do
    local skill_file="skills/${controller}/SKILL.md"
    if ! assert_file_exists "$skill_file" 2>/dev/null; then
      missing+=("${controller}: FILE_NOT_FOUND")
      continue
    fi
    local val
    val=$(yaml_frontmatter_get "$skill_file" "effort") || {
      missing+=("${controller}: effort field missing")
      continue
    }
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    for m in "${missing[@]}"; do
      echo "  MISSING: ${m}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 Controller に effort フィールドが存在する" test_all_controllers_have_effort

# [edge-case] effort 値が期待通りに設定されている（全コントローラー一括）
test_all_controllers_effort_values() {
  local wrong=()
  for controller in "${!EXPECTED_EFFORTS[@]}"; do
    local skill_file="skills/${controller}/SKILL.md"
    assert_file_exists "$skill_file" 2>/dev/null || continue
    local val expected
    val=$(yaml_frontmatter_get "$skill_file" "effort") || continue
    expected="${EXPECTED_EFFORTS[$controller]}"
    if [[ "$val" != "$expected" ]]; then
      wrong+=("${controller}: got '${val}', expected '${expected}'")
    fi
  done
  if [[ ${#wrong[@]} -gt 0 ]]; then
    for w in "${wrong[@]}"; do
      echo "  MISMATCH: ${w}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 Controller effort 値が design.md D2 のマッピングと一致する [edge]" test_all_controllers_effort_values

# ---------------------------------------------------------------------------
# Scenario: effort 値は許可値のみ (spec.md line 19)
# WHEN: effort フィールドの値を確認する
# THEN: low, medium, high のいずれかでなければならない（MUST）
# ---------------------------------------------------------------------------

ALLOWED_EFFORT_VALUES=("low" "medium" "high")

test_effort_values_are_allowed() {
  python3 -c "
import sys, yaml, os

allowed = {'low', 'medium', 'high'}
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
    effort = fm.get('effort')
    if effort is not None and effort not in allowed:
        errors.append(f'{skill_name}: effort={effort!r} not in {allowed}')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "effort 値は low/medium/high のいずれかである" test_effort_values_are_allowed

# [edge-case] effort フィールドが null / 空でない
test_effort_not_null() {
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
    effort = fm.get('effort')
    if effort is None:
        continue  # effort field absence is checked in separate test
    if not isinstance(effort, str) or not effort.strip():
        errors.append(f'{skill_name}: effort is null or empty')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "effort 値は null/空でない [edge]" test_effort_not_null

# [edge-case] effort フィールドが大文字・スペース混じりでない（厳密な小文字）
test_effort_lowercase_strict() {
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
    effort = fm.get('effort')
    if effort is not None and isinstance(effort, str):
        if effort != effort.lower().strip():
            errors.append(f'{skill_name}: effort={effort!r} is not lowercase/trimmed')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "effort 値は厳密な小文字形式 [edge]" test_effort_lowercase_strict

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
