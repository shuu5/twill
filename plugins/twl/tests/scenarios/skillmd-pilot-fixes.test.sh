#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-autopilot SKILL.md pilot-3 fixes
# Generated from: deltaspec/changes/issue-387/specs/skillmd-pilot-fixes/spec.md
# Coverage level: edge-cases
#
# Change: issue-387 (co-autopilot SKILL.md: 3 error pattern fixes)
# Requirement 1: autopilot-plan.sh --issues space-separated format + --project-dir required
# Requirement 2: python-env.sh source instruction in Step 3
# Requirement 3: orchestrator --session-file absolute path example
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
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

SKILL_MD="skills/co-autopilot/SKILL.md"

# =============================================================================
# Requirement: autopilot-plan.sh 引数フォーマット明記
# =============================================================================
echo ""
echo "--- Requirement: autopilot-plan.sh 引数フォーマット明記 ---"

# Scenario: スペース区切りフォーマット明記
# WHEN: Pilot が SKILL.md の Step 1 を参照して autopilot-plan.sh を呼び出す
# THEN: --issues "342 323" のようにスペース区切り形式で実行し、カンマ区切りによる parse error が発生しない

# Test: スペース区切りの --issues 例が SKILL.md に記載されている
test_issues_space_separated_example() {
  assert_file_exists "$SKILL_MD" || return 1
  # Example like: --issues "342 323" or --issues "84 78 83"
  assert_file_contains "$SKILL_MD" '--issues\s+"[0-9]+ [0-9]+'
}

run_test "Step 1: --issues スペース区切り例が記載されている" test_issues_space_separated_example

# Edge case: カンマ区切りの --issues 例が SKILL.md に含まれていない（誤例が混入していない）
test_issues_no_comma_example() {
  assert_file_exists "$SKILL_MD" || return 1
  # The SKILL.md should NOT instruct --issues "342,323" (comma-separated)
  # Note: --explicit "19,18 → 20 → 23" uses commas legitimately; only --issues is checked
  assert_file_not_contains "$SKILL_MD" '--issues\s+"[0-9]+,[0-9]+'
}

run_test "Step 1 [edge: --issues にカンマ区切り例が混入していない]" test_issues_no_comma_example

# Scenario: --project-dir 必須明記
# WHEN: Pilot が autopilot-plan.sh を呼び出す
# THEN: --project-dir "$PROJECT_DIR" または --repo-mode オプションが引数に含まれる

# Test: --project-dir の記述が SKILL.md に存在する
test_project_dir_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '--project-dir'
}

run_test "Step 1: --project-dir が SKILL.md に記載されている" test_project_dir_mentioned

# Test: autopilot-plan.sh 呼び出し例に --project-dir が含まれている
test_plan_call_includes_project_dir() {
  assert_file_exists "$SKILL_MD" || return 1
  # The call example must show --project-dir together with autopilot-plan.sh
  assert_file_contains "$SKILL_MD" 'autopilot-plan\.sh.*--project-dir|--project-dir.*autopilot-plan\.sh'
}

run_test "Step 1: autopilot-plan.sh 呼び出し例に --project-dir が含まれる" test_plan_call_includes_project_dir

# Edge case: --repo-mode も必須オプションとして言及されている
test_repo_mode_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '--repo-mode'
}

run_test "Step 1 [edge: --repo-mode も必須オプションとして言及されている]" test_repo_mode_mentioned

# Edge case: Step 1 の autopilot-plan.sh 例が不完全（--project-dir 省略）でない
test_plan_example_complete() {
  assert_file_exists "$SKILL_MD" || return 1
  # If autopilot-plan.sh is mentioned in a code block, --project-dir must follow
  # This checks that no bare "autopilot-plan.sh --issues" appears without --project-dir nearby
  # We verify the bash example block contains both --issues and --project-dir
  python3 - "${PROJECT_ROOT}/${SKILL_MD}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    content = f.read()

# Find code blocks containing autopilot-plan.sh
blocks = re.findall(r'```bash(.*?)```', content, re.DOTALL)
for block in blocks:
    if 'autopilot-plan.sh' in block and '--issues' in block:
        if '--project-dir' not in block and '--repo-mode' not in block:
            print(f"autopilot-plan.sh --issues block lacks --project-dir/--repo-mode", file=sys.stderr)
            sys.exit(1)
sys.exit(0)
PYEOF
}

run_test "Step 1 [edge: autopilot-plan.sh コードブロック例に --project-dir が含まれる]" test_plan_example_complete

# =============================================================================
# Requirement: python-env.sh source 指示追加
# =============================================================================
echo ""
echo "--- Requirement: python-env.sh source 指示追加 ---"

# Scenario: PYTHONPATH 設定
# WHEN: Pilot が SKILL.md の Step 3 を参照して python3 -m twl.autopilot.session を呼び出す
# THEN: 事前に source "${CLAUDE_PLUGIN_ROOT}/scripts/lib/python-env.sh" が実行されており ModuleNotFoundError が発生しない

# Test: python-env.sh の source 指示が SKILL.md に存在する
test_python_env_source_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'python-env\.sh'
}

run_test "Step 3: python-env.sh への言及が SKILL.md に存在する" test_python_env_source_mentioned

# Test: source コマンドを伴う python-env.sh 指示がある
test_python_env_source_instruction() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'source.*python-env\.sh'
}

run_test "Step 3: source python-env.sh の指示が記載されている" test_python_env_source_instruction

# Test: CLAUDE_PLUGIN_ROOT または scripts/lib パスが含まれている
test_python_env_path_correct() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'CLAUDE_PLUGIN_ROOT.*python-env\.sh|scripts/lib/python-env\.sh'
}

run_test "Step 3: python-env.sh のパス（CLAUDE_PLUGIN_ROOT または scripts/lib）が正しい" test_python_env_path_correct

# Scenario: モジュール解決
# WHEN: source python-env.sh が実行される
# THEN: PYTHONPATH に cli/twl/src が追加され twl.autopilot モジュールが正しく解決される

# Test: python-env.sh 自体（実装）が cli/twl/src を PYTHONPATH に追加することを確認
test_python_env_sh_sets_pythonpath() {
  local impl="scripts/lib/python-env.sh"
  assert_file_exists "$impl" || return 1
  assert_file_contains "$impl" 'cli/twl/src'
}

run_test "python-env.sh [edge: scripts/lib/python-env.sh が cli/twl/src を参照する]" test_python_env_sh_sets_pythonpath

# Test: PYTHONPATH への追加ロジックが python-env.sh に存在する
test_python_env_sh_exports_pythonpath() {
  local impl="scripts/lib/python-env.sh"
  assert_file_exists "$impl" || return 1
  assert_file_contains "$impl" 'PYTHONPATH'
}

run_test "python-env.sh [edge: PYTHONPATH 設定ロジックが存在する]" test_python_env_sh_exports_pythonpath

# Edge case: Step 3 が python3 -m twl.autopilot への言及を含む場合 python-env.sh が先行する
test_python_env_precedes_module_call() {
  assert_file_exists "$SKILL_MD" || return 1
  python3 - "${PROJECT_ROOT}/${SKILL_MD}" <<'PYEOF'
import sys, re

with open(sys.argv[1]) as f:
    content = f.read()

# Locate Step 3 section
step3_match = re.search(r'## Step 3[^#]*', content, re.DOTALL)
if not step3_match:
    sys.exit(0)  # Step 3 not found - skip

step3_text = step3_match.group(0)

# If twl.autopilot.session is mentioned in Step 3, python-env.sh must precede it
if 'twl.autopilot' in step3_text or 'python3 -m' in step3_text:
    env_pos = step3_text.find('python-env.sh')
    module_pos = step3_text.find('python3 -m')
    if module_pos == -1:
        module_pos = step3_text.find('twl.autopilot')
    if env_pos == -1 or (module_pos != -1 and env_pos > module_pos):
        print("python-env.sh source must precede python3 -m call in Step 3", file=sys.stderr)
        sys.exit(1)

sys.exit(0)
PYEOF
}

run_test "Step 3 [edge: python-env.sh の source が python3 -m 呼び出しより前に記載されている]" test_python_env_precedes_module_call

# =============================================================================
# Requirement: orchestrator --session-file 絶対パス例明示
# =============================================================================
echo ""
echo "--- Requirement: orchestrator --session-file 絶対パス例明示 ---"

# Scenario: 絶対パスによる orchestrator 起動
# WHEN: Pilot が SKILL.md を参照して orchestrator を呼び出す
# THEN: --session-file "${AUTOPILOT_DIR}/session.json" のように絶対パス形式で指定されパスエラーが発生しない

# Test: orchestrator の --session-file または --session 引数の記述が SKILL.md にある
test_orchestrator_session_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'autopilot-orchestrator.*--session|orchestrator.*--session'
}

run_test "Step 4: orchestrator --session 引数が SKILL.md に記載されている" test_orchestrator_session_mentioned

# Test: AUTOPILOT_DIR 変数を使った session.json 絶対パス例が含まれる
test_orchestrator_absolute_session_path() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'AUTOPILOT_DIR.*session\.json|\$\{AUTOPILOT_DIR\}/session\.json|\$AUTOPILOT_DIR/session\.json'
}

run_test "Step 4: orchestrator に AUTOPILOT_DIR を使った session.json 絶対パスが示されている" test_orchestrator_absolute_session_path

# Edge case: 相対パス ./session.json を直接渡す例が SKILL.md に含まれていない
test_no_relative_session_path() {
  assert_file_exists "$SKILL_MD" || return 1
  # Relative path like --session ./session.json or --session session.json (without variable)
  assert_file_not_contains "$SKILL_MD" '--session\s+\./session\.json|--session\s+session\.json[^/]'
}

run_test "Step 4 [edge: 相対パス ./session.json の誤例が含まれていない]" test_no_relative_session_path

# Edge case: orchestrator 呼び出し例に --autopilot-dir も含まれている（session path の親として一貫）
test_orchestrator_includes_autopilot_dir() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'autopilot-orchestrator.*--autopilot-dir|--autopilot-dir.*autopilot-orchestrator'
}

run_test "Step 4 [edge: orchestrator 例に --autopilot-dir が含まれている（絶対パスの一貫性）]" test_orchestrator_includes_autopilot_dir

# Edge case: AUTOPILOT_DIR が SKILL.md 内で定義・説明されている
test_autopilot_dir_defined() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'AUTOPILOT_DIR'
}

run_test "AUTOPILOT_DIR [edge: SKILL.md で AUTOPILOT_DIR が定義または説明されている]" test_autopilot_dir_defined

# =============================================================================
# Cross-cutting: 既存の正常動作への非デグレード検証
# =============================================================================
echo ""
echo "--- Cross-cutting: 既存動作への非デグレード検証 ---"

# Test: Step 0-5 構成が変更後も維持されている
test_step_structure_intact() {
  assert_file_exists "$SKILL_MD" || return 1
  for step in 0 1 2 3 4 5; do
    assert_file_contains "$SKILL_MD" "Step\s*${step}" || return 1
  done
  return 0
}

run_test "非デグレード: Step 0-5 の構成が維持されている" test_step_structure_intact

# Test: --auto フラグの記述が残っている
test_auto_flag_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '\-\-auto'
}

run_test "非デグレード: --auto フラグの記述が保持されている" test_auto_flag_preserved

# Test: 不変条件の参照が残っている
test_invariants_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '不変条件'
}

run_test "非デグレード: 不変条件の参照が保持されている" test_invariants_preserved

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
