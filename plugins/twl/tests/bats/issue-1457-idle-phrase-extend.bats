#!/usr/bin/env bats
# issue-1457-idle-phrase-extend.bats — Issue #1457 TDD RED フェーズ
#
# tech-debt(cld-observe-any): IDLE_COMPLETED_PHRASE_REGEX が idle 待機 phrase に未対応で AUTO_KILL 不発火
#
# AC coverage:
#   AC1 — 4件 idle 待機 phrase を IDLE_COMPLETED_PHRASE_REGEX に追加 + bats match 確認
#   AC2 — timeout-based fallback: IDLE_COMPLETED_TIMEOUT_SEC env で制御
#   AC3 — spawn prompt 規約を su-observer-controller-spawn-playbook.md に追加
#   AC4 — Wave 完遂シナリオ再現テスト (regex match / timeout / thinking の 3 ケース)
#
# 全テストは実装前（RED）状態で fail する。実装後に GREEN になる。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  OBSERVER_LIB="${REPO_ROOT}/skills/su-observer/scripts/lib/observer-idle-check.sh"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"
  SPAWN_PLAYBOOK="${REPO_ROOT}/skills/su-observer/refs/su-observer-controller-spawn-playbook.md"

  export OBSERVER_LIB CLD_OBSERVE_ANY SPAWN_PLAYBOOK

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: 4件 idle 待機 phrase が IDLE_COMPLETED_PHRASE_REGEX に追加される
# ===========================================================================

@test "ac1(#1457): IDLE_COMPLETED_PHRASE_REGEX contains 'observer.*(待機|休止|介入を待)' pattern" {
  # AC: "observer の次の指示を待機" 等の phrase を catch するパターンが追加される
  # RED: 現在の regex にこのパターンがないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    echo \"\${IDLE_COMPLETED_PHRASE_REGEX}\" | grep -qE 'observer.*(待機|休止|介入を待)'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): IDLE_COMPLETED_PHRASE_REGEX contains '次の.*Wave.*(指示|まで)' pattern" {
  # AC: "次の Wave 指示まで休止" 等の phrase を catch するパターンが追加される
  # RED: 現在の regex にこのパターンがないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    echo \"\${IDLE_COMPLETED_PHRASE_REGEX}\" | grep -qE '次の.*Wave.*(指示|まで)'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): IDLE_COMPLETED_PHRASE_REGEX matches 'Wave 50 完遂確認' phrase" {
  # AC: "Wave 50 完遂確認" 等の phrase を catch するパターンが追加される
  # RED: 現在の regex にこのパターンがないため fail
  # NOTE: "Wave [0-9]+ co-autopilot complete" は既存。"Wave N 完遂/完了" が未追加
  # NOTE: 構造テスト（regex文字列自体をgrep）は .* が | を跨いで false positive を生じる
  #       ため、サンプルフレーズで動作確認する
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    echo 'Wave 50 完遂確認' | grep -qE \"\${IDLE_COMPLETED_PHRASE_REGEX}\"
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): IDLE_COMPLETED_PHRASE_REGEX contains 'これ以上.*(処理|追加).*不要' pattern" {
  # AC: "これ以上の処理は不要" 等の phrase を catch するパターンが追加される
  # RED: 現在の regex にこのパターンがないため fail
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    echo \"\${IDLE_COMPLETED_PHRASE_REGEX}\" | grep -qE 'これ以上.*(処理|追加).*不要'
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): _check_idle_completed detects 'observer の次の指示を待機'" {
  # AC: 実際に Pilot が出す "observer の次の指示を待機" フレーズで idle と判定される
  # 出典: Wave 51 closing (doobidoo 926469a2)
  # RED: IDLE_COMPLETED_PHRASE_REGEX にパターンがないため return 1
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='Wave 51 の実装が完了しました。
observer の次の指示を待機しています。
> '
    _check_idle_completed \"\${pane_content}\" 100 161
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): _check_idle_completed detects '次の Wave 指示まで休止'" {
  # AC: "次の Wave 指示まで休止" フレーズで idle と判定される
  # 出典: Wave 50 closing (doobidoo dfc653b8)
  # RED: IDLE_COMPLETED_PHRASE_REGEX にパターンがないため return 1
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='全 Issue のマージが完了しました。
次の Wave 指示まで休止します。
> '
    _check_idle_completed \"\${pane_content}\" 100 161
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): _check_idle_completed detects 'Wave 50 完遂確認'" {
  # AC: "Wave 50 完遂確認" フレーズで idle と判定される
  # RED: IDLE_COMPLETED_PHRASE_REGEX にパターンがないため return 1
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='Wave 50 完遂確認 / Pilot session は idle 状態で待機
> '
    _check_idle_completed \"\${pane_content}\" 100 161
  "
  [ "${status}" -eq 0 ]
}

@test "ac1(#1457): _check_idle_completed detects 'observer の介入を待機'" {
  # AC: "observer の介入を待機" フレーズで idle と判定される
  # RED: IDLE_COMPLETED_PHRASE_REGEX にパターンがないため return 1
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane_content='全タスクが完了しました。observer の介入を待機しています。
> '
    _check_idle_completed \"\${pane_content}\" 100 161
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: timeout-based fallback — IDLE_COMPLETED_TIMEOUT_SEC env で制御
# ===========================================================================

@test "ac2(#1457): cld-observe-any references IDLE_COMPLETED_TIMEOUT_SEC env var" {
  # AC: cld-observe-any に IDLE_COMPLETED_TIMEOUT_SEC による timeout 判定が追加される
  # RED: 現在 IDLE_COMPLETED_TIMEOUT_SEC が cld-observe-any に存在しないため fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qE 'IDLE_COMPLETED_TIMEOUT_SEC' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac2(#1457): IDLE_COMPLETED_TIMEOUT_SEC default is 0 (disabled)" {
  # AC: デフォルト値 0 = 無効化（既存動作に影響しない）
  # RED: 変数が実装されていないため fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qE 'IDLE_COMPLETED_TIMEOUT_SEC.*:-.*0|IDLE_COMPLETED_TIMEOUT_SEC.*=.*0' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac2(#1457): observer-idle-check.sh or cld-observe-any handles timeout-based kill path" {
  # AC: phrase regex 非マッチ状態で IDLE_COMPLETED_TIMEOUT_SEC 秒経過後に auto-kill が発火する
  # RED: timeout パスが実装されていないため fail
  run bash -c "
    grep -qE 'IDLE_COMPLETED_TIMEOUT_SEC' '${CLD_OBSERVE_ANY}' && \
    grep -qE 'TIMEOUT|timeout.*kill|timeout.*auto.kill|TIMEOUT.*SEC' '${CLD_OBSERVE_ANY}'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC3: spawn prompt 規約を su-observer-controller-spawn-playbook.md に追加
# ===========================================================================

@test "ac3(#1457): su-observer-controller-spawn-playbook.md contains Wave completion output convention" {
  # AC: spawn prompt 規約として「Wave完了時は >>> Wave N 完遂: を必ず出力する」が追加される
  # RED: 現在 playbook にこの規約が存在しないため fail
  [ -f "${SPAWN_PLAYBOOK}" ]
  run grep -qE '>>> Wave|Wave.*完遂.*出力|完遂.*MUST|Wave.*完遂.*必須' "${SPAWN_PLAYBOOK}"
  [ "${status}" -eq 0 ]
}

@test "ac3(#1457): spawn-playbook Wave convention includes literal '>>> Wave N 完遂:' example" {
  # AC: spawn prompt 規約に実際の出力例 ">>> Wave N 完遂:" が記載される
  # RED: 現在記載がないため fail
  [ -f "${SPAWN_PLAYBOOK}" ]
  run grep -qF '>>> Wave' "${SPAWN_PLAYBOOK}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: Wave 完遂シナリオ再現テスト
# ===========================================================================

@test "ac4(#1457): scenario — regex match phrase 検出 → _check_idle_completed returns 0 after debounce" {
  # AC: 新 phrase "observer の次の指示を待機" を含む pane で debounce 経過後に 0 を返す
  # RED: 現在の regex にパターンがないため return 1
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane='Wave 51 の全 PR がマージされました。
observer の次の指示を待機中
> '
    # debounce 経過シミュレーション (first_seen=100, now=161, debounce=60)
    _check_idle_completed \"\$pane\" 100 161
  "
  [ "${status}" -eq 0 ]
}

@test "ac4(#1457): scenario — LLM thinking indicator あり → _check_idle_completed returns 1 (no kill)" {
  # AC: LLM が思考中（Brewing/Thinking）の場合は idle 判定しない
  # GREEN: この挙動は既実装（_check_idle_completed C3 条件）。regression として保全
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane='Brewing for 2m 30s · max effort
Wave 51 の次の指示を待機しています。'
    # first_seen=100, now=161: debounce 経過済みだが Brewing あり
    _check_idle_completed \"\$pane\" 100 161
  "
  [ "${status}" -ne 0 ]
}

@test "ac4(#1457): scenario — IDLE_COMPLETED_TIMEOUT_SEC=1800 で phrase なし + 経過 → auto-kill パス存在" {
  # AC: phrase regex 非マッチかつ IDLE_COMPLETED_TIMEOUT_SEC 秒経過でも auto-kill が発火する
  # RED: IDLE_COMPLETED_TIMEOUT_SEC が cld-observe-any に実装されていないため fail
  [ -f "${CLD_OBSERVE_ANY}" ]
  run grep -qE 'IDLE_COMPLETED_TIMEOUT_SEC' "${CLD_OBSERVE_ANY}"
  [ "${status}" -eq 0 ]
}

@test "ac4(#1457): scenario — 通常 phrase 'nothing pending' は引き続き match する (regression)" {
  # AC: 既存の regex パターンが新 phrase 追加後も動作することを確認
  # GREEN: 既実装のパターンが壊れていないことを確認する regression テスト
  [ -f "${OBSERVER_LIB}" ]
  run bash -c "
    source '${OBSERVER_LIB}'
    pane='Tasks completed.
nothing pending
> '
    _check_idle_completed \"\$pane\" 100 161
  "
  [ "${status}" -eq 0 ]
}
