#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: 設計ドキュメントのモード廃止
# Generated from: deltaspec/changes/issue-440/specs/design-docs/spec.md
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

DESIGN_DOC="architecture/designs/su-observer-skill-design.md"
SUPERVISION_MD="architecture/domain/contexts/supervision.md"

# =============================================================================
# Requirement: su-observer-skill-design.md のモードルーティングテーブル廃止
# Scenario: 行動判断ガイドラインへの置換 (spec.md line 7)
# WHEN: su-observer-skill-design.md を参照する LLM が行動を決定する
# THEN: モード番号ではなく、文脈に基づく行動判断ガイドラインから
#       適切なアクションを選択しなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: su-observer-skill-design.md モードルーティングテーブル廃止 ---"

# Test: モードルーティングテーブル（6モード列挙）が存在しない
test_no_mode_routing_table() {
  assert_file_exists "$DESIGN_DOC" || return 1
  # "autopilot | issue | architect | observe | compact | delegate" 形式の表が存在しないか
  assert_file_not_contains "$DESIGN_DOC" \
    "^\|\s*(autopilot|observe|compact|delegate)\s*\|"
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "モードルーティングテーブル（6モード）が存在しない" test_no_mode_routing_table
else
  run_test_skip "モードルーティングテーブルなし" "${DESIGN_DOC} not yet created"
fi

# Test: 行動判断ガイドラインが存在する
test_action_guideline_exists() {
  assert_file_exists "$DESIGN_DOC" || return 1
  assert_file_contains "$DESIGN_DOC" \
    "行動.*判断|判断.*ガイド|ガイドライン|文脈.*判断|context.*based|action.*guide"
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "行動判断ガイドラインが設計ドキュメントに存在する" test_action_guideline_exists
else
  run_test_skip "行動判断ガイドライン存在" "${DESIGN_DOC} not yet created"
fi

# Edge case: モード番号（「モード 1」「mode 1」など）による参照が存在しない
test_no_mode_number_reference() {
  assert_file_exists "$DESIGN_DOC" || return 1
  assert_file_not_contains "$DESIGN_DOC" \
    "モード\s*[1-6]|mode\s*[1-6]|モード番号"
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "[edge] モード番号による参照が存在しない" test_no_mode_number_reference
else
  run_test_skip "[edge] モード番号参照なし" "${DESIGN_DOC} not yet created"
fi

# Edge case: 廃止された 6 モード名（observe, compact, delegate）がモードテーブルとして残存しない
# （ただし文脈説明としての言及は許容するため、テーブル行形式のみ禁止）
test_no_mode_table_rows() {
  assert_file_exists "$DESIGN_DOC" || return 1
  # パイプ区切りテーブルの行として残っていないか
  if grep -qiP "^\|\s*compact\s*\|" "${PROJECT_ROOT}/${DESIGN_DOC}"; then
    echo "compact mode table row found in ${DESIGN_DOC}" >&2
    return 1
  fi
  if grep -qiP "^\|\s*delegate\s*\|" "${PROJECT_ROOT}/${DESIGN_DOC}"; then
    echo "delegate mode table row found in ${DESIGN_DOC}" >&2
    return 1
  fi
  return 0
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "[edge] compact / delegate モードのテーブル行が存在しない" test_no_mode_table_rows
else
  run_test_skip "[edge] compact/delegate テーブル行なし" "${DESIGN_DOC} not yet created"
fi

# =============================================================================
# Requirement: su-observer-skill-design.md のステップ構造簡素化
# Scenario: 設計ドキュメントと SKILL.md の整合 (spec.md line 15)
# WHEN: 設計ドキュメントを参照して SKILL.md の動作を理解しようとする
# THEN: 両ドキュメントのステップ構造が一致しており、モードの乖離がない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: su-observer-skill-design.md ステップ構造簡素化 ---"

# Test: 設計ドキュメントに Step 0 が存在する
test_design_step0_exists() {
  assert_file_exists "$DESIGN_DOC" || return 1
  assert_file_contains "$DESIGN_DOC" "Step\s*0"
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "設計ドキュメントに Step 0 が存在する" test_design_step0_exists
else
  run_test_skip "設計ドキュメント Step 0" "${DESIGN_DOC} not yet created"
fi

# Test: 設計ドキュメントに Step 1（常駐ループ）が存在する
test_design_step1_exists() {
  assert_file_exists "$DESIGN_DOC" || return 1
  assert_file_contains "$DESIGN_DOC" "Step\s*1"
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "設計ドキュメントに Step 1 (常駐ループ) が存在する" test_design_step1_exists
else
  run_test_skip "設計ドキュメント Step 1" "${DESIGN_DOC} not yet created"
fi

# Test: 設計ドキュメントに Step 2（終了）が存在する
test_design_step2_exists() {
  assert_file_exists "$DESIGN_DOC" || return 1
  assert_file_contains "$DESIGN_DOC" "Step\s*2"
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "設計ドキュメントに Step 2 (終了) が存在する" test_design_step2_exists
else
  run_test_skip "設計ドキュメント Step 2" "${DESIGN_DOC} not yet created"
fi

# Edge case: 設計ドキュメントに SKILL.md にない追加ステップ（Step 4 以上）が見出しとして存在しない
test_design_no_extra_steps() {
  assert_file_exists "$DESIGN_DOC" || return 1
  if grep -qiP "^#{1,6}\s*Step\s*[4-9]" "${PROJECT_ROOT}/${DESIGN_DOC}"; then
    echo "Extra steps (Step 4+) found in ${DESIGN_DOC}" >&2
    return 1
  fi
  return 0
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "[edge] 設計ドキュメントに Step 4 以上の見出しが存在しない" test_design_no_extra_steps
else
  run_test_skip "[edge] 設計ドキュメント Step 4 以上なし" "${DESIGN_DOC} not yet created"
fi

# Edge case: SKILL.md と設計ドキュメントのステップ数が一致している（共に 3 ステップ）
test_skill_and_design_step_consistency() {
  local skill_path="${PROJECT_ROOT}/skills/su-observer/SKILL.md"
  local design_path="${PROJECT_ROOT}/${DESIGN_DOC}"
  [[ -f "$skill_path" ]] || return 0  # SKILL.md 未作成はスキップ
  [[ -f "$design_path" ]] || return 1

  # 両ファイルから Step N 見出し（Step 0, 1, 2...）を抽出して件数比較
  local skill_steps design_steps
  skill_steps=$(grep -ciP "^#{1,6}\s*Step\s*[0-9]" "$skill_path" 2>/dev/null || echo 0)
  design_steps=$(grep -ciP "^#{1,6}\s*Step\s*[0-9]" "$design_path" 2>/dev/null || echo 0)

  if [[ "$skill_steps" != "$design_steps" ]]; then
    echo "Step count mismatch: SKILL.md has ${skill_steps}, design doc has ${design_steps}" >&2
    return 1
  fi
  return 0
}

if [[ -f "${PROJECT_ROOT}/${DESIGN_DOC}" ]]; then
  run_test "[edge] SKILL.md と設計ドキュメントのステップ数が一致している" test_skill_and_design_step_consistency
else
  run_test_skip "[edge] ステップ数整合" "${DESIGN_DOC} not yet created"
fi

# =============================================================================
# Requirement: supervision.md の「モード」言及削除
# Scenario: supervision.md のワークフロー図確認 (spec.md line 23)
# WHEN: supervision.md の flowchart を確認する
# THEN: 「モード」という文字列が存在してはならない（SHALL NOT）
#       分岐ラベルは「指示」や「判断」の例示として記述されていなければならない（SHALL）
# =============================================================================
echo ""
echo "--- Requirement: supervision.md の「モード」言及削除 ---"

# Test: supervision.md に「モード」という文字列が存在しない
test_no_mode_word_in_supervision() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  assert_file_not_contains "$SUPERVISION_MD" "モード"
}

if [[ -f "${PROJECT_ROOT}/${SUPERVISION_MD}" ]]; then
  run_test "supervision.md に「モード」という文字列が存在しない" test_no_mode_word_in_supervision
else
  run_test_skip "supervision.md モード文字列なし" "${SUPERVISION_MD} not yet created"
fi

# Test: supervision.md のワークフロー図が存在する（flowchart を削除していないこと）
test_supervision_flowchart_exists() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  assert_file_contains "$SUPERVISION_MD" "flowchart\|graph\|mermaid\|--->"
}

if [[ -f "${PROJECT_ROOT}/${SUPERVISION_MD}" ]]; then
  run_test "supervision.md にワークフロー図（flowchart）が存在する" test_supervision_flowchart_exists
else
  run_test_skip "supervision.md flowchart 存在" "${SUPERVISION_MD} not yet created"
fi

# Test: supervision.md に「指示」や「判断」の例示が存在する
test_supervision_has_instruction_label() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  assert_file_contains "$SUPERVISION_MD" "指示\|判断\|autopilot.*指示\|issue.*指示"
}

if [[ -f "${PROJECT_ROOT}/${SUPERVISION_MD}" ]]; then
  run_test "supervision.md に「指示」「判断」の例示ラベルが存在する" test_supervision_has_instruction_label
else
  run_test_skip "supervision.md 指示/判断ラベル" "${SUPERVISION_MD} not yet created"
fi

# Edge case: flowchart 内に「モード:」「モード選択」といった記述が残存しない
test_no_mode_in_flowchart() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  # mermaid ブロック内のみを対象にモード文字を検索
  python3 - "${PROJECT_ROOT}/${SUPERVISION_MD}" <<'PYEOF'
import re, sys

with open(sys.argv[1]) as f:
    content = f.read()

# mermaid コードブロックを全て抽出
mermaid_blocks = re.findall(r'```mermaid(.*?)```', content, re.DOTALL)
for block in mermaid_blocks:
    if 'モード' in block:
        print(f"'モード' found in mermaid block", file=sys.stderr)
        sys.exit(1)
sys.exit(0)
PYEOF
}

if [[ -f "${PROJECT_ROOT}/${SUPERVISION_MD}" ]]; then
  run_test "[edge] flowchart 内に「モード」が残存しない" test_no_mode_in_flowchart
else
  run_test_skip "[edge] flowchart モードなし" "${SUPERVISION_MD} not yet created"
fi

# Edge case: supervision.md が Markdown として壊れていない（最低限の見出しが存在する）
test_supervision_has_headings() {
  assert_file_exists "$SUPERVISION_MD" || return 1
  assert_file_contains "$SUPERVISION_MD" "^#{1,3}\s+\S"
}

if [[ -f "${PROJECT_ROOT}/${SUPERVISION_MD}" ]]; then
  run_test "[edge] supervision.md に見出しが存在する（ファイル破損なし）" test_supervision_has_headings
else
  run_test_skip "[edge] supervision.md 見出し存在" "${SUPERVISION_MD} not yet created"
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
