#!/usr/bin/env bats
# issue-1574-bats-warn-echo-output-grep-q.bats
#
# Issue #1574: tech-debt bats WARN検証で `echo ${output} | grep -qi` を
#              `assert_output --partial` に置き換え
#
# AC1: session-id-uuid-validation.bats に `echo "${output}" | grep -qi` パターンが
#      存在しないこと（L157, L289, L354, L526 全て置換済み）
# AC2: 置換後も既存テストが pass すること（テストの意図・アサーション内容が維持されていること）
#
# RED: 現在 L157, L289, L354, L526 に旧パターンが残存しているため AC1 テストは FAIL する
# GREEN: 4 箇所全て assert_output --partial に置換後に PASS する

load 'helpers/common'

TARGET_BATS=""

setup() {
  common_setup
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  TARGET_BATS="${this_dir}/scripts/session-id-uuid-validation.bats"
  export TARGET_BATS
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: session-id-uuid-validation.bats に echo "${output}" | grep -qi パターンが
#      存在しないこと
#
# RED: 現在 L157, L289, L354, L526 に旧パターンが残存しているため FAIL する
# GREEN: 4 箇所全て置換後に PASS する
# ===========================================================================

@test "ac1: session-id-uuid-validation.bats が存在する" {
  # 前提確認: テスト対象ファイルが存在すること
  [ -f "${TARGET_BATS}" ]
}

@test "ac1: echo \"\${output}\" | grep -qi パターンが session-id-uuid-validation.bats に存在しない" {
  # AC: ファイル内に `echo "${output}" | grep -qi` または `echo "${output}" | grep -qiE` が
  #     存在しないこと（L157, L289, L354, L526 全て置換済みであること）
  # RED: 現在 4 箇所に旧パターンが残存しているため assert_failure が通らず FAIL する
  run grep -cE 'echo[[:space:]]+"?\$\{output\}"?[[:space:]]*\|[[:space:]]*grep[[:space:]]+-qi' "${TARGET_BATS}"
  # grep -c は一致行数を返す。0 行（パターン不在）なら exit code 1 → assert_failure が PASS
  # 現在は 4 行一致するため exit code 0 → assert_failure が FAIL（RED 状態）
  assert_failure
}

@test "ac1-count: echo output grep -qi パターンが 0 件であること（全 4 箇所置換済み）" {
  # AC: 旧パターンの残存件数が 0 であること
  # RED: 現在 4 件残存しているため count が 0 でなく FAIL する
  local count
  count=$(grep -cE 'echo[[:space:]]+"?\$\{output\}"?[[:space:]]*\|[[:space:]]*grep[[:space:]]+-qi' "${TARGET_BATS}" || true)
  [ "${count}" -eq 0 ]
}

@test "ac1-L157: L157 に echo \"\${output}\" | grep -qi パターンが存在しない" {
  # AC: 旧パターン（origin/main L157 に存在）が置換済みであること
  # 行番号は置換前の origin/main を基準とした歴史的マーカー（Issue body の L158 と 1 行ズレあり）
  # grep -n が L157 を返す場合は旧パターンが残存 → assert_failure が FAIL（RED）
  # 置換後は grep -n が空 → assert_failure が PASS（GREEN）
  run bash -c "grep -n 'echo.*output.*grep -qi' '${TARGET_BATS}' | grep -q '^157:'"
  assert_failure
}

@test "ac1-L289: L289 に echo \"\${output}\" | grep -qi パターンが存在しない" {
  # AC: 旧パターン（origin/main L289 に存在）が置換済みであること
  # 行番号は置換前の origin/main を基準とした歴史的マーカー（Issue body の L287 と 2 行ズレあり）
  run bash -c "grep -n 'echo.*output.*grep -qi' '${TARGET_BATS}' | grep -q '^289:'"
  assert_failure
}

@test "ac1-L354: L354 に echo \"\${output}\" | grep -qi パターンが存在しない" {
  # AC: 旧パターン（origin/main L354 に存在）が置換済みであること
  # 行番号は置換前の origin/main を基準とした歴史的マーカー（Issue body の L352 と 2 行ズレあり）
  run bash -c "grep -n 'echo.*output.*grep -qi' '${TARGET_BATS}' | grep -q '^354:'"
  assert_failure
}

@test "ac1-L526: L526 に echo \"\${output}\" | grep -qiE パターンが存在しない" {
  # AC: 旧パターン（origin/main L526 に存在）が置換済みであること
  # 行番号は置換前の origin/main を基準とした歴史的マーカー（Issue body の L524 と 2 行ズレあり）
  run bash -c "grep -n 'echo.*output.*grep -qiE' '${TARGET_BATS}' | grep -q '^526:'"
  assert_failure
}

# ===========================================================================
# AC2: 置換後も既存テストが pass すること（静的検証）
#
# AC2 は「assert_output --partial または run_*_pattern を使ったアサーションが
# 同数存在すること」を静的に確認する。
# 実際の動的 PASS は実装後の CI で確認する。
#
# このテストは AC2 の静的部分のみを確認し、GREEN になることを期待する。
# （動的部分は実装後の CI に委ねる）
# ===========================================================================

@test "ac2: assert_output --partial が session-id-uuid-validation.bats に存在する（置換後の確認）" {
  # AC: 置換後に assert_output --partial が使われていること（4箇所以上）
  # RED: 現在 assert_output --partial が 0 件のため grep が exit 1 → assert_success が FAIL する
  # GREEN: 4 箇所置換後に grep が exit 0 → assert_success が PASS する
  run grep -cF 'assert_output --partial' "${TARGET_BATS}"
  assert_success
}
