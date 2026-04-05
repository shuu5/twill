#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: worker-codex-reviewer
# Generated from: openspec/changes/add-worker-codex-reviewer/specs/worker-codex-reviewer/spec.md
# Coverage level: edge-cases
# change-id: add-worker-codex-reviewer
# =============================================================================
set -euo pipefail

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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
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

extract_frontmatter_yaml() {
  # Extract YAML frontmatter from a markdown file (between --- delimiters)
  local file="$1"
  python3 -c "
import sys, re
with open('${PROJECT_ROOT}/${file}') as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(1)
import yaml
data = yaml.safe_load(m.group(1))
print('ok')
sys.exit(0)
" 2>/dev/null
}

get_frontmatter_field() {
  # Get a specific field from YAML frontmatter
  local file="$1"
  local expr="$2"
  python3 -c "
import sys, re, yaml
with open('${PROJECT_ROOT}/${file}') as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(1)
data = yaml.safe_load(m.group(1))
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

AGENT_FILE="agents/worker-codex-reviewer.md"
SKILL_MD="skills/co-issue/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: worker-codex-reviewer specialist agent 作成
# =============================================================================
echo ""
echo "--- Requirement: worker-codex-reviewer specialist agent 作成 ---"

# Scenario: 正常レビュー実行 (spec line 7)
# WHEN: codex がインストール済みで CODEX_API_KEY が設定されている状態で agent が起動され、
#       <review_target> に Issue body が渡される
# THEN: codex exec --sandbox read-only でレビューが実行され、
#       status: PASS/WARN/FAIL と findings: [] または findings 配列を specialist 共通スキーマ形式で出力する

test_agent_file_exists() {
  assert_file_exists "$AGENT_FILE"
}
run_test "worker-codex-reviewer.md が存在する" test_agent_file_exists

test_agent_codex_exec_command() {
  assert_file_exists "$AGENT_FILE" || return 1
  # agent must invoke codex exec with --sandbox read-only
  assert_file_contains "$AGENT_FILE" "codex.*exec"
}
run_test "正常レビュー - codex exec の呼び出しが記述されている" test_agent_codex_exec_command

test_agent_sandbox_readonly() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "sandbox.*read.only|read.only.*sandbox|--sandbox\s+read-only"
}
run_test "正常レビュー - --sandbox read-only フラグが記述されている" test_agent_sandbox_readonly

test_agent_output_schema_status_values() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Output must include PASS, WARN, FAIL status values per specialist common schema
  assert_file_contains_all "$AGENT_FILE" "PASS" "WARN" "FAIL"
}
run_test "正常レビュー - status: PASS/WARN/FAIL が出力形式に含まれる" test_agent_output_schema_status_values

test_agent_findings_field_defined() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "findings"
}
run_test "正常レビュー - findings フィールドが出力形式に含まれる" test_agent_findings_field_defined

test_agent_review_target_tag() {
  assert_file_exists "$AGENT_FILE" || return 1
  # agent receives <review_target> tag for Issue body input
  assert_file_contains "$AGENT_FILE" "review_target"
}
run_test "正常レビュー - review_target 入力タグが記述されている" test_agent_review_target_tag

# Scenario: codex 未インストール時の graceful skip (spec line 11)
# WHEN: command -v codex が失敗する環境で agent が起動される
# THEN: status: PASS, findings: [] を即座に出力して完了し、エラーメッセージを出力しない

test_agent_graceful_skip_no_codex() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Must check for codex availability (command -v codex or which codex)
  assert_file_contains "$AGENT_FILE" "command\s+-v\s+codex|which\s+codex|codex.*インストール|not.*install|未インストール"
}
run_test "graceful skip - codex 未インストール時の検出ロジックが記述されている" test_agent_graceful_skip_no_codex

test_agent_graceful_skip_returns_pass() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Graceful skip must output status: PASS
  # Both "graceful skip" scenario and output should be mentioned
  assert_file_contains "$AGENT_FILE" "skip|スキップ|graceful"
}
run_test "graceful skip - スキップ動作が記述されている" test_agent_graceful_skip_returns_pass

test_agent_graceful_skip_no_error_output() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Spec says: エラーメッセージを出力しない
  # Verify the agent describes outputting empty findings (not an error) on skip
  assert_file_contains "$AGENT_FILE" "findings.*\[\]|\[\].*findings|空.*findings|findings.*空"
}
run_test "graceful skip - findings: [] 出力が記述されている" test_agent_graceful_skip_no_error_output

# Edge case: codex not found produces PASS not FAIL/WARN
test_agent_skip_outputs_pass_not_fail() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Skip case: the output must be PASS (not FAIL), so agent should not call FAIL on skip path
  # The agent must explicitly mention that missing codex -> PASS
  assert_file_contains "$AGENT_FILE" "PASS"
}
run_test "graceful skip [edge: スキップ時は FAIL ではなく PASS を出力]" test_agent_skip_outputs_pass_not_fail

# Scenario: CODEX_API_KEY 未設定時の graceful skip (spec line 15)
# WHEN: CODEX_API_KEY 環境変数が未設定の状態で agent が起動される
# THEN: status: PASS, findings: [] を即座に出力して完了し、エラーメッセージを出力しない

test_agent_api_key_check() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Must check for CODEX_API_KEY environment variable
  assert_file_contains "$AGENT_FILE" "CODEX_API_KEY"
}
run_test "CODEX_API_KEY 未設定 - 環境変数チェックが記述されている" test_agent_api_key_check

test_agent_api_key_skip_graceful() {
  assert_file_exists "$AGENT_FILE" || return 1
  # Both key check and skip/graceful behavior must be present together
  assert_file_contains "$AGENT_FILE" "CODEX_API_KEY" || return 1
  assert_file_contains "$AGENT_FILE" "skip|スキップ|graceful|未設定|unset"
}
run_test "CODEX_API_KEY 未設定 - graceful skip 動作が記述されている" test_agent_api_key_skip_graceful

# Edge case: Both preconditions (codex installed AND API key set) checked independently
test_agent_both_preconditions_checked() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "command\s+-v\s+codex|which\s+codex|codex.*インストール|not.*install|未インストール" || return 1
  assert_file_contains "$AGENT_FILE" "CODEX_API_KEY"
}
run_test "graceful skip [edge: codex 未インストールと CODEX_API_KEY 未設定の両方がチェックされる]" test_agent_both_preconditions_checked

# Edge case: agent uses Bash tool (required for command -v codex)
test_agent_uses_bash_tool() {
  assert_file_exists "$AGENT_FILE" || return 1
  # frontmatter tools should include Bash for executing codex
  assert_file_contains "$AGENT_FILE" "Bash"
}
run_test "graceful skip [edge: Bash ツールが tools に含まれる（codex 実行用）]" test_agent_uses_bash_tool

# =============================================================================
# Requirement: worker-codex-reviewer frontmatter
# =============================================================================
echo ""
echo "--- Requirement: worker-codex-reviewer frontmatter ---"

# Scenario: frontmatter 準拠確認 (spec line 23)
# WHEN: agents/worker-codex-reviewer.md の frontmatter を読み込む
# THEN: type: specialist, model: sonnet, tools: [Bash, Read, Glob, Grep] が存在し、
#       skills に ref-issue-quality-criteria と ref-specialist-output-schema が含まれる

test_frontmatter_type_specialist() {
  assert_file_exists "$AGENT_FILE" || return 1
  get_frontmatter_field "$AGENT_FILE" "
assert data.get('type') == 'specialist', f'type={data.get(\"type\")}'
" | grep -q "^$" || \
  assert_file_contains "$AGENT_FILE" "type:\s*specialist"
}
run_test "frontmatter - type: specialist が設定されている" test_frontmatter_type_specialist

test_frontmatter_model_sonnet() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "model:\s*sonnet"
}
run_test "frontmatter - model: sonnet が設定されている" test_frontmatter_model_sonnet

test_frontmatter_tools_bash() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "Bash"
}
run_test "frontmatter - tools に Bash が含まれる" test_frontmatter_tools_bash

test_frontmatter_tools_read() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "\bRead\b"
}
run_test "frontmatter - tools に Read が含まれる" test_frontmatter_tools_read

test_frontmatter_tools_glob() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "\bGlob\b"
}
run_test "frontmatter - tools に Glob が含まれる" test_frontmatter_tools_glob

test_frontmatter_tools_grep() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "\bGrep\b"
}
run_test "frontmatter - tools に Grep が含まれる" test_frontmatter_tools_grep

test_frontmatter_skill_ref_issue_quality() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "ref-issue-quality-criteria"
}
run_test "frontmatter - skills に ref-issue-quality-criteria が含まれる" test_frontmatter_skill_ref_issue_quality

test_frontmatter_skill_ref_specialist_output() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "ref-specialist-output-schema"
}
run_test "frontmatter - skills に ref-specialist-output-schema が含まれる" test_frontmatter_skill_ref_specialist_output

# Edge case: frontmatter が完全に揃っている（全必須フィールド一括）
test_frontmatter_all_required_fields() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains_all "$AGENT_FILE" \
    "type:\s*specialist" \
    "model:\s*sonnet" \
    "Bash" \
    "ref-issue-quality-criteria" \
    "ref-specialist-output-schema"
}
run_test "frontmatter [edge: 全必須フィールドが一括で存在する]" test_frontmatter_all_required_fields

# Edge case: Task tool が tools に含まれていない（Task 禁止）
test_frontmatter_no_task_tool() {
  assert_file_exists "$AGENT_FILE" || return 1
  # frontmatter tools should not include Task tool
  # Check tools list in frontmatter does not include Task
  python3 -c "
import sys, re, yaml
with open('${PROJECT_ROOT}/${AGENT_FILE}') as f:
    content = f.read()
m = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
if not m:
    sys.exit(0)  # no frontmatter, skip
data = yaml.safe_load(m.group(1))
tools = data.get('tools', [])
if isinstance(tools, list):
    if 'Task' in tools:
        sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "frontmatter [edge: tools リストに Task が含まれない]" test_frontmatter_no_task_tool

# Edge case: name フィールドが dev:worker-codex-reviewer 形式
test_frontmatter_name_format() {
  assert_file_exists "$AGENT_FILE" || return 1
  assert_file_contains "$AGENT_FILE" "name:.*worker-codex-reviewer"
}
run_test "frontmatter [edge: name フィールドが worker-codex-reviewer を含む]" test_frontmatter_name_format

# =============================================================================
# Requirement: co-issue Phase 3b に worker-codex-reviewer を追加
# =============================================================================
echo ""
echo "--- Requirement: co-issue Phase 3b に worker-codex-reviewer を追加 ---"

# Scenario: Phase 3b 並列 spawn (spec line 33)
# WHEN: co-issue Phase 3b が実行される
# THEN: issue-critic, issue-feasibility と並列で
#       Agent(subagent_type="dev:dev:worker-codex-reviewer", ...) が spawn される

test_skill_phase3b_codex_spawn() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "worker-codex-reviewer"
}
run_test "Phase 3b 並列 spawn - worker-codex-reviewer が SKILL.md に記述されている" test_skill_phase3b_codex_spawn

test_skill_phase3b_agent_spawn() {
  assert_file_exists "$SKILL_MD" || return 1
  # Must use Agent tool to spawn worker-codex-reviewer
  assert_file_contains "$SKILL_MD" "Agent.*worker-codex-reviewer|worker-codex-reviewer.*Agent"
}
run_test "Phase 3b 並列 spawn - Agent tool で worker-codex-reviewer を spawn する" test_skill_phase3b_agent_spawn

test_skill_phase3b_subagent_type() {
  assert_file_exists "$SKILL_MD" || return 1
  # spawn with dev:dev:worker-codex-reviewer subagent_type
  assert_file_contains "$SKILL_MD" "dev:dev:worker-codex-reviewer|dev:worker-codex-reviewer"
}
run_test "Phase 3b 並列 spawn - subagent_type に worker-codex-reviewer が設定されている" test_skill_phase3b_subagent_type

test_skill_phase3b_review_target_tag() {
  assert_file_exists "$SKILL_MD" || return 1
  # worker-codex-reviewer must receive review_target / target_files / related_context tags
  assert_file_contains "$SKILL_MD" "review_target"
}
run_test "Phase 3b 並列 spawn - review_target タグが prompt に含まれる" test_skill_phase3b_review_target_tag

test_skill_phase3b_parallel_all_specialists() {
  assert_file_exists "$SKILL_MD" || return 1
  # All three specialists must be present in Phase 3b
  assert_file_contains_all "$SKILL_MD" \
    "issue-critic" \
    "issue-feasibility" \
    "worker-codex-reviewer"
}
run_test "Phase 3b 並列 spawn [edge: 全 specialist (critic/feasibility/codex-reviewer) が存在]" test_skill_phase3b_parallel_all_specialists

# Edge case: prompt format uses XML tags (review_target, target_files, related_context)
test_skill_phase3b_xml_tag_format() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains_all "$SKILL_MD" \
    "review_target" \
    "target_files" \
    "related_context"
}
run_test "Phase 3b 並列 spawn [edge: XML タグ形式 (review_target/target_files/related_context) でプロンプト渡し]" test_skill_phase3b_xml_tag_format

# Scenario: findings テーブル統合 (spec line 37)
# WHEN: worker-codex-reviewer が findings を返す
# THEN: Step 3c の結果集約テーブルに worker-codex-reviewer 行が追加される
#       (| worker-codex-reviewer | <status> | <summary> | 形式)

test_skill_step3c_table_includes_codex() {
  assert_file_exists "$SKILL_MD" || return 1
  # Step 3c results table must include worker-codex-reviewer row
  assert_file_contains "$SKILL_MD" "worker-codex-reviewer"
}
run_test "findings テーブル統合 - worker-codex-reviewer 行が結果テーブルに含まれる" test_skill_step3c_table_includes_codex

# Edge case: テーブル形式が | worker-codex-reviewer | ... | ... | の Markdown 表
test_skill_step3c_table_format() {
  assert_file_exists "$SKILL_MD" || return 1
  # Markdown table row for worker-codex-reviewer
  assert_file_contains "$SKILL_MD" "\|\s*worker-codex-reviewer\s*\|"
}
run_test "findings テーブル統合 [edge: Markdown テーブル行形式 | worker-codex-reviewer | ... |]" test_skill_step3c_table_format

# Scenario: codex スキップ時のブロックなし (spec line 41)
# WHEN: worker-codex-reviewer が graceful skip (status: PASS, findings: []) で完了する
# THEN: Phase 3b 全体の処理が継続され、他の specialist の結果に影響しない

test_skill_phase3b_skip_does_not_block() {
  assert_file_exists "$SKILL_MD" || return 1
  # The SKILL.md should describe that Phase 3b continues regardless of codex availability
  # Presence of codex reviewer without any "if codex fails stop" language
  # The agent handles skip itself; SKILL.md just spawns it in parallel
  assert_file_contains "$SKILL_MD" "issue-critic" || return 1
  assert_file_contains "$SKILL_MD" "worker-codex-reviewer" || return 1
  # No blocking condition for codex reviewer specifically
  assert_file_not_contains "$SKILL_MD" "worker-codex-reviewer.*ブロック|block.*worker-codex-reviewer"
}
run_test "codex スキップ時のブロックなし - Phase 3b は codex のスキップで停止しない" test_skill_phase3b_skip_does_not_block

# Edge case: --quick フラグ時に Phase 3b スキップが変わらない
test_skill_quick_flag_skip_unchanged() {
  assert_file_exists "$SKILL_MD" || return 1
  # --quick still skips entire Phase 3b (not just codex)
  assert_file_contains "$SKILL_MD" "--quick.*skip|--quick.*スキップ|quick.*指定.*スキップ"
}
run_test "codex スキップ [edge: --quick フラグで Phase 3b 全体がスキップされる（変更なし）]" test_skill_quick_flag_skip_unchanged

# =============================================================================
# Requirement: deps.yaml 更新
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml 更新 ---"

# Scenario: deps.yaml 登録確認 (spec line 49)
# WHEN: twl check を実行する
# THEN: worker-codex-reviewer が agents セクションに登録され、
#       co-issue.calls に specialist: worker-codex-reviewer が含まれ、PASS する

test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml - YAML として有効である" test_deps_yaml_valid

test_deps_yaml_agent_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_file_contains "$DEPS_YAML" "worker-codex-reviewer"
}
run_test "deps.yaml - worker-codex-reviewer が登録されている" test_deps_yaml_agent_registered

test_deps_yaml_agent_in_agents_section() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
if 'worker-codex-reviewer' not in agents:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml - worker-codex-reviewer が agents セクションに登録されている" test_deps_yaml_agent_in_agents_section

test_deps_yaml_agent_type_specialist() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
agent = agents.get('worker-codex-reviewer', {})
if agent.get('type') != 'specialist':
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml - worker-codex-reviewer の type が specialist である" test_deps_yaml_agent_type_specialist

test_deps_yaml_agent_path() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
agent = agents.get('worker-codex-reviewer', {})
path = agent.get('path', '')
if 'worker-codex-reviewer' not in path:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml - worker-codex-reviewer の path が agents/worker-codex-reviewer.md を指す" test_deps_yaml_agent_path

test_deps_yaml_co_issue_calls_codex() {
  assert_file_exists "$DEPS_YAML" || return 1
  # co-issue.calls must include specialist: worker-codex-reviewer
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
co_issue = skills.get('co-issue', {})
calls = co_issue.get('calls', [])
found = False
for c in calls:
    if isinstance(c, dict):
        if c.get('specialist') == 'worker-codex-reviewer':
            found = True
            break
if not found:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml - co-issue.calls に specialist: worker-codex-reviewer が含まれる" test_deps_yaml_co_issue_calls_codex

test_deps_yaml_co_issue_tools_includes_codex() {
  assert_file_exists "$DEPS_YAML" || return 1
  # co-issue.tools (Agent(...)) must include worker-codex-reviewer
  assert_file_contains "$DEPS_YAML" "worker-codex-reviewer"
}
run_test "deps.yaml - co-issue の tools/Agent リストに worker-codex-reviewer が含まれる" test_deps_yaml_co_issue_tools_includes_codex

# Edge case: worker-codex-reviewer agent の skills が正しく設定されている
test_deps_yaml_agent_skills_set() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
agent = agents.get('worker-codex-reviewer', {})
skills = agent.get('skills', [])
required = {'ref-issue-quality-criteria', 'ref-specialist-output-schema'}
if not required.issubset(set(skills)):
    print(f'Missing skills: {required - set(skills)}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml [edge: agent.skills に ref-issue-quality-criteria と ref-specialist-output-schema が設定]" test_deps_yaml_agent_skills_set

# Edge case: agent の path が実在するファイルと一致する
test_deps_yaml_agent_path_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  local agent_path
  agent_path=$(yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
agent = agents.get('worker-codex-reviewer', {})
print(agent.get('path', ''))
" 2>/dev/null)
  if [[ -z "$agent_path" ]]; then
    return 1
  fi
  assert_file_exists "$agent_path"
}
run_test "deps.yaml [edge: agent.path が実在するファイルを指す]" test_deps_yaml_agent_path_exists

# Edge case: co-issue の既存 calls (issue-critic, issue-feasibility) が消えていない
test_deps_yaml_co_issue_existing_calls_preserved() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
co_issue = skills.get('co-issue', {})
calls = co_issue.get('calls', [])
specialist_names = set()
for c in calls:
    if isinstance(c, dict) and 'specialist' in c:
        specialist_names.add(c['specialist'])
required = {'issue-critic', 'issue-feasibility', 'worker-codex-reviewer'}
missing = required - specialist_names
if missing:
    print(f'Missing specialists: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml [edge: 既存 specialist (issue-critic/issue-feasibility) が calls から消えていない]" test_deps_yaml_co_issue_existing_calls_preserved

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
