#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: architecture-documents.md
# Generated from: deltaspec/changes/b-1-chain-driven-autopilot-first/specs/architecture-documents.md
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
  if [[ -f "${PROJECT_ROOT}/${file}" ]]; then
    return 0
  else
    return 1
  fi
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  if [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 0
  else
    return 1
  fi
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    return 1
  fi
  for pattern in "${patterns[@]}"; do
    if ! grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
      return 1
    fi
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
# Requirement: コンポーネントマッピング表
# =============================================================================
echo ""
echo "--- Requirement: コンポーネントマッピング表 ---"

# Scenario: 全コンポーネント種別をカバー (line 15)
# WHEN: architecture/migration/component-mapping.md を確認する
# THEN: controller, workflow, atomic, specialist, script, reference の全種別について旧→新マッピングが記載されている
test_component_mapping_all_types() {
  local file="architecture/migration/component-mapping.md"
  assert_file_exists "$file" "component-mapping.md exists" || return 1
  assert_file_contains_all "$file" \
    "controller" \
    "workflow" \
    "atomic" \
    "specialist" \
    "script" \
    "reference"
}
run_test "全コンポーネント種別をカバー" test_component_mapping_all_types

# Scenario: 全コンポーネント種別をカバー - Edge Case: 種別が見出しレベルで分類されている
test_component_mapping_types_as_headings() {
  local file="architecture/migration/component-mapping.md"
  assert_file_exists "$file" "component-mapping.md exists" || return 1
  # Each type should appear as a heading or table header, not just in body text
  local count=0
  for type in controller workflow atomic specialist script reference; do
    if grep -qiP "^#{1,4}\s.*${type}|^\|.*${type}" "${PROJECT_ROOT}/${file}"; then
      ((count++))
    fi
  done
  [[ $count -ge 6 ]]
}
run_test "全コンポーネント種別をカバー [edge: 見出しまたはテーブルで分類]" test_component_mapping_types_as_headings

# Scenario: 吸収先が明確 (line 19)
# WHEN: マッピング表で「吸収」カテゴリのコンポーネントを確認する
# THEN: 各エントリに吸収先の新コンポーネント名と根拠が記載されている
test_component_mapping_absorption_clear() {
  local file="architecture/migration/component-mapping.md"
  assert_file_exists "$file" "component-mapping.md exists" || return 1
  assert_file_contains "$file" "吸収" || return 1
  # Verify absorption entries have target component names (at least one table row with absorption)
  # Pattern: table row containing "吸収" should also have content in other columns
  grep -iP "吸収" "${PROJECT_ROOT}/${file}" | grep -qiP "\|.*\|.*\|"
}
run_test "吸収先が明確" test_component_mapping_absorption_clear

# Edge case: 吸収カテゴリに根拠列が空でない
test_component_mapping_absorption_has_rationale() {
  local file="architecture/migration/component-mapping.md"
  assert_file_exists "$file" "component-mapping.md exists" || return 1
  # Check that rows with "吸収" don't have empty trailing cells (e.g., "| 吸収 | | |")
  if grep -iP "吸収" "${PROJECT_ROOT}/${file}" | grep -qP "\|\s*\|\s*$"; then
    return 1  # Found empty cells = fail
  fi
  return 0
}
run_test "吸収先が明確 [edge: 根拠列が空でない]" test_component_mapping_absorption_has_rationale

# Edge case: 4つのカテゴリ（吸収・削除・移植・新規）が全て存在
test_component_mapping_all_categories() {
  local file="architecture/migration/component-mapping.md"
  assert_file_exists "$file" "component-mapping.md exists" || return 1
  assert_file_contains_all "$file" "吸収" "削除" "移植" "新規"
}
run_test "4カテゴリ（吸収・削除・移植・新規）が全て存在 [edge]" test_component_mapping_all_categories

# =============================================================================
# Requirement: B-3/C-4 スコープ境界定義
# =============================================================================
echo ""
echo "--- Requirement: B-3/C-4 スコープ境界定義 ---"

# Scenario: スコープの分類基準が明確 (line 29)
# WHEN: architecture/migration/scope-boundary.md を確認する
# THEN: B-3 と C-4 の分類基準が定義されている
test_scope_boundary_criteria() {
  local file="architecture/migration/scope-boundary.md"
  assert_file_exists "$file" "scope-boundary.md exists" || return 1
  assert_file_contains "$file" "B-3" || return 1
  assert_file_contains "$file" "C-4" || return 1
  # Verify key B-3 components are mentioned
  assert_file_contains_all "$file" \
    "autopilot-plan" \
    "init-session" \
    "phase-execute"
}
run_test "スコープの分類基準が明確" test_scope_boundary_criteria

# Edge case: B-3 と C-4 が同一行に混在しない（分離定義されている）
test_scope_boundary_separated() {
  local file="architecture/migration/scope-boundary.md"
  assert_file_exists "$file" "scope-boundary.md exists" || return 1
  # B-3 section and C-4 section should exist as separate headings or table sections
  local b3_line c4_line
  b3_line=$(grep -n "B-3" "${PROJECT_ROOT}/${file}" | head -1 | cut -d: -f1)
  c4_line=$(grep -n "C-4" "${PROJECT_ROOT}/${file}" | head -1 | cut -d: -f1)
  [[ -n "$b3_line" && -n "$c4_line" && "$b3_line" != "$c4_line" ]]
}
run_test "スコープの分類基準が明確 [edge: B-3/C-4が分離定義]" test_scope_boundary_separated

# Scenario: 全 script が分類済み (line 33)
# WHEN: スコープ境界テーブルを確認する
# THEN: B-5 を含む全 script に対してスコープが割り当てられている
test_scope_boundary_all_scripts() {
  local file="architecture/migration/scope-boundary.md"
  assert_file_exists "$file" "scope-boundary.md exists" || return 1
  assert_file_contains "$file" "B-5" || return 1
  assert_file_contains "$file" "merge-gate"
}
run_test "全 script が分類済み" test_scope_boundary_all_scripts

# Edge case: テーブルに「未分類」や空セルがない
test_scope_boundary_no_unclassified() {
  local file="architecture/migration/scope-boundary.md"
  assert_file_exists "$file" "scope-boundary.md exists" || return 1
  # No rows with empty scope column (pattern: "| something | |" at end)
  if grep -P "^\|[^|]+\|\s*\|" "${PROJECT_ROOT}/${file}" | grep -qvP "---|---"; then
    return 1  # Found unclassified entries
  fi
  return 0
}
run_test "全 script が分類済み [edge: 未分類エントリなし]" test_scope_boundary_no_unclassified

# =============================================================================
# Requirement: Specialist 共通出力スキーマ仕様
# =============================================================================
echo ""
echo "--- Requirement: Specialist 共通出力スキーマ仕様 ---"

# Scenario: JSON スキーマが完全定義 (line 43)
# WHEN: architecture/contracts/specialist-output-schema.md を確認する
# THEN: status, severity, confidence, findings の必須フィールドが全て定義されている
test_specialist_schema_complete() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  assert_file_contains_all "$file" \
    "status" \
    "severity" \
    "confidence" \
    "findings"
}
run_test "JSON スキーマが完全定義" test_specialist_schema_complete

# Edge case: status の有効値 PASS/WARN/FAIL が全て定義
test_specialist_schema_status_values() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  assert_file_contains_all "$file" "PASS" "WARN" "FAIL"
}
run_test "JSON スキーマ [edge: status値 PASS/WARN/FAIL が定義]" test_specialist_schema_status_values

# Edge case: severity の有効値 CRITICAL/WARNING/INFO が全て定義
test_specialist_schema_severity_values() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  assert_file_contains_all "$file" "CRITICAL" "WARNING" "INFO"
}
run_test "JSON スキーマ [edge: severity値 CRITICAL/WARNING/INFO が定義]" test_specialist_schema_severity_values

# Edge case: confidence の範囲 0-100 が明記
test_specialist_schema_confidence_range() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  assert_file_contains "$file" "0.*100|0-100|0〜100"
}
run_test "JSON スキーマ [edge: confidence範囲 0-100 が明記]" test_specialist_schema_confidence_range

# Scenario: few-shot 例が含まれる (line 47)
# WHEN: specialist-output-schema.md を確認する
# THEN: PASS ケースと FAIL ケースの few-shot 例が各1つ以上
test_specialist_schema_fewshot() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  # Look for code blocks (json/yaml) containing PASS and FAIL examples
  local content
  content=$(cat "${PROJECT_ROOT}/${file}")
  echo "$content" | grep -qP '"status"\s*:\s*"PASS"|status:\s*PASS' || return 1
  echo "$content" | grep -qP '"status"\s*:\s*"FAIL"|status:\s*FAIL' || return 1
}
run_test "few-shot 例が含まれる" test_specialist_schema_fewshot

# Edge case: few-shot例がコードブロック内に記載されている
test_specialist_schema_fewshot_in_codeblock() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  # Check that there are at least 2 code blocks (for PASS and FAIL examples)
  local codeblock_count
  codeblock_count=$(grep -c '```' "${PROJECT_ROOT}/${file}" || echo "0")
  [[ $codeblock_count -ge 4 ]]  # Opening + closing for at least 2 blocks
}
run_test "few-shot 例 [edge: コードブロック内に記載]" test_specialist_schema_fewshot_in_codeblock

# =============================================================================
# Requirement: Model 割り当て表
# =============================================================================
echo ""
echo "--- Requirement: Model 割り当て表 ---"

# Scenario: 全 specialist の model が指定 (line 57)
# WHEN: model 割り当て表を確認する
# THEN: haiku/sonnet/opus の分類基準と対象一覧が記載されている
test_model_assignment() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  assert_file_contains_all "$file" "haiku" "sonnet" "opus"
}
run_test "全 specialist の model が指定" test_model_assignment

# Edge case: haiku の用途（構造チェック・パターンマッチ）が明記
test_model_assignment_haiku_purpose() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  # haiku line should mention structural check or pattern match
  grep -iP "haiku" "${PROJECT_ROOT}/${file}" | grep -qiP "構造|パターン|structure|pattern"
}
run_test "Model 割り当て [edge: haiku用途が明記]" test_model_assignment_haiku_purpose

# Edge case: sonnet の用途（コードレビュー・品質判断）が明記
test_model_assignment_sonnet_purpose() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  grep -iP "sonnet" "${PROJECT_ROOT}/${file}" | grep -qiP "レビュー|品質|review|quality|code"
}
run_test "Model 割り当て [edge: sonnet用途が明記]" test_model_assignment_sonnet_purpose

# Edge case: opus の用途（controller/workflow）が明記
test_model_assignment_opus_purpose() {
  local file="architecture/contracts/specialist-output-schema.md"
  assert_file_exists "$file" "specialist-output-schema.md exists" || return 1
  grep -iP "opus" "${PROJECT_ROOT}/${file}" | grep -qiP "controller|workflow"
}
run_test "Model 割り当て [edge: opus用途が明記]" test_model_assignment_opus_purpose

# =============================================================================
# Requirement: Bare repo 構造検証ルール
# =============================================================================
echo ""
echo "--- Requirement: Bare repo 構造検証ルール ---"

# Scenario: 検証条件が3件定義 (line 67)
# WHEN: project-mgmt.md の bare repo 検証セクションを確認する
# THEN: .bare/ 存在、main/.git がファイル、CWD が main/ 配下の 3 条件が記載されている
test_bare_repo_three_conditions() {
  local file="architecture/domain/contexts/project-mgmt.md"
  assert_file_exists "$file" "project-mgmt.md exists" || return 1
  assert_file_contains_all "$file" \
    '\.bare' \
    'main/\.git' \
    'CWD|cwd|カレントディレクトリ|main.*配下'
}
run_test "検証条件が3件定義" test_bare_repo_three_conditions

# Edge case: 各条件に失敗時の対処が記載
test_bare_repo_failure_handling() {
  local file="architecture/domain/contexts/project-mgmt.md"
  assert_file_exists "$file" "project-mgmt.md exists" || return 1
  # The verification table should have a failure handling column
  assert_file_contains "$file" "失敗|対処|エラー|failure"
}
run_test "検証条件 [edge: 失敗時対処が記載]" test_bare_repo_failure_handling

# Edge case: 検証条件が番号付きで3件ある
test_bare_repo_numbered_conditions() {
  local file="architecture/domain/contexts/project-mgmt.md"
  assert_file_exists "$file" "project-mgmt.md exists" || return 1
  # Check for numbered conditions (1, 2, 3 in a table or list)
  local count
  count=$(grep -cP "^\|\s*[123]\s*\||^[123][\.\)]\s" "${PROJECT_ROOT}/${file}" || echo "0")
  [[ $count -ge 3 ]]
}
run_test "検証条件 [edge: 番号付き3件]" test_bare_repo_numbered_conditions

# Scenario: 正規ディレクトリ構造が記載 (line 71)
# WHEN: project-mgmt.md を確認する
# THEN: project-name/.bare/, project-name/main/, project-name/worktrees/ の構造が図示されている
test_bare_repo_directory_structure() {
  local file="architecture/domain/contexts/project-mgmt.md"
  assert_file_exists "$file" "project-mgmt.md exists" || return 1
  assert_file_contains_all "$file" \
    '\.bare/' \
    'main/' \
    'worktrees/'
}
run_test "正規ディレクトリ構造が記載" test_bare_repo_directory_structure

# Edge case: ディレクトリ構造がコードブロックまたはツリー形式で図示
test_bare_repo_structure_as_tree() {
  local file="architecture/domain/contexts/project-mgmt.md"
  assert_file_exists "$file" "project-mgmt.md exists" || return 1
  # Check for code block containing directory tree
  assert_file_contains "$file" '```'  # At least one code block
}
run_test "正規ディレクトリ構造 [edge: ツリー形式で図示]" test_bare_repo_structure_as_tree

# =============================================================================
# Requirement: Worktree ライフサイクル安全ルール
# =============================================================================
echo ""
echo "--- Requirement: Worktree ライフサイクル安全ルール ---"

# Scenario: Pilot/Worker の役割が明確 (line 81)
# WHEN: autopilot.md の worktree ライフサイクルセクションを確認する
# THEN: Worker は worktree 作成のみ、Pilot が merge 成功後に削除する旨が記載
test_worktree_lifecycle_roles() {
  local file="architecture/domain/contexts/autopilot.md"
  assert_file_exists "$file" "autopilot.md exists" || return 1
  assert_file_contains "$file" "Worker.*worktree.*作成|Worker.*作成.*worktree" || return 1
  assert_file_contains "$file" "Pilot.*削除|削除.*Pilot"
}
run_test "Pilot/Worker の役割が明確" test_worktree_lifecycle_roles

# Edge case: Worker が削除しないことが明示的に禁止されている
test_worktree_worker_no_delete() {
  local file="architecture/domain/contexts/autopilot.md"
  assert_file_exists "$file" "autopilot.md exists" || return 1
  assert_file_contains "$file" "Worker.*削除.*しない|Worker.*削除.*禁止|worktree.*削除.*しない"
}
run_test "Pilot/Worker 役割 [edge: Worker削除禁止が明示]" test_worktree_worker_no_delete

# Scenario: 不変条件 B との整合性 (line 85)
# WHEN: worktree ライフサイクルルールを確認する
# THEN: 不変条件 B（Worktree 削除 pilot 専任）と矛盾しない
test_worktree_invariant_b_consistency() {
  local file="architecture/domain/contexts/autopilot.md"
  assert_file_exists "$file" "autopilot.md exists" || return 1
  # Invariant B should be referenced or its content consistent
  assert_file_contains "$file" "不変条件.*B|B.*Worktree.*削除.*pilot|Worktree 削除 pilot 専任" || return 1
  # Should not contain contradicting statements
  if grep -qiP "Worker.*が.*worktree.*を.*削除する" "${PROJECT_ROOT}/${file}"; then
    return 1  # Contradiction found
  fi
  return 0
}
run_test "不変条件 B との整合性" test_worktree_invariant_b_consistency

# Edge case: 不変条件 B が ID で参照されている
test_worktree_invariant_b_referenced() {
  local file="architecture/domain/contexts/autopilot.md"
  assert_file_exists "$file" "autopilot.md exists" || return 1
  assert_file_contains "$file" "不変条件.*B|Invariant.*B|\*\*B\*\*"
}
run_test "不変条件 B との整合性 [edge: 不変条件BがID参照]" test_worktree_invariant_b_referenced

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
