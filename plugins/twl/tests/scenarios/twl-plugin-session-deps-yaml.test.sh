#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: deps-yaml.md
# Generated from: deltaspec/changes/twl-plugin-session/specs/deps-yaml.md
# Coverage level: edge-cases
# Target repo: ~/projects/local-projects/twill-plugin-session/main/
# =============================================================================
set -uo pipefail

# Target repo root (twl-plugin-session)
TARGET_ROOT="${TWILL_PLUGIN_SESSION_ROOT:-/home/shuu5/projects/local-projects/twill-plugin-session/main}"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${TARGET_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${TARGET_ROOT}/${file}" ]] && grep -qP "$pattern" "${TARGET_ROOT}/${file}"
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${TARGET_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${TARGET_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_get() {
  local file="$1"
  local expr="$2"
  python3 -c "
import yaml, sys
with open('${TARGET_ROOT}/${file}') as f:
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

# =============================================================================
# Requirement: deps.yaml v3 の作成
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml v3 の作成 ---"

# Scenario: バージョンと plugin 名 (line 7)
# WHEN: deps.yaml を読む
# THEN: version: "3.0" かつ plugin: session が設定されている

test_deps_yaml_exists() {
  assert_file_exists "$DEPS_YAML"
}
run_test "deps.yaml が存在する" test_deps_yaml_exists

test_deps_yaml_valid() {
  assert_valid_yaml "$DEPS_YAML"
}
run_test "deps.yaml が有効な YAML である" test_deps_yaml_valid

test_deps_yaml_version_3_0() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
version = str(data.get('version', ''))
if version != '3.0':
    print(f'Expected version 3.0, got: {version}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の version が \"3.0\" である" test_deps_yaml_version_3_0

test_deps_yaml_plugin_session() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
plugin = data.get('plugin', '')
if plugin != 'session':
    print(f'Expected plugin session, got: {plugin}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の plugin が \"session\" である" test_deps_yaml_plugin_session

# Scenario: entry_points の定義 (line 11)
# WHEN: deps.yaml の entry_points を確認する
# THEN: spawn, observe, fork の 3 スキルが登録されている

test_deps_yaml_entry_points_exist() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points', [])
if not eps:
    print('entry_points is empty or missing', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に entry_points セクションがある" test_deps_yaml_entry_points_exist

test_deps_yaml_entry_point_spawn() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points', [])
if not any('spawn' in str(ep) for ep in eps):
    print('spawn not found in entry_points', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の entry_points に spawn が登録されている" test_deps_yaml_entry_point_spawn

test_deps_yaml_entry_point_observe() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points', [])
if not any('observe' in str(ep) for ep in eps):
    print('observe not found in entry_points', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の entry_points に observe が登録されている" test_deps_yaml_entry_point_observe

test_deps_yaml_entry_point_fork() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points', [])
if not any('fork' in str(ep) for ep in eps):
    print('fork not found in entry_points', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の entry_points に fork が登録されている" test_deps_yaml_entry_point_fork

# Edge case: entry_points の数が正確に 3 であること
test_deps_yaml_entry_points_count() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
eps = data.get('entry_points', [])
if len(eps) != 3:
    print(f'Expected 3 entry_points, got {len(eps)}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "[edge: deps.yaml の entry_points が正確に 3 件である]" test_deps_yaml_entry_points_count

# Scenario: 全コンポーネント登録 (line 15)
# WHEN: deps.yaml の skills セクションと scripts セクションを確認する
# THEN: skills 3 件と scripts 7 件が登録されている

test_deps_yaml_skills_section() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
if not skills:
    print('skills section is empty or missing', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に skills セクションがある" test_deps_yaml_skills_section

test_deps_yaml_skills_count() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
count = len(skills)
if count != 3:
    print(f'Expected 3 skills, got {count}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に skills が正確に 3 件登録されている" test_deps_yaml_skills_count

test_deps_yaml_scripts_section() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if not scripts:
    print('scripts section is empty or missing', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に scripts セクションがある" test_deps_yaml_scripts_section

test_deps_yaml_scripts_count() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
count = len(scripts)
if count != 7:
    print(f'Expected 7 scripts, got {count}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に scripts が正確に 7 件登録されている" test_deps_yaml_scripts_count

# 各スクリプトの個別登録確認
test_deps_yaml_has_session_state() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'session-state' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に session-state が登録されている" test_deps_yaml_has_session_state

test_deps_yaml_has_session_comm() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'session-comm' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に session-comm が登録されている" test_deps_yaml_has_session_comm

test_deps_yaml_has_cld() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'cld' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に cld が登録されている" test_deps_yaml_has_cld

test_deps_yaml_has_cld_spawn() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'cld-spawn' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に cld-spawn が登録されている" test_deps_yaml_has_cld_spawn

test_deps_yaml_has_cld_observe() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'cld-observe' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に cld-observe が登録されている" test_deps_yaml_has_cld_observe

test_deps_yaml_has_cld_fork() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'cld-fork' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に cld-fork が登録されている" test_deps_yaml_has_cld_fork

test_deps_yaml_has_claude_session_save() {
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
if 'claude-session-save' not in scripts:
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に claude-session-save が登録されている" test_deps_yaml_has_claude_session_save

# Scenario: 依存関係の正確性 (line 19)
# WHEN: session-comm の calls を確認する
# THEN: session-state への依存が宣言されている

test_deps_yaml_session_comm_exists_as_script() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
session_comm = scripts.get('session-comm', {})
if not isinstance(session_comm, dict) or session_comm.get('type') != 'script':
    print(f'session-comm is not registered as script type', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml の session-comm が script として登録されている" test_deps_yaml_session_comm_exists_as_script

# Edge case: 全スクリプトエントリに type: script があること
test_deps_yaml_scripts_have_type() {
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
run_test "[edge: deps.yaml の全スクリプトに type: script がある]" test_deps_yaml_scripts_have_type

# Edge case: 全スクリプトエントリに path があること
test_deps_yaml_scripts_have_path() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
missing = []
for name, entry in scripts.items():
    if isinstance(entry, dict) and not entry.get('path'):
        missing.append(name)
if missing:
    print(f'Missing path: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "[edge: deps.yaml の全スクリプトに path が定義されている]" test_deps_yaml_scripts_have_path

# Edge case: 全スクリプトエントリに description があること
test_deps_yaml_scripts_have_description() {
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
run_test "[edge: deps.yaml の全スクリプトに description がある]" test_deps_yaml_scripts_have_description

# Edge case: スクリプトの path が scripts/ 配下を指していること
test_deps_yaml_scripts_paths_prefix() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
scripts = data.get('scripts', {})
invalid = []
for name, entry in scripts.items():
    if isinstance(entry, dict):
        path = entry.get('path', '')
        if not path.startswith('scripts/'):
            invalid.append(f'{name}: {path}')
if invalid:
    print(f'Invalid paths: {invalid}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "[edge: deps.yaml の全スクリプト path が scripts/ 配下を指している]" test_deps_yaml_scripts_paths_prefix

# Edge case: 全スキルエントリに type があること
test_deps_yaml_skills_have_type() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
missing = []
for name, entry in skills.items():
    if isinstance(entry, dict) and not entry.get('type'):
        missing.append(name)
if missing:
    print(f'Missing type: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "[edge: deps.yaml の全スキルに type が定義されている]" test_deps_yaml_skills_have_type

# =============================================================================
# Requirement: twl check PASS
# =============================================================================
echo ""
echo "--- Requirement: twl check PASS ---"

# Scenario: twl check 実行 (line 27)
# WHEN: plugin ルートで twl check を実行する
# THEN: Missing 0 で PASS が返る

if command -v twl &>/dev/null; then
  test_twl_check_pass() {
    local output
    output=$(cd "${TARGET_ROOT}" && twl check 2>&1)
    local exit_code=$?
    # Missing 0 を含むこと、または PASS が含まれること
    if [[ $exit_code -ne 0 ]]; then
      echo "twl check failed with exit code $exit_code" >&2
      echo "$output" >&2
      return 1
    fi
    if echo "$output" | grep -qiP '(Missing.*[1-9]|FAIL)'; then
      echo "twl check has Missing or FAIL: $output" >&2
      return 1
    fi
    return 0
  }
  run_test "twl check が Missing 0 で PASS する" test_twl_check_pass
else
  run_test_skip "twl check が Missing 0 で PASS する" "twl コマンドが見つかりません"
fi

# =============================================================================
# Requirement: twl validate PASS
# =============================================================================
echo ""
echo "--- Requirement: twl validate PASS ---"

# Scenario: twl validate 実行 (line 33)
# WHEN: plugin ルートで twl validate を実行する
# THEN: Violations 0 で PASS が返る

if command -v twl &>/dev/null; then
  test_twl_validate_pass() {
    local output
    output=$(cd "${TARGET_ROOT}" && twl validate 2>&1)
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
      echo "twl validate failed with exit code $exit_code" >&2
      echo "$output" >&2
      return 1
    fi
    if echo "$output" | grep -qiP '(Violation.*[1-9]|FAIL)'; then
      echo "twl validate has Violations or FAIL: $output" >&2
      return 1
    fi
    return 0
  }
  run_test "twl validate が Violations 0 で PASS する" test_twl_validate_pass
else
  run_test_skip "twl validate が Violations 0 で PASS する" "twl コマンドが見つかりません"
fi

# Edge case: deps.yaml 内のスクリプトパスが実際に存在すること
test_deps_yaml_script_files_exist() {
  assert_file_exists "$DEPS_YAML" || return 1
  local missing=()
  while IFS= read -r path; do
    [[ -f "${TARGET_ROOT}/${path}" ]] || missing+=("$path")
  done < <(python3 -c "
import yaml, sys
with open('${TARGET_ROOT}/${DEPS_YAML}') as f:
    data = yaml.safe_load(f)
scripts = data.get('scripts', {})
for name, entry in scripts.items():
    if isinstance(entry, dict):
        print(entry.get('path', ''))
" 2>/dev/null)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing script files: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "[edge: deps.yaml の全スクリプトファイルが実際に存在する]" test_deps_yaml_script_files_exist

# Edge case: deps.yaml 内のスキルパスが実際に存在すること
test_deps_yaml_skill_files_exist() {
  assert_file_exists "$DEPS_YAML" || return 1
  local missing=()
  while IFS= read -r path; do
    [[ -f "${TARGET_ROOT}/${path}" ]] || missing+=("$path")
  done < <(python3 -c "
import yaml, sys
with open('${TARGET_ROOT}/${DEPS_YAML}') as f:
    data = yaml.safe_load(f)
skills = data.get('skills', {})
for name, entry in skills.items():
    if isinstance(entry, dict):
        print(entry.get('path', ''))
" 2>/dev/null)
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing skill files: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "[edge: deps.yaml の全スキルファイルが実際に存在する]" test_deps_yaml_skill_files_exist

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "twl-plugin-session-deps-yaml: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
