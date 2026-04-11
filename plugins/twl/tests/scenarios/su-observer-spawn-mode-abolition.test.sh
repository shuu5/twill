#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: su-observer モード廃止・常駐ループ・spawn構造
# Generated from: deltaspec/changes/issue-440/specs/su-observer-skill/spec.md
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

assert_valid_yaml() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && python3 -c "
import yaml, sys
with open('${PROJECT_ROOT}/${file}') as f:
    yaml.safe_load(f)
" 2>/dev/null
}

yaml_list_contains() {
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
  ((SKIP++)) || true
}

SU_OBSERVER_SKILL="skills/su-observer/SKILL.md"
CO_SELF_IMPROVE_SKILL="skills/co-self-improve/SKILL.md"
DEPS_YAML="deps.yaml"
DESIGN_DOC="architecture/designs/su-observer-skill-design.md"
SUPERVISION_MD="architecture/domain/contexts/supervision.md"

# =============================================================================
# Requirement: su-observer SKILL.md モード分離廃止
# Scenario: ユーザーが「Issue 実装して」と指示した場合 (spec.md line 7)
# WHEN: ユーザーが特定の Issue 番号とともに実装指示を出す
# THEN: su-observer は AskUserQuestion でモードを確認せず、直接 co-autopilot を
#       cld-spawn 経由で spawn し、cld-observe-loop で能動 observe を開始する（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: su-observer SKILL.md モード分離廃止 ---"

# Test: モード判定テーブルが存在しない
test_no_mode_table() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # "モード" + テーブル（| 区切り行）または numbered list のモード番号が存在しないか
  assert_file_not_contains "$SU_OBSERVER_SKILL" \
    "モード.*テーブル|mode.*table|^\|\s*(autopilot|issue|architect|observe|compact|delegate)\s*\|"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "モード判定テーブルが存在しない" test_no_mode_table
else
  run_test_skip "モード判定テーブルが存在しない" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: AskUserQuestion によるモード強制選択が記述されていない
test_no_ask_user_question_mode() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" \
    "AskUserQuestion.*モード|モード.*AskUserQuestion|モード選択.*確認|確認.*モード"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "AskUserQuestion でモード強制選択する記述がない" test_no_ask_user_question_mode
else
  run_test_skip "AskUserQuestion モード強制選択なし" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: cld-spawn が記述されている（実装指示受取後 spawn する経路の明示）
test_cld_spawn_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "cld-spawn"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "cld-spawn が記述されている" test_cld_spawn_referenced
else
  run_test_skip "cld-spawn 参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: cld-observe-loop が記述されている（能動 observe の明示）
test_cld_observe_loop_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "cld-observe-loop"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "cld-observe-loop が記述されている" test_cld_observe_loop_referenced
else
  run_test_skip "cld-observe-loop 参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# Edge case: Skill() 直接呼出し記述が存在しない（spawn 経由のみ許容）
test_no_skill_direct_call() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" \
    "Skill\s*\(\s*twl:co-autopilot\s*\)|Skill\s*\(\s*twl:co-issue\s*\)|Skill\s*\(\s*twl:co-self-improve\s*\)"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] Skill() 直接呼出し記述が存在しない" test_no_skill_direct_call
else
  run_test_skip "[edge] Skill() 直接呼出しなし" "${SU_OBSERVER_SKILL} not yet created"
fi

# Scenario: ユーザーが「状況は？」と問い合わせた場合 (spec.md line 11)
# WHEN: ユーザーが現在の進捗や状況確認を求める
# THEN: su-observer は cld-observe（単発）で観察し、状況レポートをユーザーに返す（SHALL）

# Test: cld-observe（単発）が記述されている
test_cld_observe_single_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "cld-observe\b"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "cld-observe（単発）が記述されている" test_cld_observe_single_referenced
else
  run_test_skip "cld-observe 単発参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# =============================================================================
# Requirement: su-observer SKILL.md 常駐ループ構造
# Scenario: セッション初期化 (spec.md line 19)
# WHEN: su-observer が起動される
# THEN: Step 0 で bare repo 検証、SupervisorSession 復帰/新規作成、
#       Project Board 状態取得、doobidoo 記憶復元を実行しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: su-observer SKILL.md 常駐ループ構造 ---"

# Test: Step 0 が存在する
test_step0_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*0"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0 (初期化) が定義されている" test_step0_exists
else
  run_test_skip "Step 0 存在" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: Step 1 が存在する（常駐ループ）
test_step1_resident_loop_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*1"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 1 (常駐ループ) が定義されている" test_step1_resident_loop_exists
else
  run_test_skip "Step 1 存在" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: Step 2 が存在する（終了）
test_step2_exit_exists() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Step\s*2"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 2 (終了) が定義されている" test_step2_exit_exists
else
  run_test_skip "Step 2 存在" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: Step 0 に bare repo 検証の記述がある
test_step0_bare_repo_check() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "bare.*repo|bare\s*リポ|\.bare"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0 に bare repo 検証の記述がある" test_step0_bare_repo_check
else
  run_test_skip "Step 0 bare repo 検証" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: Step 0 に SupervisorSession 復帰/新規作成の記述がある
test_step0_supervisor_session() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "SupervisorSession|supervisor.*session|セッション.*復帰|セッション.*新規"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0 に SupervisorSession 復帰/新規作成の記述がある" test_step0_supervisor_session
else
  run_test_skip "Step 0 SupervisorSession" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: Step 0 に Project Board 状態取得の記述がある
test_step0_project_board() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Project\s*Board|project.*board"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0 に Project Board 状態取得の記述がある" test_step0_project_board
else
  run_test_skip "Step 0 Project Board" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: Step 0 に doobidoo 記憶復元の記述がある
test_step0_doobidoo_memory() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "doobidoo|memory.*復元|記憶.*復元|memory_search"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 0 に doobidoo 記憶復元の記述がある" test_step0_doobidoo_memory
else
  run_test_skip "Step 0 doobidoo 記憶復元" "${SU_OBSERVER_SKILL} not yet created"
fi

# Scenario: 常駐ループでの controller spawn (spec.md line 23)
# WHEN: Step 1 の常駐ループ中にユーザーが controller 起動を必要とする指示を出す
# THEN: 対象 controller を cld-spawn 経由で起動しなければならない（SHALL）
#       co-autopilot の場合は追加で cld-observe-loop を実行しなければならない（SHALL）

# Test: Step 1 の常駐ループ内に cld-spawn の記述がある
test_step1_cld_spawn() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "cld-spawn"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Step 1 常駐ループ内に cld-spawn の記述がある" test_step1_cld_spawn
else
  run_test_skip "Step 1 cld-spawn" "${SU_OBSERVER_SKILL} not yet created"
fi

# Edge case: Step 2（終了）以降に Step 3 以上のステップが定義されていない（3ステップ構造）
test_no_step3_or_higher() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # Step 3 が見出し行（## または ### Step 3）として現れないことを確認
  if grep -qiP "^#{1,6}\s*Step\s*3\b" "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}"; then
    return 1
  fi
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] Step 3 以上の見出しが存在しない（3 ステップ構造）" test_no_step3_or_higher
else
  run_test_skip "[edge] Step 3 以上なし" "${SU_OBSERVER_SKILL} not yet created"
fi

# =============================================================================
# Requirement: 全 controller の session:spawn 経由起動
# Scenario: co-self-improve の起動 (spec.md line 31)
# WHEN: su-observer がテスト実行を co-self-improve に委譲する
# THEN: cld-spawn で co-self-improve セッションを起動しなければならない（SHALL）
#       Skill(twl:co-self-improve) 直接呼出しを使ってはならない（SHALL NOT）
# =============================================================================
echo ""
echo "--- Requirement: 全 controller の session:spawn 経由起動 ---"

# Test: co-self-improve への Skill() 直接呼出し記述が存在しない
test_no_skill_co_self_improve_direct() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" \
    "Skill\s*\(\s*twl:co-self-improve\s*\)"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Skill(twl:co-self-improve) 直接呼出し記述が存在しない" test_no_skill_co_self_improve_direct
else
  run_test_skip "Skill(twl:co-self-improve) 直接呼出しなし" "${SU_OBSERVER_SKILL} not yet created"
fi

# Edge case: co-autopilot・co-issue・co-architect・co-project・co-utility についても
#            Skill() 直接呼出し記述が存在しない
test_no_skill_any_controller_direct() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_not_contains "$SU_OBSERVER_SKILL" \
    "Skill\s*\(\s*twl:(co-autopilot|co-issue|co-architect|co-project|co-utility|co-self-improve)\s*\)"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] 全 controller の Skill() 直接呼出し記述が存在しない" test_no_skill_any_controller_direct
else
  run_test_skip "[edge] 全 controller Skill() 直接呼出しなし" "${SU_OBSERVER_SKILL} not yet created"
fi

# =============================================================================
# Requirement: session plugin スクリプト群の明示的参照
# Scenario: observe ループの実行 (spec.md line 39)
# WHEN: co-autopilot が spawn された後
# THEN: cld-observe-loop で能動 observe ループを実行しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: session plugin スクリプト群の明示的参照 ---"

# Test: session-state.sh が参照されている
test_session_state_sh_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-state\.sh"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "session-state.sh が参照されている" test_session_state_sh_referenced
else
  run_test_skip "session-state.sh 参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# Test: session-comm.sh が参照されている
test_session_comm_sh_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "session-comm\.sh"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "session-comm.sh が参照されている" test_session_comm_sh_referenced
else
  run_test_skip "session-comm.sh 参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# Scenario: 介入が必要な問題の検出 (spec.md line 43)
# WHEN: observe 中に問題パターンを検出した場合
# THEN: session-comm.sh を使用して介入プロトコル（SU-1〜SU-7）に従い対応（SHALL）

# Test: SU-1 から SU-7 の制約参照が維持されている
test_su_constraints_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "SU-1"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SU-1 制約参照が維持されている" test_su_constraints_referenced
else
  run_test_skip "SU-1 制約参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# Edge case: SU-1〜SU-7 が全て参照されている
test_all_su_constraints_referenced() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  local missing_count=0
  for i in 1 2 3 4 5 6 7; do
    if ! grep -qiP "SU-${i}\b" "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}"; then
      echo "SU-${i} not found in ${SU_OBSERVER_SKILL}" >&2
      ((missing_count++)) || true
    fi
  done
  [[ $missing_count -eq 0 ]]
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] SU-1〜SU-7 が全て参照されている" test_all_su_constraints_referenced
else
  run_test_skip "[edge] SU-1〜SU-7 全参照" "${SU_OBSERVER_SKILL} not yet created"
fi

# =============================================================================
# Requirement: SU-1〜SU-7 制約の維持
# Scenario: 介入実行時の 3 層プロトコル遵守 (spec.md line 51)
# WHEN: su-observer が問題を検出して介入する
# THEN: SU-1 に従い Auto / Confirm / Escalate の 3 層プロトコルに従う（SHALL）
#       SU-2 に従い Layer 2（Escalate）はユーザー確認が必要（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: SU-1〜SU-7 制約の維持 ---"

# Test: Auto / Confirm / Escalate の 3 層プロトコルが記述されている
test_three_layer_protocol() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "Auto|Confirm|Escalate"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "Auto / Confirm / Escalate の 3 層プロトコルが記述されている" test_three_layer_protocol
else
  run_test_skip "3 層プロトコル記述" "${SU_OBSERVER_SKILL} not yet created"
fi

# Scenario: 直接実装の禁止 (spec.md line 55)
# WHEN: su-observer が Issue の実装を求められた場合
# THEN: SU-3 に従い自ら実装を行ってはならない（SHALL NOT）
#       適切な controller に委譲しなければならない（SHALL）

# Test: SU-3（自ら実装禁止）が記述されている
test_su3_no_direct_impl() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  assert_file_contains "$SU_OBSERVER_SKILL" "SU-3"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "SU-3（直接実装禁止）が記述されている" test_su3_no_direct_impl
else
  run_test_skip "SU-3 記述" "${SU_OBSERVER_SKILL} not yet created"
fi

# Edge case: su-observer 自身が実装コマンド（git commit 等）を直接実行する記述がない
test_no_direct_impl_commands() {
  assert_file_exists "$SU_OBSERVER_SKILL" || return 1
  # su-observer が直接 git commit や実装操作を行う指示でないこと（委譲が必須）
  # "su-observer は git commit" や "自ら実装" のような記述がないことを確認
  assert_file_not_contains "$SU_OBSERVER_SKILL" \
    "su-observer.*自ら実装|自ら.*コード.*実装|自ら.*書く"
}

if [[ -f "${PROJECT_ROOT}/${SU_OBSERVER_SKILL}" ]]; then
  run_test "[edge] su-observer が自ら実装する記述が存在しない" test_no_direct_impl_commands
else
  run_test_skip "[edge] 自ら実装記述なし" "${SU_OBSERVER_SKILL} not yet created"
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
