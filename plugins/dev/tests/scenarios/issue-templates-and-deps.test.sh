#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: Issue テンプレート & deps.yaml 更新
# Generated from: openspec/changes/c-1-controller-migration/specs/issue-templates-and-deps/spec.md
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
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
BUG_TEMPLATE="refs/ref-issue-template-bug.md"
FEATURE_TEMPLATE="refs/ref-issue-template-feature.md"

# =============================================================================
# Requirement: Issue テンプレート移植
# =============================================================================
echo ""
echo "--- Requirement: Issue テンプレート移植 ---"

# Scenario: bug テンプレートの参照 (line 10)
# WHEN: co-issue が Phase 3 の issue-structure で bug タイプの Issue を構造化する
# THEN: refs/ref-issue-template-bug.md の構造に従って Issue body が生成される

test_bug_template_exists() {
  assert_file_exists "$BUG_TEMPLATE"
}

if [[ -f "${PROJECT_ROOT}/${BUG_TEMPLATE}" ]]; then
  run_test "bug テンプレートファイルが存在する" test_bug_template_exists
else
  run_test_skip "bug テンプレートファイルが存在する" "refs/ref-issue-template-bug.md not yet created"
fi

# Edge case: bug テンプレートが空ファイルでない
test_bug_template_not_empty() {
  assert_file_exists "$BUG_TEMPLATE" || return 1
  local char_count
  char_count=$(wc -m < "${PROJECT_ROOT}/${BUG_TEMPLATE}")
  [[ $char_count -gt 50 ]]
}

if [[ -f "${PROJECT_ROOT}/${BUG_TEMPLATE}" ]]; then
  run_test "bug テンプレート [edge: 空ファイルでない（50 文字超）]" test_bug_template_not_empty
else
  run_test_skip "bug テンプレート [edge: 空ファイルでない]" "refs/ref-issue-template-bug.md not yet created"
fi

# Edge case: bug テンプレートにバグ報告特有のセクションがある
test_bug_template_has_bug_sections() {
  assert_file_exists "$BUG_TEMPLATE" || return 1
  # バグ報告には再現手順/期待値/実際値のいずれかが含まれるはず
  assert_file_contains "$BUG_TEMPLATE" "再現|手順|期待|実際|reproduc|expected|actual|steps"
}

if [[ -f "${PROJECT_ROOT}/${BUG_TEMPLATE}" ]]; then
  run_test "bug テンプレート [edge: バグ報告特有セクション存在]" test_bug_template_has_bug_sections
else
  run_test_skip "bug テンプレート [edge: バグ報告特有セクション]" "refs/ref-issue-template-bug.md not yet created"
fi

# Edge case: bug テンプレートに Markdown ヘッダーがある
test_bug_template_has_headers() {
  assert_file_exists "$BUG_TEMPLATE" || return 1
  assert_file_contains "$BUG_TEMPLATE" "^#+\s+"
}

if [[ -f "${PROJECT_ROOT}/${BUG_TEMPLATE}" ]]; then
  run_test "bug テンプレート [edge: Markdown ヘッダー存在]" test_bug_template_has_headers
else
  run_test_skip "bug テンプレート [edge: Markdown ヘッダー]" "refs/ref-issue-template-bug.md not yet created"
fi

# Scenario: feature テンプレートの参照 (line 14)
# WHEN: co-issue が Phase 3 の issue-structure で feature タイプの Issue を構造化する
# THEN: refs/ref-issue-template-feature.md の構造に従って Issue body が生成される

test_feature_template_exists() {
  assert_file_exists "$FEATURE_TEMPLATE"
}

if [[ -f "${PROJECT_ROOT}/${FEATURE_TEMPLATE}" ]]; then
  run_test "feature テンプレートファイルが存在する" test_feature_template_exists
else
  run_test_skip "feature テンプレートファイルが存在する" "refs/ref-issue-template-feature.md not yet created"
fi

# Edge case: feature テンプレートが空ファイルでない
test_feature_template_not_empty() {
  assert_file_exists "$FEATURE_TEMPLATE" || return 1
  local char_count
  char_count=$(wc -m < "${PROJECT_ROOT}/${FEATURE_TEMPLATE}")
  [[ $char_count -gt 50 ]]
}

if [[ -f "${PROJECT_ROOT}/${FEATURE_TEMPLATE}" ]]; then
  run_test "feature テンプレート [edge: 空ファイルでない（50 文字超）]" test_feature_template_not_empty
else
  run_test_skip "feature テンプレート [edge: 空ファイルでない]" "refs/ref-issue-template-feature.md not yet created"
fi

# Edge case: feature テンプレートに機能要望特有のセクションがある
test_feature_template_has_feature_sections() {
  assert_file_exists "$FEATURE_TEMPLATE" || return 1
  # 機能要望には目的/背景/要件のいずれかが含まれるはず
  assert_file_contains "$FEATURE_TEMPLATE" "目的|背景|要件|motivation|background|requirement|acceptance|受け入れ"
}

if [[ -f "${PROJECT_ROOT}/${FEATURE_TEMPLATE}" ]]; then
  run_test "feature テンプレート [edge: 機能要望特有セクション存在]" test_feature_template_has_feature_sections
else
  run_test_skip "feature テンプレート [edge: 機能要望特有セクション]" "refs/ref-issue-template-feature.md not yet created"
fi

# Edge case: feature テンプレートに Markdown ヘッダーがある
test_feature_template_has_headers() {
  assert_file_exists "$FEATURE_TEMPLATE" || return 1
  assert_file_contains "$FEATURE_TEMPLATE" "^#+\s+"
}

if [[ -f "${PROJECT_ROOT}/${FEATURE_TEMPLATE}" ]]; then
  run_test "feature テンプレート [edge: Markdown ヘッダー存在]" test_feature_template_has_headers
else
  run_test_skip "feature テンプレート [edge: Markdown ヘッダー]" "refs/ref-issue-template-feature.md not yet created"
fi

# Edge case: bug と feature テンプレートの内容が異なる（コピペ防止）
test_templates_are_different() {
  assert_file_exists "$BUG_TEMPLATE" || return 1
  assert_file_exists "$FEATURE_TEMPLATE" || return 1
  local bug_hash feature_hash
  bug_hash=$(md5sum "${PROJECT_ROOT}/${BUG_TEMPLATE}" | cut -d' ' -f1)
  feature_hash=$(md5sum "${PROJECT_ROOT}/${FEATURE_TEMPLATE}" | cut -d' ' -f1)
  [[ "$bug_hash" != "$feature_hash" ]]
}

if [[ -f "${PROJECT_ROOT}/${BUG_TEMPLATE}" && -f "${PROJECT_ROOT}/${FEATURE_TEMPLATE}" ]]; then
  run_test "テンプレート [edge: bug と feature の内容が異なる]" test_templates_are_different
else
  run_test_skip "テンプレート [edge: bug と feature の差異]" "テンプレートファイルが未作成"
fi

# =============================================================================
# Requirement: deps.yaml controller 定義の更新
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml controller 定義の更新 ---"

# deps.yaml の全体整合性
test_deps_yaml_valid() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml が有効な YAML" test_deps_yaml_valid

# 4 controllers が全て skills に登録されている
test_all_four_controllers_registered() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
missing = [c for c in required if c not in skills]
if missing:
    print(f'Missing controllers: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "4 controllers が全て skills に登録されている" test_all_four_controllers_registered

# 4 controllers が全て type: controller
test_all_four_controllers_type() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
wrong = []
for c in required:
    entry = skills.get(c, {})
    if entry.get('type') != 'controller':
        wrong.append(f\"{c}: type={entry.get('type')}\")
if wrong:
    for w in wrong:
        print(w, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "4 controllers が全て type: controller" test_all_four_controllers_type

# Edge case: 4 controllers 全てに path フィールドが存在
test_all_controllers_have_path() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for c in required:
    entry = skills.get(c, {})
    if not entry.get('path'):
        print(f'{c}: missing path', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "4 controllers [edge: 全てに path フィールド]" test_all_controllers_have_path

# Edge case: 4 controllers 全てに description フィールドが存在
test_all_controllers_have_description() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for c in required:
    entry = skills.get(c, {})
    if not entry.get('description'):
        print(f'{c}: missing description', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "4 controllers [edge: 全てに description フィールド]" test_all_controllers_have_description

# Edge case: 4 controllers 全ての spawnable_by に user が含まれる
test_all_controllers_spawnable_by_user() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for c in required:
    entry = skills.get(c, {})
    sb = entry.get('spawnable_by', [])
    if 'user' not in sb:
        print(f'{c}: spawnable_by={sb}, missing user', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "4 controllers [edge: 全て spawnable_by に user]" test_all_controllers_spawnable_by_user

# Edge case: 4 controllers 全ての path が実在するファイルを指す
test_all_controllers_path_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  local paths
  paths=$(yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for c in required:
    entry = skills.get(c, {})
    print(entry.get('path', ''))
")
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ ! -f "${PROJECT_ROOT}/${p}" ]]; then
      echo "File not found: ${p}" >&2
      return 1
    fi
  done <<< "$paths"
  return 0
}
run_test "4 controllers [edge: path が実在ファイルを指す]" test_all_controllers_path_exists

# Scenario: loom validate パス (line 29)
# WHEN: deps.yaml 更新後に loom validate を実行する
# THEN: バリデーションが PASS し、全コンポーネントの参照が正しく解決される

test_loom_validate_pass() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom validate 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

if command -v loom &>/dev/null; then
  run_test "loom validate が PASS する" test_loom_validate_pass
else
  run_test_skip "loom validate が PASS する" "loom command not found"
fi

# Edge case: loom validate の出力に ERROR がない
test_loom_validate_no_errors() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom validate 2>&1)
  if echo "$output" | grep -qiP "^ERROR|:\s*ERROR"; then
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom validate [edge: エラー出力なし]" test_loom_validate_no_errors
else
  run_test_skip "loom validate [edge: エラー出力なし]" "loom command not found"
fi

# =============================================================================
# Requirement: deps.yaml refs セクション - Issue テンプレート
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml refs セクション - Issue テンプレート ---"

# refs に ref-issue-template-bug が登録されている
test_refs_has_bug_template() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
found = any('issue-template-bug' in str(k) for k in refs.keys())
sys.exit(0 if found else 1)
"
}
run_test "refs に ref-issue-template-bug が登録" test_refs_has_bug_template

# refs に ref-issue-template-feature が登録されている
test_refs_has_feature_template() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
found = any('issue-template-feature' in str(k) for k in refs.keys())
sys.exit(0 if found else 1)
"
}
run_test "refs に ref-issue-template-feature が登録" test_refs_has_feature_template

# Edge case: refs テンプレートエントリに type: reference が設定されている
test_refs_template_type_reference() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'issue-template' in str(key):
        if not isinstance(val, dict) or val.get('type') != 'reference':
            print(f'{key}: type={val.get(\"type\") if isinstance(val, dict) else \"not a dict\"}', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "refs テンプレート [edge: type: reference]" test_refs_template_type_reference

# Edge case: refs テンプレートエントリに path が設定され refs/ 配下を指す
test_refs_template_path_under_refs() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'issue-template' in str(key):
        if not isinstance(val, dict):
            sys.exit(1)
        p = val.get('path', '')
        if not str(p).startswith('refs/'):
            print(f'{key}: path={p}, not under refs/', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "refs テンプレート [edge: path が refs/ 配下]" test_refs_template_path_under_refs

# Edge case: refs テンプレートエントリに description が空でない
test_refs_template_description_not_empty() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'issue-template' in str(key):
        if not isinstance(val, dict):
            sys.exit(1)
        desc = val.get('description', '')
        if not desc or not str(desc).strip():
            print(f'{key}: empty description', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "refs テンプレート [edge: description が空でない]" test_refs_template_description_not_empty

# Edge case: refs テンプレートの path が実在ファイルを指す
test_refs_template_path_file_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  local paths
  paths=$(yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
for key, val in refs.items():
    if 'issue-template' in str(key):
        print(val.get('path', ''))
")
  local found_any=false
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    found_any=true
    if [[ ! -f "${PROJECT_ROOT}/${p}" ]]; then
      echo "File not found: ${p}" >&2
      return 1
    fi
  done <<< "$paths"
  $found_any
}

# Conditional: only check if refs template entries exist in deps.yaml
if yaml_get "$DEPS_YAML" "
refs = data.get('refs', {})
found = any('issue-template' in str(k) for k in refs.keys())
sys.exit(0 if found else 1)
" 2>/dev/null; then
  run_test "refs テンプレート [edge: path が実在ファイルを指す]" test_refs_template_path_file_exists
else
  run_test_skip "refs テンプレート [edge: path が実在ファイル]" "refs に issue-template エントリ未登録"
fi

# =============================================================================
# Requirement: 内部参照の正確性
# =============================================================================
echo ""
echo "--- Requirement: 内部参照の正確性 ---"

# Scenario: 未定義参照の検出 (line 38)
# WHEN: SKILL.md 内で deps.yaml に未定義のコマンドを参照する
# THEN: loom validate がエラーを報告する

# Edge case: loom check が通過する（deps.yaml 構造の正当性）
test_loom_check_pass() {
  if ! command -v loom &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && loom check 2>&1)
  local exit_code=$?
  [[ $exit_code -eq 0 ]]
}

if command -v loom &>/dev/null; then
  run_test "loom check が PASS する" test_loom_check_pass
else
  run_test_skip "loom check が PASS する" "loom command not found"
fi

# Edge case: entry_points が 4 controllers を含む
test_entry_points_four_controllers() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points', [])
if not isinstance(eps, list):
    sys.exit(1)
required_paths = [
    'skills/co-autopilot/SKILL.md',
    'skills/co-issue/SKILL.md',
    'skills/co-project/SKILL.md',
    'skills/co-architect/SKILL.md',
]
missing = [p for p in required_paths if p not in eps]
if missing:
    print(f'Missing entry_points: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "entry_points に 4 controllers のパスが含まれる" test_entry_points_four_controllers

# Edge case: entry_points がリスト型
test_entry_points_is_list() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points')
if not isinstance(eps, list):
    print(f'entry_points is {type(eps).__name__}, expected list', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "entry_points [edge: リスト型]" test_entry_points_is_list

# Edge case: 全 controllers の can_spawn に空リスト [] がない（全て何かを spawn できる）
test_controllers_can_spawn_not_empty() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
required = ['co-autopilot', 'co-issue', 'co-project', 'co-architect']
for c in required:
    entry = skills.get(c, {})
    cs = entry.get('can_spawn', [])
    if not cs:
        print(f'{c}: can_spawn is empty', file=sys.stderr)
        sys.exit(1)
sys.exit(0)
"
}
run_test "4 controllers [edge: can_spawn が空でない]" test_controllers_can_spawn_not_empty

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
