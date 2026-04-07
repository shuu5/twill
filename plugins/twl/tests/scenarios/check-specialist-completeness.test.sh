#!/usr/bin/env bash
# =============================================================================
# Hook Verification Tests: check-specialist-completeness.sh
# Source: scripts/hooks/check-specialist-completeness.sh
# PostToolUse hook (Agent|Task matcher) — specialist spawn completeness check
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/check-specialist-completeness.sh"
HOOKS_JSON="${PROJECT_ROOT}/hooks/hooks.json"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

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

# Unique per-process context to avoid /tmp collisions across parallel runs
CTX_PREFIX="csc-test-$$-$RANDOM"
cleanup_ctx() {
  local ctx="$1"
  rm -f "/tmp/.specialist-manifest-${ctx}.txt" "/tmp/.specialist-spawned-${ctx}.txt"
}

hook_input() {
  local tool_name="$1"
  local subagent_type="$2"
  printf '{"tool_name":"%s","tool_input":{"subagent_type":"%s"}}' "$tool_name" "$subagent_type"
}

# ---------------------------------------------------------------------------
# Requirement 1: hook script exists and is executable
# ---------------------------------------------------------------------------
test_hook_exists() {
  [[ -f "$HOOK_SCRIPT" ]] || { echo "missing: $HOOK_SCRIPT" >&2; return 1; }
  [[ -x "$HOOK_SCRIPT" ]] || { echo "not executable: $HOOK_SCRIPT" >&2; return 1; }
  return 0
}
run_test "hook script が存在し実行可能である" test_hook_exists

# ---------------------------------------------------------------------------
# Requirement 2: hooks.json に Agent|Task matcher で登録されている
# ---------------------------------------------------------------------------
test_hook_registered() {
  [[ -f "$HOOKS_JSON" ]] || return 1
  jq -e '.hooks.PostToolUse[] | select(.matcher == "Agent|Task") | .hooks[] | select(.command | contains("check-specialist-completeness.sh"))' \
    "$HOOKS_JSON" > /dev/null
}
run_test "hooks.json に Agent|Task matcher で登録されている" test_hook_registered

# ---------------------------------------------------------------------------
# Requirement 3: マニフェスト不在時は noop（出力なし、exit 0）
# ---------------------------------------------------------------------------
test_noop_without_manifest() {
  local ctx="${CTX_PREFIX}-nomf"
  cleanup_ctx "$ctx"
  local out
  out=$(hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  local rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || { echo "exit=$rc" >&2; return 1; }
  # stdout may be empty or only from other manifests; look for our context marker not being present
  if echo "$out" | grep -q "${CTX_PREFIX}-nomf"; then
    echo "unexpected output referencing test context: $out" >&2
    return 1
  fi
  return 0
}
run_test "マニフェスト不在時は noop" test_noop_without_manifest

# ---------------------------------------------------------------------------
# Requirement 4: 非対象 tool (Bash) は noop
# ---------------------------------------------------------------------------
test_noop_wrong_tool() {
  local ctx="${CTX_PREFIX}-wrongtool"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  printf 'worker-code-reviewer\nworker-codex-reviewer\n' > "$mf"
  local out rc
  out=$(hook_input "Bash" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  if echo "$out" | grep -q "$ctx"; then
    echo "non-target tool triggered hook: $out" >&2
    return 1
  fi
  return 0
}
run_test "非対象 tool (Bash) は noop" test_noop_wrong_tool

# ---------------------------------------------------------------------------
# Requirement 5: 不足があれば stdout に警告（Agent tool）
# ---------------------------------------------------------------------------
test_warns_on_missing_agent() {
  local ctx="${CTX_PREFIX}-warn-ag"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  printf 'worker-code-reviewer\nworker-codex-reviewer\n' > "$mf"
  local out rc
  out=$(hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  echo "$out" | grep -q "worker-codex-reviewer" || { echo "missing warning absent: $out" >&2; return 1; }
  echo "$out" | grep -q "$ctx" || { echo "context not in warning: $out" >&2; return 1; }
  return 0
}
run_test "不足 specialist を Agent tool 後に stdout 警告する" test_warns_on_missing_agent

# ---------------------------------------------------------------------------
# Requirement 6: Task tool でも発火する
# ---------------------------------------------------------------------------
test_warns_on_missing_task() {
  local ctx="${CTX_PREFIX}-warn-tk"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  printf 'worker-code-reviewer\nworker-codex-reviewer\n' > "$mf"
  local out rc
  out=$(hook_input "Task" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  echo "$out" | grep -q "worker-codex-reviewer" || { echo "Task tool did not trigger warning: $out" >&2; return 1; }
  return 0
}
run_test "Task tool でも hook が発火する" test_warns_on_missing_task

# ---------------------------------------------------------------------------
# Requirement 7: 全件 spawn 済みなら noop
# ---------------------------------------------------------------------------
test_noop_all_spawned() {
  local ctx="${CTX_PREFIX}-allspawned"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  local sf="/tmp/.specialist-spawned-${ctx}.txt"
  printf 'worker-code-reviewer\nworker-codex-reviewer\n' > "$mf"
  printf 'worker-code-reviewer\nworker-codex-reviewer\n' > "$sf"
  local out rc
  out=$(hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  if echo "$out" | grep -q "$ctx"; then
    echo "noop violated when all spawned: $out" >&2
    return 1
  fi
  return 0
}
run_test "全件 spawn 済みなら noop" test_noop_all_spawned

# ---------------------------------------------------------------------------
# Requirement 8: twl:twl: プレフィックスを strip して照合する
# ---------------------------------------------------------------------------
test_prefix_stripped() {
  local ctx="${CTX_PREFIX}-prefix"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  local sf="/tmp/.specialist-spawned-${ctx}.txt"
  printf 'worker-code-reviewer\n' > "$mf"
  hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" >/dev/null 2>&1
  local result=1
  if [[ -f "$sf" ]] && grep -Fxq "worker-code-reviewer" "$sf"; then
    result=0
  fi
  cleanup_ctx "$ctx"
  return $result
}
run_test "twl:twl: プレフィックスを strip 後に spawn tracking へ記録する" test_prefix_stripped

# ---------------------------------------------------------------------------
# Requirement 9: マニフェスト側の twl:twl: プレフィックスも正規化される
# ---------------------------------------------------------------------------
test_manifest_prefix_normalized() {
  local ctx="${CTX_PREFIX}-mfprefix"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  printf 'twl:twl:worker-code-reviewer\n' > "$mf"
  local out rc
  out=$(hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  if echo "$out" | grep -q "$ctx"; then
    echo "manifest prefix not normalized: $out" >&2
    return 1
  fi
  return 0
}
run_test "マニフェスト側の twl:twl: プレフィックスも正規化される" test_manifest_prefix_normalized

# ---------------------------------------------------------------------------
# Requirement 10: 複数コンテキストの同時実行が分離される
# ---------------------------------------------------------------------------
test_multiple_contexts_isolated() {
  local ctx_a="${CTX_PREFIX}-ctxA"
  local ctx_b="${CTX_PREFIX}-ctxB"
  printf 'worker-code-reviewer\nworker-codex-reviewer\n' > "/tmp/.specialist-manifest-${ctx_a}.txt"
  printf 'worker-code-reviewer\n' > "/tmp/.specialist-manifest-${ctx_b}.txt"

  local out rc
  out=$(hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx_a"
  cleanup_ctx "$ctx_b"

  [[ $rc -eq 0 ]] || return 1
  # Context A should still warn (codex-reviewer missing)
  echo "$out" | grep -q "$ctx_a" || { echo "ctxA warning missing: $out" >&2; return 1; }
  # Context B should be complete (no warning)
  if echo "$out" | grep -q "$ctx_b"; then
    echo "ctxB should be complete but warned: $out" >&2
    return 1
  fi
  return 0
}
run_test "複数コンテキストの同時実行が一時ファイル名で分離される" test_multiple_contexts_isolated

# ---------------------------------------------------------------------------
# Requirement 11: コメント・空行を無視する
# ---------------------------------------------------------------------------
test_ignores_comments_and_blank_lines() {
  local ctx="${CTX_PREFIX}-comments"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  cat > "$mf" <<EOF
# leading comment
worker-code-reviewer

# trailing comment
worker-codex-reviewer
EOF
  local out rc
  out=$(hook_input "Agent" "twl:twl:worker-code-reviewer" | bash "$HOOK_SCRIPT" 2>&1)
  rc=$?
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  echo "$out" | grep -q "worker-codex-reviewer" || return 1
  if echo "$out" | grep -q "# leading comment"; then
    echo "comment line leaked: $out" >&2
    return 1
  fi
  return 0
}
run_test "コメント行と空行が無視される" test_ignores_comments_and_blank_lines

# ---------------------------------------------------------------------------
# Requirement 12: subagent_type に制御文字を含む入力は拒否される
# ---------------------------------------------------------------------------
test_rejects_unsafe_subagent_type() {
  local ctx="${CTX_PREFIX}-unsafe"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  local sf="/tmp/.specialist-spawned-${ctx}.txt"
  printf 'worker-code-reviewer\n' > "$mf"
  # Inject name containing a space - should be rejected by regex validation
  local input='{"tool_name":"Agent","tool_input":{"subagent_type":"twl:twl:evil name"}}'
  printf '%s' "$input" | bash "$HOOK_SCRIPT" >/dev/null 2>&1
  local rc=$?
  local result=0
  # Must not have recorded "evil name" into spawn tracking
  if [[ -f "$sf" ]] && grep -q "evil" "$sf"; then
    echo "unsafe subagent_type recorded: $(cat "$sf")" >&2
    result=1
  fi
  cleanup_ctx "$ctx"
  [[ $rc -eq 0 ]] || return 1
  return $result
}
run_test "subagent_type に不正文字を含む入力を拒否する" test_rejects_unsafe_subagent_type

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
