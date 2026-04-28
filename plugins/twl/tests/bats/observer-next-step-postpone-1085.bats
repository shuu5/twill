#!/usr/bin/env bats
# observer-next-step-postpone-1085.bats
#
# RED-phase tests for Issue #1085:
#   Tech-debt: Observer Pilot next-step postpone 判断 error
#
# AC coverage:
#   AC1 - pitfalls-catalog.md §15 節の追加
#   AC2 - su-observer-wave-management.md / SKILL.md の postpone MUST 規約追加
#   AC3 - pilot-completion-signals.md への .explore/<N>/summary.md 検知エントリ追加
#   AC4 - monitor-channel-catalog.md への co-explore 完遂 Layer 0 Auto エントリ追加
#   AC5 - mock Wave による next-step spawn 検証（functional）
#   AC6 - su-observer-supervise-channels.md / SKILL.md の heartbeat self-update 除外規約追加
#
# 全テストは実装前（RED）状態で fail する。

setup() {
  local this_dir
  this_dir="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  local tests_dir
  tests_dir="$(cd "${this_dir}/.." && pwd)"
  REPO_ROOT="$(cd "${tests_dir}/.." && pwd)"
  export REPO_ROOT

  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  WAVE_MANAGEMENT="${REPO_ROOT}/skills/su-observer/refs/su-observer-wave-management.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  PILOT_COMPLETION="${REPO_ROOT}/skills/su-observer/refs/pilot-completion-signals.md"
  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  SUPERVISE_CHANNELS="${REPO_ROOT}/skills/su-observer/refs/su-observer-supervise-channels.md"

  export PITFALLS_CATALOG WAVE_MANAGEMENT SKILL_MD PILOT_COMPLETION MONITOR_CATALOG SUPERVISE_CHANNELS

  TMPDIR_TEST="$(mktemp -d)"
  export TMPDIR_TEST
}

teardown() {
  rm -rf "${TMPDIR_TEST}"
}

# ===========================================================================
# AC1: pitfalls-catalog.md に §15 節が存在する
#
# §15「Pilot/co-explore 完遂後の next-step postpone 判断 error」を追加し、
# §11「Observer idle 中の session disconnect 対策」とのクロスリファレンスを記載
# ===========================================================================

@test "ac1: pitfalls-catalog.md has §15 section heading" {
  # AC: pitfalls-catalog.md に §15「Pilot/co-explore 完遂後の next-step postpone 判断 error」節が存在する
  # RED: 実装前は §15 節が存在しないため fail
  run grep -E "^## 15\." "${PITFALLS_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac1: pitfalls-catalog §15 contains cross-reference to §11" {
  # AC: §15 が §11「Observer idle 中の session disconnect 対策」へのクロスリファレンスを含む
  # RED: 実装前はクロスリファレンスが存在しないため fail
  run grep -n "§11" "${PITFALLS_CATALOG}"
  [ "${status}" -eq 0 ]
  # §15 節の範囲内に §11 参照があることを確認（§15 以降のコンテンツ内）
  local section15_line
  section15_line="$(grep -n "^## 15\." "${PITFALLS_CATALOG}" | cut -d: -f1)"
  local ref11_line
  ref11_line="$(grep -n "§11" "${PITFALLS_CATALOG}" | tail -1 | cut -d: -f1)"
  [ -n "${section15_line}" ]
  [ -n "${ref11_line}" ]
  [ "${ref11_line}" -gt "${section15_line}" ]
}

@test "ac1: pitfalls-catalog §15 mentions next-step postpone error pattern" {
  # AC: §15 本文が postpone 判断 error の regression check パターンを含む
  # RED: 実装前は本文が存在しないため fail
  run grep -iE "postpone|next.step|完遂後" "${PITFALLS_CATALOG}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC2: MUST 規約「Pilot/co-explore 完遂検知 → 即時 next-step 自律 spawn」
#
# su-observer-wave-management.md または SKILL.md に記載
# ===========================================================================

@test "ac2: wave-management or SKILL.md has MUST rule for immediate next-step after completion" {
  # AC: 「Pilot/co-explore 完遂検知 → 即時 next-step 自律 spawn（postpone は user 明示指示時のみ）」の MUST 規約
  # RED: 実装前は規約が存在しないため fail
  run bash -c "grep -lE 'MUST' '${WAVE_MANAGEMENT}' '${SKILL_MD}' | xargs grep -lE 'postpone' 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac2: next-step spawn rule specifies user-explicit-only postpone exception" {
  # AC: postpone が user 明示指示時のみであることが明記される
  # RED: 実装前は記載なしのため fail
  run bash -c "grep -rE 'postpone.*(user|明示|explicit)|(user|明示|explicit).*postpone' '${WAVE_MANAGEMENT}' '${SKILL_MD}' 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC3: pilot-completion-signals.md に .explore/<N>/summary.md 検知エントリ追加
# ===========================================================================

@test "ac3: pilot-completion-signals.md has explore summary.md detection entry" {
  # AC: .explore/<N>/summary.md 生成検知が co-explore 完遂用に定義される
  # RED: 実装前はエントリが存在しないため fail
  run grep -E "\.explore|explore.*summary|summary\.md" "${PILOT_COMPLETION}"
  [ "${status}" -eq 0 ]
}

@test "ac3: pilot-completion-signals.md explore entry is co-explore completion signal" {
  # AC: explore/summary パターンが co-explore 完遂を示すシグナルとして定義される
  # RED: 実装前は co-explore 完遂用の記述がないため fail
  run grep -iE "co.explore.*完遂|完遂.*co.explore|co-explore.*completion|completion.*co-explore" "${PILOT_COMPLETION}"
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC4: monitor-channel-catalog.md に co-explore 完遂 Layer 0 Auto エントリ
# ===========================================================================

@test "ac4: monitor-channel-catalog.md has co-explore completion channel entry" {
  # AC: co-explore 完遂チャンネルが monitor-channel-catalog.md に Layer 0 Auto として codify される
  # RED: 実装前は co-explore 完遂エントリが存在しないため fail
  run grep -iE "co.explore.*完遂|完遂.*co.explore|EXPLORE.*COMPLETE|co-explore.*summary" "${MONITOR_CATALOG}"
  [ "${status}" -eq 0 ]
}

@test "ac4: monitor-channel-catalog.md co-explore entry is Layer 0 Auto" {
  # AC: co-explore 完遂チャンネルが Layer 0 Auto パターンとして分類される
  # RED: 実装前は Layer 0 Auto 分類が存在しないため fail
  # co-explore 完遂エントリと「Auto」の両方が同一行または近傍に存在することを確認
  run bash -c "
    file='${MONITOR_CATALOG}'
    # co-explore 完遂エントリの行番号を取得
    entry_line=\"\$(grep -niE 'co.explore.*完遂|EXPLORE.*COMPLETE|co-explore.*summary' \"\${file}\" | head -1 | cut -d: -f1)\"
    [ -n \"\${entry_line}\" ] || exit 1
    # その前後5行に Auto が含まれることを確認
    start=\$(( entry_line > 5 ? entry_line - 5 : 1 ))
    end=\$(( entry_line + 5 ))
    sed -n \"\${start},\${end}p\" \"\${file}\" | grep -qE 'Auto|Layer 0'
  "
  [ "${status}" -eq 0 ]
}

# ===========================================================================
# AC5: mock Wave functional test
#   .explore/test-phase2/summary.md を作成後、
#   observer が next-step spawn 判定を返すことを検証
# ===========================================================================

@test "ac5: observer detects co-explore completion via summary.md creation" {
  # AC: mock Wave - .explore/<N>/summary.md 作成 → observer が next-step spawn 判定を返す
  # RED: 実装前は判定スクリプトが存在しないため fail

  # mock explore ディレクトリと summary.md を作成
  local mock_wave_dir="${TMPDIR_TEST}/mock-wave"
  mkdir -p "${mock_wave_dir}/.explore/test-phase2"
  echo "# Phase 2 Summary" > "${mock_wave_dir}/.explore/test-phase2/summary.md"
  echo "Phase 2 complete" >> "${mock_wave_dir}/.explore/test-phase2/summary.md"

  # observer の co-explore 完遂判定スクリプトが存在することを確認
  local detect_script="${REPO_ROOT}/skills/su-observer/scripts/detect-explore-completion.sh"
  [ -f "${detect_script}" ]
  [ -x "${detect_script}" ]

  # スクリプトを実行し、next-step spawn 判定を得る
  run bash "${detect_script}" --wave-dir "${mock_wave_dir}" --phase "test-phase2"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"SPAWN_NEXT_STEP"* ]] || [[ "${output}" == *"next-step"* ]]
}

@test "ac5: observer next-step spawn decision triggers within 5 minutes of phase completion" {
  # AC: Phase 2 完遂後 observer が next-step を 5 分以内に spawn する規約が定義される
  # RED: 実装前は next-step spawn タイムアウト規約の記述が存在しないため fail
  # NOTE: 既存の BUDGET-LOW "5分" とは区別し、next-step spawn に特化したパターンで検証
  run bash -c "grep -rE 'next.step.*5.*(分|min)|5.*(分|min).*next.step|spawn.*next.step.*5|完遂.*5.*(分|min).*spawn' \
    '${WAVE_MANAGEMENT}' '${SKILL_MD}' 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

# ===========================================================================
# AC6: heartbeat self-update は silence reset の対象外
#
# su-observer-supervise-channels.md または SKILL.md に記載
# ===========================================================================

@test "ac6: supervise-channels or SKILL.md has heartbeat self-update exclusion rule" {
  # AC: observer 自身の heartbeat 更新は silence 検知の reset 対象外であることの規約
  # RED: 実装前は除外規約が存在しないため fail
  run bash -c "grep -rE 'heartbeat.*(自身|self|observer).*(対象外|除外|exclude|reset 対象外)|(対象外|除外|exclude).*(heartbeat|self.update)' \
    '${SUPERVISE_CHANNELS}' '${SKILL_MD}' 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}

@test "ac6: supervise-channels or SKILL.md mandates active capture polling (Monitor task) for Pilot watch" {
  # AC: Pilot 監視時に能動 capture polling (Monitor task) を MUST 起動する規約
  # RED: 実装前は Monitor task MUST 規約が存在しないため fail
  run bash -c "grep -rE 'Monitor task|能動.*capture.*poll|capture.*poll.*Monitor|MUST.*Monitor task|Monitor task.*MUST' \
    '${SUPERVISE_CHANNELS}' '${SKILL_MD}' 2>/dev/null"
  [ "${status}" -eq 0 ]
  [ -n "${output}" ]
}
