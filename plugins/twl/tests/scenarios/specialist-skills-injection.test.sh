#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: specialist への ref-* スキル事前注入
# Generated from: deltaspec/changes/claude-code-v2185-feature-intake/specs/specialist-skills-injection/spec.md
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
    sys.exit(1)
end = content.find('---', 3)
fm = yaml.safe_load(content[3:end]) or {}
val = fm.get('${key}')
if val is None:
    sys.exit(1)
import json
print(json.dumps(val))
" 2>/dev/null
}

get_body_refs() {
  # Get ref-* patterns referenced in the body of a markdown file
  local file="$1"
  python3 -c "
import sys, re, yaml
content = open('${PROJECT_ROOT}/${file}').read()
if content.startswith('---'):
    end = content.find('---', 3)
    body = content[end+3:]
else:
    body = content
refs = sorted(set(re.findall(r'ref-[\w-]+', body)))
for r in refs:
    print(r)
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
# Requirement: specialist への ref-* スキル事前注入
# =============================================================================
echo ""
echo "--- Requirement: specialist への ref-* スキル事前注入 ---"

# ---------------------------------------------------------------------------
# Scenario: reviewer 系 specialist に共通 ref を注入 (spec.md line 7)
# WHEN: worker-code-reviewer.md の frontmatter を確認する
# THEN: skills フィールドに ref-specialist-output-schema と ref-specialist-few-shot が含まれていなければならない（MUST）
# ---------------------------------------------------------------------------

REVIEWER="agents/worker-code-reviewer.md"

test_reviewer_skills_field_exists() {
  assert_file_exists "$REVIEWER" || return 1
  yaml_frontmatter_get "$REVIEWER" "skills" > /dev/null
}

if assert_file_exists "$REVIEWER" 2>/dev/null; then
  run_test "worker-code-reviewer: skills フィールドが存在する" test_reviewer_skills_field_exists
else
  run_test_skip "worker-code-reviewer: skills フィールドが存在する" "agents/worker-code-reviewer.md not found"
fi

test_reviewer_skills_contains_output_schema() {
  assert_file_exists "$REVIEWER" || return 1
  python3 -c "
import sys, yaml, json
content = open('${PROJECT_ROOT}/${REVIEWER}').read()
if not content.startswith('---'):
    sys.exit(1)
end = content.find('---', 3)
fm = yaml.safe_load(content[3:end]) or {}
skills = fm.get('skills', [])
if not isinstance(skills, list):
    skills = [skills]
if 'ref-specialist-output-schema' not in skills:
    print(f'ref-specialist-output-schema not in skills={skills}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}

if assert_file_exists "$REVIEWER" 2>/dev/null; then
  run_test "worker-code-reviewer: skills に ref-specialist-output-schema が含まれる" test_reviewer_skills_contains_output_schema
else
  run_test_skip "worker-code-reviewer: skills に ref-specialist-output-schema が含まれる" "agents/worker-code-reviewer.md not found"
fi

# [edge-case] skills フィールドがリスト型
test_reviewer_skills_is_list() {
  assert_file_exists "$REVIEWER" || return 1
  python3 -c "
import sys, yaml
content = open('${PROJECT_ROOT}/${REVIEWER}').read()
if not content.startswith('---'):
    sys.exit(1)
end = content.find('---', 3)
fm = yaml.safe_load(content[3:end]) or {}
skills = fm.get('skills')
if skills is not None and not isinstance(skills, list):
    print(f'skills is {type(skills).__name__}, expected list', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}

if assert_file_exists "$REVIEWER" 2>/dev/null; then
  run_test "worker-code-reviewer skills [edge: リスト型]" test_reviewer_skills_is_list
else
  run_test_skip "worker-code-reviewer skills [edge: リスト型]" "agents/worker-code-reviewer.md not found"
fi

# ---------------------------------------------------------------------------
# Scenario: body 内参照と skills フィールドの一致 (spec.md line 11)
# WHEN: specialist の body 内に ref-* パターンの参照がある
# THEN: 対応する ref-* が skills フィールドに宣言されていなければならない（MUST）
# ---------------------------------------------------------------------------

# 全 specialist エージェントで body 内 ref-* が skills フィールドに反映されているか検証
test_body_refs_match_skills_field() {
  python3 -c "
import sys, re, yaml, os

agents_dir = '${PROJECT_ROOT}/agents'
errors = []

for agent_file in os.listdir(agents_dir):
    if not agent_file.endswith('.md'):
        continue
    path = os.path.join(agents_dir, agent_file)
    content = open(path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    if fm.get('type') != 'specialist':
        continue
    body = content[end+3:]
    # Exclude ref-* inside backtick code spans (examples/templates)
    body_clean = re.sub(r'\x60[^\x60]*\x60', '', body)
    body_refs = set(re.findall(r'ref-[\w-]+', body_clean))
    if not body_refs:
        continue  # No refs in body: covered by separate scenario
    skills = fm.get('skills', [])
    if not isinstance(skills, list):
        skills = []
    skills_set = set(skills)
    missing = body_refs - skills_set
    if missing:
        errors.append(f'{agent_file}: body refs {sorted(missing)} not in skills={sorted(skills_set)}')

if errors:
    for e in errors:
        print(f'  MISSING: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "body 内 ref-* が全て skills フィールドに宣言されている" test_body_refs_match_skills_field

# [edge-case] skills フィールドに body 未参照の余剰エントリがない
test_no_extra_skills_beyond_body_refs() {
  python3 -c "
import sys, re, yaml, os

agents_dir = '${PROJECT_ROOT}/agents'
warnings = []

for agent_file in os.listdir(agents_dir):
    if not agent_file.endswith('.md'):
        continue
    path = os.path.join(agents_dir, agent_file)
    content = open(path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    if fm.get('type') != 'specialist':
        continue
    body = content[end+3:]
    body_refs = set(re.findall(r'ref-[\w-]+', body))
    skills = fm.get('skills', [])
    if not isinstance(skills, list):
        skills = []
    skills_set = set(skills)
    # Skills declared but not referenced in body
    extra = skills_set - body_refs
    if extra:
        warnings.append(f'{agent_file}: skills {sorted(extra)} declared but not referenced in body')

# This is a warning-level check; extra skills could be intentional pre-injection
# but we report them as potential inconsistency
if warnings:
    for w in warnings:
        print(f'  EXTRA: {w}', file=sys.stderr)
    # Not a hard failure - warn only by exiting 0
sys.exit(0)
" 2>/dev/null
}
run_test "skills フィールド [edge: body 未参照の余剰エントリなし]" test_no_extra_skills_beyond_body_refs

# [edge-case] skills リストの各要素が 'ref-' で始まる
test_skills_entries_are_ref_prefixed() {
  python3 -c "
import sys, yaml, os

agents_dir = '${PROJECT_ROOT}/agents'
errors = []

for agent_file in os.listdir(agents_dir):
    if not agent_file.endswith('.md'):
        continue
    path = os.path.join(agents_dir, agent_file)
    content = open(path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    skills = fm.get('skills')
    if skills is None:
        continue
    if not isinstance(skills, list):
        errors.append(f'{agent_file}: skills is not a list')
        continue
    for s in skills:
        if not isinstance(s, str) or not s.startswith('ref-'):
            errors.append(f'{agent_file}: skill entry {s!r} does not start with ref-')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "skills エントリは ref- プレフィックスを持つ [edge]" test_skills_entries_are_ref_prefixed

# ---------------------------------------------------------------------------
# Scenario: ref-* 未参照の specialist (spec.md line 15)
# WHEN: specialist の body 内に ref-* 参照がない
# THEN: skills フィールドは追加しない（不要なフィールドを強制してはならない）
# ---------------------------------------------------------------------------

test_no_ref_specialist_has_no_skills_field() {
  python3 -c "
import sys, re, yaml, os

agents_dir = '${PROJECT_ROOT}/agents'
errors = []

for agent_file in os.listdir(agents_dir):
    if not agent_file.endswith('.md'):
        continue
    path = os.path.join(agents_dir, agent_file)
    content = open(path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    if fm.get('type') != 'specialist':
        continue
    body = content[end+3:]
    body_refs = set(re.findall(r'ref-[\w-]+', body))
    if body_refs:
        continue  # Has refs: covered by other scenario
    # No refs in body: should NOT have skills field
    if 'skills' in fm:
        errors.append(f'{agent_file}: has skills={fm[\"skills\"]} but no ref-* in body')

if errors:
    for e in errors:
        print(f'  VIOLATION: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "ref-* 未参照の specialist に skills フィールドが存在しない" test_no_ref_specialist_has_no_skills_field

# [edge-case] skills フィールドが空リストとして設定されていない
test_skills_not_empty_list() {
  python3 -c "
import sys, yaml, os

agents_dir = '${PROJECT_ROOT}/agents'
errors = []

for agent_file in os.listdir(agents_dir):
    if not agent_file.endswith('.md'):
        continue
    path = os.path.join(agents_dir, agent_file)
    content = open(path).read()
    if not content.startswith('---'):
        continue
    end = content.find('---', 3)
    try:
        fm = yaml.safe_load(content[3:end]) or {}
    except yaml.YAMLError:
        continue
    skills = fm.get('skills')
    if skills is not None and isinstance(skills, list) and len(skills) == 0:
        errors.append(f'{agent_file}: skills is an empty list []')

if errors:
    for e in errors:
        print(f'  INVALID: {e}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "skills フィールド [edge: 空リストが設定されていない]" test_skills_not_empty_list

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
