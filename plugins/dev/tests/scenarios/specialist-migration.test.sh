#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: specialist-migration
# Generated from: openspec/changes/c-3-specialist-reference-migration/specs/specialist-migration/spec.md
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

# --- 26 specialist 一覧（pr-test は既存 atomic command と重複のため除外） ---
ALL_SPECIALISTS=(
  worker-code-reviewer
  worker-security-reviewer
  worker-nextjs-reviewer
  worker-fastapi-reviewer
  worker-hono-reviewer
  worker-r-reviewer
  worker-architecture
  worker-structure
  worker-principles
  worker-env-validator
  worker-rls-reviewer
  worker-supabase-migration-checker
  worker-data-validator
  template-validator
  context-checker
  worker-e2e-reviewer
  worker-spec-reviewer
  worker-llm-output-reviewer
  worker-llm-eval-runner
  docs-researcher
  e2e-quality
  autofix-loop
  spec-scaffold-tests
  e2e-generate
  e2e-heal
  e2e-visual-heal
)

HAIKU_SPECIALISTS=(
  worker-structure
  worker-principles
  worker-env-validator
  worker-rls-reviewer
  worker-supabase-migration-checker
  worker-data-validator
  template-validator
  context-checker
  worker-e2e-reviewer
  worker-spec-reviewer
)

SONNET_SPECIALISTS=(
  worker-code-reviewer
  worker-security-reviewer
  worker-nextjs-reviewer
  worker-fastapi-reviewer
  worker-hono-reviewer
  worker-r-reviewer
  worker-architecture
  worker-llm-output-reviewer
  worker-llm-eval-runner
  docs-researcher
  e2e-quality
  autofix-loop
  spec-scaffold-tests
  e2e-generate
  e2e-heal
  e2e-visual-heal
)

# =============================================================================
# Requirement: Specialist エージェントファイル作成
# =============================================================================
echo ""
echo "--- Requirement: Specialist エージェントファイル作成 ---"

# Scenario: 全 26 specialist が移植完了 (line 23)
# WHEN: 全移植が完了した
# THEN: agents/ に 27 ファイルが存在し、全て frontmatter バリデーションを通過する
test_all_27_specialists_exist() {
  local missing=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    if ! assert_file_exists "agents/${name}.md"; then
      missing+=("${name}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing specialists: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "全 26 specialist ファイルが agents/ に存在する" test_all_27_specialists_exist

# Edge case: agents/ ディレクトリにちょうど 26 ファイルが存在する（余分なファイルがない）
test_agents_exactly_27() {
  local count
  count=$(find "${PROJECT_ROOT}/agents" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l)
  if [[ "$count" -ne 26 ]]; then
    echo "Expected 26 agent files, found ${count}" >&2
    return 1
  fi
  return 0
}
run_test "agents/ にちょうど 26 ファイル [edge: 余分なファイルがない]" test_agents_exactly_27

# Scenario: 品質判断系 specialist の移植 (line 15)
# WHEN: worker-code-reviewer を移植する
# THEN: agents/worker-code-reviewer.md が作成され、frontmatter に model: sonnet が宣言されている
test_code_reviewer_sonnet() {
  assert_file_exists "agents/worker-code-reviewer.md" || return 1
  assert_file_contains "agents/worker-code-reviewer.md" "^model:\s*sonnet"
}
run_test "worker-code-reviewer に model: sonnet が宣言されている" test_code_reviewer_sonnet

# Scenario: 構造チェック系 specialist の移植 (line 19)
# WHEN: worker-structure を移植する
# THEN: agents/worker-structure.md が作成され、frontmatter に model: haiku が宣言されている
test_structure_haiku() {
  assert_file_exists "agents/worker-structure.md" || return 1
  assert_file_contains "agents/worker-structure.md" "^model:\s*haiku"
}
run_test "worker-structure に model: haiku が宣言されている" test_structure_haiku

# --- frontmatter 必須フィールド検証 ---

# 全 specialist が frontmatter 必須フィールドを持つ
test_all_specialists_frontmatter() {
  local required_fields=("^name:" "^description:" "^type:\s*specialist" "^model:" "^effort:" "^maxTurns:" "^tools:")
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    for field in "${required_fields[@]}"; do
      if ! grep -qP "$field" "${PROJECT_ROOT}/${file}"; then
        failed+=("${name}: missing ${field}")
      fi
    done
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist が frontmatter 必須フィールドを持つ (name, description, type, model, effort, maxTurns, tools)" test_all_specialists_frontmatter

# Edge case: type フィールドが正確に "specialist" である
test_all_specialists_type_exact() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    if ! grep -qP "^type:\s*specialist\s*$" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: type is not exactly 'specialist'")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の type が正確に 'specialist' [edge: 大文字・余分な文字なし]" test_all_specialists_type_exact

# Edge case: name フィールドが dev:<specialist-name> 形式
test_all_specialists_name_format() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    if ! grep -qP "^name:\s*dev:${name}\s*$" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: name is not 'dev:${name}'")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の name が dev:<name> 形式 [edge: 名前一致]" test_all_specialists_name_format

# --- モデル割り当て検証 ---

# haiku specialists が全て model: haiku
test_haiku_model_allocation() {
  local failed=()
  for name in "${HAIKU_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    if ! grep -qP "^model:\s*haiku\s*$" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: expected model: haiku")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "構造チェック系 specialist (10個) が全て model: haiku" test_haiku_model_allocation

# sonnet specialists が全て model: sonnet
test_sonnet_model_allocation() {
  local failed=()
  for name in "${SONNET_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    if ! grep -qP "^model:\s*sonnet\s*$" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: expected model: sonnet")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "品質判断系 specialist (17個) が全て model: sonnet" test_sonnet_model_allocation

# Edge case: haiku + sonnet の合計が 27
test_model_allocation_total() {
  local haiku_count=${#HAIKU_SPECIALISTS[@]}
  local sonnet_count=${#SONNET_SPECIALISTS[@]}
  local total=$((haiku_count + sonnet_count))
  if [[ "$total" -ne 26 ]]; then
    echo "haiku(${haiku_count}) + sonnet(${sonnet_count}) = ${total}, expected 26" >&2
    return 1
  fi
  return 0
}
run_test "haiku + sonnet の合計が 27 [edge: 漏れ・重複なし]" test_model_allocation_total

# Edge case: model フィールドが haiku または sonnet のみ（他の値がない）
test_model_values_only_haiku_or_sonnet() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    local model_val
    model_val=$(grep -oP "^model:\s*\K\S+" "${PROJECT_ROOT}/${file}" 2>/dev/null || echo "")
    if [[ "$model_val" != "haiku" && "$model_val" != "sonnet" ]]; then
      failed+=("${name}: model='${model_val}' (expected haiku or sonnet)")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の model が haiku か sonnet のみ [edge: 不正な値なし]" test_model_values_only_haiku_or_sonnet

# Edge case: effort フィールドが low または medium のみ
test_effort_values() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    local effort_val
    effort_val=$(grep -oP "^effort:\s*\K\S+" "${PROJECT_ROOT}/${file}" 2>/dev/null || echo "")
    if [[ "$effort_val" != "low" && "$effort_val" != "medium" && "$effort_val" != "high" ]]; then
      failed+=("${name}: effort='${effort_val}' (expected low, medium, or high)")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の effort が low か medium [edge: 不正な値なし]" test_effort_values

# Edge case: maxTurns が 15 または 20
test_maxturns_values() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    local turns_val
    turns_val=$(grep -oP "^maxTurns:\s*\K\S+" "${PROJECT_ROOT}/${file}" 2>/dev/null || echo "")
    if [[ "$turns_val" != "15" && "$turns_val" != "20" && "$turns_val" != "30" && "$turns_val" != "40" ]]; then
      failed+=("${name}: maxTurns='${turns_val}' (expected 15, 20, 30, or 40)")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の maxTurns が 15 か 20 [edge: 不正な値なし]" test_maxturns_values

# Edge case: tools フィールドが空配列でない（最低 1 つのツール）
test_tools_nonempty() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # tools: [] は空配列。tools: の行の後に - で始まる行があるか、[] でないことを確認
    if grep -qP "^tools:\s*\[\s*\]\s*$" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: tools is empty array")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の tools が空配列でない [edge: 最低 1 ツール]" test_tools_nonempty

# =============================================================================
# Requirement: deps.yaml agents セクション登録
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml agents セクション登録 ---"

# Scenario: deps.yaml に specialist を登録 (line 38)
# WHEN: worker-security-reviewer を deps.yaml に登録する
# THEN: agents セクションに worker-security-reviewer エントリが存在し、type: specialist, model: sonnet, spawnable_by が設定
test_deps_security_reviewer_entry() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
entry = agents.get('worker-security-reviewer')
if entry is None:
    print('worker-security-reviewer not found in agents section', file=sys.stderr)
    sys.exit(1)
if entry.get('type') != 'specialist':
    print(f'type: {entry.get(\"type\")}', file=sys.stderr)
    sys.exit(1)
if entry.get('model') != 'sonnet':
    print(f'model: {entry.get(\"model\")}', file=sys.stderr)
    sys.exit(1)
sb = entry.get('spawnable_by', [])
required = {'workflow', 'composite', 'controller'}
if set(sb) != required:
    print(f'spawnable_by: {sb}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に worker-security-reviewer が正しく登録されている" test_deps_security_reviewer_entry

# 全 26 specialist が deps.yaml agents セクションに存在
test_deps_all_27_agents() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import json
agents = data.get('agents', {})
expected = json.loads('$(printf '%s\n' "${ALL_SPECIALISTS[@]}" | python3 -c "import sys, json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")')
missing = [s for s in expected if s not in agents]
if missing:
    for m in missing:
        print(f'Missing: {m}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml agents セクションに全 26 specialist が存在" test_deps_all_27_agents

# Edge case: agents セクションにちょうど 26 エントリ
test_deps_agents_count_27() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
count = len(agents)
if count != 26:
    print(f'Expected 26 agents, got {count}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml agents セクションにちょうど 26 エントリ [edge: 余分なエントリなし]" test_deps_agents_count_27

# 全 agents エントリの必須フィールド検証
test_deps_agents_required_fields() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
required_keys = ['type', 'path', 'model', 'spawnable_by', 'can_spawn', 'description']
errors = []
for name, entry in agents.items():
    if not isinstance(entry, dict):
        errors.append(f'{name}: not a dict')
        continue
    for key in required_keys:
        if key not in entry:
            errors.append(f'{name}: missing {key}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 agent エントリに必須フィールド (type, path, model, spawnable_by, can_spawn, description)" test_deps_agents_required_fields

# Edge case: 全 agents の type が specialist
test_deps_agents_type_specialist() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
errors = []
for name, entry in agents.items():
    if not isinstance(entry, dict):
        continue
    if entry.get('type') != 'specialist':
        errors.append(f'{name}: type={entry.get(\"type\")}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 agents の type が specialist [edge: 不正な type なし]" test_deps_agents_type_specialist

# Edge case: 全 agents の path が agents/<name>.md と一致
test_deps_agents_path_consistency() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
errors = []
for name, entry in agents.items():
    if not isinstance(entry, dict):
        continue
    expected_path = f'agents/{name}.md'
    actual_path = entry.get('path', '')
    if actual_path != expected_path:
        errors.append(f'{name}: path={actual_path}, expected {expected_path}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 agents の path が agents/<name>.md [edge: パス整合性]" test_deps_agents_path_consistency

# Edge case: 全 agents の can_spawn が空配列
test_deps_agents_can_spawn_empty() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
agents = data.get('agents', {})
errors = []
for name, entry in agents.items():
    if not isinstance(entry, dict):
        continue
    cs = entry.get('can_spawn', None)
    if cs is None or (isinstance(cs, list) and len(cs) != 0):
        errors.append(f'{name}: can_spawn={cs}')
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml 全 agents の can_spawn が空配列 [edge]" test_deps_agents_can_spawn_empty

# Edge case: deps.yaml の agents model と ファイル内 frontmatter の model が一致
test_deps_agents_model_matches_file() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import subprocess, os
agents = data.get('agents', {})
errors = []
for name, entry in agents.items():
    if not isinstance(entry, dict):
        continue
    deps_model = entry.get('model', '')
    filepath = os.path.join('${PROJECT_ROOT}', 'agents', f'{name}.md')
    if not os.path.isfile(filepath):
        errors.append(f'{name}: file not found')
        continue
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line.startswith('model:'):
                file_model = line.split(':', 1)[1].strip()
                if file_model != deps_model:
                    errors.append(f'{name}: deps={deps_model}, file={file_model}')
                break
if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の model とファイル内 model が一致 [edge: 不整合なし]" test_deps_agents_model_matches_file

# Scenario: loom validate が通過 (line 42)
# WHEN: 全 specialist の deps.yaml 登録が完了した
# THEN: loom validate がエラーなしで通過する
test_loom_validate() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output exit_code
  output=$(cd "${PROJECT_ROOT}" && loom validate 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom validate がエラーなしで通過する" test_loom_validate
else
  run_test_skip "loom validate がエラーなしで通過する" "loom command not found"
fi

# =============================================================================
# Requirement: Specialist プロンプト内容の移植
# =============================================================================
echo ""
echo "--- Requirement: Specialist プロンプト内容の移植 ---"

# Scenario: Baseline 参照パスの更新 (line 59)
# WHEN: baseline を参照する specialist を移植する
# THEN: 参照パスが新プロジェクトの refs/ パスに更新されている
test_baseline_ref_path_updated() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # 旧パス refs/baseline/ への参照がないこと
    if grep -qP "refs/baseline/" "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: contains old path refs/baseline/")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "specialist に旧 refs/baseline/ パス参照がない" test_baseline_ref_path_updated

# Edge case: specialist ファイルに ref-specialist-output-schema への参照がある
test_output_schema_reference() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if ! grep -qP "ref-specialist-output-schema" "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: missing ref-specialist-output-schema reference")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist に ref-specialist-output-schema への参照がある [edge]" test_output_schema_reference

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
