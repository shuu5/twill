#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: chain bypass 禁止
# Generated from: deltaspec/changes/issue-438/specs/chain-bypass-prohibition/spec.md
# Coverage level: edge-cases
# Verifies:
#   - co-autopilot SKILL.md に chain bypass 禁止ルールが記載されている
#   - autopilot.md に不変条件 M が定義されている
#   - 正規復旧手順（orchestrator 再起動 or 手動 inject）が SKILL.md に記載されている
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
    if ! grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
      return 1
    fi
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

SKILL_MD="skills/co-autopilot/SKILL.md"
AUTOPILOT_MD="architecture/domain/contexts/autopilot.md"

# =============================================================================
# Requirement: chain bypass 禁止の明文化（co-autopilot SKILL.md）
# =============================================================================
echo ""
echo "--- Requirement: chain bypass 禁止（co-autopilot SKILL.md） ---"

# Scenario: chain 停止時に Pilot が直接 nudge を行わない
# WHEN Worker の chain 遷移が停止し、orchestrator が inject を実行していない状態で Pilot が停止を検知する
# THEN Pilot は orchestrator 再起動または手動 /twl:workflow-<name> inject を実行し、直接 nudge によるチェーン迂回を行わない

test_skill_md_exists() {
  assert_file_exists "$SKILL_MD"
}
run_test "co-autopilot SKILL.md が存在する" test_skill_md_exists

test_skill_md_chain_bypass_prohibition() {
  assert_file_contains "$SKILL_MD" "chain.*bypass.*禁止|直接.*nudge.*してはならない|MUST NOT.*nudge|chain.*迂回"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md に chain bypass 禁止が明記されている" test_skill_md_chain_bypass_prohibition
else
  run_test_skip "SKILL.md に chain bypass 禁止が明記されている" "${SKILL_MD} not found"
fi

# Scenario: chain 停止時の正規復旧手順が定義されている
# WHEN orchestrator が停止して chain 遷移が行われない状態が検知される
# THEN Pilot は co-autopilot SKILL.md に記載された復旧手順（orchestrator 再起動 or 手動 skill inject）に従い chain を再開する

test_skill_md_recovery_procedure_orchestrator_restart() {
  assert_file_contains "$SKILL_MD" "orchestrator.*再起動|orchestrator.*restart"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md に orchestrator 再起動手順が記載されている" test_skill_md_recovery_procedure_orchestrator_restart
else
  run_test_skip "SKILL.md に orchestrator 再起動手順が記載されている" "${SKILL_MD} not found"
fi

test_skill_md_recovery_procedure_manual_inject() {
  assert_file_contains "$SKILL_MD" "手動.*inject|manual.*inject|/twl:workflow-"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md に手動 skill inject 手順が記載されている" test_skill_md_recovery_procedure_manual_inject
else
  run_test_skip "SKILL.md に手動 skill inject 手順が記載されている" "${SKILL_MD} not found"
fi

test_skill_md_recovery_procedure_chain_resume() {
  assert_file_contains_all "$SKILL_MD" \
    "orchestrator.*再起動|orchestrator.*restart" \
    "手動.*inject|/twl:workflow-"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md に正規復旧手順（再起動 + 手動 inject の両方）が記載されている" test_skill_md_recovery_procedure_chain_resume
else
  run_test_skip "SKILL.md に正規復旧手順（再起動 + 手動 inject の両方）が記載されている" "${SKILL_MD} not found"
fi

# Edge case: 禁止事項セクションに chain bypass が含まれる
test_skill_md_prohibition_section() {
  assert_file_contains "$SKILL_MD" "禁止事項|MUST NOT|禁止"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md に禁止事項セクションが存在する" test_skill_md_prohibition_section
else
  run_test_skip "SKILL.md に禁止事項セクションが存在する" "${SKILL_MD} not found"
fi

# Edge case: 不変条件 M への参照が SKILL.md に含まれる
# Scenario: 不変条件 M の参照先が co-autopilot SKILL.md に記載される
# WHEN co-autopilot SKILL.md の禁止事項セクションを参照する
# THEN chain bypass 禁止が不変条件 M として参照され、正規復旧手順へのリンクが明記されている

test_skill_md_invariant_m_reference() {
  # 不変条件 M を M 単体 ID として参照（A〜K の K に含まれる M などは除外）
  # grep -P で word boundary を使う: 不変条件\s+M\b または \*\*M\*\*
  grep -qP "不変条件\s+M\b|\bM\s+(chain|bypass)|不変条件.*\bM\b.*chain|\*\*M\*\*" "${PROJECT_ROOT}/${SKILL_MD}"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md が不変条件 M を参照している" test_skill_md_invariant_m_reference
else
  run_test_skip "SKILL.md が不変条件 M を参照している" "${SKILL_MD} not found"
fi

test_skill_md_invariant_m_with_recovery_link() {
  # 不変条件 M への言及 AND 復旧手順への参照が両方あること
  grep -qP "不変条件\s+M\b|\bM\s+(chain|bypass)|\*\*M\*\*" "${PROJECT_ROOT}/${SKILL_MD}" || return 1
  assert_file_contains "$SKILL_MD" "orchestrator.*再起動|手動.*inject|復旧"
}
if [[ -f "${PROJECT_ROOT}/${SKILL_MD}" ]]; then
  run_test "SKILL.md の不変条件 M 参照に正規復旧手順へのリンクが付随している" test_skill_md_invariant_m_with_recovery_link
else
  run_test_skip "SKILL.md の不変条件 M 参照に正規復旧手順へのリンクが付随している" "${SKILL_MD} not found"
fi

# =============================================================================
# Requirement: 不変条件 M（autopilot.md）
# =============================================================================
echo ""
echo "--- Requirement: 不変条件 M（autopilot.md） ---"

# Scenario: 不変条件 M が autopilot.md に追加される
# WHEN autopilot.md の不変条件テーブルを参照する
# THEN 不変条件 M「chain 遷移は orchestrator/手動 inject のみ」が定義されており、
#      Pilot の直接 nudge による chain bypass が禁止であることが明記されている

test_autopilot_md_exists() {
  assert_file_exists "$AUTOPILOT_MD"
}
run_test "autopilot.md が存在する" test_autopilot_md_exists

test_autopilot_md_invariant_table_exists() {
  assert_file_contains "$AUTOPILOT_MD" "不変条件|Invariant"
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md に不変条件テーブルが存在する" test_autopilot_md_invariant_table_exists
else
  run_test_skip "autopilot.md に不変条件テーブルが存在する" "${AUTOPILOT_MD} not found"
fi

test_autopilot_md_invariant_m_defined() {
  # ID "M" が不変条件テーブルに存在する
  assert_file_contains "$AUTOPILOT_MD" "\|\s*\*\*M\*\*\s*\||\|\s*M\s*\|"
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md の不変条件テーブルに ID M が定義されている" test_autopilot_md_invariant_m_defined
else
  run_test_skip "autopilot.md の不変条件テーブルに ID M が定義されている" "${AUTOPILOT_MD} not found"
fi

test_autopilot_md_invariant_m_content_inject_only() {
  # chain 遷移は inject のみ許可という内容
  assert_file_contains "$AUTOPILOT_MD" "inject.*のみ|inject.*only|inject_next_workflow.*のみ"
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "不変条件 M が chain 遷移は inject のみ許可と定義している" test_autopilot_md_invariant_m_content_inject_only
else
  run_test_skip "不変条件 M が chain 遷移は inject のみ許可と定義している" "${AUTOPILOT_MD} not found"
fi

test_autopilot_md_invariant_m_prohibits_direct_nudge() {
  # 不変条件 M の行に chain bypass 禁止が明記されている（不変条件 K などの false positive を避ける）
  # 不変条件 M のテーブル行を探し、そこに chain bypass 禁止が含まれることを確認
  grep -P "\|\s*\*\*M\*\*\s*\|" "${PROJECT_ROOT}/${AUTOPILOT_MD}" | grep -qiP "chain.*bypass.*禁止|直接.*nudge.*禁止|bypass.*禁止"
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "不変条件 M が Pilot の直接 nudge による chain bypass を禁止と明記している" test_autopilot_md_invariant_m_prohibits_direct_nudge
else
  run_test_skip "不変条件 M が Pilot の直接 nudge による chain bypass を禁止と明記している" "${AUTOPILOT_MD} not found"
fi

# Edge case: 不変条件 M の後に DeltaSpec 参照が記載されている
test_autopilot_md_invariant_m_deltaspec_ref() {
  assert_file_contains "$AUTOPILOT_MD" "issue-438|chain-bypass-prohibition"
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md の不変条件 M に DeltaSpec 参照が含まれる" test_autopilot_md_invariant_m_deltaspec_ref
else
  run_test_skip "autopilot.md の不変条件 M に DeltaSpec 参照が含まれる" "${AUTOPILOT_MD} not found"
fi

# Edge case: 不変条件の件数が 13 件（A-M）になっている
test_autopilot_md_invariant_count() {
  # M まで不変条件が定義されていれば 13 件（A-M）
  local count
  count=$(grep -cP '\|\s*\*\*[A-M]\*\*\s*\|' "${PROJECT_ROOT}/${AUTOPILOT_MD}" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]]
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md に不変条件 M の ID が存在する（A-M でカバー）" test_autopilot_md_invariant_count
else
  run_test_skip "autopilot.md に不変条件 M の ID が存在する（A-M でカバー）" "${AUTOPILOT_MD} not found"
fi

# Edge case: 不変条件 M のヘッダー件数表記も更新されている
test_autopilot_md_invariant_header_count() {
  # 「13件」または「A-M」または「13 件」のいずれかが記載されている
  assert_file_contains "$AUTOPILOT_MD" "13件|13 件|A-M|A〜M"
}
if [[ -f "${PROJECT_ROOT}/${AUTOPILOT_MD}" ]]; then
  run_test "autopilot.md の不変条件件数ヘッダーが 13 件（A-M）に更新されている" test_autopilot_md_invariant_header_count
else
  run_test_skip "autopilot.md の不変条件件数ヘッダーが 13 件（A-M）に更新されている" "${AUTOPILOT_MD} not found"
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
