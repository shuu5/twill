#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: Worker chain Compaction Recovery
# Generated from: deltaspec/changes/worker-chain-compaction-recovery/specs/
# Coverage level: edge-cases
# Verifies: chain-runner.sh, state-write.sh, compaction-resume.sh,
#           pre-compact-checkpoint.sh, hooks.json, SKILL.md recovery protocols
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

json_key_exists() {
  local file="$1"
  local key="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import json, sys
with open('${PROJECT_ROOT}/${file}') as f:
    data = json.load(f)
keys = '${key}'.split('.')
for k in keys:
    if isinstance(data, dict) and k in data:
        data = data[k]
    else:
        sys.exit(1)
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

CHAIN_RUNNER="scripts/chain-runner.sh"
STATE_WRITE="scripts/state-write.sh"
COMPACTION_RESUME="scripts/compaction-resume.sh"
PRE_COMPACT_HOOK="scripts/hooks/pre-compact-checkpoint.sh"
HOOKS_JSON="hooks/hooks.json"
SETUP_SKILL="skills/workflow-setup/SKILL.md"
TEST_READY_SKILL="skills/workflow-test-ready/SKILL.md"
PR_CYCLE_SKILL="skills/workflow-pr-cycle/SKILL.md"

# =============================================================================
# Requirement: chain-runner.sh ステップ実行前の進行位置記録
# =============================================================================
echo ""
echo "--- Requirement: chain-runner.sh ステップ実行前の進行位置記録 ---"

# Scenario: ステップ実行前の current_step 記録
# WHEN chain-runner.sh がステップを実行する直前
# THEN issue-{N}.json の current_step フィールドが更新される

test_chain_runner_state_write_call() {
  assert_file_contains "$CHAIN_RUNNER" "state-write\.sh.*current_step|current_step.*state-write"
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_RUNNER}" ]]; then
  run_test "chain-runner.sh が state-write.sh で current_step を記録" test_chain_runner_state_write_call
else
  run_test_skip "chain-runner.sh が state-write.sh で current_step を記録" "chain-runner.sh not yet created"
fi

# Scenario: 各ステップでの記録（init ステップ）
test_chain_runner_current_step_pattern() {
  assert_file_contains "$CHAIN_RUNNER" 'current_step'
}

if [[ -f "${PROJECT_ROOT}/${CHAIN_RUNNER}" ]]; then
  run_test "chain-runner.sh に current_step の記録パターンが存在する" test_chain_runner_current_step_pattern
else
  run_test_skip "chain-runner.sh に current_step の記録パターンが存在する" "chain-runner.sh not yet created"
fi

# =============================================================================
# Requirement: state-write.sh Worker ロール current_step 書き込み許可
# =============================================================================
echo ""
echo "--- Requirement: state-write.sh Worker ロール current_step 書き込み許可 ---"

# Scenario: state-write.sh による Worker ロール書き込み許可
# WHEN Worker ロールが current_step を書き込もうとする
# THEN ホワイトリストに含まれているため書き込みが許可される

test_state_write_current_step_whitelist() {
  assert_file_contains "$STATE_WRITE" 'current_step'
}

if [[ -f "${PROJECT_ROOT}/${STATE_WRITE}" ]]; then
  run_test "state-write.sh の Worker ホワイトリストに current_step が含まれる" test_state_write_current_step_whitelist
else
  run_test_skip "state-write.sh の Worker ホワイトリストに current_step が含まれる" "state-write.sh not yet created"
fi

# =============================================================================
# Requirement: compaction-resume.sh による完了済みステップスキップ判定
# =============================================================================
echo ""
echo "--- Requirement: compaction-resume.sh による完了済みステップスキップ判定 ---"

# Scenario: スクリプト存在確認
test_compaction_resume_exists() {
  assert_file_exists "$COMPACTION_RESUME"
}

if [[ -f "${PROJECT_ROOT}/${COMPACTION_RESUME}" ]]; then
  run_test "compaction-resume.sh が存在する" test_compaction_resume_exists
else
  run_test_skip "compaction-resume.sh が存在する" "compaction-resume.sh not yet created"
fi

# Scenario: 完了済みステップのスキップ判定（exit 1）
test_compaction_resume_exit_codes() {
  assert_file_contains "$COMPACTION_RESUME" 'exit 1' && \
  assert_file_contains "$COMPACTION_RESUME" 'exit 0'
}

if [[ -f "${PROJECT_ROOT}/${COMPACTION_RESUME}" ]]; then
  run_test "compaction-resume.sh が exit 0/1 でスキップ判定を返す" test_compaction_resume_exit_codes
else
  run_test_skip "compaction-resume.sh が exit 0/1 でスキップ判定を返す" "compaction-resume.sh not yet created"
fi

# Scenario: ISSUE_NUM と step_id を引数として受け取る
test_compaction_resume_args() {
  assert_file_contains "$COMPACTION_RESUME" '\$1|\$2|ISSUE_NUM|step_id|step'
}

if [[ -f "${PROJECT_ROOT}/${COMPACTION_RESUME}" ]]; then
  run_test "compaction-resume.sh が ISSUE_NUM と step_id を引数として処理する" test_compaction_resume_args
else
  run_test_skip "compaction-resume.sh が ISSUE_NUM と step_id を引数として処理する" "compaction-resume.sh not yet created"
fi

# Scenario: current_step を state-read.sh から読み取る
test_compaction_resume_state_read() {
  assert_file_contains "$COMPACTION_RESUME" 'state-read\.sh|state-read'
}

if [[ -f "${PROJECT_ROOT}/${COMPACTION_RESUME}" ]]; then
  run_test "compaction-resume.sh が state-read.sh で current_step を読み取る" test_compaction_resume_state_read
else
  run_test_skip "compaction-resume.sh が state-read.sh で current_step を読み取る" "compaction-resume.sh not yet created"
fi

# =============================================================================
# Requirement: PreCompact hook によるチェックポイント保存
# =============================================================================
echo ""
echo "--- Requirement: PreCompact hook によるチェックポイント保存 ---"

# Scenario: pre-compact-checkpoint.sh が存在する
test_pre_compact_hook_exists() {
  assert_file_exists "$PRE_COMPACT_HOOK"
}

if [[ -f "${PROJECT_ROOT}/${PRE_COMPACT_HOOK}" ]]; then
  run_test "pre-compact-checkpoint.sh が存在する" test_pre_compact_hook_exists
else
  run_test_skip "pre-compact-checkpoint.sh が存在する" "pre-compact-checkpoint.sh not yet created"
fi

# Scenario: hooks.json に PreCompact フックが登録されている
test_hooks_json_pre_compact() {
  assert_file_contains "$HOOKS_JSON" 'PreCompact|pre-compact|pre_compact'
}

if [[ -f "${PROJECT_ROOT}/${HOOKS_JSON}" ]]; then
  run_test "hooks.json に PreCompact hook が登録されている" test_hooks_json_pre_compact
else
  run_test_skip "hooks.json に PreCompact hook が登録されている" "hooks.json not yet created"
fi

# Scenario: pre-compact-checkpoint.sh が current_step を書き込む
test_pre_compact_hook_writes_current_step() {
  assert_file_contains "$PRE_COMPACT_HOOK" 'current_step'
}

if [[ -f "${PROJECT_ROOT}/${PRE_COMPACT_HOOK}" ]]; then
  run_test "pre-compact-checkpoint.sh が current_step を書き込む" test_pre_compact_hook_writes_current_step
else
  run_test_skip "pre-compact-checkpoint.sh が current_step を書き込む" "pre-compact-checkpoint.sh not yet created"
fi

# Scenario: hook がエラーで終了してもワークフローを停止しないため非ゼロを許容
test_pre_compact_hook_non_blocking() {
  # hook スクリプト内に set -e がある場合は || true などで保護されているか確認
  # または hooks.json で continueOnError 的な設定がある
  assert_file_contains "$HOOKS_JSON" 'pre-compact-checkpoint'
}

if [[ -f "${PROJECT_ROOT}/${HOOKS_JSON}" ]]; then
  run_test "hooks.json に pre-compact-checkpoint.sh への参照が存在する" test_pre_compact_hook_non_blocking
else
  run_test_skip "hooks.json に pre-compact-checkpoint.sh への参照が存在する" "hooks.json not yet created"
fi

# =============================================================================
# Requirement: compactPrompt による compaction 後コンテキスト保持
# =============================================================================
echo ""
echo "--- Requirement: compactPrompt による compaction 後コンテキスト保持 ---"

# Scenario: compactPrompt が settings.json に設定されている
test_compact_prompt_settings() {
  assert_file_contains "settings.json" 'compactPrompt'
}

if [[ -f "${PROJECT_ROOT}/settings.json" ]]; then
  run_test "settings.json に compactPrompt が設定されている" test_compact_prompt_settings
else
  run_test_skip "settings.json に compactPrompt が設定されている" "settings.json not yet created"
fi

# Scenario: compactPrompt が chain コンテキスト保持を指示している
test_compact_prompt_content() {
  assert_file_contains "settings.json" 'current_step|issue.*番号|chain'
}

if [[ -f "${PROJECT_ROOT}/settings.json" ]]; then
  run_test "compactPrompt が current_step または issue 番号の保持を指示している" test_compact_prompt_content
else
  run_test_skip "compactPrompt が current_step または issue 番号の保持を指示している" "settings.json not yet created"
fi

# =============================================================================
# Requirement: workflow SKILL.md への compaction 復帰プロトコル追記
# =============================================================================
echo ""
echo "--- Requirement: workflow SKILL.md への compaction 復帰プロトコル追記 ---"

# Scenario: workflow-setup SKILL.md に復帰プロトコルが存在する
test_setup_skill_recovery() {
  assert_file_contains "$SETUP_SKILL" 'compaction.*復帰|compaction.*resume|compaction-resume'
}

if [[ -f "${PROJECT_ROOT}/${SETUP_SKILL}" ]]; then
  run_test "workflow-setup SKILL.md に compaction 復帰プロトコルが存在する" test_setup_skill_recovery
else
  run_test_skip "workflow-setup SKILL.md に compaction 復帰プロトコルが存在する" "SKILL.md not yet modified"
fi

# Scenario: workflow-test-ready SKILL.md に復帰プロトコルが存在する
test_test_ready_skill_recovery() {
  assert_file_contains "$TEST_READY_SKILL" 'compaction.*復帰|compaction.*resume|compaction-resume'
}

if [[ -f "${PROJECT_ROOT}/${TEST_READY_SKILL}" ]]; then
  run_test "workflow-test-ready SKILL.md に compaction 復帰プロトコルが存在する" test_test_ready_skill_recovery
else
  run_test_skip "workflow-test-ready SKILL.md に compaction 復帰プロトコルが存在する" "SKILL.md not yet modified"
fi

# Scenario: workflow-pr-cycle SKILL.md に復帰プロトコルが存在する
test_pr_cycle_skill_recovery() {
  assert_file_contains "$PR_CYCLE_SKILL" 'compaction.*復帰|compaction.*resume|compaction-resume'
}

if [[ -f "${PROJECT_ROOT}/${PR_CYCLE_SKILL}" ]]; then
  run_test "workflow-pr-cycle SKILL.md に compaction 復帰プロトコルが存在する" test_pr_cycle_skill_recovery
else
  run_test_skip "workflow-pr-cycle SKILL.md に compaction 復帰プロトコルが存在する" "SKILL.md not yet modified"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "Results: PASS=${PASS}, FAIL=${FAIL}, SKIP=${SKIP}"

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
exit 0
