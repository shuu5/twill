#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: deps-yaml-integration.md
# Generated from: openspec/changes/c-4-scripts-migration/specs/deps-yaml-integration.md
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
  ((SKIP++)) || true
}

DEPS_YAML="deps.yaml"
WORKTREE_CREATE_CMD="commands/worktree-create.md"
PROJECT_CREATE_CMD="commands/project-create.md"
PROJECT_MIGRATE_CMD="commands/project-migrate.md"

# 移植対象の全16スクリプト
MIGRATED_SCRIPTS=(
  "autopilot-plan"
  "autopilot-should-skip"
  "merge-gate-init"
  "merge-gate-execute"
  "merge-gate-issues"
  "worktree-create"
  "branch-create"
  "project-create"
  "project-migrate"
  "classify-failure"
  "parse-issue-ac"
  "session-audit"
  "check-db-migration"
  "ecc-monitor"
  "codex-review"
  "create-harness-issue"
)

# =============================================================================
# Requirement: deps.yaml への script エントリ追加
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml への script エントリ追加 ---"

# Scenario: 全 script が deps.yaml に登録される (line 8)
# WHEN: 移植完了後に deps.yaml を確認する
# THEN: 既存 10 scripts + 移植 16 scripts = 計 26 scripts が scripts セクションに登録されている

test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml が有効な YAML である" test_deps_yaml_valid

test_deps_yaml_scripts_section() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if not scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に scripts セクションが存在する" test_deps_yaml_scripts_section

test_deps_yaml_total_scripts_count() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
count = len(scripts)
if count < 26:
    print(f'Expected >= 26 scripts, got {count}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に 26 以上の script が登録されている" test_deps_yaml_total_scripts_count

# 移植対象の各スクリプトが個別に登録されていることを検証
test_deps_yaml_has_autopilot_plan() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'autopilot-plan' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に autopilot-plan が登録されている" test_deps_yaml_has_autopilot_plan

test_deps_yaml_has_autopilot_should_skip() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'autopilot-should-skip' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に autopilot-should-skip が登録されている" test_deps_yaml_has_autopilot_should_skip

test_deps_yaml_has_merge_gate_init() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'merge-gate-init' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に merge-gate-init が登録されている" test_deps_yaml_has_merge_gate_init

test_deps_yaml_has_merge_gate_execute() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'merge-gate-execute' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に merge-gate-execute が登録されている" test_deps_yaml_has_merge_gate_execute

test_deps_yaml_has_merge_gate_issues() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'merge-gate-issues' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に merge-gate-issues が登録されている" test_deps_yaml_has_merge_gate_issues

test_deps_yaml_has_worktree_create() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'worktree-create' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に worktree-create が登録されている" test_deps_yaml_has_worktree_create

test_deps_yaml_has_branch_create() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'branch-create' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に branch-create が登録されている" test_deps_yaml_has_branch_create

test_deps_yaml_has_project_create() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'project-create' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に project-create が登録されている" test_deps_yaml_has_project_create

test_deps_yaml_has_project_migrate() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'project-migrate' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に project-migrate が登録されている" test_deps_yaml_has_project_migrate

test_deps_yaml_has_classify_failure() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'classify-failure' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に classify-failure が登録されている" test_deps_yaml_has_classify_failure

test_deps_yaml_has_parse_issue_ac() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'parse-issue-ac' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に parse-issue-ac が登録されている" test_deps_yaml_has_parse_issue_ac

test_deps_yaml_has_session_audit() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'session-audit' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に session-audit が登録されている" test_deps_yaml_has_session_audit

test_deps_yaml_has_check_db_migration() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'check-db-migration' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に check-db-migration が登録されている" test_deps_yaml_has_check_db_migration

test_deps_yaml_has_ecc_monitor() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'ecc-monitor' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に ecc-monitor が登録されている" test_deps_yaml_has_ecc_monitor

test_deps_yaml_has_codex_review() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'codex-review' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に codex-review が登録されている" test_deps_yaml_has_codex_review

test_deps_yaml_has_create_harness_issue() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'create-harness-issue' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に create-harness-issue が登録されている" test_deps_yaml_has_create_harness_issue

# Scenario: script パスの一貫性 (line 12)
# WHEN: deps.yaml の script エントリの path を確認する
# THEN: 全て scripts/<name>.sh または scripts/<name>.py の形式である

test_deps_yaml_path_consistency() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
for name, entry in scripts.items():
    path = entry.get('path', '') if isinstance(entry, dict) else entry
    if not (path.startswith('scripts/') and (path.endswith('.sh') or path.endswith('.py'))):
        print(f'Invalid path for {name}: {path}', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の全 script パスが scripts/<name>.sh|.py 形式である" test_deps_yaml_path_consistency

# Edge case: 各エントリに description フィールドがある
test_deps_yaml_description_fields() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
missing = []
for name, entry in scripts.items():
    if isinstance(entry, dict) and not entry.get('description'):
        missing.append(name)
if missing:
    print(f'Missing description: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml [edge: 全 script に description がある]" test_deps_yaml_description_fields

# Edge case: 各エントリに type: script フィールドがある
test_deps_yaml_type_script() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
missing = []
for name, entry in scripts.items():
    if isinstance(entry, dict) and entry.get('type') != 'script':
        missing.append(name)
if missing:
    print(f'Missing type=script: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml [edge: 全 script に type: script がある]" test_deps_yaml_type_script

# =============================================================================
# Requirement: COMMAND.md のスクリプトパス更新
# =============================================================================
echo ""
echo "--- Requirement: COMMAND.md のスクリプトパス更新 ---"

# Scenario: worktree-create COMMAND.md のパス更新 (line 22)
# WHEN: commands/worktree-create.md を確認する
# THEN: スクリプト呼び出しが相対パスを使用している

test_worktree_create_cmd_exists() {
  assert_file_exists "$WORKTREE_CREATE_CMD"
}
run_test "commands/worktree-create.md が存在する" test_worktree_create_cmd_exists

test_worktree_create_cmd_no_hardcoded_path() {
  assert_file_exists "$WORKTREE_CREATE_CMD" || return 1
  # 旧パス $HOME/.claude/plugins/dev/scripts/ が使われていないこと
  assert_file_not_contains "$WORKTREE_CREATE_CMD" '\$HOME/\.claude/plugins/dev/scripts' || return 1
  assert_file_not_contains "$WORKTREE_CREATE_CMD" '~/\.claude/plugins/dev/scripts' || return 1
  return 0
}
run_test "worktree-create COMMAND.md に旧固定パス参照がない" test_worktree_create_cmd_no_hardcoded_path

test_worktree_create_cmd_relative_path() {
  assert_file_exists "$WORKTREE_CREATE_CMD" || return 1
  # 相対パスまたは SCRIPT_DIR ベースのパス使用
  assert_file_contains "$WORKTREE_CREATE_CMD" '(SCRIPT_DIR|scripts/worktree-create|\.\./)' || return 1
  return 0
}
run_test "worktree-create COMMAND.md が相対パスを使用している" test_worktree_create_cmd_relative_path

# Edge case: project-create COMMAND.md のパス更新
test_project_create_cmd_no_hardcoded_path() {
  assert_file_exists "$PROJECT_CREATE_CMD" || return 1
  assert_file_not_contains "$PROJECT_CREATE_CMD" '\$HOME/\.claude/plugins/dev/scripts' || return 1
  assert_file_not_contains "$PROJECT_CREATE_CMD" '~/\.claude/plugins/dev/scripts' || return 1
  return 0
}
run_test "project-create COMMAND.md [edge: 旧固定パス参照がない]" test_project_create_cmd_no_hardcoded_path

# Edge case: project-migrate COMMAND.md のパス更新
test_project_migrate_cmd_no_hardcoded_path() {
  assert_file_exists "$PROJECT_MIGRATE_CMD" || return 1
  assert_file_not_contains "$PROJECT_MIGRATE_CMD" '\$HOME/\.claude/plugins/dev/scripts' || return 1
  assert_file_not_contains "$PROJECT_MIGRATE_CMD" '~/\.claude/plugins/dev/scripts' || return 1
  return 0
}
run_test "project-migrate COMMAND.md [edge: 旧固定パス参照がない]" test_project_migrate_cmd_no_hardcoded_path

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "deps-yaml-integration-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
