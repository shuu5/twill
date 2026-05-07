#!/usr/bin/env bats
# issue-1517-lesson-structuralization.bats - TDD RED phase tests for Issue #1517
# "meta-bug: architecture lesson architecture"
#
# AC summary:
#   AC1: ADR-036-lesson-structuralization.md を新規作成
#   AC2: ref-invariants.md に Invariant N: Lesson Structuralization を追加
#   AC3: su-observer SKILL.md Step 1 末尾に lesson 確立時の MUST チェーン追加
#   AC4: pitfalls-catalog.md に §19（lesson 一時保存の落とし穴）追加
#
# RED: 全テストは実装前の状態で fail する

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  ADR_FILE="${REPO_ROOT}/architecture/decisions/ADR-036-lesson-structuralization.md"
  REF_INVARIANTS="${REPO_ROOT}/refs/ref-invariants.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  PITFALLS="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  export ADR_FILE REF_INVARIANTS SKILL_MD PITFALLS
}

# ===========================================================================
# AC1: ADR-036-lesson-structuralization.md を新規作成
# ===========================================================================

@test "issue-1517: AC1 ADR-036-lesson-structuralization.md が存在すること" {
  # RED: ファイル未作成のため fail する
  [ -f "${ADR_FILE}" ]
}

@test "issue-1517: AC1 ADR-036 に 'Context' セクションが含まれること" {
  # RED: ファイル未作成のため fail する
  [ -f "${ADR_FILE}" ]
  grep -qi "^## Context\|^# Context\|Context:" "${ADR_FILE}"
}

@test "issue-1517: AC1 ADR-036 に 'Decision' セクションが含まれること" {
  # RED: ファイル未作成のため fail する
  [ -f "${ADR_FILE}" ]
  grep -qi "^## Decision\|^# Decision\|Decision:" "${ADR_FILE}"
}

@test "issue-1517: AC1 ADR-036 に 'Consequences' セクションが含まれること" {
  # RED: ファイル未作成のため fail する
  [ -f "${ADR_FILE}" ]
  grep -qi "^## Consequences\|^# Consequences\|Consequences:" "${ADR_FILE}"
}

@test "issue-1517: AC1 ADR-036 に 4 ステップのチェーン定義が含まれること" {
  # RED: ファイル未作成のため fail する
  # 4 ステップ: doobidoo 保存 / Issue 起票 / Wave 実装 / 永続文書化
  [ -f "${ADR_FILE}" ]
  grep -qi "doobidoo" "${ADR_FILE}"
  grep -qi "Issue" "${ADR_FILE}"
  grep -qi "Wave\|実装" "${ADR_FILE}"
  grep -qi "永続\|pitfalls\|SKILL\.md\|ADR" "${ADR_FILE}"
}

@test "issue-1517: AC1 ADR-036 の Decision に 'MUST' が含まれること" {
  # RED: ファイル未作成のため fail する
  # lesson 確立時の構造化チェーンを MUST 化
  [ -f "${ADR_FILE}" ]
  grep -q "MUST" "${ADR_FILE}"
}

# ===========================================================================
# AC2: ref-invariants.md に Invariant N: Lesson Structuralization を追加
# ===========================================================================

@test "issue-1517: AC2 ref-invariants.md に 'Lesson Structuralization' が含まれること" {
  # RED: Invariant 未追加のため fail する
  [ -f "${REF_INVARIANTS}" ]
  grep -qi "Lesson Structuralization" "${REF_INVARIANTS}"
}

@test "issue-1517: AC2 ref-invariants.md に ADR-036 への参照が含まれること" {
  # RED: Invariant 未追加のため fail する
  [ -f "${REF_INVARIANTS}" ]
  grep -qF "ADR-036" "${REF_INVARIANTS}"
}

@test "issue-1517: AC2 ref-invariants.md の Lesson Structuralization invariant に 4 ステップのチェーンが含まれること" {
  # RED: Invariant 未追加のため fail する
  [ -f "${REF_INVARIANTS}" ]
  grep -qi "Lesson Structuralization" "${REF_INVARIANTS}"

  # Lesson Structuralization セクション内で 4 ステップが言及されていること
  local section_line
  section_line=$(grep -ni "Lesson Structuralization" "${REF_INVARIANTS}" | head -1 | cut -d: -f1)
  [ -n "${section_line}" ]

  local section_text
  section_text=$(tail -n +"${section_line}" "${REF_INVARIANTS}" | head -30)

  echo "${section_text}" | grep -qi "doobidoo"
  echo "${section_text}" | grep -qi "Issue"
  echo "${section_text}" | grep -qi "Wave\|実装"
  echo "${section_text}" | grep -qi "永続\|pitfalls\|SKILL\.md\|ADR"
}

@test "issue-1517: AC2 ref-invariants.md の Lesson Structuralization invariant に '完遂' の定義が含まれること" {
  # RED: Invariant 未追加のため fail する
  [ -f "${REF_INVARIANTS}" ]
  grep -qi "Lesson Structuralization" "${REF_INVARIANTS}"

  local section_line
  section_line=$(grep -ni "Lesson Structuralization" "${REF_INVARIANTS}" | head -1 | cut -d: -f1)
  [ -n "${section_line}" ]

  local section_text
  section_text=$(tail -n +"${section_line}" "${REF_INVARIANTS}" | head -30)
  echo "${section_text}" | grep -qi "完遂\|complete"
}

# ===========================================================================
# AC3: su-observer SKILL.md Step 1 末尾に lesson 確立時の MUST チェーン追加
# ===========================================================================

@test "issue-1517: AC3 SKILL.md に 'lesson 確立時の MUST チェーン' が含まれること" {
  # RED: Step 1 末尾への追加が未実施のため fail する
  [ -f "${SKILL_MD}" ]
  grep -qi "lesson.*MUST.*チェーン\|lesson 確立時" "${SKILL_MD}"
}

@test "issue-1517: AC3 SKILL.md に ADR-036 と Invariant N への参照が含まれること" {
  # RED: Step 1 末尾への追加が未実施のため fail する
  [ -f "${SKILL_MD}" ]
  grep -qF "ADR-036" "${SKILL_MD}"
}

@test "issue-1517: AC3 SKILL.md の lesson チェーン追記が Step 1 セクション内に位置すること" {
  # RED: Step 1 末尾への追加が未実施のため fail する
  [ -f "${SKILL_MD}" ]

  local step1_line step2_line
  step1_line=$(grep -n "^## Step 1:" "${SKILL_MD}" | head -1 | cut -d: -f1)
  step2_line=$(grep -n "^## Step 2:" "${SKILL_MD}" | head -1 | cut -d: -f1)
  [ -n "${step1_line}" ]
  [ -n "${step2_line}" ]

  # Step 1 と Step 2 の間に ADR-036 の参照があること
  local step1_section
  step1_section=$(sed -n "${step1_line},${step2_line}p" "${SKILL_MD}")
  echo "${step1_section}" | grep -qF "ADR-036"
}

@test "issue-1517: AC3 SKILL.md の lesson チェーンに Issue 起票の MUST が含まれること" {
  # RED: Step 1 末尾への追加が未実施のため fail する
  [ -f "${SKILL_MD}" ]

  local step1_line step2_line
  step1_line=$(grep -n "^## Step 1:" "${SKILL_MD}" | head -1 | cut -d: -f1)
  step2_line=$(grep -n "^## Step 2:" "${SKILL_MD}" | head -1 | cut -d: -f1)
  [ -n "${step1_line}" ]
  [ -n "${step2_line}" ]

  local step1_section
  step1_section=$(sed -n "${step1_line},${step2_line}p" "${SKILL_MD}")
  echo "${step1_section}" | grep -qi "gh issue create\|Issue 起票\|Issue.*create"
}

# ===========================================================================
# AC4: pitfalls-catalog.md に新規 section 追加
#   "lesson 一時保存の落とし穴 (本セッション 2026-05-07 失敗事例)"
# ===========================================================================

@test "issue-1517: AC4 pitfalls-catalog.md に §19 が存在すること" {
  # RED: セクション未追加のため fail する
  # 現在の最終セクションは §18 のため、§19 を追加する
  [ -f "${PITFALLS}" ]
  grep -q "^## 19\." "${PITFALLS}"
}

@test "issue-1517: AC4 pitfalls-catalog.md §19 のタイトルに 'lesson' が含まれること" {
  # RED: セクション未追加のため fail する
  [ -f "${PITFALLS}" ]
  grep -qiE "^## 19\..*(lesson|一時保存|Lesson)" "${PITFALLS}"
}

@test "issue-1517: AC4 pitfalls-catalog.md §19 に 2026-05-07 の失敗事例への言及が含まれること" {
  # RED: セクション未追加のため fail する
  [ -f "${PITFALLS}" ]

  local section_line
  section_line=$(grep -n "^## 19\." "${PITFALLS}" | head -1 | cut -d: -f1)
  [ -n "${section_line}" ]

  local section_text
  section_text=$(tail -n +"${section_line}" "${PITFALLS}" | head -50)
  echo "${section_text}" | grep -qi "2026-05-07\|失敗事例\|failure"
}

@test "issue-1517: AC4 pitfalls-catalog.md §19 に構造化チェーンへの言及が含まれること" {
  # RED: セクション未追加のため fail する
  [ -f "${PITFALLS}" ]

  local section_line
  section_line=$(grep -n "^## 19\." "${PITFALLS}" | head -1 | cut -d: -f1)
  [ -n "${section_line}" ]

  local section_text
  section_text=$(tail -n +"${section_line}" "${PITFALLS}" | head -50)
  # 構造化チェーン (ADR-036 / doobidoo / Issue) への言及
  echo "${section_text}" | grep -qiE "ADR-036|doobidoo|構造化|structuralization"
}

@test "issue-1517: AC4 pitfalls-catalog.md §19 は §18 の直後に位置すること" {
  # RED: セクション未追加のため fail する
  [ -f "${PITFALLS}" ]

  local line_18 line_19
  line_18=$(grep -n "^## 18\." "${PITFALLS}" | head -1 | cut -d: -f1)
  line_19=$(grep -n "^## 19\." "${PITFALLS}" | head -1 | cut -d: -f1)
  [ -n "${line_18}" ]
  [ -n "${line_19}" ]
  [ "${line_19}" -gt "${line_18}" ]
}
