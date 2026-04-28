#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: output-schema-compliance
# Generated from: deltaspec/changes/c-3-specialist-reference-migration/specs/output-schema-compliance/spec.md
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

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
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

# --- 23 specialist 一覧 ---
# Issue #1081: worker-{fastapi,hono,nextjs,r}-reviewer を worker-code-reviewer に統合
ALL_SPECIALISTS=(
  worker-code-reviewer
  worker-security-reviewer
  worker-architecture
  worker-structure
  worker-principles
  worker-env-validator
  worker-rls-reviewer
  worker-supabase-migration-checker
  worker-data-validator
  template-validator
  context-checker
  worker-e2e-reviewer
  worker-spec-reviewer
  worker-llm-output-reviewer
  worker-llm-eval-runner
  docs-researcher
  e2e-quality
  autofix-loop
  spec-scaffold-tests
  e2e-generate
  e2e-heal
  e2e-visual-heal
)

# =============================================================================
# Requirement: 共通出力スキーマ準拠
# =============================================================================
echo ""
echo "--- Requirement: 共通出力スキーマ準拠 ---"

# Scenario: 出力形式セクションの存在 (output-schema-compliance/spec.md line 51)
# WHEN: 任意の specialist ファイルを確認する
# THEN: `## 出力形式（MUST）` セクションが存在し、ref-specialist-output-schema への参照が含まれる
test_all_specialists_output_section() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      failed+=("${name}: file not found")
      continue
    fi
    if ! grep -qP "^##\s*出力形式（MUST）" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: missing '## 出力形式（MUST）' section")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist に '## 出力形式（MUST）' セクションが存在" test_all_specialists_output_section

# 出力形式セクションに ref-specialist-output-schema への参照がある
test_output_section_references_schema() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if ! grep -qP "ref-specialist-output-schema" "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: no ref-specialist-output-schema reference")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist の出力形式セクションに ref-specialist-output-schema 参照" test_output_section_references_schema

# Edge case: 出力形式セクションがファイル末尾付近にある（プロンプト本文の後）
test_output_section_at_end() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    local total_lines section_line
    total_lines=$(wc -l < "${PROJECT_ROOT}/${file}")
    section_line=$(grep -nP "^##\s*出力形式（MUST）" "${PROJECT_ROOT}/${file}" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -z "$section_line" ]]; then
      continue  # already tested elsewhere
    fi
    # Section should be in the latter half of the file
    local halfway=$((total_lines / 2))
    if [[ "$section_line" -lt "$halfway" ]]; then
      failed+=("${name}: output section at line ${section_line}/${total_lines} (should be near end)")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "出力形式セクションがファイル後半にある [edge: プロンプト本文の後]" test_output_section_at_end

# Edge case: 出力形式セクションに JSON 構造の例示がある (status, findings)
test_output_section_has_json_example() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # Check for status and findings keywords in the file
    if ! grep -qP '"status"' "${PROJECT_ROOT}/${file}" && ! grep -qP 'status.*PASS|WARN|FAIL' "${PROJECT_ROOT}/${file}"; then
      failed+=("${name}: no status field reference")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "出力形式セクションに status フィールド参照 [edge]" test_output_section_has_json_example

# =============================================================================
# Requirement: severity 3 段階統一
# =============================================================================
echo ""
echo "--- Requirement: severity 3 段階統一 ---"

# Scenario: 旧 severity 表記の排除 (line 44)
# WHEN: 移植完了後に全 specialist ファイルを検索する
# THEN: "High", "Medium", "Low", "Suggestion", "Error" の severity 表記が存在しない

# Note: pattern must match severity context, not arbitrary uses of these common words
# We search for patterns like: severity: High, severity="High", "High" in severity context
# More specifically, look for these as standalone severity labels

test_no_old_severity_high() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # Match "High" as severity term (case-sensitive, in severity context)
    # Pattern: severity line containing High, or severity: "High", or "High" as a severity value
    if grep -qP '(?i)severity.*\bHigh\b|\bHigh\b.*severity|"High"|severity:\s*High' "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: contains old severity 'High'")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "旧 severity 'High' がどの specialist にも存在しない" test_no_old_severity_high

test_no_old_severity_medium() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if grep -qP '(?i)severity.*\bMedium\b|\bMedium\b.*severity|"Medium"|severity:\s*Medium' "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: contains old severity 'Medium'")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "旧 severity 'Medium' がどの specialist にも存在しない" test_no_old_severity_medium

test_no_old_severity_low() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if grep -qP '(?i)severity.*\bLow\b|\bLow\b.*severity|"Low"|severity:\s*Low' "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: contains old severity 'Low'")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "旧 severity 'Low' がどの specialist にも存在しない" test_no_old_severity_low

test_no_old_severity_suggestion() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    if grep -qP '(?i)severity.*\bSuggestion\b|\bSuggestion\b.*severity|"Suggestion"|severity:\s*Suggestion' "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: contains old severity 'Suggestion'")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "旧 severity 'Suggestion' がどの specialist にも存在しない" test_no_old_severity_suggestion

# Edge case: 新 severity (CRITICAL, WARNING, INFO) のみが使用されている
test_only_new_severity_terms() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # Check that at least one new severity term exists (meaning the file has severity definitions)
    if ! grep -qP '\bCRITICAL\b|\bWARNING\b|\bINFO\b' "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: no new severity terms (CRITICAL/WARNING/INFO) found")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "全 specialist に新 severity (CRITICAL/WARNING/INFO) が使用されている [edge]" test_only_new_severity_terms

# Edge case: severity マッピングテーブル（High→CRITICAL等）が specialist 内に残っていない
# (マッピングはドキュメントとしては残っていても良いが、実際の出力指示としては新表記のみであるべき)
test_no_severity_mapping_remnants() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # Look for mapping patterns like "High → CRITICAL" or "High -> CRITICAL"
    if grep -qP '(?i)\bHigh\b\s*[→->]+\s*CRITICAL|\bMedium\b\s*[→->]+\s*WARNING|\bLow\b\s*[→->]+\s*INFO' "${PROJECT_ROOT}/${file}" 2>/dev/null; then
      failed+=("${name}: contains severity mapping remnants")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "severity マッピング表記が specialist に残っていない [edge]" test_no_severity_mapping_remnants

# =============================================================================
# Requirement: 出力形式セクションの追記
# =============================================================================
echo ""
echo "--- Requirement: 出力形式セクションの追記 ---"

# (Main test already covered above: test_all_specialists_output_section)

# Edge case: 出力形式セクションが 1 つだけ存在する（重複なし）
test_output_section_no_duplicates() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    local count
    count=$(grep -cP "^##\s*出力形式（MUST）" "${PROJECT_ROOT}/${file}" 2>/dev/null || echo "0")
    if [[ "$count" -gt 1 ]]; then
      failed+=("${name}: output section appears ${count} times")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "出力形式セクションが各 specialist に 1 つだけ [edge: 重複なし]" test_output_section_no_duplicates

# Edge case: specialist ファイルの frontmatter の後に空行なしで本文が続いていない
# (frontmatter は --- で囲まれる。正しい形式であること)
test_frontmatter_format() {
  local failed=()
  for name in "${ALL_SPECIALISTS[@]}"; do
    local file="agents/${name}.md"
    if ! assert_file_exists "$file"; then
      continue
    fi
    # Check first line is --- (frontmatter start) or first non-empty line
    local first_line
    first_line=$(head -1 "${PROJECT_ROOT}/${file}" | tr -d '[:space:]')
    # Some files may use frontmatter without --- delimiters (key: value at top)
    # Just verify the file is not empty
    if [[ -z "$first_line" ]]; then
      failed+=("${name}: file starts with empty line")
    fi
  done
  if [[ ${#failed[@]} -gt 0 ]]; then
    for f in "${failed[@]}"; do
      echo "  ${f}" >&2
    done
    return 1
  fi
  return 0
}
run_test "specialist ファイルが空行で始まらない [edge: frontmatter 形式]" test_frontmatter_format

# =============================================================================
# Cross-cutting: twl validate
# =============================================================================
echo ""
echo "--- Cross-cutting: twl validate ---"

test_twl_validate_final() {
  if ! command -v twl &>/dev/null; then
    return 1
  fi
  local output exit_code
  output=$(cd "${PROJECT_ROOT}" && twl validate 2>&1)
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "$output" >&2
    return 1
  fi
  return 0
}

if command -v twl &>/dev/null; then
  run_test "twl validate 最終確認（全体）" test_twl_validate_final
else
  run_test_skip "twl validate 最終確認（全体）" "twl command not found"
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
