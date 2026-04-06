#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: openspec-scenarios.md
# Generated from: deltaspec/changes/b-1-chain-driven-autopilot-first/specs/openspec-scenarios.md
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

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
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
  ((SKIP++))
}

# =============================================================================
# Requirement: Autopilot Lifecycle シナリオ
# =============================================================================
echo ""
echo "--- Requirement: Autopilot Lifecycle シナリオ ---"

# Target file for this requirement
AUTOPILOT_SPEC="deltaspec/specs/autopilot-lifecycle.md"

# Scenario: 正常系ライフサイクル (line 9)
# WHEN: 単一 Issue で co-autopilot を起動する
# THEN: plan.yaml 生成 -> Phase 1 開始 -> Worker 起動 -> merge-gate -> Phase 完了 -> autopilot-summary の順で実行される
test_autopilot_normal_lifecycle() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  assert_file_contains_all "$AUTOPILOT_SPEC" \
    "plan\.yaml|plan 生成|計画生成" \
    "Phase" \
    "Worker.*起動|Worker 起動" \
    "merge-gate" \
    "autopilot-summary|summary"
}
run_test "正常系ライフサイクル" test_autopilot_normal_lifecycle

# Edge case: ライフサイクルの実行順序が明示されている（番号付きまたはフロー図）
test_autopilot_lifecycle_ordered() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  # Check for ordered list or mermaid flowchart
  assert_file_contains "$AUTOPILOT_SPEC" "flowchart|sequenceDiagram|^[0-9]+\.|1\.|WHEN.*THEN"
}
run_test "正常系ライフサイクル [edge: 実行順序が明示]" test_autopilot_lifecycle_ordered

# Scenario: 複数 Phase の逐次実行 (line 13)
# WHEN: 依存関係のある 3 Issue で co-autopilot を起動する
# THEN: plan.yaml に 3 Phase が生成され、Phase 1 完了後に Phase 2 が開始される
test_autopilot_multi_phase() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  assert_file_contains_all "$AUTOPILOT_SPEC" \
    "Phase.*1|Phase 1" \
    "Phase.*2|Phase 2" \
    "依存|depends|sequential|逐次"
}
run_test "複数 Phase の逐次実行" test_autopilot_multi_phase

# Edge case: 3 Phase 以上の例が含まれる
test_autopilot_three_phases() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  assert_file_contains "$AUTOPILOT_SPEC" "Phase.*3|Phase 3|3.*Phase"
}
run_test "複数 Phase [edge: 3 Phase 以上の例]" test_autopilot_three_phases

# Scenario: Phase 内 Issue 失敗時の skip 伝播 (line 17)
# WHEN: Phase 1 の Issue が failed になり、Phase 2 の Issue が依存している
# THEN: 依存 Issue は自動 skip、status が failed に遷移する（不変条件 D）
test_autopilot_skip_propagation() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  assert_file_contains_all "$AUTOPILOT_SPEC" \
    "fail|failed" \
    "skip|スキップ" \
    "不変条件.*D|Invariant.*D|依存.*fail"
}
run_test "Phase 内 Issue 失敗時の skip 伝播" test_autopilot_skip_propagation

# Edge case: skip 伝播が再帰的であること（Phase 2 skip -> Phase 3 も skip）
test_autopilot_skip_cascading() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  # Cascading/transitive skip should be mentioned
  assert_file_contains "$AUTOPILOT_SPEC" "伝播|cascade|transitive|連鎖|以降.*skip|以降.*スキップ"
}
run_test "skip 伝播 [edge: 再帰的伝播が記載]" test_autopilot_skip_cascading

# Scenario: Emergency Bypass (line 21)
# WHEN: co-autopilot 自体の SKILL.md にバグがあり、起動に失敗する
# THEN: Emergency Bypass で main/ から直接実装->PR->merge が許可され、retrospective 記録が義務付けられる
test_autopilot_emergency_bypass() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  assert_file_contains_all "$AUTOPILOT_SPEC" \
    "Emergency|bypass|緊急" \
    "retrospective|振り返り|記録"
}
run_test "Emergency Bypass" test_autopilot_emergency_bypass

# Edge case: Emergency Bypass の許可条件が限定的に定義されている
test_autopilot_emergency_bypass_conditions() {
  assert_file_exists "$AUTOPILOT_SPEC" || return 1
  assert_file_contains "$AUTOPILOT_SPEC" "SKILL\.md|co-autopilot.*障害|bootstrap"
}
run_test "Emergency Bypass [edge: 許可条件が限定的]" test_autopilot_emergency_bypass_conditions

# =============================================================================
# Requirement: merge-gate シナリオ
# =============================================================================
echo ""
echo "--- Requirement: merge-gate シナリオ ---"

MERGEGATE_SPEC="deltaspec/specs/merge-gate.md"

# Scenario: 動的レビュアー構築 (line 31)
# WHEN: PR の変更ファイルに deps.yaml と TypeScript ファイルが含まれる
# THEN: worker-structure, worker-principles, worker-code-reviewer, worker-security-reviewer が specialist リストに追加される
test_mergegate_dynamic_reviewer() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains_all "$MERGEGATE_SPEC" \
    "動的|dynamic|レビュアー.*構築" \
    "deps\.yaml" \
    "TypeScript|\.ts" \
    "specialist"
}
run_test "動的レビュアー構築" test_mergegate_dynamic_reviewer

# Edge case: 4つの specialist が全て列挙
test_mergegate_all_specialists() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains_all "$MERGEGATE_SPEC" \
    "worker-structure" \
    "worker-principles" \
    "worker-code-reviewer" \
    "worker-security-reviewer"
}
run_test "動的レビュアー [edge: 4 specialist 全列挙]" test_mergegate_all_specialists

# Scenario: merge-gate PASS (line 35)
# WHEN: 全 specialist の findings に severity=CRITICAL かつ confidence>=80 のエントリがない
# THEN: merge-gate は PASS を返し、Pilot が squash merge を実行
test_mergegate_pass() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains_all "$MERGEGATE_SPEC" \
    "PASS" \
    "CRITICAL" \
    "confidence.*80|confidence >= 80" \
    "squash.*merge|squash merge"
}
run_test "merge-gate PASS" test_mergegate_pass

# Edge case: PASS 条件が否定形で正確に定義（CRITICAL かつ confidence>=80 が「ない」）
test_mergegate_pass_negative_condition() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains "$MERGEGATE_SPEC" "ない|no.*CRITICAL|absence|存在しない"
}
run_test "merge-gate PASS [edge: 否定条件が正確]" test_mergegate_pass_negative_condition

# Scenario: merge-gate REJECT（1回目） (line 39)
# WHEN: CRITICAL findings かつ retry_count=0
# THEN: status が failed->running に遷移、fix_instructions に findings 記録、fix-phase 実行
test_mergegate_reject_first() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains_all "$MERGEGATE_SPEC" \
    "REJECT|reject|リジェクト" \
    "retry_count.*0|retry.*0|1回目" \
    "fix_instructions|fix.*instructions" \
    "fix-phase|fix phase"
}
run_test "merge-gate REJECT（1回目）" test_mergegate_reject_first

# Edge case: status 遷移 failed -> running が明示
test_mergegate_reject_status_transition() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains "$MERGEGATE_SPEC" "failed.*running|failed.*→.*running|failed -> running"
}
run_test "merge-gate REJECT 1回目 [edge: status遷移が明示]" test_mergegate_reject_status_transition

# Scenario: merge-gate REJECT（2回目、確定失敗） (line 43)
# WHEN: fix-phase 後の再レビューで再度 CRITICAL findings、retry_count=1
# THEN: status が failed に確定、Pilot に手動介入が要求される（不変条件 E）
test_mergegate_reject_second() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains_all "$MERGEGATE_SPEC" \
    "retry_count.*1|2回目|retry.*1" \
    "failed.*確定|確定.*fail|permanent" \
    "手動|manual|Pilot.*介入|不変条件.*E"
}
run_test "merge-gate REJECT（2回目、確定失敗）" test_mergegate_reject_second

# Edge case: 不変条件 E（リトライ制限）が参照されている
test_mergegate_invariant_e_referenced() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains "$MERGEGATE_SPEC" "不変条件.*E|Invariant.*E|\*\*E\*\*"
}
run_test "merge-gate REJECT 2回目 [edge: 不変条件E参照]" test_mergegate_invariant_e_referenced

# Edge case: リトライ上限が明示的に「最大1回」と記載
test_mergegate_max_retry() {
  assert_file_exists "$MERGEGATE_SPEC" || return 1
  assert_file_contains "$MERGEGATE_SPEC" "最大.*1.*回|max.*1.*retry|リトライ.*1回|1回.*制限"
}
run_test "merge-gate REJECT [edge: リトライ上限 最大1回]" test_mergegate_max_retry

# =============================================================================
# Requirement: Project Create シナリオ
# =============================================================================
echo ""
echo "--- Requirement: Project Create シナリオ ---"

PROJECT_SPEC="deltaspec/specs/project-create.md"

# Scenario: 正常系プロジェクト作成 (line 53)
# WHEN: co-project create my-project を実行する
# THEN: my-project/.bare/ が作成され、worktree が初期化され、テンプレートが配置
test_project_create_normal() {
  assert_file_exists "$PROJECT_SPEC" || return 1
  assert_file_contains_all "$PROJECT_SPEC" \
    "co-project.*create|project.*create" \
    "\.bare/" \
    "worktree|main/" \
    "テンプレート|template"
}
run_test "正常系プロジェクト作成" test_project_create_normal

# Edge case: 作成されるディレクトリ構成が明示
test_project_create_directory_layout() {
  assert_file_exists "$PROJECT_SPEC" || return 1
  assert_file_contains_all "$PROJECT_SPEC" \
    "\.bare" \
    "main" \
    "worktrees"
}
run_test "正常系プロジェクト作成 [edge: ディレクトリ構成明示]" test_project_create_directory_layout

# Scenario: bare repo 構造検証 (line 57)
# WHEN: プロジェクト作成完了後にセッションを開始する
# THEN: .bare/ 存在、main/.git がファイル、CWD が main/ 配下の 3 条件が満たされる
test_project_create_bare_repo_validation() {
  assert_file_exists "$PROJECT_SPEC" || return 1
  assert_file_contains_all "$PROJECT_SPEC" \
    "\.bare/" \
    "main/\.git" \
    "CWD|main.*配下|カレントディレクトリ"
}
run_test "bare repo 構造検証" test_project_create_bare_repo_validation

# Edge case: main/.git がファイル（ディレクトリではない）ことが明示
test_project_create_git_is_file() {
  assert_file_exists "$PROJECT_SPEC" || return 1
  assert_file_contains "$PROJECT_SPEC" "\.git.*ファイル|\.git.*file|ファイル.*\.git"
}
run_test "bare repo 構造検証 [edge: .git がファイルと明示]" test_project_create_git_is_file

# Scenario: Project Board 自動作成 (line 61)
# WHEN: プロジェクト作成時に GitHub リポジトリが指定されている
# THEN: GitHub Project V2 が自動作成され、リポジトリにリンクされる
test_project_create_board() {
  assert_file_exists "$PROJECT_SPEC" || return 1
  assert_file_contains_all "$PROJECT_SPEC" \
    "Project.*V2|Project Board|GitHub.*Project" \
    "自動.*作成|auto.*create" \
    "リンク|link"
}
run_test "Project Board 自動作成" test_project_create_board

# Edge case: GitHub リポジトリ未指定時の挙動が定義されている
test_project_create_board_no_repo() {
  assert_file_exists "$PROJECT_SPEC" || return 1
  # Should mention behavior when no GitHub repo is specified
  assert_file_contains "$PROJECT_SPEC" "指定.*ない|未指定|without.*repo|skip.*board|ローカル"
}
run_test "Project Board [edge: GitHub未指定時の挙動定義]" test_project_create_board_no_repo

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
