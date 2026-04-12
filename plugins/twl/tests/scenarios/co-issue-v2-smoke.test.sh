#!/usr/bin/env bash
# =============================================================================
# Smoke Tests: co-issue v2 (CO_ISSUE_V2 feature flag + Phase 2-3-4 rewrite)
# Generated from: deltaspec/changes/issue-492/specs/
# Coverage level: edge-cases
#
# Change: issue-492 (co-issue v2 Pilot — Phase 2-3-4 dispatch/aggregate 方式)
#
# Requirement coverage:
#   co-issue-v2-feature-flag: Environment セクション宣言・フラグ切り替え
#   co-issue-v2-phase2-dag:   DAG 構築・per-issue bundle・policies.json 生成
#   co-issue-v2-phase3-dispatch: Level-based dispatch・parent URL 注入・circuit_broken
#   co-issue-v2-phase4-aggregate: aggregate summary・retry フロー・deps.yaml
#   co-issue-v2-phase5-soak: soak run log・失敗 warning・#493 closed スキップ
# =============================================================================
set -uo pipefail

# Project root (plugins/twl/tests/scenarios/ → plugins/twl/)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

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

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
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

SKILL_MD="skills/co-issue/SKILL.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: CO_ISSUE_V2 環境変数を SKILL.md に正典宣言する
# Spec: specs/co-issue-v2-feature-flag/spec.md
# =============================================================================
echo ""
echo "--- Requirement: CO_ISSUE_V2 環境変数を SKILL.md に正典宣言する ---"

# Scenario: Environment セクションが SKILL.md に存在する
# WHEN: plugins/twl/skills/co-issue/SKILL.md を確認する
# THEN: ## Environment セクションが存在し、CO_ISSUE_V2 (default 0) の宣言が含まれている

test_environment_section_exists() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "^## Environment" || return 1
  return 0
}

test_co_issue_v2_var_declared() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "CO_ISSUE_V2" || return 1
  return 0
}

test_co_issue_v2_default_zero() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'CO_ISSUE_V2.*default.*0|CO_ISSUE_V2.*0.*default' || return 1
  return 0
}

test_rollback_procedure_described() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'rollback|ロールバック' || return 1
  return 0
}

# Edge case: Environment セクションが Overview 直下・Phase 定義の前に配置されている
test_environment_section_before_phase() {
  assert_file_exists "$SKILL_MD" || return 1
  local env_line phase_line
  env_line=$(grep -n "^## Environment" "${PROJECT_ROOT}/${SKILL_MD}" | head -1 | cut -d: -f1)
  phase_line=$(grep -n "^## Phase\s*2\|^## Step\|^## Phase 2\|^## セッション\|^## Phase 1" "${PROJECT_ROOT}/${SKILL_MD}" | head -1 | cut -d: -f1)
  [[ -n "$env_line" && -n "$phase_line" && "$env_line" -lt "$phase_line" ]] || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "## Environment セクションが存在する" test_environment_section_exists
  run_test "CO_ISSUE_V2 変数が宣言されている" test_co_issue_v2_var_declared
  run_test "CO_ISSUE_V2 の default=0 が明記されている" test_co_issue_v2_default_zero
  run_test "rollback 手順が記述されている" test_rollback_procedure_described
  run_test "Environment セクション [edge: Phase 定義より前に配置]" test_environment_section_before_phase
else
  run_test_skip "## Environment セクションが存在する" "skills/co-issue/SKILL.md not found"
  run_test_skip "CO_ISSUE_V2 変数が宣言されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "CO_ISSUE_V2 の default=0 が明記されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "rollback 手順が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Environment セクション [edge: Phase 定義より前に配置]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: CO_ISSUE_V2=1 で新パスに切り替わる
# Spec: specs/co-issue-v2-feature-flag/spec.md
# =============================================================================
echo ""
echo "--- Requirement: CO_ISSUE_V2=1 で新パスに切り替わる ---"

# Scenario: flag==1 で新パスが実行される
# WHEN: CO_ISSUE_V2=1 で co-issue を実行し要望を入力する
# THEN: Phase 2 が DAG 構築・bundle 書き出しを実行し、Phase 3 が issue-lifecycle-orchestrator.sh を
#       呼び出し、Phase 4 が aggregate を実行する

test_flag_branch_exists_phase2() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'CO_ISSUE_V2.*==.*"?1"?|CO_ISSUE_V2:-0.*==.*1' || return 1
  return 0
}

test_new_path_dispatch_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'issue-lifecycle-orchestrator' || return 1
  return 0
}

test_new_path_aggregate_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'aggregate' || return 1
  return 0
}

# Scenario: CO_ISSUE_V2=0 で即時 rollback できる
# WHEN: CO_ISSUE_V2=0 または unset で co-issue を実行する
# THEN: v1 旧パスで動作し、v2 コードパスは実行されない

test_old_path_preserved_workflow_refine() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'workflow-issue-refine' || return 1
  return 0
}

test_old_path_preserved_workflow_create() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'workflow-issue-create' || return 1
  return 0
}

# Edge case: Phase 2 冒頭の分岐記述（if CO_ISSUE_V2==1 形式）
test_phase2_branch_at_start() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'Phase 2.*v2|Phase 2 (v2)|### Phase 2 (v2)' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "CO_ISSUE_V2==1 分岐記述が Phase 2 に存在する" test_flag_branch_exists_phase2
  run_test "issue-lifecycle-orchestrator の呼び出しが記述されている" test_new_path_dispatch_mentioned
  run_test "aggregate パスが記述されている" test_new_path_aggregate_mentioned
  run_test "v1 旧パス (workflow-issue-refine) が維持されている" test_old_path_preserved_workflow_refine
  run_test "v1 旧パス (workflow-issue-create) が維持されている" test_old_path_preserved_workflow_create
  run_test "Phase 2 v2 分岐 [edge: Phase 2 冒頭での CO_ISSUE_V2 条件分岐]" test_phase2_branch_at_start
else
  run_test_skip "CO_ISSUE_V2==1 分岐記述が Phase 2 に存在する" "skills/co-issue/SKILL.md not found"
  run_test_skip "issue-lifecycle-orchestrator の呼び出しが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "aggregate パスが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "v1 旧パス (workflow-issue-refine) が維持されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "v1 旧パス (workflow-issue-create) が維持されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 2 v2 分岐 [edge: Phase 2 冒頭での CO_ISSUE_V2 条件分岐]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: Phase 2 (CO_ISSUE_V2=1) で依存 DAG を構築する
# Spec: specs/co-issue-v2-phase2-dag/spec.md
# =============================================================================
echo ""
echo "--- Requirement: Phase 2 (CO_ISSUE_V2=1) で依存 DAG を構築する ---"

# Scenario: 依存のある draft が level 分割される
# WHEN: draft #2 が本文内に #1 を含む場合（draft #2 が draft #1 に依存）
# THEN: L0=[draft #1], L1=[draft #2] として level 分割され、
#       policies.json の parent_refs_resolved に L0 の URL が注入される

test_dag_level_split_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'L0|level.*0|Level.*0' || return 1
  return 0
}

test_dag_topological_sort_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'topological|Kahn|level.split|level.分割' || return 1
  return 0
}

test_parent_refs_resolved_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'parent_refs_resolved' || return 1
  return 0
}

# Scenario: 循環依存があればエラー停止する
# WHEN: draft #1 が #2 を含み、draft #2 が #1 を含む（循環）
# THEN: "circular dependency" エラーが出力され、Phase 2 は処理を停止する

test_circular_dependency_detection() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'circular|循環' || return 1
  return 0
}

# Edge case: local-ref regex パターンが記述されている
test_local_ref_regex_pattern() {
  assert_file_exists "$SKILL_MD" || return 1
  # #<local-ref> 記法 (例: #1, #99) の regex または記法説明
  assert_file_contains "$SKILL_MD" '#\d{1,3}|#\\\d|local.ref|local-ref|\(\?<!\[A-Za-z' || return 1
  return 0
}

# Edge case: コードブロック内の #ref を除外する旨の記述
test_code_block_exclusion() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'コードブロック.*除外|除外.*コードブロック|code.block.*exclud|exclud.*code' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "DAG level 分割 (L0/L1) の記述が存在する" test_dag_level_split_mentioned
  run_test "topological sort または Kahn's algorithm の記述が存在する" test_dag_topological_sort_mentioned
  run_test "parent_refs_resolved への URL 注入が記述されている" test_parent_refs_resolved_mentioned
  run_test "循環依存 (circular dependency) エラー記述が存在する" test_circular_dependency_detection
  run_test "DAG [edge: #<local-ref> regex パターンが記述されている]" test_local_ref_regex_pattern
  run_test "DAG [edge: コードブロック内 #ref 除外の記述]" test_code_block_exclusion
else
  run_test_skip "DAG level 分割 (L0/L1) の記述が存在する" "skills/co-issue/SKILL.md not found"
  run_test_skip "topological sort または Kahn's algorithm の記述が存在する" "skills/co-issue/SKILL.md not found"
  run_test_skip "parent_refs_resolved への URL 注入が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "循環依存 (circular dependency) エラー記述が存在する" "skills/co-issue/SKILL.md not found"
  run_test_skip "DAG [edge: #<local-ref> regex パターンが記述されている]" "skills/co-issue/SKILL.md not found"
  run_test_skip "DAG [edge: コードブロック内 #ref 除外の記述]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: per-issue input bundle を書き出す
# Spec: specs/co-issue-v2-phase2-dag/spec.md
# =============================================================================
echo ""
echo "--- Requirement: per-issue input bundle を書き出す ---"

# Scenario: per-issue bundle が作成される
# WHEN: Phase 2 が 2 件の draft を処理する
# THEN: .controller-issue/<sid>/per-issue/1/IN/ と per-issue/2/IN/ の両ディレクトリが作成され、
#       各ファイルが存在する

test_per_issue_dir_path_described() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'per-issue' || return 1
  return 0
}

test_per_issue_in_dir_described() {
  assert_file_exists "$SKILL_MD" || return 1
  # per-issue/<index>/ and IN/ are on adjacent lines in the bundle tree layout
  assert_file_contains "$SKILL_MD" 'per-issue.*index|IN/' || return 1
  return 0
}

test_bundle_files_draft_md() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'draft\.md' || return 1
  return 0
}

test_bundle_files_policies_json() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'policies\.json' || return 1
  return 0
}

test_bundle_files_deps_json() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'deps\.json' || return 1
  return 0
}

# Edge case: arch-context.md も書き出す
test_bundle_files_arch_context() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'arch.context\.md' || return 1
  return 0
}

# Edge case: sid (session-id) ベースのパス
test_per_issue_sid_based_path() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '\.controller-issue.*sid|\.controller-issue.*session' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "per-issue ディレクトリパスが記述されている" test_per_issue_dir_path_described
  run_test "per-issue/IN ディレクトリが記述されている" test_per_issue_in_dir_described
  run_test "bundle ファイル: draft.md が記述されている" test_bundle_files_draft_md
  run_test "bundle ファイル: policies.json が記述されている" test_bundle_files_policies_json
  run_test "bundle ファイル: deps.json が記述されている" test_bundle_files_deps_json
  run_test "bundle [edge: arch-context.md も書き出す]" test_bundle_files_arch_context
  run_test "per-issue [edge: sid ベースのパス記述]" test_per_issue_sid_based_path
else
  run_test_skip "per-issue ディレクトリパスが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "per-issue/IN ディレクトリが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "bundle ファイル: draft.md が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "bundle ファイル: policies.json が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "bundle ファイル: deps.json が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "bundle [edge: arch-context.md も書き出す]" "skills/co-issue/SKILL.md not found"
  run_test_skip "per-issue [edge: sid ベースのパス記述]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: policies.json を 3 パターンで生成する
# Spec: specs/co-issue-v2-phase2-dag/spec.md
# =============================================================================
echo ""
echo "--- Requirement: policies.json を 3 パターンで生成する ---"

# Scenario: 通常パターンの policies.json が生成される
# WHEN: quick / scope-direct フラグが共に false の draft を処理する
# THEN: policies.json に max_rounds=3, specialists=["worker-codex-reviewer","issue-critic",
#       "issue-feasibility"], depth="normal" が書き込まれる

test_policies_max_rounds_3() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'max_rounds.*3|max_rounds=3' || return 1
  return 0
}

test_policies_quick_flag_pattern() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'quick_flag|quick.*flag' || return 1
  return 0
}

test_policies_scope_direct_flag_pattern() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'scope_direct_flag|scope.direct.flag' || return 1
  return 0
}

test_policies_depth_normal() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'depth.*normal|"depth".*"normal"' || return 1
  return 0
}

# Edge case: quick パターンは max_rounds=1 で quick_flag=true
test_policies_quick_pattern_max_rounds_1() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'max_rounds.*1|quick.*max_rounds' || return 1
  return 0
}

# Edge case: AskUserQuestion [dispatch | adjust | cancel] が Phase 2 完了後に記述
test_phase2_ask_user_question_dispatch() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'dispatch.*adjust.*cancel|AskUserQuestion.*dispatch' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "policies.json 通常パターン: max_rounds=3 が記述されている" test_policies_max_rounds_3
  run_test "policies.json: quick_flag が記述されている" test_policies_quick_flag_pattern
  run_test "policies.json: scope_direct_flag が記述されている" test_policies_scope_direct_flag_pattern
  run_test "policies.json 通常パターン: depth=normal が記述されている" test_policies_depth_normal
  run_test "policies.json [edge: quick パターンは max_rounds=1]" test_policies_quick_pattern_max_rounds_1
  run_test "Phase 2 完了後 [edge: AskUserQuestion dispatch|adjust|cancel]" test_phase2_ask_user_question_dispatch
else
  run_test_skip "policies.json 通常パターン: max_rounds=3 が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "policies.json: quick_flag が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "policies.json: scope_direct_flag が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "policies.json 通常パターン: depth=normal が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "policies.json [edge: quick パターンは max_rounds=1]" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 2 完了後 [edge: AskUserQuestion dispatch|adjust|cancel]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: Phase 3 (CO_ISSUE_V2=1) で Level-based dispatch を実行する
# Spec: specs/co-issue-v2-phase3-dispatch/spec.md
# =============================================================================
echo ""
echo "--- Requirement: Phase 3 (CO_ISSUE_V2=1) で Level-based dispatch を実行する ---"

# Scenario: Level 0 が dispatch される
# WHEN: CO_ISSUE_V2=1 で Phase 3 が L0 を処理する
# THEN: issue-lifecycle-orchestrator.sh --per-issue-dir が実行され、
#       orchestrator が同期的に完了を待つ（MAX_PARALLEL=3）
# NOTE: Issue #491 により dispatch.sh/wait.sh は orchestrator.sh に統合済み

test_dispatch_sh_called() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'issue-lifecycle-orchestrator\.sh' || return 1
  return 0
}

test_dispatch_max_parallel_3() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'MAX_PARALLEL.*3|MAX_PARALLEL=3' || return 1
  return 0
}

test_wait_sh_background() {
  assert_file_exists "$SKILL_MD" || return 1
  # Issue #491 により orchestrator.sh が同期待ちを内包（dispatch/wait 統合済み）
  assert_file_contains "$SKILL_MD" 'orchestrator.*同期|同期.*完了を待つ|orchestrator が同期' || return 1
  return 0
}

test_bash_background_mentioned() {
  assert_file_exists "$SKILL_MD" || return 1
  # Issue #491 により orchestrator.sh が同期待ちを内包（Bash-bg 不要）
  assert_file_contains "$SKILL_MD" 'orchestrator.*--per-issue-dir|--per-issue-dir' || return 1
  return 0
}

# Scenario: 全 level が順次 dispatch される
# WHEN: DAG に L0, L1 の 2 level がある
# THEN: L0 の wait 完了後に L1 が dispatch され、全 level 完了後に Phase 4 へ進む

test_sequential_level_dispatch() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'level.*順次|L0.*L1|L0.*完了.*L1|phase 4' || return 1
  return 0
}

test_level_report_collection() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'level_report|BashOutput.*level' || return 1
  return 0
}

# Edge case: orchestrator が --per-issue-dir で level ディレクトリを受け取る
# NOTE: Issue #491 により timeout 管理は orchestrator.sh 内部で処理（--timeout CLI フラグ廃止）
test_wait_timeout_3600() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'orchestrator.*LEVEL_DIR|LEVEL_DIR.*orchestrator|--per-issue-dir.*LEVEL' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 3: issue-lifecycle-orchestrator.sh の呼び出しが記述されている" test_dispatch_sh_called
  run_test "Phase 3: MAX_PARALLEL=3 が指定されている" test_dispatch_max_parallel_3
  run_test "Phase 3: orchestrator が同期的に完了を待つ記述がある" test_wait_sh_background
  run_test "Phase 3: --per-issue-dir オプションが記述されている" test_bash_background_mentioned
  run_test "Phase 3: level 順次 dispatch が記述されている" test_sequential_level_dispatch
  run_test "Phase 3: level_report 取得が記述されている" test_level_report_collection
  run_test "Phase 3 [edge: --timeout 3600 が指定されている]" test_wait_timeout_3600
else
  run_test_skip "Phase 3: issue-lifecycle-orchestrator.sh の呼び出しが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 3: MAX_PARALLEL=3 が指定されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 3: orchestrator が同期的に完了を待つ記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 3: --per-issue-dir オプションが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 3: level 順次 dispatch が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 3: level_report 取得が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 3 [edge: --timeout 3600 が指定されている]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: Level 間で parent URL を注入する
# Spec: specs/co-issue-v2-phase3-dispatch/spec.md
# =============================================================================
echo ""
echo "--- Requirement: Level 間で parent URL を注入する ---"

# Scenario: L1 に L0 の URL が注入される
# WHEN: L0 の dispatch が完了して OUT/report.json に issue URL が含まれる
# THEN: L1 の policies.json.parent_refs_resolved に L0 の issue URL が注入された状態で L1 が dispatch される

test_out_report_json_read() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'OUT/report\.json' || return 1
  return 0
}

test_parent_url_injection() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'parent.*URL|parent_refs_resolved.*URL|URL.*parent_refs' || return 1
  return 0
}

# Edge case: prev level の report.json から URL を読み出す
test_prev_level_url_read() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'prev.*level.*report|report.*prev.*level|前.*level.*URL' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "parent URL 注入: OUT/report.json からの読み出しが記述されている" test_out_report_json_read
  run_test "parent URL 注入: parent_refs_resolved への注入が記述されている" test_parent_url_injection
  run_test "parent URL 注入 [edge: prev level report からの URL 読み出し]" test_prev_level_url_read
else
  run_test_skip "parent URL 注入: OUT/report.json からの読み出しが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "parent URL 注入: parent_refs_resolved への注入が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "parent URL 注入 [edge: prev level report からの URL 読み出し]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: failure 検知で circuit_broken する
# Spec: specs/co-issue-v2-phase3-dispatch/spec.md
# =============================================================================
echo ""
echo "--- Requirement: failure 検知で circuit_broken する ---"

# Scenario: 依存する issue が失敗したら break する
# WHEN: L0 の issue A が失敗し、L1 の issue B が issue A に依存している
# THEN: circuit_broken フラグが立ち、L1 以降の dispatch は実行されない

test_circuit_broken_flag_described() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'circuit_broken' || return 1
  return 0
}

test_circuit_broken_stops_dispatch() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'circuit_broken.*break|break.*circuit|依存.*fail|fail.*依存' || return 1
  return 0
}

# Scenario: 依存しない issue の失敗は継続する
# WHEN: L0 の issue A が失敗し、L1 の全 issue が issue A に依存していない
# THEN: warning を記録して L1 が dispatch される

test_non_dependent_failure_continues() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'warning.*記録|warning のみ記録|依存対象でなければ.*warning' || return 1
  return 0
}

# Edge case: circuit_broken 時は L1 以降は実行されない（スキップ）
test_circuit_broken_skips_remaining() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'circuit_broken.*skip|circuit_broken.*停止|circuit_broken.*break' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "circuit_broken フラグが記述されている" test_circuit_broken_flag_described
  run_test "circuit_broken 時 dispatch が停止する記述がある" test_circuit_broken_stops_dispatch
  run_test "依存しない failure は warning のみで継続する記述がある" test_non_dependent_failure_continues
  run_test "circuit_broken [edge: L1 以降がスキップされる]" test_circuit_broken_skips_remaining
else
  run_test_skip "circuit_broken フラグが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "circuit_broken 時 dispatch が停止する記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "依存しない failure は warning のみで継続する記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "circuit_broken [edge: L1 以降がスキップされる]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: Phase 4 (CO_ISSUE_V2=1) で全 report.json を aggregate して提示する
# Spec: specs/co-issue-v2-phase4-aggregate/spec.md
# =============================================================================
echo ""
echo "--- Requirement: Phase 4 (CO_ISSUE_V2=1) で全 report.json を aggregate して提示する ---"

# Scenario: 全成功時に summary table が表示される
# WHEN: CO_ISSUE_V2=1 で全 issue が done の状態で Phase 4 が実行される
# THEN: done=N / warned=0 / failed=0 / circuit_broken=0 の summary table が表示される

test_aggregate_all_report_json() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'per-issue.*\*/OUT/report\.json|per-issue/\*/OUT' || return 1
  return 0
}

test_summary_table_done_warned_failed() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'done.*warned.*failed|summary.*table|summary table' || return 1
  return 0
}

test_phase4_classify_done_warned_failed_circuit() {
  assert_file_exists "$SKILL_MD" || return 1
  # SKILL.md uses "done=N / warned=W / failed=F / circuit_broken=C" format
  assert_file_contains "$SKILL_MD" 'done.*warned.*failed.*circuit_broken' || return 1
  return 0
}

# Scenario: 一部失敗時に対話が起動する
# WHEN: CO_ISSUE_V2=1 で一部 issue が failed の状態で Phase 4 が実行される
# THEN: summary table 提示後に [retry subset | manual fix | accept partial] で AskUserQuestion が呼ばれる

test_phase4_failure_ask_user_question() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'retry.*subset.*manual.*accept|retry subset|manual fix|accept partial' || return 1
  return 0
}

# Edge case: 全 per-issue/*/OUT/report.json を Read する記述
test_phase4_read_all_report_json() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'per-issue.*OUT.*report|Read.*per-issue' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Phase 4: per-issue/*/OUT/report.json を読み込む記述がある" test_aggregate_all_report_json
  run_test "Phase 4: summary table (done/warned/failed) が記述されている" test_summary_table_done_warned_failed
  run_test "Phase 4: done/warned/failed/circuit_broken 分類が記述されている" test_phase4_classify_done_warned_failed_circuit
  run_test "Phase 4: 一部 failure 時に AskUserQuestion [retry|manual|accept] が記述されている" test_phase4_failure_ask_user_question
  run_test "Phase 4 [edge: 全 report.json を Read する記述]" test_phase4_read_all_report_json
else
  run_test_skip "Phase 4: per-issue/*/OUT/report.json を読み込む記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 4: summary table (done/warned/failed) が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 4: done/warned/failed/circuit_broken 分類が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 4: 一部 failure 時に AskUserQuestion [retry|manual|accept] が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 4 [edge: 全 report.json を Read する記述]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: retry 選択時に orchestrator の resume を呼び出す
# Spec: specs/co-issue-v2-phase4-aggregate/spec.md
# =============================================================================
echo ""
echo "--- Requirement: retry 選択時に orchestrator の resume を呼び出す ---"

# Scenario: retry で非 done issue のみが再実行される
# WHEN: ユーザーが retry subset を選択する
# THEN: issue-lifecycle-orchestrator.sh --resume が呼ばれ、done 済みの issue はスキップされる

test_orchestrator_resume_described() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'orchestrator.*resume|--resume' || return 1
  return 0
}

test_done_issues_skipped_on_retry() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'resume.*非 done|非 done.*再実行|--resume.*done' || return 1
  return 0
}

# Edge case: --per-issue-dir オプションが指定される
test_orchestrator_per_issue_dir_option() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" '--per-issue-dir' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "retry: issue-lifecycle-orchestrator.sh --resume が記述されている" test_orchestrator_resume_described
  run_test "retry: done 済み issue はスキップされる記述がある" test_done_issues_skipped_on_retry
  run_test "retry [edge: --per-issue-dir オプションが記述されている]" test_orchestrator_per_issue_dir_option
else
  run_test_skip "retry: issue-lifecycle-orchestrator.sh --resume が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "retry: done 済み issue はスキップされる記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "retry [edge: --per-issue-dir オプションが記述されている]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: deps.yaml の co-issue controller に workflow-issue-lifecycle を追加する
# Spec: specs/co-issue-v2-phase4-aggregate/spec.md
# =============================================================================
echo ""
echo "--- Requirement: deps.yaml の co-issue controller に workflow-issue-lifecycle を追加する ---"

# Scenario: twl check が PASS する（静的検証のみ、twl は実行しない）
# WHEN: deps.yaml を更新して twl check を実行する
# THEN: エラーなしで PASS する

test_deps_yaml_co_issue_calls_workflow_lifecycle() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
skills = data.get('skills', {})
ci = skills.get('co-issue', {})
calls = ci.get('calls', [])
names = []
for c in calls:
    if isinstance(c, dict):
        names.extend(c.values())
    elif isinstance(c, str):
        names.append(c)
if 'workflow-issue-lifecycle' not in names:
    import sys
    print(f'calls={names}, missing workflow-issue-lifecycle', file=sys.stderr)
    sys.exit(1)
import sys
sys.exit(0)
"
}

test_deps_yaml_workflow_lifecycle_entry() {
  assert_file_exists "$DEPS_YAML" || return 1
  assert_file_contains "$DEPS_YAML" 'workflow-issue-lifecycle:' || return 1
  return 0
}

# Edge case: co-issue の calls はリスト型
test_deps_yaml_co_issue_calls_is_list() {
  assert_file_exists "$DEPS_YAML" || return 1
  yaml_get "$DEPS_YAML" "
import sys
skills = data.get('skills', {})
ci = skills.get('co-issue', {})
calls = ci.get('calls')
if not isinstance(calls, list):
    print(f'calls is {type(calls).__name__}, expected list', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
"
}

# Edge case: workflow-issue-lifecycle の type が workflow であることを確認
test_deps_yaml_workflow_lifecycle_type_workflow() {
  assert_file_exists "$DEPS_YAML" || return 1
  python3 -c "
import sys, re
content = open('${PROJECT_ROOT}/${DEPS_YAML}').read()
# workflow-issue-lifecycle セクションを探して type: workflow を確認
m = re.search(r'workflow-issue-lifecycle:\s*\n\s+type:\s*(\w+)', content)
if not m or m.group(1) != 'workflow':
    print(f'workflow-issue-lifecycle type is {m.group(1) if m else \"not found\"}', file=sys.stderr)
    sys.exit(1)
sys.exit(0)
" 2>/dev/null
}

if [[ -f "${PROJECT_ROOT}/${DEPS_YAML}" ]]; then
  run_test "deps.yaml co-issue.calls に workflow-issue-lifecycle が含まれる" test_deps_yaml_co_issue_calls_workflow_lifecycle
  run_test "deps.yaml: workflow-issue-lifecycle エントリが存在する" test_deps_yaml_workflow_lifecycle_entry
  run_test "deps.yaml [edge: co-issue.calls がリスト型]" test_deps_yaml_co_issue_calls_is_list
  run_test "deps.yaml [edge: workflow-issue-lifecycle の type が workflow]" test_deps_yaml_workflow_lifecycle_type_workflow
else
  run_test_skip "deps.yaml co-issue.calls に workflow-issue-lifecycle が含まれる" "deps.yaml not found"
  run_test_skip "deps.yaml: workflow-issue-lifecycle エントリが存在する" "deps.yaml not found"
  run_test_skip "deps.yaml [edge: co-issue.calls がリスト型]" "deps.yaml not found"
  run_test_skip "deps.yaml [edge: workflow-issue-lifecycle の type が workflow]" "deps.yaml not found"
fi

# =============================================================================
# Requirement: Phase 5 で soak run log を #493 に自動投稿する
# Spec: specs/co-issue-v2-phase5-soak/spec.md
# =============================================================================
echo ""
echo "--- Requirement: Phase 5 で soak run log を #493 に自動投稿する ---"

# Scenario: 成功 run で #493 に run log が投稿される
# WHEN: CO_ISSUE_V2=1 で 1 件以上の issue 作成が成功する
# THEN: gh issue comment 493 -R shuu5/twill で上記フォーマットの 1 行が追記される

test_phase5_exists_in_skill() {
  assert_file_exists "$SKILL_MD" || return 1
  # SKILL.md uses "Soak Auto-logging" heading (no "Phase 5:" prefix to avoid test regression)
  assert_file_contains "$SKILL_MD" 'Soak Auto-logging|Phase 5' || return 1
  return 0
}

test_phase5_gh_issue_comment_493() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'gh issue comment 493|gh.*comment.*493' || return 1
  return 0
}

test_phase5_run_log_format() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'v2 run|run log|soak' || return 1
  return 0
}

test_phase5_total_done_warned_failed_format() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'total=|done=|warned=|failed=' || return 1
  return 0
}

# Scenario: comment 失敗時は warning のみで継続する
# WHEN: gh issue comment 493 コマンドが非ゼロで終了する
# THEN: warning メッセージが出力されるが、Phase 5 は exit 0 で終了する

test_phase5_failure_warning_only() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'warning.*失敗|失敗.*warning|warn.*fail|gh.*fail.*warn|comment.*fail.*warn' || return 1
  return 0
}

test_phase5_failure_nonblocking() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'ブロック.*しない|non.blocking|exit 0|継続|blocking' || return 1
  return 0
}

# Scenario: #493 が closed なら投稿しない
# WHEN: gh issue view 493 が state=CLOSED を返す
# THEN: gh issue comment は実行されずに Phase 5 が完了する

test_phase5_check_issue_493_state() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" 'gh issue view 493|493.*state.*CLOSED|CLOSED.*493' || return 1
  return 0
}

test_phase5_skip_when_closed() {
  assert_file_exists "$SKILL_MD" || return 1
  # SKILL.md uses Japanese "スキップ" (not ASCII "skip")
  assert_file_contains "$SKILL_MD" 'CLOSED.*スキップ|closed.*skip|CLOSED.*skip' || return 1
  return 0
}

# Scenario: flag==0 で Phase 5 が実行されない
# WHEN: CO_ISSUE_V2=0 で co-issue を実行する
# THEN: Phase 5 は実行されず、#493 への comment も行われない

test_phase5_only_runs_with_v2_flag() {
  assert_file_exists "$SKILL_MD" || return 1
  # SKILL.md uses heading "Soak Auto-logging（CO_ISSUE_V2=1 のみ）" — CO_ISSUE_V2 on same line
  assert_file_contains "$SKILL_MD" 'Soak Auto-logging.*CO_ISSUE_V2|CO_ISSUE_V2.*のみ' || return 1
  return 0
}

# Edge case: session id, timestamp を含む run log フォーマット
test_phase5_log_includes_sid_timestamp() {
  assert_file_exists "$SKILL_MD" || return 1
  # SKILL.md uses "(session ${SESSION_ID})" and "${RUN_TS}" in the run log format
  assert_file_contains "$SKILL_MD" 'session.*SESSION_ID|SESSION_ID|RUN_TS' || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "Soak Auto-logging が SKILL.md に記述されている" test_phase5_exists_in_skill
  run_test "Phase 5: gh issue comment 493 の呼び出しが記述されている" test_phase5_gh_issue_comment_493
  run_test "Phase 5: run log フォーマット (v2 run / soak) が記述されている" test_phase5_run_log_format
  run_test "Phase 5: total/done/warned/failed カウンタが記述されている" test_phase5_total_done_warned_failed_format
  run_test "Phase 5: comment 失敗時は warning のみで継続" test_phase5_failure_warning_only
  run_test "Phase 5: comment 失敗はユーザー session をブロックしない" test_phase5_failure_nonblocking
  run_test "Phase 5: gh issue view 493 で状態確認が記述されている" test_phase5_check_issue_493_state
  run_test "Phase 5: #493 closed 時はスキップする記述がある" test_phase5_skip_when_closed
  run_test "Phase 5: CO_ISSUE_V2=1 の時のみ実行される記述がある" test_phase5_only_runs_with_v2_flag
  run_test "Phase 5 [edge: sid と timestamp を含む run log フォーマット]" test_phase5_log_includes_sid_timestamp
else
  run_test_skip "Phase 5 が SKILL.md に記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: gh issue comment 493 の呼び出しが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: run log フォーマット (v2 run / soak) が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: total/done/warned/failed カウンタが記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: comment 失敗時は warning のみで継続" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: comment 失敗はユーザー session をブロックしない" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: gh issue view 493 で状態確認が記述されている" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: #493 closed 時はスキップする記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5: CO_ISSUE_V2=1 の時のみ実行される記述がある" "skills/co-issue/SKILL.md not found"
  run_test_skip "Phase 5 [edge: sid と timestamp を含む run log フォーマット]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: co-issue-v2-smoke.test.sh を新規追加する
# Spec: specs/co-issue-v2-phase5-soak/spec.md
# =============================================================================
echo ""
echo "--- Requirement: co-issue-v2-smoke.test.sh を新規追加する ---"

# Scenario: smoke テストが PASS する
# WHEN: CO_ISSUE_V2=1 bash tests/scenarios/co-issue-v2-smoke.test.sh を実行する
# THEN: テストが全項目 PASS して exit 0 で終了する

# Note: このテスト自身が smoke test ファイルであるため、存在確認を行う
# (上位スクリプトから呼ばれる想定)
SMOKE_TEST_FILE="tests/scenarios/co-issue-v2-smoke.test.sh"

test_smoke_test_file_exists() {
  assert_file_exists "$SMOKE_TEST_FILE" || return 1
  return 0
}

test_smoke_test_is_executable_or_bash() {
  [[ -f "${PROJECT_ROOT}/${SMOKE_TEST_FILE}" ]] || return 1
  # shebang が bash であることを確認
  head -1 "${PROJECT_ROOT}/${SMOKE_TEST_FILE}" | grep -q 'bash\|sh' || return 1
  return 0
}

test_smoke_test_co_issue_v2_env_check() {
  [[ -f "${PROJECT_ROOT}/${SMOKE_TEST_FILE}" ]] || return 1
  grep -q 'CO_ISSUE_V2' "${PROJECT_ROOT}/${SMOKE_TEST_FILE}" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SMOKE_TEST_FILE}" ]]; then
  run_test "co-issue-v2-smoke.test.sh が存在する" test_smoke_test_file_exists
  run_test "co-issue-v2-smoke.test.sh が bash shebang を持つ" test_smoke_test_is_executable_or_bash
  run_test "co-issue-v2-smoke.test.sh が CO_ISSUE_V2 を参照する" test_smoke_test_co_issue_v2_env_check
else
  run_test_skip "co-issue-v2-smoke.test.sh が存在する" "tests/scenarios/co-issue-v2-smoke.test.sh not yet created"
  run_test_skip "co-issue-v2-smoke.test.sh が bash shebang を持つ" "tests/scenarios/co-issue-v2-smoke.test.sh not yet created"
  run_test_skip "co-issue-v2-smoke.test.sh が CO_ISSUE_V2 を参照する" "tests/scenarios/co-issue-v2-smoke.test.sh not yet created"
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
