#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: session-audit-verification
# Generated from: openspec/changes/archive/2026-03-31-session-audit-verification/specs/controller-verification/spec.md
# Coverage level: edge-cases
#
# NOTE: このIssueはコード変更を含まない手動検証タスク。
# テストはcontroller/skill/scriptが実行可能な状態であることを
# 静的・構造的に検証する。実際のcontroller実行は手動で行う。
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

assert_file_executable() {
  local file="$1"
  [[ -x "${PROJECT_ROOT}/${file}" ]]
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

assert_dir_exists() {
  local dir="$1"
  [[ -d "${PROJECT_ROOT}/${dir}" ]]
}

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
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
  ((SKIP++))
}

# =============================================================================
# Requirement: Controller 基本フロー動作確認
# =============================================================================
echo ""
echo "--- Requirement: Controller 基本フロー動作確認 ---"

# --- Scenario: co-project 基本フロー検証 (line 7) ---
# WHEN: 独立セッションから co-project を起動する
# THEN: プロジェクト作成フローが正常に開始され、エラーなく完了する

test_co_project_skill_exists() {
  assert_file_exists "skills/co-project/SKILL.md"
}
run_test "co-project SKILL.md が存在する" test_co_project_skill_exists

test_co_project_type_controller() {
  assert_file_exists "skills/co-project/SKILL.md" || return 1
  assert_file_contains "skills/co-project/SKILL.md" "type:\s*controller"
}
run_test "co-project SKILL.md - type: controller が宣言されている" test_co_project_type_controller

test_co_project_spawnable_by_user() {
  assert_file_exists "skills/co-project/SKILL.md" || return 1
  assert_file_contains "skills/co-project/SKILL.md" "spawnable_by"
  assert_file_contains "skills/co-project/SKILL.md" "user"
}
run_test "co-project SKILL.md - spawnable_by user が設定されている" test_co_project_spawnable_by_user

test_co_project_modes_defined() {
  assert_file_exists "skills/co-project/SKILL.md" || return 1
  assert_file_contains "skills/co-project/SKILL.md" "create" || return 1
  assert_file_contains "skills/co-project/SKILL.md" "migrate" || return 1
  assert_file_contains "skills/co-project/SKILL.md" "snapshot" || return 1
  return 0
}
run_test "co-project SKILL.md - 3モード（create/migrate/snapshot）が定義されている" test_co_project_modes_defined

test_co_project_not_stub() {
  assert_file_exists "skills/co-project/SKILL.md" || return 1
  assert_file_not_contains "skills/co-project/SKILL.md" "以降で実装|TODO.*実装|placeholder"
}
run_test "co-project SKILL.md [edge: stubではなく完全実装]" test_co_project_not_stub

test_co_project_scripts_accessible() {
  assert_file_exists "scripts/project-create.sh" || return 1
  assert_file_executable "scripts/project-create.sh"
}
if [[ -f "${PROJECT_ROOT}/scripts/project-create.sh" ]]; then
  run_test "co-project - project-create.sh が実行可能" test_co_project_scripts_accessible
else
  run_test_skip "co-project - project-create.sh が実行可能" "scripts/project-create.sh not found"
fi

test_co_project_migrate_script_accessible() {
  assert_file_exists "scripts/project-migrate.sh" || return 1
  assert_file_executable "scripts/project-migrate.sh"
}
if [[ -f "${PROJECT_ROOT}/scripts/project-migrate.sh" ]]; then
  run_test "co-project - project-migrate.sh が実行可能" test_co_project_migrate_script_accessible
else
  run_test_skip "co-project - project-migrate.sh が実行可能" "scripts/project-migrate.sh not found"
fi

# --- Scenario: co-architect 基本フロー検証 (line 11) ---
# WHEN: 独立セッションから co-architect を起動する
# THEN: アーキテクチャ設計フローが正常に開始され、対話的に進行する

test_co_architect_skill_exists() {
  assert_file_exists "skills/co-architect/SKILL.md"
}
run_test "co-architect SKILL.md が存在する" test_co_architect_skill_exists

test_co_architect_type_controller() {
  assert_file_exists "skills/co-architect/SKILL.md" || return 1
  assert_file_contains "skills/co-architect/SKILL.md" "type:\s*controller"
}
run_test "co-architect SKILL.md - type: controller が宣言されている" test_co_architect_type_controller

test_co_architect_interactive_flow() {
  assert_file_exists "skills/co-architect/SKILL.md" || return 1
  # 対話的フローの指標: AskUserQuestion / Step 記述 / TaskCreate
  assert_file_contains "skills/co-architect/SKILL.md" "AskUserQuestion|Step\s*[0-9]|TaskCreate|対話"
}
run_test "co-architect SKILL.md - 対話的フローの記述がある" test_co_architect_interactive_flow

test_co_architect_architecture_dir() {
  # architecture/ ディレクトリへの言及: 設計ファイルの保存先
  assert_file_exists "skills/co-architect/SKILL.md" || return 1
  assert_file_contains "skills/co-architect/SKILL.md" "architecture/"
}
run_test "co-architect SKILL.md - architecture/ ディレクトリへの言及" test_co_architect_architecture_dir

test_co_architect_not_stub() {
  assert_file_exists "skills/co-architect/SKILL.md" || return 1
  assert_file_not_contains "skills/co-architect/SKILL.md" "以降で実装|TODO.*実装|placeholder"
}
run_test "co-architect SKILL.md [edge: stubではなく完全実装]" test_co_architect_not_stub

# --- Scenario: co-issue 基本フロー検証 (line 15) ---
# WHEN: 独立セッションから co-issue を起動する
# THEN: Issue 作成フローが正常に開始され、要望から Issue への変換が行える

test_co_issue_skill_exists() {
  assert_file_exists "skills/co-issue/SKILL.md"
}
run_test "co-issue SKILL.md が存在する" test_co_issue_skill_exists

test_co_issue_type_controller() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  assert_file_contains "skills/co-issue/SKILL.md" "type:\s*controller"
}
run_test "co-issue SKILL.md - type: controller が宣言されている" test_co_issue_type_controller

test_co_issue_phase_flow() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  assert_file_contains "skills/co-issue/SKILL.md" "Phase\s*1" || return 1
  assert_file_contains "skills/co-issue/SKILL.md" "Phase\s*4" || return 1
  return 0
}
run_test "co-issue SKILL.md - Phase フロー（Phase 1〜4）が定義されている" test_co_issue_phase_flow

test_co_issue_create_command() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  assert_file_contains "skills/co-issue/SKILL.md" "issue-create"
}
run_test "co-issue SKILL.md - issue-create コマンドへの言及" test_co_issue_create_command

test_co_issue_not_stub() {
  assert_file_exists "skills/co-issue/SKILL.md" || return 1
  assert_file_not_contains "skills/co-issue/SKILL.md" "以降で実装|TODO.*実装|placeholder"
}
run_test "co-issue SKILL.md [edge: stubではなく完全実装]" test_co_issue_not_stub

# deps.yaml での全controller登録確認
test_all_controllers_in_deps_yaml() {
  assert_file_exists "deps.yaml" || return 1
  assert_file_contains "deps.yaml" "co-project" || return 1
  assert_file_contains "deps.yaml" "co-architect" || return 1
  assert_file_contains "deps.yaml" "co-issue" || return 1
  return 0
}
run_test "deps.yaml - 全controller（co-project/co-architect/co-issue）が登録されている" test_all_controllers_in_deps_yaml

# =============================================================================
# Requirement: workflow-setup chain エンドツーエンド検証
# =============================================================================
echo ""
echo "--- Requirement: workflow-setup chain エンドツーエンド検証 ---"

# --- Scenario: workflow-setup chain 正常完了 (line 23) ---
# WHEN: Issue 番号を指定して workflow-setup を実行する
# THEN: 全ステップが順に実行され、workflow-test-ready への遷移案内が表示される

test_workflow_setup_skill_exists() {
  assert_file_exists "skills/workflow-setup/SKILL.md"
}
run_test "workflow-setup SKILL.md が存在する" test_workflow_setup_skill_exists

test_workflow_setup_all_steps() {
  local skill="skills/workflow-setup/SKILL.md"
  assert_file_exists "$skill" || return 1
  # chain の全ステップが言及されていること
  assert_file_contains "$skill" "init" || return 1
  assert_file_contains "$skill" "worktree-create" || return 1
  assert_file_contains "$skill" "project-board-status-update" || return 1
  assert_file_contains "$skill" "crg-auto-build" || return 1
  assert_file_contains "$skill" "change-propose" || return 1
  assert_file_contains "$skill" "ac-extract" || return 1
  assert_file_contains "$skill" "workflow-test-ready" || return 1
  return 0
}
run_test "workflow-setup SKILL.md - 全 chain ステップ（init→workflow-test-ready）が記述されている" test_workflow_setup_all_steps

test_workflow_setup_issue_num_parsing() {
  local skill="skills/workflow-setup/SKILL.md"
  assert_file_exists "$skill" || return 1
  # ISSUE_NUM 解析の記述
  assert_file_contains "$skill" "ISSUE_NUM|#N|\\\$ARGUMENTS"
}
run_test "workflow-setup SKILL.md - Issue 番号解析（ISSUE_NUM）の記述" test_workflow_setup_issue_num_parsing

test_workflow_setup_chain_continuation_instruction() {
  local skill="skills/workflow-setup/SKILL.md"
  assert_file_exists "$skill" || return 1
  # chain 継続の強制指示（途中停止禁止）
  assert_file_contains "$skill" "停止するな|途中.*停止|全ステップ.*順.*実行|MUST"
}
run_test "workflow-setup SKILL.md - chain 継続の強制指示（途中停止禁止）" test_workflow_setup_chain_continuation_instruction

test_workflow_setup_test_ready_transition() {
  local skill="skills/workflow-setup/SKILL.md"
  assert_file_exists "$skill" || return 1
  # workflow-test-ready への遷移案内
  assert_file_contains "$skill" "workflow-test-ready"
}
run_test "workflow-setup SKILL.md - workflow-test-ready への遷移案内" test_workflow_setup_test_ready_transition

# --- Scenario: workflow-setup chain エラーハンドリング (line 27) ---
# WHEN: 依存 Issue が存在しない番号で workflow-setup を実行する
# THEN: 適切なエラーメッセージが表示され、chain が安全に停止する

test_workflow_setup_deps_yaml_chain() {
  assert_file_exists "deps.yaml" || return 1
  assert_file_contains "deps.yaml" "workflow-setup"
}
run_test "deps.yaml - workflow-setup chain が登録されている" test_workflow_setup_deps_yaml_chain

test_workflow_setup_calls_in_deps() {
  assert_file_exists "deps.yaml" || return 1
  # workflow-setup の calls（chain）に init が含まれることを確認
  # deps.yaml v3 では chain は "calls" キーで管理される
  yaml_get "deps.yaml" "
skills = data.get('skills', {})
ws = skills.get('workflow-setup', {})
calls = ws.get('calls', [])
content = str(calls)
if 'init' not in content:
    print(f'init not found in calls: {calls}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
if assert_file_exists "deps.yaml" && assert_file_contains "deps.yaml" "workflow-setup"; then
  run_test "deps.yaml workflow-setup [edge: calls に init ステップが含まれる]" test_workflow_setup_calls_in_deps
else
  run_test_skip "deps.yaml workflow-setup calls 検証" "deps.yaml not found or workflow-setup not registered"
fi

test_workflow_setup_commands_exist() {
  local all_ok=0
  for cmd in "init" "worktree-create" "crg-auto-build" "change-propose" "ac-extract"; do
    if [[ ! -f "${PROJECT_ROOT}/commands/${cmd}.md" ]]; then
      echo "    Missing: commands/${cmd}.md" >&2
      all_ok=1
    fi
  done
  return $all_ok
}
run_test "workflow-setup - 全 chain コマンド（commands/*.md）が存在する" test_workflow_setup_commands_exist

# =============================================================================
# Requirement: session-audit 品質基準
# =============================================================================
echo ""
echo "--- Requirement: session-audit 品質基準 ---"

# --- Scenario: session-audit PASS 条件 (line 35) ---
# WHEN: 全 controller 検証完了後に session-audit を実行する
# THEN: confidence >= 70 の findings が 0 件である

test_session_audit_command_exists() {
  assert_file_exists "commands/session-audit.md"
}
run_test "commands/session-audit.md が存在する" test_session_audit_command_exists

test_session_audit_confidence_threshold() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # confidence >= 70 の閾値が明記
  assert_file_contains "$cmd" "confidence.*70|70.*confidence|>= 70|>= 70"
}
run_test "session-audit - confidence >= 70 閾値が明記されている" test_session_audit_confidence_threshold

test_session_audit_five_categories() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # 5 カテゴリが全て言及されている
  assert_file_contains "$cmd" "script-fragility" || return 1
  assert_file_contains "$cmd" "silent-failure" || return 1
  assert_file_contains "$cmd" "ai-compensation" || return 1
  assert_file_contains "$cmd" "retry-loop" || return 1
  assert_file_contains "$cmd" "twl-inline-logic" || return 1
  return 0
}
run_test "session-audit - 5 カテゴリ（script-fragility/silent-failure/ai-compensation/retry-loop/twl-inline-logic）が定義されている" test_session_audit_five_categories

test_session_audit_script_exists() {
  assert_file_exists "scripts/session-audit.sh" || return 1
  assert_file_executable "scripts/session-audit.sh"
}
run_test "scripts/session-audit.sh が存在し実行可能" test_session_audit_script_exists

test_session_audit_script_usage() {
  local script="scripts/session-audit.sh"
  assert_file_exists "$script" || return 1
  # 引数バリデーション（usage メッセージ）
  assert_file_contains "$script" "Usage|usage|JSONL|jsonl"
}
run_test "scripts/session-audit.sh - Usage 説明が含まれる" test_session_audit_script_usage

# --- Scenario: session-audit findings 検出時 (line 39) ---
# WHEN: session-audit で confidence >= 70 の findings が検出される
# THEN: findings を Issue #44 コメントに記録し、対応 Issue を特定する

test_session_audit_issue_creation() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # 自動 Issue 起票への言及
  assert_file_contains "$cmd" "Issue.*起票|起票|gh issue|self-improve"
}
run_test "session-audit - findings 検出時の Issue 起票が記述されている" test_session_audit_issue_creation

test_session_audit_dedup_logic() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # 重複排除チェック
  assert_file_contains "$cmd" "重複|dedup|sha256|PATTERN_HASH"
}
run_test "session-audit - 重複排除チェックが記述されている" test_session_audit_dedup_logic

test_session_audit_output_format() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # 出力形式（テーブル or JSON）
  assert_file_contains "$cmd" "カテゴリ|category|confidence|表示|出力形式"
}
run_test "session-audit - 出力形式（テーブル）が定義されている" test_session_audit_output_format

test_session_audit_haiku_model() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # haiku モデル使用の明記（コスト効率）
  assert_file_contains "$cmd" "haiku|Haiku"
}
run_test "session-audit [edge: haiku モデル使用が明記されている]" test_session_audit_haiku_model

test_session_audit_no_low_confidence_issue() {
  local cmd="commands/session-audit.md"
  assert_file_exists "$cmd" || return 1
  # confidence < 70 での Issue 起票禁止
  assert_file_contains "$cmd" "< 70|禁止|MUST NOT|してはならない"
}
run_test "session-audit [edge: confidence < 70 での Issue 起票禁止が明記]" test_session_audit_no_low_confidence_issue

# =============================================================================
# Requirement: 検証結果レポート記録
# =============================================================================
echo ""
echo "--- Requirement: 検証結果レポート記録 ---"

# --- Scenario: レポート記録 (line 47) ---
# WHEN: 全検証タスクが完了する
# THEN: Issue #44 コメントに構造化されたレポートが投稿される

test_gh_cli_available() {
  command -v gh &>/dev/null
}
if command -v gh &>/dev/null; then
  run_test "gh CLI が利用可能" test_gh_cli_available
else
  run_test_skip "gh CLI が利用可能" "gh CLI not installed"
fi

test_issue_44_report_structure_spec_exists() {
  # 検証結果レポートの要件が spec に記述されている
  local spec="openspec/changes/archive/2026-03-31-session-audit-verification/specs/controller-verification/spec.md"
  assert_file_exists "$spec" || return 1
  assert_file_contains "$spec" "Issue.*#44|#44.*コメント|レポート"
}
run_test "spec - Issue #44 へのレポート記録要件が記述されている" test_issue_44_report_structure_spec_exists

# --- Scenario: レポート内容の網羅性 (line 51) ---
# WHEN: レポートを確認する
# THEN: co-issue, co-project, co-architect, workflow-setup, session-audit の各結果が含まれている

test_spec_covers_all_controllers() {
  local spec="openspec/changes/archive/2026-03-31-session-audit-verification/specs/controller-verification/spec.md"
  assert_file_exists "$spec" || return 1
  assert_file_contains "$spec" "co-issue" || return 1
  assert_file_contains "$spec" "co-project" || return 1
  assert_file_contains "$spec" "co-architect" || return 1
  assert_file_contains "$spec" "workflow-setup" || return 1
  assert_file_contains "$spec" "session-audit" || return 1
  return 0
}
run_test "spec - 全検証対象（co-issue/co-project/co-architect/workflow-setup/session-audit）が網羅されている" test_spec_covers_all_controllers

# deps.yaml 構造整合性（全controller skill が skills キーに存在）
test_deps_yaml_skills_structure() {
  assert_file_exists "deps.yaml" || return 1
  assert_valid_yaml "deps.yaml" || return 1
  yaml_get "deps.yaml" "
skills = data.get('skills', {})
required = ['co-project', 'co-architect', 'co-issue', 'workflow-setup']
missing = [r for r in required if r not in skills]
if missing:
    print(f'Missing skills in deps.yaml: {missing}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}
run_test "deps.yaml [edge: 全controller skill が skills セクションに登録されている]" test_deps_yaml_skills_structure

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
