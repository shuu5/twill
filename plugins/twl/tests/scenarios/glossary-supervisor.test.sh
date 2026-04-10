#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: glossary-supervisor
# Generated from: deltaspec/changes/issue-355/specs/glossary-supervisor/spec.md
# Coverage level: edge-cases
# Target file: plugins/twl/architecture/domain/glossary.md
# =============================================================================
set -uo pipefail

# Project root (relative to test file location: tests/scenarios/ -> plugins/twl/)
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
  if [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP "$pattern" "${PROJECT_ROOT}/${file}"; then
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
    if ! grep -qP "$pattern" "${PROJECT_ROOT}/${file}"; then
      return 1
    fi
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    return 1
  fi
  if grep -qP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

# MUSTテーブル（MUST用語セクション内の行）にパターンが存在するか確認
# MUSTセクション = "### MUST 用語" から "### SHOULD 用語" の手前まで
assert_must_section_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    return 1
  fi
  # SHOULDセクション行番号を取得
  local should_line
  should_line=$(grep -n "### SHOULD 用語" "${PROJECT_ROOT}/${file}" | head -1 | cut -d: -f1)
  if [[ -z "$should_line" ]]; then
    return 1
  fi
  # MUSTセクション（先頭からSHOULDの手前まで）でパターン検索
  head -n "$((should_line - 1))" "${PROJECT_ROOT}/${file}" | grep -qP "$pattern"
}

assert_must_section_not_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    return 1
  fi
  local should_line
  should_line=$(grep -n "### SHOULD 用語" "${PROJECT_ROOT}/${file}" | head -1 | cut -d: -f1)
  if [[ -z "$should_line" ]]; then
    return 1
  fi
  if head -n "$((should_line - 1))" "${PROJECT_ROOT}/${file}" | grep -qP "$pattern"; then
    return 1
  fi
  return 0
}

# SHOULDテーブル（SHOULD用語セクション内の行）にパターンが存在するか確認
assert_should_section_contains() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "${PROJECT_ROOT}/${file}" ]]; then
    return 1
  fi
  local should_line
  should_line=$(grep -n "### SHOULD 用語" "${PROJECT_ROOT}/${file}" | head -1 | cut -d: -f1)
  if [[ -z "$should_line" ]]; then
    return 1
  fi
  tail -n "+${should_line}" "${PROJECT_ROOT}/${file}" | grep -qP "$pattern"
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

GLOSSARY="architecture/domain/glossary.md"

# =============================================================================
# Requirement: Three-Layer Memory 定義の ADR-014 整合
# =============================================================================
echo ""
echo "--- Requirement: Three-Layer Memory 定義の ADR-014 整合 ---"

# Scenario: Three-Layer Memory 定義更新 (spec line 7-9)
# WHEN: glossary.md の Three-Layer Memory 行の定義列を確認する
# THEN: Long-term Memory（永続）+ Working Memory Externalization（一時退避）+ Compressed Memory（compaction後）と記述されている
test_three_layer_memory_definition_updated() {
  assert_file_exists "$GLOSSARY" || return 1
  # Three-Layer Memory の行に ADR-014 準拠の3層名称が含まれているか確認
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "Long-term Memory"
}
run_test "Three-Layer Memory 定義更新: Long-term Memory が含まれる" test_three_layer_memory_definition_updated

test_three_layer_memory_working_memory_externalization() {
  assert_file_exists "$GLOSSARY" || return 1
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "Working Memory Externalization"
}
run_test "Three-Layer Memory 定義更新: Working Memory Externalization が含まれる" test_three_layer_memory_working_memory_externalization

test_three_layer_memory_compressed_memory() {
  assert_file_exists "$GLOSSARY" || return 1
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "Compressed Memory"
}
run_test "Three-Layer Memory 定義更新: Compressed Memory が含まれる" test_three_layer_memory_compressed_memory

# Edge case: 旧定義（Externalized Memory / Working Memory（context））が残っていない
test_three_layer_memory_old_definition_removed() {
  assert_file_exists "$GLOSSARY" || return 1
  # 旧定義の "Externalized Memory" が Three-Layer Memory 行に残っていないこと
  if grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" | grep -qP "Externalized Memory"; then
    return 1
  fi
  return 0
}
run_test "Three-Layer Memory 定義更新 [edge: 旧定義 Externalized Memory が残っていない]" test_three_layer_memory_old_definition_removed

# Edge case: 旧定義 "Working Memory（context）" が残っていない
test_three_layer_memory_old_working_memory_removed() {
  assert_file_exists "$GLOSSARY" || return 1
  if grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" | grep -qP "Working Memory（context）"; then
    return 1
  fi
  return 0
}
run_test "Three-Layer Memory 定義更新 [edge: 旧定義 Working Memory（context）が残っていない]" test_three_layer_memory_old_working_memory_removed

# Edge case: 3層が全て同一行のテーブルセル内に記述されている
test_three_layer_memory_all_layers_same_row() {
  assert_file_exists "$GLOSSARY" || return 1
  # Three-Layer Memory 用語行が3層全てを含む1行になっている
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "Long-term Memory.*Working Memory Externalization.*Compressed Memory"
}
run_test "Three-Layer Memory 定義更新 [edge: 3層が同一行に記述]" test_three_layer_memory_all_layers_same_row

# =============================================================================
# Requirement: ADR-014 との整合確認
# =============================================================================
echo ""
echo "--- Requirement: ADR-014 との整合確認 ---"

# Scenario: ADR-014 との整合確認 (spec line 11-13)
# WHEN: ADR-014 Decision 3 の層名称と glossary.md の Three-Layer Memory 定義を比較する
# THEN: 3層すべての名称が ADR-014 の正式名称と完全一致している
# ADR-014 Decision 3 正式名称: Long-term Memory / Working Memory Externalization / Compressed Memory

test_adr014_layer1_exact_match() {
  assert_file_exists "$GLOSSARY" || return 1
  # "Long-term Memory" が完全な形で（前後に余計な語なく）存在するか
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "\bLong-term Memory\b"
}
run_test "ADR-014 整合: Long-term Memory が完全一致" test_adr014_layer1_exact_match

test_adr014_layer2_exact_match() {
  assert_file_exists "$GLOSSARY" || return 1
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "\bWorking Memory Externalization\b"
}
run_test "ADR-014 整合: Working Memory Externalization が完全一致" test_adr014_layer2_exact_match

test_adr014_layer3_exact_match() {
  assert_file_exists "$GLOSSARY" || return 1
  grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "\bCompressed Memory\b"
}
run_test "ADR-014 整合: Compressed Memory が完全一致" test_adr014_layer3_exact_match

# Edge case: ADR-014 の非公式変形（Long Term Memory / WorkingMemory 等）が混入していない
test_adr014_no_informal_variants() {
  assert_file_exists "$GLOSSARY" || return 1
  # ハイフンなし "Long Term Memory" が Three-Layer Memory 行にない
  if grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" | grep -qP "\bLong Term Memory\b"; then
    return 1
  fi
  return 0
}
run_test "ADR-014 整合 [edge: 非公式変形 'Long Term Memory' が混入していない]" test_adr014_no_informal_variants

# Edge case: Working Memory（ADR-014以前の略称）単体が Three-Layer Memory 定義に残っていない
test_adr014_no_bare_working_memory() {
  assert_file_exists "$GLOSSARY" || return 1
  # "Working Memory" が "Working Memory Externalization" の一部としてのみ現れること
  # つまり "Working Memory" の後に "Externalization" が続かないケースがない
  if grep -P "Three-Layer Memory" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -qP "\bWorking Memory\b(?!\s+Externalization)"; then
    return 1
  fi
  return 0
}
run_test "ADR-014 整合 [edge: 'Working Memory' 単体が Three-Layer Memory 定義に残っていない]" test_adr014_no_bare_working_memory

# =============================================================================
# Requirement: Supervisor 6 用語の MUST セクション存在確認
# =============================================================================
echo ""
echo "--- Requirement: Supervisor 6 用語の MUST セクション存在確認 ---"

# Scenario: 6 用語の存在確認 (spec line 21-23)
# WHEN: glossary.md の MUST テーブルを参照する
# THEN: Supervisor, su-observer, SupervisorSession, su-compact, Three-Layer Memory, Wave の 6 用語が存在する

test_must_has_supervisor() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_contains "$GLOSSARY" "^\| Supervisor \|"
}
run_test "MUST セクション: Supervisor が存在する" test_must_has_supervisor

test_must_has_su_observer() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_contains "$GLOSSARY" "^\| su-observer \|"
}
run_test "MUST セクション: su-observer が存在する" test_must_has_su_observer

test_must_has_supervisor_session() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_contains "$GLOSSARY" "^\| SupervisorSession \|"
}
run_test "MUST セクション: SupervisorSession が存在する" test_must_has_supervisor_session

test_must_has_su_compact() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_contains "$GLOSSARY" "^\| su-compact \|"
}
run_test "MUST セクション: su-compact が存在する" test_must_has_su_compact

test_must_has_three_layer_memory() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_contains "$GLOSSARY" "^\| Three-Layer Memory \|"
}
run_test "MUST セクション: Three-Layer Memory が存在する" test_must_has_three_layer_memory

test_must_has_wave() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_contains "$GLOSSARY" "^\| Wave \|"
}
run_test "MUST セクション: Wave が存在する" test_must_has_wave

# Edge case: 6用語が全て Supervision context に属している
test_must_supervisor_terms_have_supervision_context() {
  assert_file_exists "$GLOSSARY" || return 1
  local should_line
  should_line=$(grep -n "### SHOULD 用語" "${PROJECT_ROOT}/${GLOSSARY}" | head -1 | cut -d: -f1)
  if [[ -z "$should_line" ]]; then
    return 1
  fi
  local must_content
  must_content=$(head -n "$((should_line - 1))" "${PROJECT_ROOT}/${GLOSSARY}")
  # Supervisor と SupervisorSession は Supervision context
  echo "$must_content" | grep -P "^\| Supervisor \|" | grep -qP "Supervision" || return 1
  echo "$must_content" | grep -P "^\| SupervisorSession \|" | grep -qP "Supervision" || return 1
  echo "$must_content" | grep -P "^\| su-observer \|" | grep -qP "Supervision" || return 1
  echo "$must_content" | grep -P "^\| su-compact \|" | grep -qP "Supervision" || return 1
  echo "$must_content" | grep -P "^\| Three-Layer Memory \|" | grep -qP "Supervision" || return 1
  return 0
}
run_test "MUST 6用語 [edge: 全て Supervision context に属している]" test_must_supervisor_terms_have_supervision_context

# Edge case: MUSTテーブルの行数が正常（最低6つのSupervision用語行がある）
test_must_section_has_six_supervision_terms() {
  assert_file_exists "$GLOSSARY" || return 1
  local should_line
  should_line=$(grep -n "### SHOULD 用語" "${PROJECT_ROOT}/${GLOSSARY}" | head -1 | cut -d: -f1)
  if [[ -z "$should_line" ]]; then
    return 1
  fi
  local count
  count=$(head -n "$((should_line - 1))" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -cP "^\|.*\| Supervision" || true)
  [[ $count -ge 6 ]]
}
run_test "MUST 6用語 [edge: Supervision context の行が6件以上ある]" test_must_section_has_six_supervision_terms

# =============================================================================
# Requirement: Observer 用語の MUST 外維持
# =============================================================================
echo ""
echo "--- Requirement: Observer 用語の MUST 外維持 ---"

# Scenario: Observer 用語の SHOULD 維持 (spec line 29-31)
# WHEN: glossary.md の MUST テーブルを参照する
# THEN: Observer, Observed, Live Observation の各用語が MUST テーブルに存在しない

test_must_not_has_observer() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_not_contains "$GLOSSARY" "^\| Observer \|"
}
run_test "MUST テーブル外: Observer が MUST に存在しない" test_must_not_has_observer

test_must_not_has_observed() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_not_contains "$GLOSSARY" "^\| Observed \|"
}
run_test "MUST テーブル外: Observed が MUST に存在しない" test_must_not_has_observed

test_must_not_has_live_observation() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_not_contains "$GLOSSARY" "^\| Live Observation \|"
}
run_test "MUST テーブル外: Live Observation が MUST に存在しない" test_must_not_has_live_observation

# Edge case: Observer 用語が Observation context のままである（context 列を確認）
test_observer_terms_remain_observation_context() {
  assert_file_exists "$GLOSSARY" || return 1
  # Observer 行の context 列が Observation であること
  grep -P "^\| Observer \|" "${PROJECT_ROOT}/${GLOSSARY}" | grep -qP "\| Observation"
}
run_test "Observer 用語 MUST 外 [edge: Observer の context が Observation のまま]" test_observer_terms_remain_observation_context

test_observed_remains_observation_context() {
  assert_file_exists "$GLOSSARY" || return 1
  grep -P "^\| Observed \|" "${PROJECT_ROOT}/${GLOSSARY}" | grep -qP "\| Observation"
}
run_test "Observer 用語 MUST 外 [edge: Observed の context が Observation のまま]" test_observed_remains_observation_context

# Scenario: Observer 用語の SHOULD 存在確認 (spec line 33-35)
# WHEN: glossary.md の SHOULD テーブルを参照する
# THEN: observer-evaluator 等の Observation context 用語が SHOULD テーブルに存在する

test_should_has_observer_evaluator() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_should_section_contains "$GLOSSARY" "^\| observer-evaluator \|"
}
run_test "SHOULD テーブル: observer-evaluator が存在する" test_should_has_observer_evaluator

# Edge case: SHOULDテーブルに Observation context の用語が複数ある
test_should_has_multiple_observation_terms() {
  assert_file_exists "$GLOSSARY" || return 1
  local should_line
  should_line=$(grep -n "### SHOULD 用語" "${PROJECT_ROOT}/${GLOSSARY}" | head -1 | cut -d: -f1)
  if [[ -z "$should_line" ]]; then
    return 1
  fi
  local count
  count=$(tail -n "+${should_line}" "${PROJECT_ROOT}/${GLOSSARY}" \
    | grep -cP "^\|.*\| Observation" || true)
  [[ $count -ge 2 ]]
}
run_test "SHOULD テーブル [edge: Observation context の用語が複数存在する]" test_should_has_multiple_observation_terms

# Edge case: co-self-improve が Observer 関連として MUST 外に維持されている
test_must_not_has_co_self_improve() {
  assert_file_exists "$GLOSSARY" || return 1
  assert_must_section_not_contains "$GLOSSARY" "^\| co-self-improve \|"
}
run_test "Observer 用語 MUST 外 [edge: co-self-improve も MUST に含まれていない]" test_must_not_has_co_self_improve

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
