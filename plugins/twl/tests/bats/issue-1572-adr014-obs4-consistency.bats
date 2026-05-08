#!/usr/bin/env bats
# issue-1572-adr014-obs4-consistency.bats
#
# Issue #1572: tech-debt: ADR-014-supervisor-redesign.md の L161 OBS-4 記述が旧値（3→5）のまま
#
# AC1: ADR-014 の OBS-4 記述が現行値（10）を参照している
#   - L161 の記述に「10」または「#1560」が含まれること
#   - 旧値の「3 → 5」が更新されずに単独残存していないこと
#
# AC2: ADR-014 と supervision.md の SU-4 上限値が整合している
#   - ADR-014 の OBS-4 セクションが supervision.md SU-4（≤10）と一致すること
#
# RED: 現在 ADR-014 L161 は「3 → 5」のままであり、全テストが FAIL する
# GREEN: ADR-014 を「10」に更新後に PASS する

load 'helpers/common'

ADR014_FILE=""
SUPERVISION_FILE=""

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  local repo_root
  repo_root="$(cd "${tests_dir}/.." && pwd)"

  ADR014_FILE="${repo_root}/architecture/decisions/ADR-014-supervisor-redesign.md"
  SUPERVISION_FILE="${repo_root}/architecture/domain/contexts/supervision.md"
  export ADR014_FILE SUPERVISION_FILE
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: ADR-014 の OBS-4 記述が現行値（10）を参照している
#
# L161 に「3 → 5」が旧値のまま残存している（RED 状態）。
# 「10」または「#1560」が OBS-4 の緩和記述に含まれることが PASS 条件。
#
# RED: 現在 L161 は "3 → **5**" のみであり、「10」も「#1560」も存在しない
# ===========================================================================

@test "ac1a: ADR-014 OBS-4 行に現行上限値「10」が含まれる" {
  # AC: OBS-4 の緩和記述（L161 付近）に「10」という値が含まれること
  # RED: 現在 L161 は「3 → 5」のみ。「10」が存在しないため grep fail
  [ -f "${ADR014_FILE}" ]
  run bash -c "grep -qE 'OBS-4.*10|10.*OBS-4' '${ADR014_FILE}'"
  assert_success
}

@test "ac1b: ADR-014 OBS-4 行に「#1560」参照が含まれる（または上限値が 10 に更新済み）" {
  # AC: OBS-4 の行に「#1560」による緩和履歴が記録されているか、上限が 10 に更新されていること
  # RED: 現在 L161 に「#1560」も「10」も存在しないため fail
  [ -f "${ADR014_FILE}" ]
  run bash -c "grep -E 'OBS-4.*(#1560|10 に|→.*10|\b10\b)' '${ADR014_FILE}' | grep -qF 'OBS-4'"
  assert_success
}

@test "ac1c: ADR-014 に「3 → 5」が単独残存していない（旧値が更新済みであること）" {
  # AC: 旧値「3 → 5」が最終値として単独残存していないこと（10 への更新を経ていること）
  # RED: 現在 L161 は "3 → **5**" のみで終わっており、旧値が単独残存している
  #
  # 注意: Markdown テーブル用語列マッチルールに従い、grep -qF '| term |' パターンを使用。
  # ただし OBS-4 の記述はテーブル外の箇条書きのため、行全体を対象とした grep を使用する。
  #
  # PASS 条件: 「→ 5」で終わる OBS-4 行が存在しない（→ 10 に更新済みか注記追加済み）
  [ -f "${ADR014_FILE}" ]
  # 「→ 5」または「→ **5**」で行末付近が終わっており、かつ 10 の記述が同行にない場合を fail とする
  local obs4_line
  obs4_line="$(grep 'OBS-4' "${ADR014_FILE}" | grep '→.*5' | grep -v '10' | grep -v '#1560' || true)"
  # obs4_line が空であれば（旧値単独残存がなければ）PASS
  [ -z "${obs4_line}" ]
}

# ===========================================================================
# AC2: ADR-014 と supervision.md の SU-4 上限値が整合している
#
# supervision.md の SU-4 は「上限 10」（#1560 で更新済み）。
# ADR-014 の OBS-4 記述も同じ値（10）を参照していること。
#
# RED: ADR-014 の OBS-4 は「5」のままであり、SU-4（10）と不整合
# ===========================================================================

@test "ac2a: supervision.md の SU-4 テーブル行に上限値 10 が記載されている（前提確認）" {
  # AC: supervision.md の constraints テーブルで SU-4 用語列の行に「10」が含まれること
  # GREEN 前提: supervision.md は #1560 で既に更新済みのため PASS するはず
  # （このテストが FAIL する場合は supervision.md 自体に問題がある）
  [ -f "${SUPERVISION_FILE}" ]
  # 用語列マッチ: SU-4 が用語列（1列目）にある行のみ対象
  run bash -c "grep -qF '| SU-4 |' '${SUPERVISION_FILE}'"
  assert_success
  # SU-4 行に「10」が含まれること
  run bash -c "grep '| SU-4 |' '${SUPERVISION_FILE}' | grep -qF '10'"
  assert_success
}

@test "ac2b: ADR-014 の OBS-4 記述が supervision.md SU-4 の上限値（10）と整合している" {
  # AC: ADR-014 の OBS-4 セクションと supervision.md SU-4 の上限値（10）が一致すること
  # RED: ADR-014 OBS-4 は「5」、supervision.md SU-4 は「10」で不整合のため fail
  [ -f "${ADR014_FILE}" ]
  [ -f "${SUPERVISION_FILE}" ]

  # supervision.md の SU-4 行から上限値を抽出（10 が含まれることを確認済み）
  local su4_has_10
  su4_has_10="$(grep '| SU-4 |' "${SUPERVISION_FILE}" | grep -c '10' || echo 0)"
  [ "${su4_has_10}" -ge 1 ]

  # ADR-014 の OBS-4 記述にも「10」が含まれること（整合確認）
  # RED: 現在 ADR-014 OBS-4 に「10」が存在しないため fail
  run bash -c "grep 'OBS-4' '${ADR014_FILE}' | grep -qF '10'"
  assert_success
}
