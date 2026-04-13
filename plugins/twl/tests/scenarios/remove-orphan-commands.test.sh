#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: remove-orphan-commands
# Generated from: deltaspec/changes/issue-562/specs/remove-orphan-commands/spec.md
# Coverage level: edge-cases
# Type: unit
#
# Verifies that architect-decompose and architect-issue-create have been fully
# removed from deps.yaml and the commands/ directory.
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

TWILL_BIN="${TWILL_BIN:-/home/shuu5/.local/bin/twl}"

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

assert_file_not_exists() {
  local file="$1"
  [[ ! -f "${PROJECT_ROOT}/${file}" ]]
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

# =============================================================================
# Requirement: architect-decompose コンポーネントの廃止
# =============================================================================
echo ""
echo "--- Requirement: architect-decompose コンポーネントの廃止 ---"

# Scenario: deps.yaml から architect-decompose エントリ削除 (spec.md line 7)
# WHEN: plugins/twl/deps.yaml を確認する
# THEN: architect-decompose キーが存在しない
test_architect_decompose_not_in_deps_yaml() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
commands = data.get('commands', {})
if 'architect-decompose' in commands:
    print('architect-decompose key still present in commands section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に architect-decompose キーが存在しない" test_architect_decompose_not_in_deps_yaml

# Edge case: deps.yaml の文字列としても architect-decompose が commands セクションに残存しない
test_architect_decompose_not_in_deps_yaml_text() {
  assert_file_exists "$DEPS_YAML" || return 1
  # YAML key として "architect-decompose:" が commands ブロック内に存在しないこと
  # (コメント内での言及は許容するため、YAML パース結果で確認済みだが文字列レベルでも補足)
  python3 - "${PROJECT_ROOT}/${DEPS_YAML}" <<'PYEOF'
import yaml, sys

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

commands = data.get('commands', {})
if not isinstance(commands, dict):
    print('commands section not found or not a dict', file=sys.stderr)
    sys.exit(1)

# Ensure key is completely absent (not hidden under aliases or anchors)
if 'architect-decompose' in commands:
    print('architect-decompose found in commands', file=sys.stderr)
    sys.exit(1)

# Also check skills and agents sections
for section in ('skills', 'agents', 'scripts'):
    sec = data.get(section, {})
    if isinstance(sec, dict) and 'architect-decompose' in sec:
        print(f'architect-decompose found in {section}', file=sys.stderr)
        sys.exit(1)

sys.exit(0)
PYEOF
}
run_test "deps.yaml [edge: commands/skills/agents 全セクションに architect-decompose なし]" test_architect_decompose_not_in_deps_yaml_text

# Scenario: コマンドファイルの削除 (spec.md line 11)
# WHEN: ファイルシステムを確認する
# THEN: plugins/twl/commands/architect-decompose.md が存在しない
test_architect_decompose_command_file_deleted() {
  assert_file_not_exists "commands/architect-decompose.md"
}
run_test "commands/architect-decompose.md が存在しない" test_architect_decompose_command_file_deleted

# Edge case: architect-decompose.md が commands/ に隠し形式でも残存しない
test_architect_decompose_no_variants() {
  # .bak, .orig などのバックアップファイルも存在しないこと
  local found=0
  while IFS= read -r -d '' f; do
    found=1
    echo "Found: $f" >&2
  done < <(find "${PROJECT_ROOT}/commands" -maxdepth 1 \
    -name "architect-decompose*" -print0 2>/dev/null)
  [[ $found -eq 0 ]]
}
run_test "commands/ [edge: architect-decompose* のバリアントファイルも存在しない]" test_architect_decompose_no_variants

# =============================================================================
# Requirement: architect-issue-create コンポーネントの廃止
# =============================================================================
echo ""
echo "--- Requirement: architect-issue-create コンポーネントの廃止 ---"

# Scenario: deps.yaml から architect-issue-create エントリ削除 (spec.md line 24)
# WHEN: plugins/twl/deps.yaml を確認する
# THEN: architect-issue-create キーが存在しない
test_architect_issue_create_not_in_deps_yaml() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
commands = data.get('commands', {})
if 'architect-issue-create' in commands:
    print('architect-issue-create key still present in commands section', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml に architect-issue-create キーが存在しない" test_architect_issue_create_not_in_deps_yaml

# Edge case: deps.yaml の全セクションに architect-issue-create が残存しない
test_architect_issue_create_not_in_deps_yaml_text() {
  assert_file_exists "$DEPS_YAML" || return 1
  python3 - "${PROJECT_ROOT}/${DEPS_YAML}" <<'PYEOF'
import yaml, sys

with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)

for section in ('commands', 'skills', 'agents', 'scripts'):
    sec = data.get(section, {})
    if isinstance(sec, dict) and 'architect-issue-create' in sec:
        print(f'architect-issue-create found in {section}', file=sys.stderr)
        sys.exit(1)

sys.exit(0)
PYEOF
}
run_test "deps.yaml [edge: 全セクションに architect-issue-create なし]" test_architect_issue_create_not_in_deps_yaml_text

# Scenario: コマンドファイルの削除 (spec.md line 28)
# WHEN: ファイルシステムを確認する
# THEN: plugins/twl/commands/architect-issue-create.md が存在しない
test_architect_issue_create_command_file_deleted() {
  assert_file_not_exists "commands/architect-issue-create.md"
}
run_test "commands/architect-issue-create.md が存在しない" test_architect_issue_create_command_file_deleted

# Edge case: architect-issue-create.md のバリアントファイルも存在しない
test_architect_issue_create_no_variants() {
  local found=0
  while IFS= read -r -d '' f; do
    found=1
    echo "Found: $f" >&2
  done < <(find "${PROJECT_ROOT}/commands" -maxdepth 1 \
    -name "architect-issue-create*" -print0 2>/dev/null)
  [[ $found -eq 0 ]]
}
run_test "commands/ [edge: architect-issue-create* のバリアントファイルも存在しない]" test_architect_issue_create_no_variants

# =============================================================================
# Requirement: twl check が orphan を検出しない（統合テスト）
# =============================================================================
echo ""
echo "--- Requirement: twl check が orphan を検出しない ---"

# Scenario: twl check が orphan を検出しない (spec.md line 17)
# WHEN: plugins/twl/ ディレクトリで twl check を実行する
# THEN: violations=0、orphans=0 で終了する
test_twl_check_no_violations() {
  local output exit_code
  exit_code=0
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" check --format json 2>&1) || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "twl check exited with code ${exit_code}" >&2
    echo "${output}" >&2
    return 1
  fi

  # critical (=violations) must be 0
  local critical
  critical=$(echo "${output}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('summary', {}).get('critical', -1))
" 2>/dev/null)

  if [[ "${critical}" != "0" ]]; then
    echo "twl check: critical=${critical} (expected 0)" >&2
    echo "${output}" >&2
    return 1
  fi
  return 0
}

if command -v "${TWILL_BIN}" &>/dev/null || [[ -x "${TWILL_BIN}" ]]; then
  run_test "twl check: critical violations=0" test_twl_check_no_violations
else
  run_test_skip "twl check: critical violations=0" "twl binary not found at ${TWILL_BIN}"
fi

# Edge case: twl check --format json の warning も 0 であること
test_twl_check_no_warnings() {
  local output exit_code
  exit_code=0
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" check --format json 2>&1) || exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    echo "twl check exited with code ${exit_code}" >&2
    return 1
  fi

  local warning
  warning=$(echo "${output}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get('summary', {}).get('warning', -1))
" 2>/dev/null)

  if [[ "${warning}" != "0" ]]; then
    echo "twl check: warning=${warning} (expected 0)" >&2
    return 1
  fi
  return 0
}

if command -v "${TWILL_BIN}" &>/dev/null || [[ -x "${TWILL_BIN}" ]]; then
  run_test "twl check [edge: warnings=0]" test_twl_check_no_warnings
else
  run_test_skip "twl check [edge: warnings=0]" "twl binary not found at ${TWILL_BIN}"
fi

# Edge case: twl --orphans の出力に architect-decompose が出現しない
test_twl_orphans_no_architect_decompose() {
  local output
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" --orphans 2>&1) || true

  if echo "${output}" | grep -qP "command:architect-decompose"; then
    echo "architect-decompose still listed as orphan in 'twl --orphans'" >&2
    return 1
  fi
  return 0
}

if command -v "${TWILL_BIN}" &>/dev/null || [[ -x "${TWILL_BIN}" ]]; then
  run_test "twl --orphans [edge: architect-decompose が孤立コンポーネントに出現しない]" test_twl_orphans_no_architect_decompose
else
  run_test_skip "twl --orphans [edge: architect-decompose not listed]" "twl binary not found at ${TWILL_BIN}"
fi

# Edge case: twl --orphans の出力に architect-issue-create が出現しない
test_twl_orphans_no_architect_issue_create() {
  local output
  output=$(cd "${PROJECT_ROOT}" && "${TWILL_BIN}" --orphans 2>&1) || true

  if echo "${output}" | grep -qP "command:architect-issue-create"; then
    echo "architect-issue-create still listed as orphan in 'twl --orphans'" >&2
    return 1
  fi
  return 0
}

if command -v "${TWILL_BIN}" &>/dev/null || [[ -x "${TWILL_BIN}" ]]; then
  run_test "twl --orphans [edge: architect-issue-create が孤立コンポーネントに出現しない]" test_twl_orphans_no_architect_issue_create
else
  run_test_skip "twl --orphans [edge: architect-issue-create not listed]" "twl binary not found at ${TWILL_BIN}"
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
