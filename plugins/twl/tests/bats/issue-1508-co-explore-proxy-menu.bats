#!/usr/bin/env bats
# issue-1508-co-explore-proxy-menu.bats
#
# RED-phase tests for Issue #1508:
#   bug(su-observer): co-explore proxy 対話 menu の検知漏れ
#     - su-observer SKILL.md に co-explore active 時の補助 polling 仕様追加（AC1）
#     - su-observer-supervise-channels.md に co-explore dedicated Monitor channel 追加（AC1/AC2）
#     - su-observer-controller-spawn-playbook.md の co-explore 行更新（AC3）
#     - record-detection-gap.sh --type proxy-stuck で observer-co-explore-gap タグ追加（AC4）
#     - bats test 追加（本ファイル・AC5）
#
# AC coverage:
#   AC1 - SKILL.md または su-observer-supervise-channels.md に co-explore active 時の
#         補助 polling 3-5 分間隔仕様が記述されている
#   AC2 - su-observer-supervise-channels.md に co-explore window の dedicated Monitor channel
#         (tail -F + grep wt-co-explore-) が追加されている
#   AC3 - su-observer-controller-spawn-playbook.md の co-explore 行に menu 連発型・SLA 60s・
#         自律完了型判別パターンが記述されている
#   AC4 - record-detection-gap.sh の --type proxy-stuck 実行時に
#         observer-co-explore-gap タグが出力に含まれる
#   AC5 - bats テスト自身が存在し、10 件以上のテストを含む（self-referential）
#
# 全テストは実装前（RED）状態で fail する（AC5 を除く）。
# AC5 のみ self-referential のため、このファイルが書き出された時点で GREEN になる。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  CHANNELS_MD="${REPO_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"
  PLAYBOOK_MD="${REPO_ROOT}/skills/su-observer/refs/su-observer-controller-spawn-playbook.md"
  RECORD_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/record-detection-gap.sh"
  THIS_BATS="${REPO_ROOT}/tests/bats/issue-1508-co-explore-proxy-menu.bats"

  export SKILL_MD CHANNELS_MD PLAYBOOK_MD RECORD_SCRIPT THIS_BATS
}

# ===========================================================================
# AC1: co-explore active 時の補助 polling 3-5 分間隔仕様化
# ===========================================================================

@test "ac1: SKILL.md or su-observer-supervise-channels.md contains co-explore polling interval spec (3-5 min)" {
  # AC: co-explore active 中の補助 polling が 3-5 分間隔で起動 MUST という仕様が存在する
  # RED: 仕様がまだ追加されていないため fail
  run bash -c "
    grep -qE '3.{0,5}5.*分|3-5.*min|3.*5.*minutes|3.*to.*5.*min' '${SKILL_MD}' || \
    grep -qE '3.{0,5}5.*分|3-5.*min|3.*5.*minutes|3.*to.*5.*min' '${CHANNELS_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: co-explore polling spec mentions auxiliary polling or supplemental monitor" {
  # AC: 補助 polling Monitor / auxiliary polling が明示されている
  # RED: 仕様がまだ追加されていないため fail
  run bash -c "
    grep -qE '補助.*polling|auxiliary.*poll|co-explore.*poll|poll.*co-explore' '${SKILL_MD}' || \
    grep -qE '補助.*polling|auxiliary.*poll|co-explore.*poll|poll.*co-explore' '${CHANNELS_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1: co-explore ScheduleWakeup cycle is independent from co-autopilot cycle" {
  # AC: ScheduleWakeup は co-autopilot cycle と独立に co-explore 用 cycle を持つことが明記されている
  # RED: 仕様がまだ追加されていないため fail
  run bash -c "
    grep -qE 'co-explore.*ScheduleWakeup|ScheduleWakeup.*co-explore|co-explore.*cycle|co-explore.*独立' '${SKILL_MD}' || \
    grep -qE 'co-explore.*ScheduleWakeup|ScheduleWakeup.*co-explore|co-explore.*cycle|co-explore.*独立' '${CHANNELS_MD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: co-explore 用 dedicated Monitor channel
# ===========================================================================

@test "ac2: su-observer-supervise-channels.md contains co-explore dedicated channel section" {
  # AC: co-explore window を対象とした dedicated channel の記述がある
  # RED: dedicated channel がまだ追加されていないため fail
  run grep -qE 'co-explore.*dedicated|dedicated.*co-explore|co-explore.*channel|co-explore.*Monitor' "${CHANNELS_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac2: su-observer-supervise-channels.md contains wt-co-explore- grep pattern" {
  # AC: wt-co-explore- を grep するパターンが channel 定義に含まれる
  # RED: パターンがまだ追加されていないため fail
  run grep -qF 'wt-co-explore-' "${CHANNELS_MD}"
  [ "${status}" -eq 0 ]
}

@test "ac2: su-observer-supervise-channels.md contains tail -F for co-explore window watch" {
  # AC: tail -F を使った co-explore window の高頻度 watch が記述されている
  # RED: 記述がまだ追加されていないため fail
  run bash -c "
    grep -qE 'tail.*-F.*co-explore|tail.*-F.*wt-co-explore' '${CHANNELS_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac2: su-observer-supervise-channels.md co-explore alert is described as immediate (即時)" {
  # AC: co-explore window の alert が即時（即時 alert / immediate）として記述されている
  # RED: 記述がまだ追加されていないため fail
  run bash -c "
    grep -qE '即時.*alert|alert.*即時|immediate.*alert|alert.*immediate' '${CHANNELS_MD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: su-observer-controller-spawn-playbook.md の co-explore 行更新
# ===========================================================================

@test "ac3: controller-spawn-playbook.md co-explore row mentions menu-heavy pattern" {
  # AC: co-explore テーブル行に「menu 連発型」または「4-5 menu/session」の記述がある
  # RED: 記述がまだ追加されていないため fail
  run bash -c "
    grep -qE 'menu.*連発|menu.*4.{0,3}5|4.{0,3}5.*menu|menu.*(session|セッション)' '${PLAYBOOK_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: controller-spawn-playbook.md co-explore row mentions SLA 60 seconds" {
  # AC: observer が menu 出現 ≤ 60s 以内に応答すべき SLA が明記されている
  # RED: 記述がまだ追加されていないため fail
  run bash -c "
    grep -qE '60s|60 s|60.*秒|SLA.*60|60.*SLA' '${PLAYBOOK_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: controller-spawn-playbook.md co-explore row mentions autonomous-completion detection pattern" {
  # AC: 自律完了型 co-explore の判別パターンが明記されている
  #     (例: "単一 summary" "menu なし判定" "single summary, no menu" など具体的な判別方法)
  # RED: 現在は「自律完了待ち」のみで判別パターンの詳細がないため fail
  run bash -c "
    grep -qE 'single.*summary.*no.*menu|no.*menu.*single.*summary|summary.*menu.*なし|menu.*なし.*summary|判別.*パターン.*no.*menu|単一.*summary.*menu.*なし' '${PLAYBOOK_MD}'
  "
  [ "${status}" -eq 0 ]
}

@test "ac3: controller-spawn-playbook.md co-explore section has SLA and menu pattern together" {
  # AC: menu 連発型 AND SLA 60s の両方が co-explore セクションに存在する
  # RED: 両方の記述がまだ追加されていないため fail
  run bash -c "
    grep -qE 'menu.*連発|menu.*4.{0,3}5|4.{0,3}5.*menu.*セッション' '${PLAYBOOK_MD}' && \
    grep -qE '60s|60 s|SLA.*60|60.*SLA' '${PLAYBOOK_MD}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: record-detection-gap.sh --type proxy-stuck で co-explore-specific tag 追加
# ===========================================================================

@test "ac4: record-detection-gap.sh exists and is executable" {
  # AC: スクリプトが存在し実行可能である
  # RED: スクリプト自体は既存だが tag 追加未実装のため後続テストが fail する
  [ -f "${RECORD_SCRIPT}" ]
  [ -x "${RECORD_SCRIPT}" ]
}

@test "ac4: record-detection-gap.sh --type proxy-stuck outputs observer-co-explore-gap tag" {
  # AC: --type proxy-stuck で実行すると observer-co-explore-gap タグが stderr hint に含まれる
  # RED: co-explore-specific tag がまだ追加されていないため fail
  local tmpdir
  tmpdir="$(mktemp -d)"
  run bash -c "
    SUPERVISOR_DIR='${tmpdir}/.supervisor' \
    bash '${RECORD_SCRIPT}' \
      --type proxy-stuck \
      --detail 'test-detection-gap' \
    2>&1 | grep -qF 'observer-co-explore-gap'
    status=\$?
    rm -rf '${tmpdir}'
    exit \$status
  "
  [ "${status}" -eq 0 ]
}

@test "ac4: record-detection-gap.sh --type proxy-stuck tag appears in tags list" {
  # AC: hint の tags: [...] 配列に observer-co-explore-gap が含まれる
  # RED: tag がまだ追加されていないため fail
  local tmpdir
  tmpdir="$(mktemp -d)"
  run bash -c "
    output=\$(SUPERVISOR_DIR='${tmpdir}/.supervisor' \
      bash '${RECORD_SCRIPT}' \
        --type proxy-stuck \
        --detail 'test-detection-gap' \
      2>&1)
    rm -rf '${tmpdir}'
    echo \"\$output\" | grep -qE 'tags:.*observer-co-explore-gap|observer-co-explore-gap.*tags'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: bats テスト自身が存在し、10 件以上のテストを含む（self-referential）
#
# 注記: このテストは self-referential である。本ファイル自体が存在し、
#       かつ 10 件以上の @test ブロックを含むことを検証する。
#       このファイルが書き出された時点で GREEN になる（他の AC と異なる）。
# ===========================================================================

@test "ac5: this bats test file exists at expected path" {
  # AC: bats ファイルが plugins/twl/tests/bats/issue-1508-co-explore-proxy-menu.bats として存在する
  # GREEN: このファイル自体が存在するため、実行時点では pass する
  [ -f "${THIS_BATS}" ]
}

@test "ac5: this bats test file contains at least 10 test blocks" {
  # AC: 本ファイルに 10 件以上の @test ブロックが含まれる
  # GREEN: このファイルが書き出された時点で pass する
  local count
  count="$(grep -c '^@test ' "${THIS_BATS}")"
  [ "${count}" -ge 10 ]
}
