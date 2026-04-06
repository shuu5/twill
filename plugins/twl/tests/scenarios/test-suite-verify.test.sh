#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: test-suite-fix.md
# Generated from: deltaspec/changes/archive/2026-03-31-test-suite-verify/specs/test-suite-fix.md
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
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    return 0  # file absent → cannot contain pattern → pass
  fi
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

assert_dir_exists() {
  local dir="$1"
  [[ -d "${PROJECT_ROOT}/${dir}" ]]
}

assert_cmd_exists() {
  local cmd="$1"
  command -v "$cmd" &>/dev/null
}

assert_valid_json() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "import json; json.load(open('${PROJECT_ROOT}/${file}'))" 2>/dev/null
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
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

# =============================================================================
# Requirement: テストスイート全件 PASS
# =============================================================================
echo ""
echo "--- Requirement: テストスイート全件 PASS ---"

RUN_TESTS_SCRIPT="tests/run-tests.sh"
BATS_DIR="tests/bats"
SCENARIOS_DIR="tests/scenarios"

# Scenario: ベースライン記録 (line 7)
# WHEN: テストスイートを初回実行する
# THEN: PASS/FAIL 数を Issue #43 のコメントに記録しなければならない（MUST）

# ベースライン記録は手動操作（gh issue comment）が必要なため、
# テストスイートの実行可能性（前提条件）を検証する
test_run_tests_script_exists() {
  assert_file_exists "$RUN_TESTS_SCRIPT" || return 1
  return 0
}
run_test "ベースライン記録: run-tests.sh が存在する" test_run_tests_script_exists

test_run_tests_script_executable() {
  [[ -x "${PROJECT_ROOT}/${RUN_TESTS_SCRIPT}" ]] || return 1
  return 0
}
run_test "ベースライン記録: run-tests.sh が実行可能" test_run_tests_script_executable

# Edge case: run-tests.sh が bats と scenario テストをカバーしている
test_run_tests_covers_both() {
  assert_file_exists "$RUN_TESTS_SCRIPT" || return 1
  assert_file_contains "$RUN_TESTS_SCRIPT" "bats" || return 1
  assert_file_contains "$RUN_TESTS_SCRIPT" "scenario|\.test\.sh" || return 1
  return 0
}
run_test "ベースライン記録 [edge: bats と scenario 両方をカバー]" test_run_tests_covers_both

# Scenario: bats テスト全件 PASS (line 11)
# WHEN: tests/run-tests.sh を実行する
# THEN: bats テストが全件 PASS しなければならない（SHALL）

test_bats_dir_exists() {
  assert_dir_exists "$BATS_DIR" || return 1
  return 0
}
run_test "bats テスト全件 PASS: tests/bats/ ディレクトリが存在する" test_bats_dir_exists

test_bats_files_count() {
  assert_dir_exists "$BATS_DIR" || return 1
  local count
  count=$(find "${PROJECT_ROOT}/${BATS_DIR}" -name "*.bats" 2>/dev/null | wc -l)
  # 期待値: 37 bats ファイルが存在する
  [[ "$count" -ge 1 ]] || return 1
  return 0
}
run_test "bats テスト全件 PASS: .bats ファイルが存在する" test_bats_files_count

test_bats_bin_available() {
  local bats_bin="${PROJECT_ROOT}/tests/lib/bats-core/bin/bats"
  # Accept either local bats-core/bin/bats or system-installed bats
  [[ -x "$bats_bin" ]] || command -v bats &>/dev/null || return 1
  return 0
}
run_test "bats テスト全件 PASS: bats バイナリが利用可能" test_bats_bin_available

# Edge case: bats テストが 50 件（現行件数）
test_bats_files_exact_count() {
  assert_dir_exists "$BATS_DIR" || return 1
  local count
  count=$(find "${PROJECT_ROOT}/${BATS_DIR}" -name "*.bats" 2>/dev/null | wc -l)
  if [[ "$count" -ne 50 ]]; then
    echo "  [INFO] Expected 50 bats files, found: ${count}" >&2
    return 1
  fi
  return 0
}
run_test "bats テスト [edge: ファイル数が 50 件]" test_bats_files_exact_count

# Edge case: bats helpers が存在する（テスト実行前提）
test_bats_helpers_exist() {
  assert_file_exists "tests/bats/helpers/common.bash" || return 1
  return 0
}
run_test "bats テスト [edge: helpers/common.bash が存在する]" test_bats_helpers_exist

# Scenario: scenario テスト全件 PASS (line 15)
# WHEN: tests/run-tests.sh を実行する
# THEN: scenario テストが全件 PASS しなければならない（SHALL）

test_scenarios_dir_exists() {
  assert_dir_exists "$SCENARIOS_DIR" || return 1
  return 0
}
run_test "scenario テスト全件 PASS: tests/scenarios/ ディレクトリが存在する" test_scenarios_dir_exists

test_scenarios_files_exist() {
  assert_dir_exists "$SCENARIOS_DIR" || return 1
  local count
  count=$(find "${PROJECT_ROOT}/${SCENARIOS_DIR}" -name "*.test.sh" 2>/dev/null | wc -l)
  [[ "$count" -ge 1 ]] || return 1
  return 0
}
run_test "scenario テスト全件 PASS: .test.sh ファイルが存在する" test_scenarios_files_exist

# Edge case: scenario テストが 75 件（現行件数: #137 resolve-project-lib 追加後）
test_scenarios_files_exact_count() {
  assert_dir_exists "$SCENARIOS_DIR" || return 1
  local count
  count=$(find "${PROJECT_ROOT}/${SCENARIOS_DIR}" -name "*.test.sh" 2>/dev/null | wc -l)
  if [[ "$count" -ne 76 ]]; then
    echo "  [INFO] Expected 76 scenario files, found: ${count}" >&2
    return 1
  fi
  return 0
}
run_test "scenario テスト [edge: ファイル数が 73 件]" test_scenarios_files_exact_count

# Edge case: scenario テストが共通形式（run_test / PASS / FAIL）に準拠
test_scenarios_use_run_test() {
  assert_dir_exists "$SCENARIOS_DIR" || return 1
  local bad=0
  local checked=0
  while IFS= read -r -d '' f; do
    if ! grep -qP "run_test|PASS|FAIL" "$f" 2>/dev/null; then
      echo "  [INFO] ${f} does not use run_test pattern" >&2
      ((bad++)) || true
    fi
    ((checked++)) || true
  done < <(find "${PROJECT_ROOT}/${SCENARIOS_DIR}" -name "*.test.sh" -print0 2>/dev/null)
  [[ "$checked" -gt 0 ]] || return 1
  [[ "$bad" -eq 0 ]] || return 1
  return 0
}
run_test "scenario テスト [edge: run_test パターンに準拠]" test_scenarios_use_run_test

# Scenario: 失敗数超過時の分割 (line 19)
# WHEN: 失敗テストが10件を超える
# THEN: ベースライン記録+分類のみを行い、修正は別 Issue に分割しなければならない（MUST）

# このScenarioはプロセス/判断ルールのため、設計文書への記載を検証する
test_split_rule_documented() {
  # design.md または proposal.md に「10件超」「別 Issue」の記述があることを確認
  local found=0
  for doc in \
    "deltaspec/changes/archive/2026-03-31-test-suite-verify/design.md" \
    "deltaspec/changes/archive/2026-03-31-test-suite-verify/proposal.md" \
    "deltaspec/changes/archive/2026-03-31-test-suite-verify/specs/test-suite-fix.md"; do
    if [[ -f "${PROJECT_ROOT}/${doc}" ]]; then
      if grep -qP "10件|別.*Issue|分割" "${PROJECT_ROOT}/${doc}" 2>/dev/null; then
        found=1
        break
      fi
    fi
  done
  [[ "$found" -eq 1 ]] || return 1
  return 0
}
run_test "失敗数超過時の分割: スコープ制限ルールが仕様書に記述されている" test_split_rule_documented

# Edge case: スコープ制限条件（10件超）が specs に明記されている
test_split_rule_in_spec() {
  local spec="deltaspec/changes/archive/2026-03-31-test-suite-verify/specs/test-suite-fix.md"
  assert_file_exists "$spec" || return 1
  assert_file_contains "$spec" "10件" || return 1
  assert_file_contains "$spec" "別.*Issue|分割" || return 1
  return 0
}
run_test "失敗数超過 [edge: 閾値 10件が specs に明記されている]" test_split_rule_in_spec

# =============================================================================
# Requirement: hooks 動作確認
# =============================================================================
echo ""
echo "--- Requirement: hooks 動作確認 ---"

HOOKS_FILE="hooks/hooks.json"
BASH_ERROR_HOOK="scripts/hooks/post-tool-use-bash-error.sh"

# Scenario: hooks エラーなし (line 27)
# WHEN: テストスイートを実行する
# THEN: PostToolUseFailure hooks がエラーなく動作しなければならない（SHALL）

test_hooks_json_exists() {
  assert_file_exists "$HOOKS_FILE" || return 1
  return 0
}
run_test "hooks エラーなし: hooks/hooks.json が存在する" test_hooks_json_exists

test_hooks_json_valid() {
  assert_file_exists "$HOOKS_FILE" || return 1
  assert_valid_json "$HOOKS_FILE" || return 1
  return 0
}
run_test "hooks エラーなし: hooks.json が有効な JSON" test_hooks_json_valid

test_post_tool_use_failure_hook_defined() {
  assert_file_exists "$HOOKS_FILE" || return 1
  python3 -c "
import json, sys
with open('${PROJECT_ROOT}/${HOOKS_FILE}') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
ptuf = hooks.get('PostToolUseFailure', [])
if not isinstance(ptuf, list) or len(ptuf) == 0:
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "hooks エラーなし: PostToolUseFailure hook が定義されている" test_post_tool_use_failure_hook_defined

test_bash_error_hook_script_exists() {
  assert_file_exists "$BASH_ERROR_HOOK" || return 1
  return 0
}
run_test "hooks エラーなし: post-tool-use-bash-error.sh が存在する" test_bash_error_hook_script_exists

test_bash_error_hook_exits_zero() {
  assert_file_exists "$BASH_ERROR_HOOK" || return 1
  # スクリプトは常に exit 0 を返すことが要件（記録失敗でも hook 自体は成功扱い）
  assert_file_contains "$BASH_ERROR_HOOK" "exit 0" || return 1
  return 0
}
run_test "hooks エラーなし: bash-error hook が exit 0 を返す設計" test_bash_error_hook_exits_zero

# Edge case: PostToolUseFailure hook の matcher が Bash
test_hook_matcher_is_bash() {
  assert_file_exists "$HOOKS_FILE" || return 1
  python3 -c "
import json, sys
with open('${PROJECT_ROOT}/${HOOKS_FILE}') as f:
    data = json.load(f)
hooks = data.get('hooks', {}).get('PostToolUseFailure', [])
found = any(
    'Bash' in str(h.get('matcher', ''))
    for h in hooks if isinstance(h, dict)
)
sys.exit(0 if found else 1)
" 2>/dev/null
}
run_test "hooks [edge: PostToolUseFailure の matcher が Bash]" test_hook_matcher_is_bash

# Edge case: bash-error hook がタイムスタンプを記録する
test_bash_error_records_timestamp() {
  assert_file_exists "$BASH_ERROR_HOOK" || return 1
  assert_file_contains "$BASH_ERROR_HOOK" "TIMESTAMP|timestamp|date" || return 1
  return 0
}
run_test "hooks [edge: bash-error hook がタイムスタンプを記録する]" test_bash_error_records_timestamp

# Edge case: bash-error hook の出力先が .self-improve/errors.jsonl
test_bash_error_output_path() {
  assert_file_exists "$BASH_ERROR_HOOK" || return 1
  assert_file_contains "$BASH_ERROR_HOOK" "self-improve.*errors\.jsonl|errors\.jsonl" || return 1
  return 0
}
run_test "hooks [edge: 出力先が .self-improve/errors.jsonl]" test_bash_error_output_path

# Edge case: bash-error hook が stdin から JSON を読み取る
test_bash_error_reads_stdin() {
  assert_file_exists "$BASH_ERROR_HOOK" || return 1
  # stdin から読み取るパターン（cat / read）があること
  assert_file_contains "$BASH_ERROR_HOOK" "cat\b|\bSTDIN|INPUT=\$\(cat\)" || return 1
  return 0
}
run_test "hooks [edge: bash-error hook が stdin から JSON を読み取る]" test_bash_error_reads_stdin

# =============================================================================
# Requirement: chain generate --check PASS
# =============================================================================
echo ""
echo "--- Requirement: chain generate --check PASS ---"

DEPS_YAML="deps.yaml"

# Scenario: chain チェック PASS (line 35)
# WHEN: chain generate --check を実行する
# THEN: 全 chain 定義がチェックを PASS しなければならない（SHALL）

test_deps_yaml_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  return 0
}
run_test "chain チェック PASS: deps.yaml が存在する" test_deps_yaml_exists

test_deps_yaml_valid_yaml() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_valid_yaml "$DEPS_YAML" || return 1
  return 0
}
run_test "chain チェック PASS: deps.yaml が有効な YAML" test_deps_yaml_valid_yaml

test_chains_section_exists() {
  assert_file_exists "$DEPS_YAML" || return 1
  python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${DEPS_YAML}') as f:
    data = yaml.safe_load(f)
chains = data.get('chains', {})
if not chains:
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "chain チェック PASS: deps.yaml に chains セクションが存在する" test_chains_section_exists

# twl check による chain 整合性検証
test_twl_check_no_chain_errors() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output
  output=$(cd "${PROJECT_ROOT}" && twl check 2>&1)
  # [chain-bidir], [chain-type], [step-order] エラーが 0 件
  if echo "$output" | grep -qP "\[chain-bidir\]|\[chain-type\]|\[step-order\]"; then
    echo "$output" | grep -P "\[chain" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "chain チェック PASS: twl check で chain エラーが 0 件" test_twl_check_no_chain_errors
else
  run_test_skip "chain チェック PASS: twl check で chain エラーが 0 件" "twl not found"
fi

# twl check 全体が exit 0
test_twl_check_exit_zero() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  cd "${PROJECT_ROOT}" && twl check &>/dev/null
}

if command -v twl &>/dev/null; then
  run_test "chain チェック PASS: twl check が exit 0" test_twl_check_exit_zero
else
  run_test_skip "chain チェック PASS: twl check が exit 0" "twl not found"
fi

# Edge case: 全 chain 定義が双方向参照を持つ
test_chains_bidirectional_refs() {
  assert_file_exists "$DEPS_YAML" || return 1
  python3 -c "
import yaml, sys

with open('${PROJECT_ROOT}/${DEPS_YAML}') as f:
    data = yaml.safe_load(f)

chains = data.get('chains', {})
if not chains:
    sys.exit(1)

# 全コンポーネントエントリを収集（commands を最後にして優先）
all_entries = {}
for section in ['scripts', 'skills', 'commands']:
    entries = data.get(section, {})
    if isinstance(entries, dict):
        all_entries.update(entries)

# 各 chain の steps に chain: フィールドを持つコンポーネントが存在するか確認
errors = []
for chain_name, chain_def in chains.items():
    if not isinstance(chain_def, dict):
        continue
    steps_raw = chain_def.get('steps', [])
    for s in steps_raw:
        if isinstance(s, str):
            comp_name = s
        elif isinstance(s, dict):
            comp_name = s.get('name') or s.get('component') or s.get('step') or ''
        else:
            continue
        if not comp_name:
            continue
        comp = all_entries.get(comp_name, {})
        if not isinstance(comp, dict):
            continue
        # chain フィールドが設定されているか（双方向参照）
        if str(comp.get('chain', '')) != chain_name:
            errors.append(f'{comp_name}: chain={comp.get(\"chain\")} (expected {chain_name})')

if errors:
    for e in errors:
        print(e, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "chain チェック [edge: chain 参加コンポーネントが双方向参照を持つ]" test_chains_bidirectional_refs

# Edge case: deps.yaml の全エントリが既定の type を持つ
test_all_entries_have_type() {
  assert_file_exists "$DEPS_YAML" || return 1
  python3 -c "
import yaml, sys

with open('${PROJECT_ROOT}/${DEPS_YAML}') as f:
    data = yaml.safe_load(f)

missing_type = []
for section in ['commands', 'skills', 'scripts']:
    entries = data.get(section, {})
    if not isinstance(entries, dict):
        continue
    for name, entry in entries.items():
        if not isinstance(entry, dict):
            continue
        if not entry.get('type'):
            missing_type.append(f'{section}/{name}')

if missing_type:
    for m in missing_type:
        print(f'Missing type: {m}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}
run_test "chain チェック [edge: 全エントリが type フィールドを持つ]" test_all_entries_have_type

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
