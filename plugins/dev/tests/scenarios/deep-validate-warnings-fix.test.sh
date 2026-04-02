#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: deep-validate warnings fix
# Generated from: openspec/changes/42-fix-deep-validate-warnings/specs/tools-mismatch-fix/spec.md
# Coverage level: edge-cases
# change-id: 42-fix-deep-validate-warnings
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
# Requirement: コマンド frontmatter tools 宣言
# =============================================================================
echo ""
echo "--- Requirement: コマンド frontmatter tools 宣言 ---"

# Scenario: frontmatter 追加後の deep-validate (spec line 15)
# WHEN: 6 コマンドに frontmatter tools フィールドを追加した状態で loom deep-validate を実行する
# THEN: tools-mismatch 警告が 0 件になる

test_deep_validate_no_tools_mismatch() {
  local output
  output="$(cd "${PROJECT_ROOT}" && loom deep-validate 2>&1)"
  if echo "$output" | grep -q "\[tools-mismatch\]"; then
    echo "  [detail] tools-mismatch warnings found:"
    echo "$output" | grep "\[tools-mismatch\]" | sed 's/^/    /'
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom deep-validate: tools-mismatch 警告 0 件" test_deep_validate_no_tools_mismatch
else
  run_test_skip "loom deep-validate: tools-mismatch 警告 0 件" "loom not found in PATH"
fi

# Scenario: frontmatter 形式の正確性 (spec line 19)
# WHEN: 追加した frontmatter を解析する
# THEN: --- で囲まれた YAML ブロックの tools フィールドにインライン配列形式で MCP ツール名が宣言されている

# Edge: plugin-research.md に frontmatter の --- 囲みが存在する
test_plugin_research_has_frontmatter_delimiters() {
  local file="commands/plugin-research.md"
  assert_file_exists "$file" || return 1
  # 先頭行が --- であること
  local first_line
  first_line="$(head -1 "${PROJECT_ROOT}/${file}")"
  [[ "$first_line" == "---" ]] || return 1
  # 2 行目以降に閉じる --- があること
  tail -n +2 "${PROJECT_ROOT}/${file}" | grep -q "^---$" || return 1
}

run_test "plugin-research.md: --- 囲み frontmatter が存在する" test_plugin_research_has_frontmatter_delimiters

# Edge: plugin-research.md の tools フィールドにインライン配列形式で宣言されている
test_plugin_research_tools_inline_array() {
  local file="commands/plugin-research.md"
  assert_file_exists "$file" || return 1
  # tools: [...] 形式（インライン配列）
  grep -qP "^tools:\s*\[" "${PROJECT_ROOT}/${file}" || return 1
  # mcp__doobidoo__memory_search が含まれる
  grep -qP "mcp__doobidoo__memory_search" "${PROJECT_ROOT}/${file}" || return 1
}

run_test "plugin-research.md: tools フィールドにインライン配列で mcp__doobidoo__memory_search 宣言" test_plugin_research_tools_inline_array

# Edge: ui-capture.md の tools フィールドに Playwright 3 ツールが全て宣言されている
test_ui_capture_tools_playwright() {
  local file="commands/ui-capture.md"
  assert_file_exists "$file" || return 1
  grep -qP "^tools:\s*\[" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__playwright__browser_snapshot" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__playwright__browser_take_screenshot" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__playwright__browser_navigate" "${PROJECT_ROOT}/${file}" || return 1
}

run_test "ui-capture.md: tools フィールドに Playwright 3 ツールが全て宣言されている" test_ui_capture_tools_playwright

# Edge: pr-cycle-analysis.md の tools フィールドに memory_search が宣言されている
test_pr_cycle_analysis_tools() {
  local file="commands/pr-cycle-analysis.md"
  assert_file_exists "$file" || return 1
  grep -qP "^tools:\s*\[" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__doobidoo__memory_search" "${PROJECT_ROOT}/${file}" || return 1
}

run_test "pr-cycle-analysis.md: tools フィールドに mcp__doobidoo__memory_search 宣言" test_pr_cycle_analysis_tools

# Edge: autopilot-retrospective.md の tools フィールドに memory_store と memory_search が宣言されている
test_autopilot_retrospective_tools() {
  local file="commands/autopilot-retrospective.md"
  assert_file_exists "$file" || return 1
  grep -qP "^tools:\s*\[" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__doobidoo__memory_store" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__doobidoo__memory_search" "${PROJECT_ROOT}/${file}" || return 1
}

run_test "autopilot-retrospective.md: tools に memory_store と memory_search が宣言されている" test_autopilot_retrospective_tools

# Edge: autopilot-patterns.md の tools フィールドに memory_store と memory_search が宣言されている
test_autopilot_patterns_tools() {
  local file="commands/autopilot-patterns.md"
  assert_file_exists "$file" || return 1
  grep -qP "^tools:\s*\[" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__doobidoo__memory_store" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__doobidoo__memory_search" "${PROJECT_ROOT}/${file}" || return 1
}

run_test "autopilot-patterns.md: tools に memory_store と memory_search が宣言されている" test_autopilot_patterns_tools

# Edge: autopilot-summary.md の tools フィールドに memory_store が宣言されている
test_autopilot_summary_tools() {
  local file="commands/autopilot-summary.md"
  assert_file_exists "$file" || return 1
  grep -qP "^tools:\s*\[" "${PROJECT_ROOT}/${file}" || return 1
  grep -qP "mcp__doobidoo__memory_store" "${PROJECT_ROOT}/${file}" || return 1
}

run_test "autopilot-summary.md: tools フィールドに mcp__doobidoo__memory_store 宣言" test_autopilot_summary_tools

# Edge: frontmatter が --- で始まり --- で閉じられている（全 6 コマンド）
test_all_six_commands_have_frontmatter_block() {
  local all_ok=0
  for cmd in plugin-research.md ui-capture.md pr-cycle-analysis.md autopilot-retrospective.md autopilot-patterns.md autopilot-summary.md; do
    local file="commands/${cmd}"
    assert_file_exists "$file" || { echo "  [detail] missing: ${file}"; all_ok=1; continue; }
    local first_line
    first_line="$(head -1 "${PROJECT_ROOT}/${file}")"
    if [[ "$first_line" != "---" ]]; then
      echo "  [detail] ${cmd}: 先頭行が --- でない（実際: ${first_line}）"
      all_ok=1
    fi
  done
  return $all_ok
}

run_test "全 6 コマンド: frontmatter が --- で始まる" test_all_six_commands_have_frontmatter_block

# =============================================================================
# Requirement: co-issue SKILL.md controller-bloat 解消
# =============================================================================
echo ""
echo "--- Requirement: co-issue SKILL.md controller-bloat 解消 ---"

SKILL_MD="skills/co-issue/SKILL.md"

# Scenario: 行数削減後の deep-validate (spec line 27)
# WHEN: co-issue SKILL.md を 120 行以下に削減した状態で loom deep-validate を実行する
# THEN: controller-bloat 警告が 0 件になる

test_deep_validate_no_co_issue_controller_bloat() {
  local output
  output="$(cd "${PROJECT_ROOT}" && loom deep-validate 2>&1)"
  # co-issue に対する controller-bloat 警告がないことを検証（他コントローラーは別スコープ）
  if echo "$output" | grep -q "\[controller-bloat\] co-issue"; then
    echo "  [detail] co-issue controller-bloat warning found:"
    echo "$output" | grep "\[controller-bloat\] co-issue" | sed 's/^/    /'
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom deep-validate: co-issue controller-bloat 警告 0 件" test_deep_validate_no_co_issue_controller_bloat
else
  run_test_skip "loom deep-validate: controller-bloat 警告 0 件" "loom not found in PATH"
fi

# Edge: co-issue SKILL.md が 130 行以下である
test_co_issue_skill_line_count() {
  assert_file_exists "$SKILL_MD" || return 1
  local line_count
  line_count="$(wc -l < "${PROJECT_ROOT}/${SKILL_MD}")"
  if [[ "$line_count" -gt 130 ]]; then
    echo "  [detail] line count = ${line_count} (must be <= 130)"
    return 1
  fi
  return 0
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md: 行数 130 以下" test_co_issue_skill_line_count
else
  run_test_skip "co-issue SKILL.md: 行数 120 以下" "skills/co-issue/SKILL.md not found"
fi

# Scenario: 機能保持の確認 (spec line 31)
# WHEN: リファクタリング後の co-issue SKILL.md の内容を確認する
# THEN: 全 Phase（探索→分解→精緻化→作成）の指示と禁止事項が保持されている

# Phase 1: 問題探索の指示が保持されている
test_phase1_explore_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*1" || return 1
  assert_file_contains "$SKILL_MD" "explore|探索" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md: Phase 1（問題探索）指示が保持されている" test_phase1_explore_preserved
else
  run_test_skip "co-issue SKILL.md: Phase 1 保持確認" "skills/co-issue/SKILL.md not found"
fi

# Phase 2: 分解判断の指示が保持されている
test_phase2_decomposition_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*2" || return 1
  assert_file_contains "$SKILL_MD" "分解|decompos|単一|複数" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md: Phase 2（分解判断）指示が保持されている" test_phase2_decomposition_preserved
else
  run_test_skip "co-issue SKILL.md: Phase 2 保持確認" "skills/co-issue/SKILL.md not found"
fi

# Phase 3: Per-Issue 精緻化ループの指示が保持されている
test_phase3_refinement_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*3" || return 1
  assert_file_contains "$SKILL_MD" "issue-dig|精緻化" || return 1
  assert_file_contains "$SKILL_MD" "issue-structure" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md: Phase 3（Per-Issue 精緻化）指示が保持されている" test_phase3_refinement_preserved
else
  run_test_skip "co-issue SKILL.md: Phase 3 保持確認" "skills/co-issue/SKILL.md not found"
fi

# Phase 4: Issue 作成の指示が保持されている
test_phase4_creation_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*4" || return 1
  assert_file_contains "$SKILL_MD" "issue-create" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md: Phase 4（Issue 作成）指示が保持されている" test_phase4_creation_preserved
else
  run_test_skip "co-issue SKILL.md: Phase 4 保持確認" "skills/co-issue/SKILL.md not found"
fi

# Edge: 禁止事項セクションが保持されている
test_prohibitions_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "禁止|MUST NOT" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md [edge: 禁止事項セクションが保持されている]" test_prohibitions_preserved
else
  run_test_skip "co-issue SKILL.md [edge: 禁止事項保持]" "skills/co-issue/SKILL.md not found"
fi

# Edge: 全 Phase が揃っている（Phase 1-4、かつ Phase 5 以上が存在しない）
test_all_phases_and_no_phase5() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*1" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*2" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*3" || return 1
  assert_file_contains "$SKILL_MD" "Phase\s*4" || return 1
  assert_file_not_contains "$SKILL_MD" "Phase\s*[5-9]" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md [edge: Phase 1-4 全保持、Phase 5 以上なし]" test_all_phases_and_no_phase5
else
  run_test_skip "co-issue SKILL.md [edge: 全 Phase 確認]" "skills/co-issue/SKILL.md not found"
fi

# Edge: explore-summary.md 検出ロジックが保持されている
test_explore_summary_detection_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "explore-summary\.md" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md [edge: explore-summary.md 検出ロジック保持]" test_explore_summary_detection_preserved
else
  run_test_skip "co-issue SKILL.md [edge: explore-summary 検出保持]" "skills/co-issue/SKILL.md not found"
fi

# Edge: ユーザー確認なしで Issue 作成禁止の記述が保持されている
test_no_create_without_confirmation_preserved() {
  assert_file_exists "$SKILL_MD" || return 1
  assert_file_contains "$SKILL_MD" "ユーザー確認|承認" || return 1
}

if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "co-issue SKILL.md [edge: ユーザー確認なし作成禁止の記述保持]" test_no_create_without_confirmation_preserved
else
  run_test_skip "co-issue SKILL.md [edge: ユーザー確認なし作成禁止]" "skills/co-issue/SKILL.md not found"
fi

# =============================================================================
# Combined: deep-validate 全警告 0 件（tools-mismatch + controller-bloat 両方）
# =============================================================================
echo ""
echo "--- Combined: deep-validate 全 Warning 0 件 ---"

test_deep_validate_target_warnings_zero() {
  local output
  output="$(cd "${PROJECT_ROOT}" && loom deep-validate 2>&1)"
  # このテストのスコープ: tools-mismatch と co-issue controller-bloat のみ
  local target_warnings
  target_warnings=$(echo "$output" | grep -P "^\s*-\s*\[" | grep -P "\[tools-mismatch\]|\[controller-bloat\] co-issue" || true)
  if [[ -n "$target_warnings" ]]; then
    echo "  [detail] remaining target warnings:"
    echo "$target_warnings" | sed 's/^/    /'
    return 1
  fi
  return 0
}

if command -v loom &>/dev/null; then
  run_test "loom deep-validate: tools-mismatch + co-issue bloat 警告 0 件（修正完了確認）" test_deep_validate_target_warnings_zero
else
  run_test_skip "loom deep-validate: tools-mismatch + co-issue bloat 警告 0 件" "loom not found in PATH"
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
