#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: specialist-few-shot.md
# Generated from: deltaspec/changes/b-6-specialist-few-shot/specs/specialist-few-shot.md
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

count_pattern_occurrences() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || { echo "0"; return; }
  grep -cP "$pattern" "${PROJECT_ROOT}/${file}" 2>/dev/null || echo "0"
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

REF_FEWSHOT="refs/ref-specialist-few-shot.md"

# =============================================================================
# Requirement: ref-specialist-few-shot reference コンポーネント
# =============================================================================
echo ""
echo "--- Requirement: ref-specialist-few-shot reference コンポーネント ---"

# Scenario: few-shot テンプレートの構造 (line 13)
# WHEN: ref-specialist-few-shot.md を検査する
# THEN: FAIL ケースの出力例が 1 つ存在する
# AND: findings に CRITICAL, WARNING, INFO の 3 レベルが全て含まれている
test_fewshot_fail_case_exists() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains "$REF_FEWSHOT" "FAIL"
}
run_test "few-shot テンプレート - FAIL ケースの存在" test_fewshot_fail_case_exists

test_fewshot_three_severity_levels() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains_all "$REF_FEWSHOT" "CRITICAL" "WARNING" "INFO"
}
run_test "few-shot テンプレート - 3 severity レベル全含有" test_fewshot_three_severity_levels

# Edge case: FAIL ケースの findings 配列が空でない（実際のエントリを含む）
test_fewshot_fail_case_has_findings() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains "$REF_FEWSHOT" "findings" || return 1
  # findings should have actual entries (not just the key)
  assert_file_contains "$REF_FEWSHOT" "severity"
}
run_test "few-shot テンプレート [edge: findings にエントリあり]" test_fewshot_fail_case_has_findings

# Scenario: findings 必須フィールドの網羅 (line 18)
# WHEN: few-shot テンプレートの各 finding を検査する
# THEN: severity, confidence, file, line, message, category の全フィールドが存在する
test_fewshot_finding_required_fields() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains_all "$REF_FEWSHOT" \
    "severity" "confidence" '\bfile\b' '\bline\b' '\bmessage\b' '\bcategory\b'
}
run_test "findings 必須フィールドの網羅" test_fewshot_finding_required_fields

# Edge case: confidence が数値として記載されている（文字列でなく整数）
test_fewshot_confidence_numeric() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  # confidence should be followed by a number (e.g., confidence: 95 or "confidence": 95)
  assert_file_contains "$REF_FEWSHOT" 'confidence.*[0-9]+'
}
run_test "findings [edge: confidence が数値]" test_fewshot_confidence_numeric

# Edge case: file フィールドがファイルパス形式（拡張子を含む）
test_fewshot_file_field_has_path() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  # file field should contain a path-like value (with / or .)
  assert_file_contains "$REF_FEWSHOT" '"file".*:.*"[^"]*[./][^"]*"|\bfile\b.*:.*\S+\.\S+'
}
run_test "findings [edge: file がパス形式]" test_fewshot_file_field_has_path

# Edge case: line フィールドが正の整数
test_fewshot_line_field_numeric() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains "$REF_FEWSHOT" '"line".*:\s*[0-9]+|\bline\b.*:\s*[0-9]+'
}
run_test "findings [edge: line が正の整数]" test_fewshot_line_field_numeric

# =============================================================================
# Requirement: コンテキスト消費の最小化
# =============================================================================
echo ""
echo "--- Requirement: コンテキスト消費の最小化 ---"

# Scenario: テンプレート例数の制限 (line 29)
# WHEN: ref-specialist-few-shot.md の出力例の数を数える
# THEN: 1 例のみである
test_fewshot_single_example() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  # Count code blocks that represent output examples
  # A complete output example would contain "status:" within a code block
  # Count occurrences of "status: FAIL" or "status: PASS" or "status: WARN" as example indicators
  local status_count
  status_count=$(grep -cP '^\s*status:\s*(PASS|WARN|FAIL)' "${PROJECT_ROOT}/${REF_FEWSHOT}" 2>/dev/null || echo "0")
  [[ "$status_count" -eq 1 ]]
}
run_test "テンプレート例数 - 1 例のみ" test_fewshot_single_example

# Edge case: コードブロック内に出力例が含まれている（```で囲まれている）
test_fewshot_example_in_codeblock() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  # Should have code block markers
  assert_file_contains "$REF_FEWSHOT" '```'
}
run_test "テンプレート例数 [edge: コードブロック内に出力例]" test_fewshot_example_in_codeblock

# Edge case: 複数の status 行がないこと（2例以上は禁止）
test_fewshot_no_multiple_examples() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  local count
  count=$(grep -cP '^\s*status:\s*(PASS|WARN|FAIL)' "${PROJECT_ROOT}/${REF_FEWSHOT}" 2>/dev/null || echo "0")
  [[ "$count" -le 1 ]]
}
run_test "テンプレート例数 [edge: 2例以上の status 行なし]" test_fewshot_no_multiple_examples

# =============================================================================
# Requirement: specialist プロンプトへの注入形式
# =============================================================================
echo ""
echo "--- Requirement: specialist プロンプトへの注入形式 ---"

# Scenario: 注入セクションの形式 (line 42)
# WHEN: few-shot テンプレートの注入セクションを検査する
# THEN: ## 出力形式（MUST）ヘッダーが存在する
# AND: コードブロック内に完全な出力例が含まれている
test_injection_section_header() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains "$REF_FEWSHOT" '##\s*出力形式'
}
run_test "注入セクション - ヘッダーの存在" test_injection_section_header

test_injection_section_must() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains "$REF_FEWSHOT" 'MUST'
}
run_test "注入セクション - MUST 強制の記載" test_injection_section_must

test_injection_codeblock_with_example() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  # Code block should exist and contain status/findings
  assert_file_contains "$REF_FEWSHOT" '```' || return 1
  assert_file_contains "$REF_FEWSHOT" "status" || return 1
  assert_file_contains "$REF_FEWSHOT" "findings"
}
run_test "注入セクション - コードブロック内に出力例" test_injection_codeblock_with_example

# Edge case: 形式説明文（「以下の形式で出力すること」等）が存在
test_injection_format_description() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  local found=0
  for term in "以下の形式" "出力すること" "format" "以下のフォーマット"; do
    if grep -qP "$term" "${PROJECT_ROOT}/${REF_FEWSHOT}" 2>/dev/null; then
      found=1
      break
    fi
  done
  [[ $found -eq 1 ]]
}
run_test "注入セクション [edge: 形式説明文の存在]" test_injection_format_description

# Edge case: specialist 名プレースホルダー {specialist-name} が存在
test_fewshot_specialist_placeholder() {
  assert_file_exists "$REF_FEWSHOT" || return 1
  assert_file_contains "$REF_FEWSHOT" '\{specialist-name\}|\{specialist_name\}'
}
run_test "注入セクション [edge: specialist 名プレースホルダー]" test_fewshot_specialist_placeholder

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
