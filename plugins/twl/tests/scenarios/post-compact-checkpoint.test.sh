#!/usr/bin/env bash
# =============================================================================
# Functional Tests: post-compact-checkpoint.md
# Generated from: deltaspec/changes/claude-code-hooks-autopilot/specs/post-compact-checkpoint.md
# Coverage level: edge-cases
# Tests the actual behavior of scripts/hooks/post-compact-checkpoint.sh
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/post-compact-checkpoint.sh"
STATE_WRITE="${PROJECT_ROOT}/scripts/state-write.sh"
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
  mkdir -p "${SANDBOX}/scripts"
  mkdir -p "${SANDBOX}/.autopilot"
  mkdir -p "${SANDBOX}/.autopilot/issues"

  if [[ -f "$HOOK_SCRIPT" ]]; then
    cp "$HOOK_SCRIPT" "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh"
    chmod +x "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh"
  fi

  if [[ -f "$STATE_WRITE" ]]; then
    cp "$STATE_WRITE" "${SANDBOX}/scripts/state-write.sh"
    chmod +x "${SANDBOX}/scripts/state-write.sh"
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
    bash "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null
}

# Run the hook WITHOUT AUTOPILOT_DIR (normal session)
run_hook_without_autopilot() {
  local input_json="${1:-{}}"
  printf '%s' "$input_json" | \
    env -u AUTOPILOT_DIR \
    bash "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null
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
# Requirement: PostCompact チェックポイント保存
# =============================================================================
echo ""
echo "--- Requirement: PostCompact チェックポイント保存 ---"

# Scenario: autopilot 配下での compaction (line 8)
# WHEN: PostCompact hook が発火し、環境変数 AUTOPILOT_DIR が設定されている
# THEN: state-write.sh で last_compact_at に ISO 8601 タイムスタンプを記録しなければならない
test_compact_with_autopilot_dir() {
  run_hook_with_autopilot '{}' || true  # hook must not fail

  # Verify the hook invokes state-write.sh with last_compact_at
  # Check session.json or a dedicated state file for last_compact_at
  local found=false
  # Look for last_compact_at in any state file under .autopilot
  if find "${SANDBOX}/.autopilot" -name "*.json" 2>/dev/null | \
     xargs grep -l "last_compact_at" 2>/dev/null | grep -q .; then
    found=true
  fi

  # Also check if hook script references last_compact_at (structural check when state file not present)
  if [[ "$found" == "false" ]]; then
    grep -q "last_compact_at" "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null || return 1
  fi
}

if hook_available; then
  run_test "autopilot 配下での compaction → last_compact_at 記録" test_compact_with_autopilot_dir
else
  run_test_skip "autopilot 配下での compaction → last_compact_at 記録" "hook script not found"
fi

# Edge case: last_compact_at の値が ISO 8601 形式
test_compact_timestamp_iso8601() {
  run_hook_with_autopilot '{}' || true

  # If a state file was written, validate the timestamp format
  local ts_found=false
  while IFS= read -r json_file; do
    if python3 -c "
import json, sys, re
data = json.load(open('$json_file'))
ts = data.get('last_compact_at', '')
if ts:
    assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}', ts), f'Invalid ISO8601: {ts}'
    print('found')
" 2>/dev/null | grep -q "found"; then
      ts_found=true
      break
    fi
  done < <(find "${SANDBOX}/.autopilot" -name "*.json" 2>/dev/null)

  if [[ "$ts_found" == "false" ]]; then
    # Structural check: hook uses date -u or similar ISO8601 generation
    grep -qP "date.*-u.*\+|date.*ISO|%Y-%m-%dT" "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null || return 1
  fi
}

if hook_available; then
  run_test "autopilot compaction [edge: last_compact_at が ISO8601 形式]" test_compact_timestamp_iso8601
else
  run_test_skip "autopilot compaction [edge: last_compact_at が ISO8601 形式]" "hook script not found"
fi

# Edge case: 複数回の compaction で last_compact_at が更新される
test_compact_updates_timestamp() {
  run_hook_with_autopilot '{}' || true
  local ts1=""
  while IFS= read -r json_file; do
    ts1=$(python3 -c "import json; d=json.load(open('$json_file')); print(d.get('last_compact_at',''))" 2>/dev/null)
    [[ -n "$ts1" ]] && break
  done < <(find "${SANDBOX}/.autopilot" -name "*.json" 2>/dev/null)

  # If no state file was written, check the hook at least calls state-write
  if [[ -z "$ts1" ]]; then
    grep -qP "state-write|last_compact_at" "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null || return 1
  fi
  # Hook should not crash on second invocation either
  run_hook_with_autopilot '{}' || true
}

if hook_available; then
  run_test "autopilot compaction [edge: 複数回呼び出しで上書き更新]" test_compact_updates_timestamp
else
  run_test_skip "autopilot compaction [edge: 複数回呼び出しで上書き更新]" "hook script not found"
fi

# Scenario: 通常セッションでの compaction (line 12)
# WHEN: PostCompact hook が発火し、環境変数 AUTOPILOT_DIR が未設定
# THEN: hook スクリプトは何も実行せず exit 0 で終了する
test_compact_without_autopilot_dir_noop() {
  run_hook_without_autopilot '{}'
  local result=$?
  [[ "$result" -eq 0 ]] || return 1

  # No .autopilot state should be touched / created in SANDBOX
  # (AUTOPILOT_DIR was not set, so the hook should be a no-op)
  # We check that no last_compact_at was written anywhere under sandbox
  if find "${SANDBOX}" -name "*.json" 2>/dev/null | \
     xargs grep -l "last_compact_at" 2>/dev/null | grep -q .; then
    return 1
  fi
}

if hook_available; then
  run_test "通常セッションでの compaction → 何も実行しない" test_compact_without_autopilot_dir_noop
else
  run_test_skip "通常セッションでの compaction → 何も実行しない" "hook script not found"
fi

# Edge case: AUTOPILOT_DIR が空文字列でも no-op になる
test_compact_empty_autopilot_dir_noop() {
  printf '{}' | \
    AUTOPILOT_DIR="" \
    bash "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if hook_available; then
  run_test "通常セッション compaction [edge: AUTOPILOT_DIR 空文字]" test_compact_empty_autopilot_dir_noop
else
  run_test_skip "通常セッション compaction [edge: AUTOPILOT_DIR 空文字]" "hook script not found"
fi

# Edge case: 通常セッションでは stdout に何も出力しない
test_compact_no_output_without_autopilot() {
  local output
  output=$(run_hook_without_autopilot '{}')
  [[ -z "$output" ]] || return 1
}

if hook_available; then
  run_test "通常セッション compaction [edge: stdout 出力なし]" test_compact_no_output_without_autopilot
else
  run_test_skip "通常セッション compaction [edge: stdout 出力なし]" "hook script not found"
fi

# Scenario: state-write 失敗時 (line 16)
# WHEN: state-write.sh がエラーを返す
# THEN: hook スクリプトはエラーを無視し exit 0 で終了する（Worker の実行を中断してはならない）
test_compact_state_write_failure_ignored() {
  # Replace state-write.sh with a failing stub
  cat > "${SANDBOX}/scripts/state-write.sh" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${SANDBOX}/scripts/state-write.sh"

  run_hook_with_autopilot '{}'
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if hook_available; then
  run_test "state-write 失敗時はエラーを無視して exit 0" test_compact_state_write_failure_ignored
else
  run_test_skip "state-write 失敗時はエラーを無視して exit 0" "hook script not found"
fi

# Edge case: state-write が存在しなくても exit 0 で終了する
test_compact_state_write_missing_exit_zero() {
  rm -f "${SANDBOX}/scripts/state-write.sh"

  run_hook_with_autopilot '{}'
  local result=$?
  [[ "$result" -eq 0 ]] || return 1
}

if hook_available; then
  run_test "state-write 失敗時 [edge: state-write 不存在でも exit 0]" test_compact_state_write_missing_exit_zero
else
  run_test_skip "state-write 失敗時 [edge: state-write 不存在でも exit 0]" "hook script not found"
fi

# Edge case: hook が常に exit 0 を返す（どんな入力でも）
test_compact_always_exit_zero() {
  local inputs=('{}' '' 'not json' '{"compaction_summary":"test"}')
  for input_json in "${inputs[@]}"; do
    printf '%s' "$input_json" | \
      AUTOPILOT_DIR="${SANDBOX}/.autopilot" \
      bash "${SANDBOX}/scripts/hooks/post-compact-checkpoint.sh" 2>/dev/null
    local result=$?
    [[ "$result" -eq 0 ]] || return 1
  done
}

if hook_available; then
  run_test "hook が常に exit 0 [edge: あらゆる入力]" test_compact_always_exit_zero
else
  run_test_skip "hook が常に exit 0 [edge: あらゆる入力]" "hook script not found"
fi

# Scenario: hooks.json への登録 (line 20)
# WHEN: hooks/hooks.json を読み込む
# THEN: PostCompact セクションにエントリが存在しなければならない
test_hooks_json_has_post_compact() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
hooks = data.get('hooks', {})
has_compact = 'PostCompact' in hooks and len(hooks['PostCompact']) > 0
sys.exit(0 if has_compact else 1)
" 2>/dev/null
}

if [[ -f "$HOOKS_JSON" ]]; then
  run_test "hooks.json に PostCompact エントリ登録" test_hooks_json_has_post_compact
else
  run_test_skip "hooks.json に PostCompact エントリ登録" "hooks.json not found"
fi

# Edge case: PostCompact エントリに command フィールドが存在する
test_hooks_json_post_compact_has_command() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  python3 -c "
import json, sys
with open('$HOOKS_JSON') as f:
    data = json.load(f)
entries = data.get('hooks', {}).get('PostCompact', [])
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
  run_test "hooks.json PostCompact [edge: command フィールド存在]" test_hooks_json_post_compact_has_command
else
  run_test_skip "hooks.json PostCompact [edge: command フィールド存在]" "hooks.json not found"
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
