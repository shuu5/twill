#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: co-issue-specialist-maxturns-fix
# Generated from:
#   deltaspec/changes/co-issue-specialist-maxturns-fix/specs/agent-budget-control/spec.md
#   deltaspec/changes/co-issue-specialist-maxturns-fix/specs/co-issue-depth-control/spec.md
# Coverage level: edge-cases
# Type: unit
#
# Note: Target files are Markdown prompt definitions (agent/skill files).
# These tests verify structural correctness: required instruction sections,
# budget control directives, output detection logic, and guard ordering.
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

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
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

ISSUE_CRITIC="agents/issue-critic.md"
ISSUE_FEASIBILITY="agents/issue-feasibility.md"
SKILL_MD="skills/co-issue/SKILL.md"

# =============================================================================
# Requirement: issue-critic 調査バジェット制御（ref 参照化）
# =============================================================================
echo ""
echo "--- Requirement: issue-critic 調査バジェット制御（ref 参照化） ---"

REF_INVESTIGATION_BUDGET="refs/ref-investigation-budget.md"

# Test: ref-investigation-budget.md が存在する
test_ref_investigation_budget_exists() {
  assert_file_exists "$REF_INVESTIGATION_BUDGET" || return 1
  return 0
}

run_test "ref-investigation-budget.md が存在する" test_ref_investigation_budget_exists

# Test: ref ファイルに調査バジェット制御の内容が含まれる
test_ref_investigation_budget_content() {
  assert_file_exists "$REF_INVESTIGATION_BUDGET" || return 1
  assert_file_contains "$REF_INVESTIGATION_BUDGET" "scope_files.*[3-9]|3.*ファイル以上|scope.*3以上" || return 1
  return 0
}

run_test "ref-investigation-budget: scope_files >= 3 の調査制限内容が存在する" test_ref_investigation_budget_content

# Test: issue-critic の frontmatter skills に ref-investigation-budget が含まれる
test_issue_critic_skills_ref_budget() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic: frontmatter skills に ref-investigation-budget が含まれる" test_issue_critic_skills_ref_budget
else
  run_test_skip "issue-critic: frontmatter skills に ref-investigation-budget" "agents/issue-critic.md not found"
fi

# Test: issue-critic 本文に ref 参照指示が含まれる
test_issue_critic_ref_instruction() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget.*Glob.*Read|Glob.*Read.*ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic: 本文に ref-investigation-budget の Glob/Read 指示が含まれる" test_issue_critic_ref_instruction
else
  run_test_skip "issue-critic: ref-investigation-budget Glob/Read 指示" "agents/issue-critic.md not found"
fi

# Edge case: issue-critic 本文に旧セクション（調査バジェット制御の詳細）が直接記述されていない
test_issue_critic_no_inline_budget() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  # ref 参照指示行以外で "3.*ファイル以上" や "2-3.*tool" が直接存在しないことを確認
  local inline
  inline=$(grep -v "ref-investigation-budget" "${PROJECT_ROOT}/${ISSUE_CRITIC}" | grep -E "3.*ファイル以上|2-3.*tool calls|再帰追跡禁止" | wc -l)
  [[ "$inline" -eq 0 ]] || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "issue-critic [edge: 調査バジェット制御の詳細がインライン記述されていない]" test_issue_critic_no_inline_budget
else
  run_test_skip "issue-critic [edge: インライン記述不在]" "agents/issue-critic.md not found"
fi

# =============================================================================
# Requirement: issue-feasibility 調査バジェット制御（ref 参照化）
# =============================================================================
echo ""
echo "--- Requirement: issue-feasibility 調査バジェット制御（ref 参照化） ---"

# Test: issue-feasibility の frontmatter skills に ref-investigation-budget が含まれる
test_issue_feasibility_skills_ref_budget() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility: frontmatter skills に ref-investigation-budget が含まれる" test_issue_feasibility_skills_ref_budget
else
  run_test_skip "issue-feasibility: frontmatter skills に ref-investigation-budget" "agents/issue-feasibility.md not found"
fi

# Test: issue-feasibility 本文に ref 参照指示が含まれる
test_issue_feasibility_ref_instruction() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget.*Glob.*Read|Glob.*Read.*ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility: 本文に ref-investigation-budget の Glob/Read 指示が含まれる" test_issue_feasibility_ref_instruction
else
  run_test_skip "issue-feasibility: ref-investigation-budget Glob/Read 指示" "agents/issue-feasibility.md not found"
fi

# Edge case: issue-feasibility 本文に旧セクション（調査バジェット制御の詳細）が直接記述されていない
test_issue_feasibility_no_inline_budget() {
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  local inline
  inline=$(grep -v "ref-investigation-budget" "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" | grep -E "3.*ファイル以上|2-3.*tool calls|再帰追跡禁止" | wc -l)
  [[ "$inline" -eq 0 ]] || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-feasibility [edge: 調査バジェット制御の詳細がインライン記述されていない]" test_issue_feasibility_no_inline_budget
else
  run_test_skip "issue-feasibility [edge: インライン記述不在]" "agents/issue-feasibility.md not found"
fi

# =============================================================================
# Requirement: Phase 3b scope_files 依存の調査深度指示注入
# =============================================================================
echo ""
echo "--- Requirement: Phase 3b scope_files 依存の調査深度指示注入 ---"

# Scenario: scope_files が 3 以上の specialist spawn (spec line 7)
# WHEN: co-issue Phase 3b が scope_files: [A, B, C] を含む structured_issue で issue-critic を spawn する
# THEN: spawn プロンプトに「各ファイルは存在確認と直接参照のみ。再帰追跡禁止。
#       残りturns=3になったら出力生成を優先」という調査深度指示が含まれる

# Test: scope_files >= 3 の分岐指示が Phase 3b に存在する
test_skill_phase3b_scope_depth_injection_3plus() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "scope_files.*[3-9]|3.*以上.*scope|scope.*files.*3以上" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Phase 3b: scope_files >= 3 の調査深度指示注入" test_skill_phase3b_scope_depth_injection_3plus
else
  run_test_skip "SKILL.md Phase 3b: scope_files >= 3 の調査深度指示注入" "skills/co-issue/SKILL.md not found"
fi

# Test: 再帰追跡禁止の注入指示が記述されている
test_skill_phase3b_recursive_ban_injected() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "再帰.*追跡.*禁止|再帰追跡禁止|recursive.*禁止" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Phase 3b: 再帰追跡禁止指示がスポーンプロンプトに注入される" test_skill_phase3b_recursive_ban_injected
else
  run_test_skip "SKILL.md Phase 3b: 再帰追跡禁止注入" "skills/co-issue/SKILL.md not found"
fi

# Test: 残り turns=3 になったら出力生成を優先の注入指示
test_skill_phase3b_turns_priority_injected() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "残り.*turns.*3|turns.*3.*出力.*優先|3.*turns.*出力" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Phase 3b: 残りturns=3で出力優先の注入指示" test_skill_phase3b_turns_priority_injected
else
  run_test_skip "SKILL.md Phase 3b: 残りturns=3 出力優先注入" "skills/co-issue/SKILL.md not found"
fi

# Scenario: scope_files が 2 以下の specialist spawn (spec line 11)
# WHEN: co-issue Phase 3b が scope_files: [A, B] を含む structured_issue で issue-critic を spawn する
# THEN: spawn プロンプトに「各ファイルの呼び出し元まで追跡可」という指示が含まれる

# Test: scope_files < 3 の場合の呼び出し元追跡許可指示
test_skill_phase3b_scope_depth_injection_2or_less() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "呼び出し元.*追跡.*可|追跡.*可.*scope|scope.*2.*以下|2以下.*追跡|呼び出し元.*まで.*追跡" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Phase 3b: scope_files <= 2 の場合の呼び出し元追跡許可指示" test_skill_phase3b_scope_depth_injection_2or_less
else
  run_test_skip "SKILL.md Phase 3b: scope_files <= 2 の呼び出し元追跡許可" "skills/co-issue/SKILL.md not found"
fi

# Edge case: 条件分岐（scope_files 数による分岐）の構造が存在する
test_skill_phase3b_conditional_structure() {
  assert_file_exists "$SKILL_MD" || return 1
  # Must have both >= 3 and <= 2 handling (either if/else or separate instructions)
  assert_file_contains "$SKILL_MD" "scope_files.*[3-9]|3.*以上" || return 1
  assert_file_contains "$SKILL_MD" "呼び出し元.*追跡|追跡.*可|2.*以下" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Phase 3b [edge: scope_files 数による分岐構造が存在する]" test_skill_phase3b_conditional_structure
else
  run_test_skip "SKILL.md Phase 3b [edge: 条件分岐構造]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: Step 3c 出力なし完了の検知と WARNING 表示
# =============================================================================
echo ""
echo "--- Requirement: Step 3c 出力なし完了の検知と WARNING 表示 ---"

# Scenario: specialist が構造化出力なしで完了 (spec line 19)
# WHEN: issue-critic の返却値に `status:` も `findings:` も含まれない
# THEN: Step 3c の findings テーブルに
#       「WARNING: issue-critic: 構造化出力なしで完了（調査が maxTurns に到達した可能性）」が表示され、
#       Phase 4 は継続される

# Test: 出力なし完了の検知ロジックが Step 3c に記述されている
test_skill_step3c_no_output_detection() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "status:.*findings:|findings:.*status:|構造化.*出力.*な|出力.*なし.*完了|status.*含まれない|findings.*含まれない" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: 出力なし完了の検知ロジックが記述されている" test_skill_step3c_no_output_detection
else
  run_test_skip "SKILL.md Step 3c: 出力なし完了の検知" "skills/co-issue/SKILL.md not found"
fi

# Test: WARNING エントリを findings テーブルに追加する旨の記述
test_skill_step3c_warning_added_to_findings() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "WARNING.*issue-critic.*構造化|WARNING.*出力なし|WARNING.*maxTurns|出力なし.*WARNING" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: 出力なし完了時に WARNING エントリを追加する" test_skill_step3c_warning_added_to_findings
else
  run_test_skip "SKILL.md Step 3c: WARNING エントリ追加" "skills/co-issue/SKILL.md not found"
fi

# Test: maxTurns への到達可能性が WARNING メッセージに含まれる
test_skill_step3c_maxtturns_mention_in_warning() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "maxTurns|max.*turns|maxターン" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: WARNING に maxTurns 到達可能性の言及がある" test_skill_step3c_maxtturns_mention_in_warning
else
  run_test_skip "SKILL.md Step 3c: maxTurns 言及" "skills/co-issue/SKILL.md not found"
fi

# Test: WARNING は Phase 4 をブロックしない（非ブロッキング）旨の記述
test_skill_step3c_warning_non_blocking() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase.*4.*継続|非ブロック|ブロック.*しない|Phase 4.*続行|SHALL NOT.*ブロック|WARNING.*継続" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: WARNING は Phase 4 をブロックしない（非ブロッキング）" test_skill_step3c_warning_non_blocking
else
  run_test_skip "SKILL.md Step 3c: Phase 4 非ブロッキング" "skills/co-issue/SKILL.md not found"
fi

# Scenario: specialist が正常に構造化出力を返す (spec line 23)
# WHEN: issue-critic の返却値に `status: ok` と `findings: [...]` が含まれる
# THEN: Step 3c は通常通りパースし、WARNING は表示されない

# Test: 正常パスは従来通りのパース処理が維持されている
test_skill_step3c_normal_parse_maintained() {
  assert_file_exists "$SKILL_MD" || return 1
  # Both status: and findings: patterns should still be parsed normally
  assert_file_contains "$SKILL_MD" "findings.*統合|findings.*マージ|findings.*集約|findings.*パース|集約.*findings" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: 正常な構造化出力は通常パース処理が維持される" test_skill_step3c_normal_parse_maintained
else
  run_test_skip "SKILL.md Step 3c: 正常パス維持" "skills/co-issue/SKILL.md not found"
fi

# Edge case: 出力なし検知は `status:` OR `findings:` のどちらか一方でも欠如した場合に発動する
test_skill_step3c_both_keywords_required() {
  assert_file_exists "$SKILL_MD" || return 1
  # Detection condition: neither status: nor findings: present
  assert_file_contains "$SKILL_MD" "status:.*も.*findings:|status.*findings.*含まれない|status.*も.*findings.*も|含まれない.*場合" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c [edge: status: も findings: も含まれない条件が明示]" test_skill_step3c_both_keywords_required
else
  run_test_skip "SKILL.md Step 3c [edge: 両キーワード不在条件]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Requirement: Step 3c ガード順序の明記
# =============================================================================
echo ""
echo "--- Requirement: Step 3c ガード順序の明記 ---"

# Scenario: 役割分担ドキュメント (spec line 31)
# WHEN: Step 3c の処理フローを参照する
# THEN: 「出力なし検知 → パース失敗フォールバック」の順序と役割が明記されている

# Test: 出力なし検知（上位ガード）の記述が存在する
test_skill_step3c_upper_guard_exists() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "上位.*ガード|出力なし.*検知|出力.*なし.*ガード|上位ガード" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: 出力なし検知が上位ガードとして記述されている" test_skill_step3c_upper_guard_exists
else
  run_test_skip "SKILL.md Step 3c: 上位ガード記述" "skills/co-issue/SKILL.md not found"
fi

# Test: パース失敗フォールバック（下位ガード）の記述が存在する
test_skill_step3c_lower_guard_exists() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "下位.*ガード|パース失敗.*フォールバック|フォールバック.*下位|パース.*失敗|ref-specialist-output-schema" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: パース失敗フォールバックが下位ガードとして記述されている" test_skill_step3c_lower_guard_exists
else
  run_test_skip "SKILL.md Step 3c: 下位ガード記述" "skills/co-issue/SKILL.md not found"
fi

# Test: 上位ガード → 下位ガードの処理順序が明記されている
test_skill_step3c_guard_order_documented() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "上位.*ガード|出力なし.*検知.*パース|出力なし.*→.*パース" || return 1
  assert_file_contains "$SKILL_MD" "下位.*ガード|パース.*失敗.*フォールバック" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c: 上位ガード → 下位ガードの処理順序が明記されている" test_skill_step3c_guard_order_documented
else
  run_test_skip "SKILL.md Step 3c: ガード順序明記" "skills/co-issue/SKILL.md not found"
fi

# Edge case: 役割分担（上位=出力なし検知、下位=パース失敗フォールバック）が区別されている
test_skill_step3c_guard_role_distinction() {
  assert_file_exists "$SKILL_MD" || return 1
  # Both concepts should co-exist in the document
  assert_file_contains_all "$SKILL_MD" \
    "出力.*なし.*検知|出力なし.*ガード|上位.*ガード" \
    "パース.*失敗|フォールバック|ref-specialist-output-schema"
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md Step 3c [edge: 上位/下位ガードの役割が区別されている]" test_skill_step3c_guard_role_distinction
else
  run_test_skip "SKILL.md Step 3c [edge: ガード役割区別]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Cross-cutting: Consistency across agent files and SKILL.md
# =============================================================================
echo ""
echo "--- Cross-cutting: エージェントファイルと SKILL.md の整合性 ---"

# Test: issue-critic と issue-feasibility の両方が ref-investigation-budget を参照する
test_both_agents_have_budget_control() {
  assert_file_exists "$ISSUE_CRITIC" || return 1
  assert_file_exists "$ISSUE_FEASIBILITY" || return 1
  # Both should reference ref-investigation-budget via skills frontmatter
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget" || return 1
  assert_file_contains "$ISSUE_FEASIBILITY" "ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]] && [[ -f "${PROJECT_ROOT}/${ISSUE_FEASIBILITY}" ]]; then
  run_test "issue-critic と issue-feasibility の両方が ref-investigation-budget を参照する" test_both_agents_have_budget_control
else
  run_test_skip "両エージェントの整合性確認" "One or both agent files not found"
fi

# Test: ref-investigation-budget.md に再帰追跡禁止指示が含まれる
test_ref_has_recursive_ban() {
  assert_file_exists "$REF_INVESTIGATION_BUDGET" || return 1
  assert_file_contains "$REF_INVESTIGATION_BUDGET" "再帰.*禁止|再帰追跡禁止|recursive.*禁止" || return 1
  return 0
}

run_test "ref-investigation-budget: 再帰追跡禁止指示が含まれる" test_ref_has_recursive_ban

# Edge case: SKILL.md の Phase 3b 注入指示と ref による agent 自己制限の二重防御構造
test_defense_in_depth_structure() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_exists "$ISSUE_CRITIC" || return 1
  # SKILL.md should have depth injection AND agents should reference the budget ref
  assert_file_contains "$SKILL_MD" "scope_files.*[3-9]|3.*以上.*scope" || return 1
  assert_file_contains "$ISSUE_CRITIC" "ref-investigation-budget" || return 1
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]] && [[ -f "${PROJECT_ROOT}/${ISSUE_CRITIC}" ]]; then
  run_test "[edge: SKILL.md 注入 + agent ref 参照の二重防御構造]" test_defense_in_depth_structure
else
  run_test_skip "[edge: 二重防御構造]" "SKILL.md or issue-critic.md not found"
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
