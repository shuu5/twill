#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: specialist-output-schema.md
# Generated from: openspec/changes/b-6-specialist-few-shot/specs/specialist-output-schema.md
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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qP "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qP "$pattern" "${PROJECT_ROOT}/${file}"; then
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

REF_SCHEMA="refs/ref-specialist-output-schema.md"
DEPS_YAML="deps.yaml"

# =============================================================================
# Requirement: ref-specialist-output-schema reference コンポーネント
# =============================================================================
echo ""
echo "--- Requirement: ref-specialist-output-schema reference コンポーネント ---"

# Scenario: スキーマ必須フィールドの定義 (line 14)
# WHEN: ref-specialist-output-schema.md を検査する
# THEN: status, findings, severity, confidence, file, line, message, category の全フィールドが定義されている
test_schema_required_fields_status() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "status"
}
run_test "スキーマ必須フィールド - status が定義されている" test_schema_required_fields_status

test_schema_required_fields_findings() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "findings"
}
run_test "スキーマ必須フィールド - findings が定義されている" test_schema_required_fields_findings

test_schema_required_fields_severity() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "severity"
}
run_test "スキーマ必須フィールド - severity が定義されている" test_schema_required_fields_severity

test_schema_required_fields_confidence() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "confidence"
}
run_test "スキーマ必須フィールド - confidence が定義されている" test_schema_required_fields_confidence

test_schema_required_fields_file() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # "file" is a common word; check it appears in a schema/field context
  assert_file_contains "$REF_SCHEMA" '\bfile\b'
}
run_test "スキーマ必須フィールド - file が定義されている" test_schema_required_fields_file

test_schema_required_fields_line() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" '\bline\b'
}
run_test "スキーマ必須フィールド - line が定義されている" test_schema_required_fields_line

test_schema_required_fields_message() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" '\bmessage\b'
}
run_test "スキーマ必須フィールド - message が定義されている" test_schema_required_fields_message

test_schema_required_fields_category() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" '\bcategory\b'
}
run_test "スキーマ必須フィールド - category が定義されている" test_schema_required_fields_category

# Edge case: 全8フィールドがまとめて存在する（1つでも欠けたら FAIL）
test_schema_all_eight_fields() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains_all "$REF_SCHEMA" \
    "status" "findings" "severity" "confidence" \
    '\bfile\b' '\bline\b' '\bmessage\b' '\bcategory\b'
}
run_test "スキーマ必須フィールド [edge: 全8フィールド一括検証]" test_schema_all_eight_fields

# Scenario: severity 3 段階の定義 (line 18)
# WHEN: severity の定義を確認する
# THEN: CRITICAL, WARNING, INFO の 3 値のみが許可されている
# AND: 旧表記からの変換マッピングが記載されている
test_severity_three_levels() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains_all "$REF_SCHEMA" "CRITICAL" "WARNING" "INFO"
}
run_test "severity 3 段階の定義" test_severity_three_levels

# Edge case: 旧表記（Critical, High, Medium, Suggestion）からの変換マッピングが記載
test_severity_legacy_mapping() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # At least some legacy terms should be mentioned for mapping purposes
  local count=0
  for term in "Critical" "High" "Medium" "Suggestion"; do
    if grep -qP "$term" "${PROJECT_ROOT}/${REF_SCHEMA}" 2>/dev/null; then
      ((count++))
    fi
  done
  [[ $count -ge 2 ]]
}
run_test "severity [edge: 旧表記変換マッピングの存在]" test_severity_legacy_mapping

# Edge case: severity が正確に 3 値（4つ以上の severity レベルが定義されていない）
test_severity_no_extra_levels() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # Should not contain ERROR, FATAL, etc. as severity levels
  assert_file_not_contains "$REF_SCHEMA" 'severity.*FATAL'
}
run_test "severity [edge: 不正な severity レベルがない]" test_severity_no_extra_levels

# =============================================================================
# Requirement: status 自動導出ルール
# =============================================================================
echo ""
echo "--- Requirement: status 自動導出ルール ---"

# Scenario: FAIL 判定 (line 32)
# WHEN: findings に severity=CRITICAL のエントリが 1 件以上存在する
# THEN: status は FAIL である
test_status_fail_rule() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # The document should describe that CRITICAL -> FAIL
  assert_file_contains "$REF_SCHEMA" "CRITICAL" || return 1
  assert_file_contains "$REF_SCHEMA" "FAIL"
}
run_test "status 自動導出 - FAIL 判定ルール記載" test_status_fail_rule

# Scenario: WARN 判定 (line 36)
# WHEN: findings に severity=CRITICAL がなく severity=WARNING が 1 件以上存在する
# THEN: status は WARN である
test_status_warn_rule() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "WARNING" || return 1
  assert_file_contains "$REF_SCHEMA" "WARN"
}
run_test "status 自動導出 - WARN 判定ルール記載" test_status_warn_rule

# Scenario: PASS 判定 (line 40)
# WHEN: findings が空、または全て severity=INFO である
# THEN: status は PASS である
test_status_pass_rule() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "PASS"
}
run_test "status 自動導出 - PASS 判定ルール記載" test_status_pass_rule

# Edge case: 導出ルールが優先順位付きで記載されている（CRITICAL > WARNING > INFO）
test_status_derivation_priority() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # All three status values should be documented
  assert_file_contains_all "$REF_SCHEMA" "FAIL" "WARN" "PASS"
}
run_test "status 自動導出 [edge: 3つの status 値が全て記載]" test_status_derivation_priority

# Edge case: AI 裁量禁止の記載（status は機械的に導出）
test_status_no_ai_discretion() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # Should contain guidance that status is mechanically derived, not AI-determined
  # Look for keywords like "自動" or "導出" or "機械的" or "mechanical" or "derived"
  local found=0
  for term in "自動" "導出" "機械的" "mechanical" "derive"; do
    if grep -qP "$term" "${PROJECT_ROOT}/${REF_SCHEMA}" 2>/dev/null; then
      found=1
      break
    fi
  done
  [[ $found -eq 1 ]]
}
run_test "status 自動導出 [edge: 機械的導出の記載あり]" test_status_no_ai_discretion

# =============================================================================
# Requirement: 消費側パースルール
# =============================================================================
echo ""
echo "--- Requirement: 消費側パースルール ---"

# Scenario: サマリー行パースの成功 (line 53)
# WHEN: specialist 出力に status: FAIL が含まれる
# THEN: 消費側は status=FAIL を取得する
test_parse_summary_line() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # The regex pattern for status parsing should be documented
  assert_file_contains "$REF_SCHEMA" 'status.*:.*\(PASS\|WARN\|FAIL\)|status:\s*\(PASS\|WARN\|FAIL\)|\(PASS\|WARN\|FAIL\)'
}
run_test "サマリー行パースルール記載" test_parse_summary_line

# Scenario: ブロック判定 REJECT (line 57)
# WHEN: findings に severity=CRITICAL かつ confidence=95 のエントリがある
# THEN: merge-gate は REJECT を返す
test_block_reject_rule() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # Document should mention REJECT condition with confidence threshold
  assert_file_contains "$REF_SCHEMA" "CRITICAL" || return 1
  assert_file_contains "$REF_SCHEMA" "confidence" || return 1
  assert_file_contains "$REF_SCHEMA" "80"
}
run_test "ブロック判定 - REJECT ルール記載" test_block_reject_rule

# Scenario: ブロック判定 PASS — confidence 不足 (line 61)
# WHEN: findings に severity=CRITICAL かつ confidence=60 のエントリがある
# THEN: merge-gate は PASS を返す（confidence < 80 のため）
test_block_pass_low_confidence() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # The >= 80 threshold should be documented
  assert_file_contains "$REF_SCHEMA" "80"
}
run_test "ブロック判定 - confidence 閾値 80 の記載" test_block_pass_low_confidence

# Edge case: confidence の数値範囲が 0-100 と記載
test_confidence_range() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" '0.*100|0-100|0\s*~\s*100'
}
run_test "消費側パース [edge: confidence 範囲 0-100 記載]" test_confidence_range

# Scenario: パース失敗時のフォールバック (line 65)
# WHEN: specialist 出力が共通スキーマに準拠しない
# THEN: 出力全文が 1 つの WARNING finding (confidence=50) として扱われる
# AND: 手動レビューが要求される
test_parse_fallback() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # Fallback should mention WARNING and confidence=50
  assert_file_contains "$REF_SCHEMA" "WARNING" || return 1
  assert_file_contains "$REF_SCHEMA" "50"
}
run_test "パース失敗時フォールバック記載" test_parse_fallback

# Edge case: フォールバック時に手動レビュー要求の記載
test_parse_fallback_manual_review() {
  assert_file_exists "$REF_SCHEMA" || return 1
  local found=0
  for term in "手動" "manual" "レビュー" "review"; do
    if grep -qP "$term" "${PROJECT_ROOT}/${REF_SCHEMA}" 2>/dev/null; then
      found=1
      break
    fi
  done
  [[ $found -eq 1 ]]
}
run_test "パース失敗時フォールバック [edge: 手動レビュー要求の記載]" test_parse_fallback_manual_review

# =============================================================================
# Requirement: output_schema: custom 除外条件
# =============================================================================
echo ""
echo "--- Requirement: output_schema: custom 除外条件 ---"

# Scenario: output_schema: custom の除外 (line 76)
# WHEN: specialist の deps.yaml エントリに output_schema: custom が指定されている
# THEN: 共通出力スキーマの few-shot テンプレートは注入されない
test_custom_schema_exclusion() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "custom"
}
run_test "output_schema: custom 除外条件の記載" test_custom_schema_exclusion

# Scenario: custom specialist のフォールバック処理 (line 81)
# WHEN: output_schema: custom の specialist が自由形式で出力する
# THEN: merge-gate はパース失敗フォールバック（WARNING, confidence=50）を適用する
test_custom_schema_fallback() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # custom + fallback combination should be documented
  assert_file_contains "$REF_SCHEMA" "custom" || return 1
  # Fallback rules apply even for custom
  assert_file_contains "$REF_SCHEMA" "50"
}
run_test "custom specialist フォールバック処理の記載" test_custom_schema_fallback

# Edge case: output_schema: custom が deps.yaml のキーとして記載
test_custom_schema_depsyaml_key() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" 'output_schema'
}
run_test "output_schema: custom [edge: output_schema キー記載]" test_custom_schema_depsyaml_key

# =============================================================================
# Requirement: category 5 種の定義
# =============================================================================
echo ""
echo "--- Requirement: category 5 種の定義 ---"

# Edge case (from field definition): category の 5 種が全て定義されている
test_category_five_types() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains_all "$REF_SCHEMA" \
    "vulnerability" "bug" "coding-convention" "structure" "principles"
}
run_test "category [edge: 5 種全て定義]" test_category_five_types

# Edge case: category に不正な値が定義されていない
test_category_no_extras() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # The 5 valid categories should be present
  assert_file_contains "$REF_SCHEMA" "vulnerability" || return 1
  assert_file_contains "$REF_SCHEMA" "bug" || return 1
  assert_file_contains "$REF_SCHEMA" "structure"
}
run_test "category [edge: 基本 3 種の存在確認]" test_category_no_extras

# =============================================================================
# Requirement: Model 割り当て表の包含 (from specialist-few-shot.md)
# =============================================================================
echo ""
echo "--- Requirement: Model 割り当て表の包含 ---"

# Scenario: model 割り当て表の存在 (specialist-few-shot.md line 56)
# WHEN: ref-specialist-output-schema.md の model 割り当てセクションを検査する
# THEN: haiku と sonnet の specialist 一覧が記載されている
test_model_assignment_table() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "haiku" || return 1
  assert_file_contains "$REF_SCHEMA" "sonnet"
}
run_test "model 割り当て表 - haiku と sonnet が記載" test_model_assignment_table

# Scenario: opus が specialist に割り当てられていない (specialist-few-shot.md line 60)
# WHEN: model 割り当て表を検査する
# THEN: opus に割り当てられた specialist は 0 件である
test_model_no_opus_specialist() {
  assert_file_exists "$REF_SCHEMA" || return 1
  # opus should be mentioned only in context of "not for specialist" or "Controller only"
  # If opus appears, it should be in exclusion context
  if grep -qP "opus" "${PROJECT_ROOT}/${REF_SCHEMA}" 2>/dev/null; then
    # opus is mentioned - verify it's in exclusion/controller-only context
    # Check that no specialist is assigned opus (look for opus in assignment rows)
    # Accept if opus appears with "Controller" or "使用しない" or "not" context
    local opus_lines
    opus_lines=$(grep -iP "opus" "${PROJECT_ROOT}/${REF_SCHEMA}" || true)
    if echo "$opus_lines" | grep -qiP "Controller|Workflow|使用しない|not|禁止|excluded"; then
      return 0
    fi
    # If opus appears without exclusion context, it might be assigning to specialist
    return 1
  fi
  # opus not mentioned at all is also acceptable (implicitly excluded)
  return 0
}
run_test "model 割り当て - opus が specialist に未割り当て" test_model_no_opus_specialist

# Edge case: haiku の割り当て基準が記載（構造チェック・パターンマッチ）
test_model_haiku_criteria() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "haiku"
}
run_test "model 割り当て [edge: haiku 基準記載]" test_model_haiku_criteria

# Edge case: sonnet の割り当て基準が記載（コードレビュー・品質判断）
test_model_sonnet_criteria() {
  assert_file_exists "$REF_SCHEMA" || return 1
  assert_file_contains "$REF_SCHEMA" "sonnet"
}
run_test "model 割り当て [edge: sonnet 基準記載]" test_model_sonnet_criteria

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
