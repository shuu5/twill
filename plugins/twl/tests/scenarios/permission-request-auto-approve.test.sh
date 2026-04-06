#!/usr/bin/env bash
# =============================================================================
# Functional Tests: permission-request-auto-approve.md
# Generated from: deltaspec/changes/claude-code-hooks-autopilot/specs/permission-request-auto-approve.md
# Coverage level: edge-cases
# Tests the actual behavior of scripts/hooks/permission-request-auto-approve.sh
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/permission-request-auto-approve.sh"
HOOKS_JSON="${PROJECT_ROOT}/hooks/hooks.json"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Sandbox Setup ---

SANDBOX=""

setup_sandbox() {
  SANDBOX=$(mktemp -d)
  mkdir -p "${SANDBOX}/scripts/hooks"
  mkdir -p "${SANDBOX}/.autopilot"
  if [[ -f "$HOOK_SCRIPT" ]]; then
    cp "$HOOK_SCRIPT" "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh"
    chmod +x "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh"
  fi
}

teardown_sandbox() {
  if [[ -n "$SANDBOX" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
  SANDBOX=""
}

# Run the hook with AUTOPILOT_DIR set (autopilot context)
run_hook_with_autopilot() {
  local input_json="${1:-{}}"
  printf '%s' "$input_json" | \
    AUTOPILOT_DIR="${SANDBOX}/.autopilot" \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null
}

# Run the hook WITHOUT AUTOPILOT_DIR (normal session)
run_hook_without_autopilot() {
  local input_json="${1:-{}}"
  printf '%s' "$input_json" | \
    env -u AUTOPILOT_DIR \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null
}

# --- Test Helpers ---

run_test() {
  local name="$1"
  local func="$2"
  local result
  setup_sandbox
  result=0
  $func || result=$?
  teardown_sandbox
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

hook_available() {
  [[ -f "$HOOK_SCRIPT" ]]
}

# =============================================================================
# Requirement: PermissionRequest 自動承認
# =============================================================================
echo ""
echo "--- Requirement: PermissionRequest 自動承認 ---"

# Scenario: autopilot 配下での permission 要求 (line 8)
# WHEN: PermissionRequest hook が発火し、環境変数 AUTOPILOT_DIR が設定されている
# THEN: hook スクリプトが "allow" を返し、permission ダイアログをスキップしなければならない
test_auto_approve_with_autopilot_dir() {
  local input_json='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
  local output
  output=$(run_hook_with_autopilot "$input_json")
  [[ -n "$output" ]] || return 1
  # Output must be valid JSON
  echo "$output" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null || return 1
  # Must contain "allow" as the decision
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
content = json.dumps(d)
# Accept 'allow' as value in any relevant key: decision, behavior, permissionDecision
assert 'allow' in content.lower(), f'allow not found in output: {content}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "autopilot 配下での permission 要求 → allow 返却" test_auto_approve_with_autopilot_dir
else
  run_test_skip "autopilot 配下での permission 要求 → allow 返却" "hook script not found"
fi

# Edge case: 出力 JSON に "behavior" または "decision" キーで "allow" が含まれる
test_auto_approve_output_structure() {
  local output
  output=$(run_hook_with_autopilot '{"tool_name":"Edit","tool_input":{"path":"/tmp/test"}}')
  [[ -n "$output" ]] || return 1
  echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
# Claude Code PermissionRequest hook expects: { 'behavior': 'allow' } or { 'decision': 'allow' }
h = d.get('hookSpecificOutput', {})
has_allow = (
    h.get('permissionDecision') == 'allow' or
    d.get('behavior') == 'allow' or
    d.get('decision') == 'allow'
)
assert has_allow, f'allow decision not found: {d}'
" 2>/dev/null || return 1
}

if hook_available; then
  run_test "autopilot permission 自動承認 [edge: JSON 出力構造]" test_auto_approve_output_structure
else
  run_test_skip "autopilot permission 自動承認 [edge: JSON 出力構造]" "hook script not found"
fi

# Edge case: 異なる tool_name でも autopilot 配下なら全て allow
test_auto_approve_all_tools_in_autopilot() {
  local tools=("Bash" "Edit" "Write" "Read" "WebSearch" "mcp__tool")
  for tool in "${tools[@]}"; do
    local input_json
    input_json=$(printf '{"tool_name":"%s","tool_input":{}}' "$tool")
    local output
    output=$(run_hook_with_autopilot "$input_json")
    [[ -n "$output" ]] || return 1
    echo "$output" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert 'allow' in json.dumps(d).lower(), f'allow not found for tool $tool: {d}'
" 2>/dev/null || return 1
  done
}

if hook_available; then
  run_test "autopilot permission 自動承認 [edge: 全 tool_name で allow]" test_auto_approve_all_tools_in_autopilot
else
  run_test_skip "autopilot permission 自動承認 [edge: 全 tool_name で allow]" "hook script not found"
fi

# Scenario: 通常セッションでの permission 要求 (line 12)
# WHEN: PermissionRequest hook が発火し、環境変数 AUTOPILOT_DIR が未設定
# THEN: hook スクリプトは JSON を出力せず exit 0 で終了する（通常の permission フローに影響を与えない）
test_no_approve_without_autopilot_dir() {
  local output
  output=$(run_hook_without_autopilot '{"tool_name":"Bash","tool_input":{"command":"ls"}}')
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
  # Must NOT output any JSON (empty stdout)
  [[ -z "$output" ]] || return 1
}

if hook_available; then
  run_test "通常セッションでの permission 要求 → JSON 出力なし、exit 0" test_no_approve_without_autopilot_dir
else
  run_test_skip "通常セッションでの permission 要求 → JSON 出力なし、exit 0" "hook script not found"
fi

# Edge case: AUTOPILOT_DIR が空文字列でも no-op になる
test_no_approve_empty_autopilot_dir() {
  local output
  output=$(printf '{"tool_name":"Bash","tool_input":{}}' | \
    AUTOPILOT_DIR="" \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null)
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
  [[ -z "$output" ]] || return 1
}

if hook_available; then
  run_test "通常セッション permission [edge: AUTOPILOT_DIR 空文字も no-op]" test_no_approve_empty_autopilot_dir
else
  run_test_skip "通常セッション permission [edge: AUTOPILOT_DIR 空文字も no-op]" "hook script not found"
fi

# Edge case: 通常セッションで JSON が出力されないこと（空 stdout）を確認
test_no_output_without_autopilot_various_inputs() {
  local inputs=(
    '{"tool_name":"Edit","tool_input":{"path":"/etc/passwd"}}'
    '{"tool_name":"Write","tool_input":{}}'
    '{}'
    ''
  )
  for input_json in "${inputs[@]}"; do
    local output
    output=$(printf '%s' "$input_json" | \
      env -u AUTOPILOT_DIR \
      bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null)
    # stdout must be empty for normal session
    [[ -z "$output" ]] || return 1
  done
}

if hook_available; then
  run_test "通常セッション permission [edge: 各種入力で stdout 空]" test_no_output_without_autopilot_various_inputs
else
  run_test_skip "通常セッション permission [edge: 各種入力で stdout 空]" "hook script not found"
fi

# Edge case: hook が常に exit 0 を返す（ブロッキング禁止）
test_hook_always_exit_zero() {
  local result

  # autopilot context
  printf '{"tool_name":"Bash","tool_input":{}}' | \
    AUTOPILOT_DIR="${SANDBOX}/.autopilot" \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1

  # no autopilot context
  printf '{"tool_name":"Bash","tool_input":{}}' | \
    env -u AUTOPILOT_DIR \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1

  # invalid input
  printf 'not json' | \
    AUTOPILOT_DIR="${SANDBOX}/.autopilot" \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null
  result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if hook_available; then
  run_test "hook が常に exit 0 [edge: ブロッキング禁止]" test_hook_always_exit_zero
else
  run_test_skip "hook が常に exit 0 [edge: ブロッキング禁止]" "hook script not found"
fi

# Edge case: 不正 JSON 入力でも crash しない
test_hook_invalid_json_no_crash() {
  printf 'totally invalid {{{{' | \
    AUTOPILOT_DIR="${SANDBOX}/.autopilot" \
    bash "${SANDBOX}/scripts/hooks/permission-request-auto-approve.sh" 2>/dev/null
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if hook_available; then
  run_test "不正 JSON 入力でも crash しない [edge]" test_hook_invalid_json_no_crash
else
  run_test_skip "不正 JSON 入力でも crash しない" "hook script not found"
fi

# Scenario: hooks.json への登録 (line 16)
# WHEN: hooks/hooks.json を読み込む
# THEN: PermissionRequest セクションにエントリが存在しなければならない
test_hooks_json_has_permission_request() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
has_perm = 'PermissionRequest' in hooks and len(hooks['PermissionRequest']) > 0
sys.exit(0 if has_perm else 1)
" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json に PermissionRequest エントリ登録" test_hooks_json_has_permission_request
else
  run_test_skip "hooks.json に PermissionRequest エントリ登録" "hooks.json not found"
fi

# Edge case: PermissionRequest エントリに command フィールドが存在する
test_hooks_json_permission_request_has_command() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PermissionRequest', [])
for entry in entries:
    if not isinstance(entry, dict):
        continue
    inner = entry.get('hooks', [])
    if isinstance(inner, list):
        for ih in inner:
            if isinstance(ih, dict) and 'command' in ih:
                sys.exit(0)
    if 'command' in entry:
        sys.exit(0)
sys.exit(1)
" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json PermissionRequest [edge: command フィールド存在]" test_hooks_json_permission_request_has_command
else
  run_test_skip "hooks.json PermissionRequest [edge: command フィールド存在]" "hooks.json not found"
fi

# Edge case: hooks.json が有効な JSON
test_hooks_json_valid() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "import json; json.load(open('$HOOKS_JSON'))" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json [edge: 有効な JSON]" test_hooks_json_valid
else
  run_test_skip "hooks.json [edge: 有効な JSON]" "hooks.json not found"
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
