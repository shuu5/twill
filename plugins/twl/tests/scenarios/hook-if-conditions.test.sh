#!/usr/bin/env bash
# =============================================================================
# Scenario Tests: hook if 条件フィルタリング追加
# Generated from: openspec/changes/claude-code-v2185-feature-intake/specs/hook-if-conditions/spec.md
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

assert_valid_json() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "import json; json.load(open('${PROJECT_ROOT}/${file}'))" 2>/dev/null
}

json_query() {
  local file="$1"
  local expr="$2"
  python3 -c "
import json, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = json.load(f)
${expr}
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

HOOKS_FILE="hooks/hooks.json"

# =============================================================================
# Requirement: hook if 条件フィルタリング追加
# =============================================================================
echo ""
echo "--- Requirement: hook if 条件フィルタリング追加 ---"

# ---------------------------------------------------------------------------
# Scenario: 既存 PostToolUse hook の維持 (spec.md line 7)
# WHEN: Edit または Write ツールが実行される
# THEN: post-tool-use-validate.sh が発火する（if 条件なし、全ファイル対象）
# ---------------------------------------------------------------------------

# hooks.json が存在し有効な JSON
test_hooks_json_exists_and_valid() {
  assert_file_exists "$HOOKS_FILE" || return 1
  assert_valid_json "$HOOKS_FILE"
}
run_test "hooks.json が存在し有効な JSON" test_hooks_json_exists_and_valid

# PostToolUse に Edit|Write matcher のエントリが存在する
test_posttooluse_edit_write_exists() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
hooks = data.get('hooks', {}).get('PostToolUse', [])
found = any(
    'Edit' in str(h.get('matcher', '')) and 'Write' in str(h.get('matcher', ''))
    for h in hooks if isinstance(h, dict)
)
sys.exit(0 if found else 1)
"
}
run_test "既存 PostToolUse hook の維持: Edit|Write matcher が存在する" test_posttooluse_edit_write_exists

# post-tool-use-validate.sh が command に含まれる
test_posttooluse_validate_script() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
import re
hooks = data.get('hooks', {}).get('PostToolUse', [])
found = False
for h in hooks:
    if not isinstance(h, dict):
        continue
    matcher = h.get('matcher', '')
    if 'Edit' not in matcher:
        continue
    for inner in h.get('hooks', []):
        if 'post-tool-use-validate' in str(inner.get('command', '')):
            found = True
sys.exit(0 if found else 1)
"
}
run_test "既存 PostToolUse hook の維持: post-tool-use-validate.sh が command に含まれる" test_posttooluse_validate_script

# [edge-case] Edit|Write hook に 'if' フィールドが存在しない（全ファイル対象）
test_posttooluse_no_if_condition() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
hooks = data.get('hooks', {}).get('PostToolUse', [])
for h in hooks:
    if not isinstance(h, dict):
        continue
    if 'Edit' in str(h.get('matcher', '')) and 'Write' in str(h.get('matcher', '')):
        # This hook should NOT have an 'if' condition
        if 'if' in h:
            print(f'Unexpected if field: {h[\"if\"]}', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "既存 PostToolUse hook の維持 [edge: if 条件なし]" test_posttooluse_no_if_condition

# ---------------------------------------------------------------------------
# Scenario: 既存 PostToolUseFailure hook の維持 (spec.md line 11)
# WHEN: Bash ツールが失敗する
# THEN: post-tool-use-bash-error.sh が発火する（if 条件なし、全失敗対象）
# ---------------------------------------------------------------------------

# PostToolUseFailure に Bash matcher のエントリが存在する
test_posttooluseFailure_bash_exists() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
hooks = data.get('hooks', {}).get('PostToolUseFailure', [])
found = any(
    'Bash' in str(h.get('matcher', ''))
    for h in hooks if isinstance(h, dict)
)
sys.exit(0 if found else 1)
"
}
run_test "既存 PostToolUseFailure hook の維持: Bash matcher が存在する" test_posttooluseFailure_bash_exists

# post-tool-use-bash-error.sh が command に含まれる
test_posttooluseFailure_error_script() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
hooks = data.get('hooks', {}).get('PostToolUseFailure', [])
found = False
for h in hooks:
    if not isinstance(h, dict):
        continue
    if 'Bash' not in str(h.get('matcher', '')):
        continue
    for inner in h.get('hooks', []):
        if 'post-tool-use-bash-error' in str(inner.get('command', '')):
            found = True
sys.exit(0 if found else 1)
"
}
run_test "既存 PostToolUseFailure hook の維持: post-tool-use-bash-error.sh が command に含まれる" test_posttooluseFailure_error_script

# [edge-case] PostToolUseFailure Bash hook に 'if' フィールドが存在しない
test_posttooluseFailure_no_if_condition() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
hooks = data.get('hooks', {}).get('PostToolUseFailure', [])
for h in hooks:
    if not isinstance(h, dict):
        continue
    if 'Bash' in str(h.get('matcher', '')):
        if 'if' in h:
            print(f'Unexpected if field: {h[\"if\"]}', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "既存 PostToolUseFailure hook の維持 [edge: if 条件なし]" test_posttooluseFailure_no_if_condition

# ---------------------------------------------------------------------------
# Scenario: if 条件付き hook の構文検証 (spec.md line 15)
# WHEN: hooks/hooks.json に "if" フィールドを持つ hook エントリが存在する
# THEN: Claude Code v2.1.85+ の if 条件構文に準拠していなければならない（MUST）
# ---------------------------------------------------------------------------

# 'if' フィールドを持つ hook が存在する場合、構文が文字列型である
test_if_condition_is_string_when_present() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
all_hooks = []
for hook_type, entries in data.get('hooks', {}).items():
    if isinstance(entries, list):
        all_hooks.extend(entries)
for h in all_hooks:
    if not isinstance(h, dict):
        continue
    if 'if' in h:
        if not isinstance(h['if'], str):
            print(f'if field is {type(h[\"if\"]).__name__}, expected str', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "if 条件付き hook の構文検証: if フィールドは文字列型" test_if_condition_is_string_when_present

# [edge-case] 'if' 条件が空文字列でない
test_if_condition_not_empty() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
all_hooks = []
for hook_type, entries in data.get('hooks', {}).items():
    if isinstance(entries, list):
        all_hooks.extend(entries)
for h in all_hooks:
    if not isinstance(h, dict):
        continue
    if 'if' in h:
        if not h['if'].strip():
            print('if field is empty string', file=sys.stderr)
            sys.exit(1)
sys.exit(0)
"
}
run_test "if 条件付き hook の構文検証 [edge: if フィールドが空でない]" test_if_condition_not_empty

# [edge-case] hooks.json 全体のスキーマ: hooks キーが存在し dict 型
test_hooks_json_schema_structure() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
if 'hooks' not in data:
    print('Missing top-level hooks key', file=sys.stderr)
    sys.exit(1)
if not isinstance(data['hooks'], dict):
    print(f'hooks is {type(data[\"hooks\"]).__name__}, expected dict', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "if 条件付き hook の構文検証 [edge: hooks スキーマ構造]" test_hooks_json_schema_structure

# [edge-case] 各 hook エントリの type フィールドが 'command' である
test_hook_entries_type_command() {
  assert_file_exists "$HOOKS_FILE" || return 1
  json_query "$HOOKS_FILE" "
for hook_type, entries in data.get('hooks', {}).items():
    if not isinstance(entries, list):
        continue
    for h in entries:
        if not isinstance(h, dict):
            continue
        for inner in h.get('hooks', []):
            if isinstance(inner, dict) and 'type' in inner:
                if inner['type'] != 'command':
                    print(f'hook type={inner[\"type\"]}, expected command', file=sys.stderr)
                    sys.exit(1)
sys.exit(0)
"
}
run_test "if 条件付き hook の構文検証 [edge: hook type は command]" test_hook_entries_type_command

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
