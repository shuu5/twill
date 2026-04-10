#!/usr/bin/env bash
# =============================================================================
# Integration Tests: Issue-446 spec-review gate
#
# Covers:
#   1. check-specialist-completeness.sh の spec-review context フィルタ
#      - spec-review-issue-NNN context で 3/3 完了 → session state completed++ される
#      - phase-review-xxx context では session state は変更されない
#   2. hooks.json への PreToolUse/Skill 登録
#   3. workflow-issue-refine/SKILL.md の Step 3b に spec-review-session-init.sh 呼び出し
#   4. architecture/domain/contexts/issue-mgmt.md の Constraints に IM-7 が存在
#   5. deps.yaml に spec-review-session-init, pre-tool-use-spec-review-gate が登録
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK_SCRIPT="${PROJECT_ROOT}/scripts/hooks/check-specialist-completeness.sh"
HOOKS_JSON="${PROJECT_ROOT}/hooks/hooks.json"
SKILL_MD="${PROJECT_ROOT}/skills/workflow-issue-refine/SKILL.md"
ISSUE_MGMT_MD="${PROJECT_ROOT}/architecture/domain/contexts/issue-mgmt.md"
DEPS_YAML="${PROJECT_ROOT}/deps.yaml"
INIT_SCRIPT="${PROJECT_ROOT}/scripts/spec-review-session-init.sh"
GATE_SCRIPT="${PROJECT_ROOT}/scripts/hooks/pre-tool-use-spec-review-gate.sh"

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

# Unique per-process prefix to avoid /tmp collision in parallel runs
CTX_PREFIX="srgtest-$$-$RANDOM"

cleanup_ctx() {
  local ctx="$1"
  rm -f "/tmp/.specialist-manifest-${ctx}.txt" \
        "/tmp/.specialist-spawned-${ctx}.txt"
}

# Compute session state file path from a project root value
_state_file_for_root() {
  local root="$1"
  local hash
  hash=$(printf '%s' "$root" | cksum | awk '{print $1}')
  echo "/tmp/.spec-review-session-${hash}.json"
}

hook_input() {
  local tool_name="$1"
  local subagent_type="$2"
  printf '{"tool_name":"%s","tool_input":{"subagent_type":"%s"}}' "$tool_name" "$subagent_type"
}

# ---------------------------------------------------------------------------
# Requirement: check-specialist-completeness.sh — spec-review context でインクリメント
#
# WHEN マニフェストの context が spec-review-issue-123 で 3/3 specialist が完了する
# THEN /tmp/.spec-review-session-{hash}.json の completed が 1 増加する
# ---------------------------------------------------------------------------
test_spec_review_context_increments_state() {
  [[ -x "$HOOK_SCRIPT" ]] || { echo "hook not found: $HOOK_SCRIPT" >&2; return 1; }

  local ctx="${CTX_PREFIX}-spec-review-issue-123"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  local sf="/tmp/.specialist-spawned-${ctx}.txt"

  # Use a temp dir as project root to get a predictable hash
  local fake_root
  fake_root=$(mktemp -d)
  local state_file
  state_file=$(_state_file_for_root "$fake_root")

  # Initialize session state with completed=0
  printf '{"total":1,"completed":0,"issues":{}}' > "$state_file"

  # Set up manifest with 3 specialists
  printf 'issue-critic\nissue-feasibility\nworker-codex-reviewer\n' > "$mf"

  # Spawn all 3 specialists (simulate PostToolUse for each)
  local specialists=("issue-critic" "issue-feasibility" "worker-codex-reviewer")
  for sp in "${specialists[@]}"; do
    CLAUDE_PROJECT_ROOT="$fake_root" hook_input "Agent" "twl:twl:${sp}" | bash "$HOOK_SCRIPT" >/dev/null 2>&1
  done

  # After all 3 done, the hook should have incremented completed
  # (This tests that the hook calls increment logic when context matches spec-review-* prefix)
  local completed
  completed=$(jq -r '.completed' "$state_file" 2>/dev/null || echo "-1")

  cleanup_ctx "$ctx"
  rm -f "$state_file"
  rm -rf "$fake_root"

  # The completed count should be 1 (incremented once when all 3 specialists done)
  if [[ "$completed" -eq 1 ]]; then
    return 0
  else
    echo "expected completed=1, got: $completed" >&2
    # If the hook doesn't yet implement increment, this test will FAIL as expected (pending)
    return 1
  fi
}
run_test "spec-review-* context で 3/3 完了時に session state completed がインクリメントされる" test_spec_review_context_increments_state

# ---------------------------------------------------------------------------
# Requirement: check-specialist-completeness.sh — 他 context への非影響
#
# WHEN マニフェストの context が phase-review-xxx で 3/3 specialist が完了する
# THEN セッション state は変更されない
# ---------------------------------------------------------------------------
test_other_context_does_not_touch_state() {
  [[ -x "$HOOK_SCRIPT" ]] || { echo "hook not found: $HOOK_SCRIPT" >&2; return 1; }

  local ctx="${CTX_PREFIX}-phase-review-xxx"
  local mf="/tmp/.specialist-manifest-${ctx}.txt"
  local fake_root
  fake_root=$(mktemp -d)
  local state_file
  state_file=$(_state_file_for_root "$fake_root")

  # Initialize session state with completed=0
  printf '{"total":1,"completed":0,"issues":{}}' > "$state_file"
  local mtime_before
  mtime_before=$(stat -c '%Y' "$state_file" 2>/dev/null || stat -f '%m' "$state_file" 2>/dev/null)

  # Set up manifest
  printf 'issue-critic\nissue-feasibility\nworker-codex-reviewer\n' > "$mf"

  # Spawn all 3 specialists
  local specialists=("issue-critic" "issue-feasibility" "worker-codex-reviewer")
  for sp in "${specialists[@]}"; do
    CLAUDE_PROJECT_ROOT="$fake_root" hook_input "Agent" "twl:twl:${sp}" | bash "$HOOK_SCRIPT" >/dev/null 2>&1
  done

  # State file should not have been modified
  local completed
  completed=$(jq -r '.completed' "$state_file" 2>/dev/null || echo "-1")

  cleanup_ctx "$ctx"
  rm -f "$state_file"
  rm -rf "$fake_root"

  if [[ "$completed" -eq 0 ]]; then
    return 0
  else
    echo "expected completed=0 (unchanged), got: $completed" >&2
    return 1
  fi
}
run_test "phase-review-* context では session state completed が変更されない" test_other_context_does_not_touch_state

# ---------------------------------------------------------------------------
# Requirement: hooks.json への PreToolUse 登録確認
#
# WHEN hooks.json の PreToolUse セクションを参照する
# THEN {"matcher":"Skill","hooks":[{"type":"command","command":"...pre-tool-use-spec-review-gate.sh"}]} エントリが存在する
# ---------------------------------------------------------------------------
test_hooks_json_pretooluse_skill_entry() {
  [[ -f "$HOOKS_JSON" ]] || { echo "hooks.json not found: $HOOKS_JSON" >&2; return 1; }

  # Check: PreToolUse には matcher="Skill" のエントリが存在する
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Skill")' "$HOOKS_JSON" >/dev/null 2>&1 \
    || { echo "PreToolUse Skill matcher not found in hooks.json" >&2; return 1; }

  # Check: そのエントリの hooks に pre-tool-use-spec-review-gate.sh が含まれる
  jq -e '.hooks.PreToolUse[] | select(.matcher == "Skill") | .hooks[] | select(.command | contains("pre-tool-use-spec-review-gate.sh"))' \
    "$HOOKS_JSON" >/dev/null 2>&1 \
    || { echo "pre-tool-use-spec-review-gate.sh not registered under Skill matcher" >&2; return 1; }
}
run_test "hooks.json の PreToolUse に Skill matcher + pre-tool-use-spec-review-gate.sh が登録されている" test_hooks_json_pretooluse_skill_entry

# ---------------------------------------------------------------------------
# Requirement: workflow-issue-refine/SKILL.md の Step 3b にセッション初期化ステップ
#
# WHEN workflow-issue-refine/SKILL.md の Step 3b を参照する
# THEN spec-review-session-init.sh の呼び出し手順が記載されている
# ---------------------------------------------------------------------------
test_skillmd_step3b_has_session_init() {
  [[ -f "$SKILL_MD" ]] || { echo "SKILL.md not found: $SKILL_MD" >&2; return 1; }

  grep -q "spec-review-session-init" "$SKILL_MD" \
    || { echo "spec-review-session-init not found in SKILL.md" >&2; return 1; }
}
run_test "workflow-issue-refine/SKILL.md の Step 3b に spec-review-session-init.sh の呼び出しが記載されている" test_skillmd_step3b_has_session_init

# ---------------------------------------------------------------------------
# Requirement: issue-mgmt.md の Constraints に IM-7 が存在
#
# WHEN architecture/domain/contexts/issue-mgmt.md の Constraints セクションを参照する
# THEN IM-7 として specialist spawn の機械的保証を規定するエントリが存在する
# ---------------------------------------------------------------------------
test_issue_mgmt_has_im7() {
  [[ -f "$ISSUE_MGMT_MD" ]] || { echo "issue-mgmt.md not found: $ISSUE_MGMT_MD" >&2; return 1; }

  grep -q "IM-7" "$ISSUE_MGMT_MD" \
    || { echo "IM-7 not found in issue-mgmt.md" >&2; return 1; }
}
run_test "architecture/domain/contexts/issue-mgmt.md に制約 IM-7 が存在する" test_issue_mgmt_has_im7

# ---------------------------------------------------------------------------
# Requirement: deps.yaml に spec-review-session-init エントリが存在
#
# WHEN deps.yaml を参照する
# THEN spec-review-session-init が script タイプで登録されている
# ---------------------------------------------------------------------------
test_deps_yaml_session_init_entry() {
  [[ -f "$DEPS_YAML" ]] || { echo "deps.yaml not found: $DEPS_YAML" >&2; return 1; }

  grep -q "spec-review-session-init" "$DEPS_YAML" \
    || { echo "spec-review-session-init not found in deps.yaml" >&2; return 1; }
}
run_test "deps.yaml に spec-review-session-init が登録されている" test_deps_yaml_session_init_entry

# ---------------------------------------------------------------------------
# Requirement: deps.yaml に pre-tool-use-spec-review-gate エントリが存在
#
# WHEN deps.yaml を参照する
# THEN pre-tool-use-spec-review-gate が script タイプで登録されている
# ---------------------------------------------------------------------------
test_deps_yaml_gate_entry() {
  [[ -f "$DEPS_YAML" ]] || { echo "deps.yaml not found: $DEPS_YAML" >&2; return 1; }

  grep -q "pre-tool-use-spec-review-gate" "$DEPS_YAML" \
    || { echo "pre-tool-use-spec-review-gate not found in deps.yaml" >&2; return 1; }
}
run_test "deps.yaml に pre-tool-use-spec-review-gate が登録されている" test_deps_yaml_gate_entry

# ---------------------------------------------------------------------------
# Requirement: spec-review-session-init.sh が存在し実行可能
# ---------------------------------------------------------------------------
test_init_script_exists() {
  [[ -f "$INIT_SCRIPT" ]] || { echo "missing: $INIT_SCRIPT" >&2; return 1; }
  [[ -x "$INIT_SCRIPT" ]] || { echo "not executable: $INIT_SCRIPT" >&2; return 1; }
}
run_test "spec-review-session-init.sh が存在し実行可能である" test_init_script_exists

# ---------------------------------------------------------------------------
# Requirement: pre-tool-use-spec-review-gate.sh が存在し実行可能
# ---------------------------------------------------------------------------
test_gate_script_exists() {
  [[ -f "$GATE_SCRIPT" ]] || { echo "missing: $GATE_SCRIPT" >&2; return 1; }
  [[ -x "$GATE_SCRIPT" ]] || { echo "not executable: $GATE_SCRIPT" >&2; return 1; }
}
run_test "pre-tool-use-spec-review-gate.sh が存在し実行可能である" test_gate_script_exists

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
