#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: auto flag removal and state-based detection
# Generated from: openspec/changes/remove-auto-flags-add-state-detection/specs/
#   - autopilot-state-detection.md
#   - openspec-contradiction-fix.md
# Coverage level: edge-cases
# Verifies: --auto/--auto-merge フラグ除去 + state-read.sh ベース autopilot 判定
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

# grep across entire directory tree, excluding openspec archive/change dirs
assert_codebase_not_contains() {
  local pattern="$1"
  # Exclude openspec (historical specs), tests (test files), .git
  if grep -rqP -- "$pattern" \
      --include="*.md" \
      --exclude-dir=openspec \
      --exclude-dir=.git \
      --exclude-dir=tests \
      "${PROJECT_ROOT}/commands/" "${PROJECT_ROOT}/skills/" 2>/dev/null; then
    return 1
  fi
  return 0
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
# Requirement: --auto-merge フラグの完全除去
# Scenario: プロジェクト全体からの --auto-merge 除去 (line 93)
# WHEN: 実装コード（commands/, skills/）内で --auto-merge を検索する
# THEN: 一致するものが存在しない（openspec の過去 change/archive は対象外）
# =============================================================================
echo ""
echo "--- Requirement: --auto-merge フラグの完全除去 ---"

test_no_auto_merge_in_commands() {
  assert_codebase_not_contains "--auto-merge"
}

run_test "commands/ と skills/ に --auto-merge が存在しない" test_no_auto_merge_in_commands

test_no_auto_merge_in_workflow_setup() {
  assert_file_not_contains "skills/workflow-setup/SKILL.md" "--auto-merge"
}

run_test "skills/workflow-setup/SKILL.md に --auto-merge が存在しない" test_no_auto_merge_in_workflow_setup

test_no_auto_merge_in_autopilot_launch() {
  assert_file_not_contains "commands/autopilot-launch.md" "--auto-merge"
}

run_test "commands/autopilot-launch.md に --auto-merge が存在しない" test_no_auto_merge_in_autopilot_launch

test_no_auto_merge_in_co_autopilot() {
  assert_file_not_contains "skills/co-autopilot/SKILL.md" "--auto-merge"
}

run_test "skills/co-autopilot/SKILL.md に --auto-merge が存在しない" test_no_auto_merge_in_co_autopilot

# =============================================================================
# Requirement: workflow-setup の引数解析統一
# Scenario: workflow-setup から --auto/--auto-merge 除去 (line 27)
# WHEN: skills/workflow-setup/SKILL.md の引数解析セクションを確認する
# THEN: --auto と --auto-merge への参照が存在しない。#N の Issue 番号解析のみ残る
# =============================================================================
echo ""
echo "--- Requirement: workflow-setup の引数解析統一 ---"

WORKFLOW_SETUP="skills/workflow-setup/SKILL.md"

test_workflow_setup_file_exists() {
  assert_file_exists "$WORKFLOW_SETUP"
}

run_test "skills/workflow-setup/SKILL.md が存在する" test_workflow_setup_file_exists

test_workflow_setup_no_auto_flag() {
  assert_file_not_contains "$WORKFLOW_SETUP" "--auto[^-]|--auto$"
}

if [[ -f "${PROJECT_ROOT}/${WORKFLOW_SETUP}" ]]; then
  run_test "workflow-setup SKILL.md に --auto フラグが存在しない" test_workflow_setup_no_auto_flag
else
  run_test_skip "workflow-setup SKILL.md に --auto フラグが存在しない" "${WORKFLOW_SETUP} not found"
fi

test_workflow_setup_no_auto_merge_flag() {
  assert_file_not_contains "$WORKFLOW_SETUP" "--auto-merge"
}

if [[ -f "${PROJECT_ROOT}/${WORKFLOW_SETUP}" ]]; then
  run_test "workflow-setup SKILL.md に --auto-merge フラグが存在しない" test_workflow_setup_no_auto_merge_flag
else
  run_test_skip "workflow-setup SKILL.md に --auto-merge フラグが存在しない" "${WORKFLOW_SETUP} not found"
fi

# Scenario: workflow-setup の自動継続判定 (line 32)
# WHEN: autopilot 配下で workflow-setup が Step 4 に到達する
# THEN: state-read.sh で status=running を確認し、自動的に workflow-test-ready を実行する

test_workflow_setup_state_read_ref() {
  assert_file_contains "$WORKFLOW_SETUP" "state-read\.sh|state-read"
}

if [[ -f "${PROJECT_ROOT}/${WORKFLOW_SETUP}" ]]; then
  run_test "workflow-setup SKILL.md が state-read.sh を参照する" test_workflow_setup_state_read_ref
else
  run_test_skip "workflow-setup SKILL.md が state-read.sh を参照する" "${WORKFLOW_SETUP} not found"
fi

test_workflow_setup_is_autopilot_condition() {
  assert_file_contains "$WORKFLOW_SETUP" "IS_AUTOPILOT|status.*running|running.*status"
}

if [[ -f "${PROJECT_ROOT}/${WORKFLOW_SETUP}" ]]; then
  run_test "workflow-setup SKILL.md が IS_AUTOPILOT 判定を使用する" test_workflow_setup_is_autopilot_condition
else
  run_test_skip "workflow-setup SKILL.md が IS_AUTOPILOT 判定を使用する" "${WORKFLOW_SETUP} not found"
fi

# =============================================================================
# Requirement: opsx-apply のフラグ除去
# Scenario: opsx-apply から --auto 分岐除去 (line 39)
# WHEN: commands/opsx-apply.md を確認する
# THEN: --auto への参照が存在しない。Step 3 の分岐が IS_AUTOPILOT 判定に置換されている
# =============================================================================
echo ""
echo "--- Requirement: opsx-apply のフラグ除去 ---"

OPSX_APPLY="commands/opsx-apply.md"

test_opsx_apply_file_exists() {
  assert_file_exists "$OPSX_APPLY"
}

if [[ -f "${PROJECT_ROOT}/${OPSX_APPLY}" ]]; then
  run_test "commands/opsx-apply.md が存在する" test_opsx_apply_file_exists
else
  run_test_skip "commands/opsx-apply.md が存在する" "${OPSX_APPLY} not found"
fi

test_opsx_apply_no_auto_flag() {
  assert_file_not_contains "$OPSX_APPLY" "--auto[^-]|--auto$"
}

if [[ -f "${PROJECT_ROOT}/${OPSX_APPLY}" ]]; then
  run_test "commands/opsx-apply.md に --auto フラグが存在しない" test_opsx_apply_no_auto_flag
else
  run_test_skip "commands/opsx-apply.md に --auto フラグが存在しない" "${OPSX_APPLY} not found"
fi

# Scenario: opsx-apply の自動継続 (line 44)
# WHEN: autopilot 配下で opsx-apply が全タスク完了後に到達する
# THEN: state-read.sh で判定し、自動的に workflow-pr-cycle を実行する

test_opsx_apply_state_read_or_is_autopilot() {
  assert_file_contains "$OPSX_APPLY" "state-read\.sh|state-read|IS_AUTOPILOT"
}

if [[ -f "${PROJECT_ROOT}/${OPSX_APPLY}" ]]; then
  run_test "commands/opsx-apply.md が state-read.sh または IS_AUTOPILOT 判定を使用する" test_opsx_apply_state_read_or_is_autopilot
else
  run_test_skip "commands/opsx-apply.md が state-read.sh または IS_AUTOPILOT 判定を使用する" "${OPSX_APPLY} not found"
fi

# =============================================================================
# Requirement: pr-cycle-analysis のフラグ除去
# Scenario: pr-cycle-analysis から --auto 除去 (line 52)
# WHEN: commands/pr-cycle-analysis.md の引数セクションを確認する
# THEN: --auto が引数リストに存在しない
# =============================================================================
echo ""
echo "--- Requirement: pr-cycle-analysis のフラグ除去 ---"

# workflow-pr-cycle が pr-cycle-analysis に相当するコマンドを内包する
PR_CYCLE_SKILL="commands/pr-cycle-analysis.md"

test_pr_cycle_file_exists() {
  assert_file_exists "$PR_CYCLE_SKILL"
}

if [[ -f "${PROJECT_ROOT}/${PR_CYCLE_SKILL}" ]]; then
  run_test "commands/pr-cycle-analysis.md が存在する" test_pr_cycle_file_exists
else
  run_test_skip "commands/pr-cycle-analysis.md が存在する" "${PR_CYCLE_SKILL} not found"
fi

test_pr_cycle_no_auto_arg() {
  assert_file_not_contains "$PR_CYCLE_SKILL" "--auto[^-]|--auto$"
}

if [[ -f "${PROJECT_ROOT}/${PR_CYCLE_SKILL}" ]]; then
  run_test "commands/pr-cycle-analysis.md に --auto 引数が存在しない" test_pr_cycle_no_auto_arg
else
  run_test_skip "commands/pr-cycle-analysis.md に --auto 引数が存在しない" "${PR_CYCLE_SKILL} not found"
fi

# Scenario: autopilot 配下での自動起票 (line 55)
# WHEN: autopilot 配下で信頼度 70 以上の Issue が検出される
# THEN: state-read.sh で status=running を確認し、自動起票を実行する

test_pr_cycle_state_read_ref() {
  assert_file_contains "$PR_CYCLE_SKILL" "state-read\.sh|state-read|IS_AUTOPILOT"
}

if [[ -f "${PROJECT_ROOT}/${PR_CYCLE_SKILL}" ]]; then
  run_test "commands/pr-cycle-analysis.md が state-read.sh または IS_AUTOPILOT を参照する" test_pr_cycle_state_read_ref
else
  run_test_skip "commands/pr-cycle-analysis.md が state-read.sh または IS_AUTOPILOT を参照する" "${PR_CYCLE_SKILL} not found"
fi

# =============================================================================
# Requirement: self-improve-propose のフラグ除去
# Scenario: self-improve-propose から --auto 除去 (line 62)
# WHEN: commands/self-improve-propose.md の引数セクションを確認する
# THEN: --auto が引数リストに存在しない
# =============================================================================
echo ""
echo "--- Requirement: self-improve-propose のフラグ除去 ---"

SELF_IMPROVE_PROPOSE="commands/self-improve-propose.md"

test_self_improve_file_exists() {
  assert_file_exists "$SELF_IMPROVE_PROPOSE"
}

if [[ -f "${PROJECT_ROOT}/${SELF_IMPROVE_PROPOSE}" ]]; then
  run_test "commands/self-improve-propose.md が存在する" test_self_improve_file_exists
else
  run_test_skip "commands/self-improve-propose.md が存在する" "${SELF_IMPROVE_PROPOSE} not found"
fi

test_self_improve_no_auto_arg() {
  assert_file_not_contains "$SELF_IMPROVE_PROPOSE" "--auto[^-]|--auto$"
}

if [[ -f "${PROJECT_ROOT}/${SELF_IMPROVE_PROPOSE}" ]]; then
  run_test "commands/self-improve-propose.md に --auto 引数が存在しない" test_self_improve_no_auto_arg
else
  run_test_skip "commands/self-improve-propose.md に --auto 引数が存在しない" "${SELF_IMPROVE_PROPOSE} not found"
fi

# Scenario: autopilot 配下での自動承認 (line 67)
# WHEN: autopilot 配下で信頼度 70 以上の改善提案が存在する
# THEN: state-read.sh で status=running を確認し、自動承認を実行する

test_self_improve_state_read_ref() {
  assert_file_contains "$SELF_IMPROVE_PROPOSE" "state-read\.sh|state-read|IS_AUTOPILOT"
}

if [[ -f "${PROJECT_ROOT}/${SELF_IMPROVE_PROPOSE}" ]]; then
  run_test "commands/self-improve-propose.md が state-read.sh または IS_AUTOPILOT を参照する" test_self_improve_state_read_ref
else
  run_test_skip "commands/self-improve-propose.md が state-read.sh または IS_AUTOPILOT を参照する" "${SELF_IMPROVE_PROPOSE} not found"
fi

# =============================================================================
# Requirement: autopilot-launch プロンプト変更
# Scenario: autopilot-launch のプロンプト (line 75)
# WHEN: commands/autopilot-launch.md の Step 3 を確認する
# THEN: PROMPT が /dev:workflow-setup #${ISSUE} である（--auto --auto-merge なし）
# =============================================================================
echo ""
echo "--- Requirement: autopilot-launch プロンプト変更 ---"

AUTOPILOT_LAUNCH="commands/autopilot-launch.md"
AUTOPILOT_LAUNCH_SH="scripts/autopilot-launch.sh"

test_autopilot_launch_file_exists() {
  assert_file_exists "$AUTOPILOT_LAUNCH"
}

if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_LAUNCH}" ]]; then
  run_test "commands/autopilot-launch.md が存在する" test_autopilot_launch_file_exists
else
  run_test_skip "commands/autopilot-launch.md が存在する" "${AUTOPILOT_LAUNCH} not found"
fi

test_autopilot_launch_prompt_no_auto_flags() {
  # PROMPT には --auto も --auto-merge も含まれてはならない（.md or .sh）
  assert_file_not_contains "$AUTOPILOT_LAUNCH_SH" "workflow-setup.*--auto"
}

if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_LAUNCH_SH}" ]]; then
  run_test "autopilot-launch のプロンプトに --auto/--auto-merge が含まれない" test_autopilot_launch_prompt_no_auto_flags
elif [[ -f "${PROJECT_ROOT}/${AUTOPILOT_LAUNCH}" ]]; then
  run_test "autopilot-launch のプロンプトに --auto/--auto-merge が含まれない" test_autopilot_launch_prompt_no_auto_flags
else
  run_test_skip "autopilot-launch のプロンプトに --auto/--auto-merge が含まれない" "autopilot-launch not found"
fi

test_autopilot_launch_prompt_issue_only() {
  # /dev:workflow-setup #${ISSUE} 形式（フラグなし）が .sh に存在する
  assert_file_contains "$AUTOPILOT_LAUNCH_SH" "workflow-setup #\\\$\{?ISSUE\}?"
}

if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_LAUNCH_SH}" ]]; then
  run_test "autopilot-launch のプロンプトが /dev:workflow-setup #\${ISSUE} 形式である" test_autopilot_launch_prompt_issue_only
elif [[ -f "${PROJECT_ROOT}/${AUTOPILOT_LAUNCH}" ]]; then
  run_test "autopilot-launch のプロンプトが /dev:workflow-setup #\${ISSUE} 形式である" test_autopilot_launch_prompt_issue_only
else
  run_test_skip "autopilot-launch のプロンプトが /dev:workflow-setup #\${ISSUE} 形式である" "autopilot-launch not found"
fi

# =============================================================================
# Requirement: co-autopilot の --auto-merge 除去
# Scenario: co-autopilot から --auto-merge 言及除去 (line 83)
# WHEN: skills/co-autopilot/SKILL.md を確認する
# THEN: --auto-merge への参照が存在しない。--auto は存続している
# =============================================================================
echo ""
echo "--- Requirement: co-autopilot の --auto-merge 除去 ---"

CO_AUTOPILOT="skills/co-autopilot/SKILL.md"

test_co_autopilot_file_exists() {
  assert_file_exists "$CO_AUTOPILOT"
}

if [[ -f "${PROJECT_ROOT}/${CO_AUTOPILOT}" ]]; then
  run_test "skills/co-autopilot/SKILL.md が存在する" test_co_autopilot_file_exists
else
  run_test_skip "skills/co-autopilot/SKILL.md が存在する" "${CO_AUTOPILOT} not found"
fi

test_co_autopilot_no_auto_merge() {
  assert_file_not_contains "$CO_AUTOPILOT" "--auto-merge"
}

if [[ -f "${PROJECT_ROOT}/${CO_AUTOPILOT}" ]]; then
  run_test "skills/co-autopilot/SKILL.md に --auto-merge が存在しない" test_co_autopilot_no_auto_merge
else
  run_test_skip "skills/co-autopilot/SKILL.md に --auto-merge が存在しない" "${CO_AUTOPILOT} not found"
fi

test_co_autopilot_auto_flag_survives() {
  # --auto（計画確認スキップ）は Pilot 層フラグとして存続する
  assert_file_contains "$CO_AUTOPILOT" "--auto"
}

if [[ -f "${PROJECT_ROOT}/${CO_AUTOPILOT}" ]]; then
  run_test "skills/co-autopilot/SKILL.md に --auto が存続している（Pilot 層フラグ）" test_co_autopilot_auto_flag_survives
else
  run_test_skip "skills/co-autopilot/SKILL.md に --auto が存続している（Pilot 層フラグ）" "${CO_AUTOPILOT} not found"
fi

# =============================================================================
# Requirement: issue-{N}.json ベース autopilot 判定パターン
# Scenario: autopilot 配下での判定 (line 11)
# WHEN: Worker が autopilot-launch 経由で起動され、issue-{N}.json が status=running で存在する
# THEN: state-read.sh が running を返し、コンポーネントは自動継続モードで動作する
#
# Scenario: standalone 実行での判定 (line 15)
# WHEN: ユーザーが直接 workflow-setup #47 を実行し、issue-47.json が存在しない
# THEN: state-read.sh が空文字列を返し、コンポーネントは案内表示で停止する
# =============================================================================
echo ""
echo "--- Requirement: issue-{N}.json ベース autopilot 判定パターン ---"

# state-read.sh の存在確認
STATE_READ=""
for candidate in \
    "scripts/state-read.sh" \
    "lib/state-read.sh" \
    "bin/state-read.sh"; do
  if [[ -f "${PROJECT_ROOT}/${candidate}" ]]; then
    STATE_READ="$candidate"
    break
  fi
done

test_state_read_sh_exists() {
  [[ -n "$STATE_READ" ]]
}

if [[ -n "$STATE_READ" ]]; then
  run_test "state-read.sh が存在する (${STATE_READ})" test_state_read_sh_exists
else
  run_test_skip "state-read.sh が存在する" "state-read.sh not found under scripts/, lib/, bin/"
fi

test_state_read_issue_flag() {
  [[ -n "$STATE_READ" ]] || return 1
  assert_file_contains "$STATE_READ" "--type.*issue|--issue|issue.*--type"
}

if [[ -n "$STATE_READ" ]]; then
  run_test "state-read.sh が --type issue / --issue フラグをサポートする" test_state_read_issue_flag
else
  run_test_skip "state-read.sh が --type issue / --issue フラグをサポートする" "state-read.sh not found"
fi

test_state_read_field_status() {
  [[ -n "$STATE_READ" ]] || return 1
  assert_file_contains "$STATE_READ" "--field"
}

if [[ -n "$STATE_READ" ]]; then
  run_test "state-read.sh が --field status をサポートする" test_state_read_field_status
else
  run_test_skip "state-read.sh が --field status をサポートする" "state-read.sh not found"
fi

test_state_read_running_value() {
  # state-write.sh --init が status=running で初期化することを確認
  local state_write="${STATE_READ/state-read/state-write}"
  [[ -f "${PROJECT_ROOT}/${state_write}" ]] || return 1
  assert_file_contains "$state_write" "running"
}

if [[ -n "$STATE_READ" ]]; then
  run_test "state-read.sh が status=running を認識する" test_state_read_running_value
else
  run_test_skip "state-read.sh が status=running を認識する" "state-read.sh not found"
fi

# =============================================================================
# Requirement: c-2d session-management spec のプロンプト修正
# Scenario: openspec c-2d の矛盾解消 (openspec-contradiction-fix.md line 10)
# WHEN: openspec/changes/c-2d-autopilot-controller-autopilot/specs/session-management/spec.md を確認する
# THEN: autopilot-launch コマンド要件のプロンプト記述が /dev:workflow-setup #${ISSUE} のみであり
#       --auto --auto-merge が含まれない
# =============================================================================
echo ""
echo "--- Requirement: c-2d session-management spec のプロンプト修正 ---"

C2D_SPEC="openspec/changes/c-2d-autopilot-controller-autopilot/specs/session-management/spec.md"

test_c2d_spec_file_exists() {
  assert_file_exists "$C2D_SPEC"
}

if [[ -f "${PROJECT_ROOT}/${C2D_SPEC}" ]]; then
  run_test "c-2d session-management spec.md が存在する" test_c2d_spec_file_exists
else
  run_test_skip "c-2d session-management spec.md が存在する" "${C2D_SPEC} not found"
fi

test_c2d_spec_no_auto_merge_in_prompt() {
  assert_file_not_contains "$C2D_SPEC" "workflow-setup.*--auto.*--auto-merge|--auto-merge.*workflow-setup"
}

if [[ -f "${PROJECT_ROOT}/${C2D_SPEC}" ]]; then
  run_test "c-2d spec の autopilot-launch プロンプトに --auto --auto-merge が含まれない" test_c2d_spec_no_auto_merge_in_prompt
else
  run_test_skip "c-2d spec の autopilot-launch プロンプトに --auto --auto-merge が含まれない" "${C2D_SPEC} not found"
fi

test_c2d_spec_prompt_issue_format() {
  assert_file_contains "$C2D_SPEC" "workflow-setup #\\\$\{?ISSUE\}?"
}

if [[ -f "${PROJECT_ROOT}/${C2D_SPEC}" ]]; then
  run_test "c-2d spec の Worker 起動プロンプトが /dev:workflow-setup #\${ISSUE} 形式である" test_c2d_spec_prompt_issue_format
else
  run_test_skip "c-2d spec の Worker 起動プロンプトが /dev:workflow-setup #\${ISSUE} 形式である" "${C2D_SPEC} not found"
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
