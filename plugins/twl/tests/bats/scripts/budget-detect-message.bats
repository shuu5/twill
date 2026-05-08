#!/usr/bin/env bats
# budget-detect-message.bats - TDD RED phase tests for Issue #1577 AC5 / AC8-b
#
# AC5: BUDGET-LOW メッセージに「reset 後 5h budget 100% 完全回復」disambiguator を追加
#
# 検証方針:
#   - budget-detect.sh の停止メッセージ（stdout）に 2 つの disambiguator が含まれることを確認
#     (a) "100%" — 回復率の明示
#     (b) "完全回復" — 回復内容の明示
#   - static grep でスクリプト内のメッセージ定数を確認
#   - 実行時 stdout で確認
#
# 背景:
#   現在の停止メッセージ (L90 in budget-detect.sh):
#     "[BUDGET-LOW] 5h budget: token残量 ${BUDGET_REMAINING_MIN:-?}分 (${BUDGET_PCT:-?}% 消費),
#      cycle reset まで ${BUDGET_CYCLE_MIN:-?}分。安全停止シーケンスを開始します。"
#   → "100%" も "完全回復" も含まれていない
#
# RED: 全テストは実装前の状態で fail する

load '../helpers/common'

setup() {
  common_setup

  BUDGET_DETECT_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/budget-detect.sh"
  export BUDGET_DETECT_SCRIPT

  # tmux スタブ: BUDGET-LOW 発動用 — 軸1発動（88% 消費、cycle 30m で軸2不発）
  stub_command "tmux" '
args=("$@")
if [[ "${args[0]}" == "capture-pane" ]]; then
  echo "5h:88%(2h00m)"
elif [[ "${args[0]}" == "list-windows" ]]; then
  echo ""
elif [[ "${args[0]}" == "send-keys" ]]; then
  exit 0
else
  exit 0
fi
'
  mkdir -p "${SANDBOX}/.supervisor"
  export PILOT_WINDOW="test-pilot-window"
  export AUTOPILOT_DIR="${SANDBOX}/.autopilot"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC5: budget-detect.sh メッセージに 100% disambiguator の static grep
# RED: 現時点のメッセージに "100%" が存在しないため fail する
# ===========================================================================

@test "ac5: budget-detect.sh の停止メッセージソースに '100%' が含まれる（static grep）" {
  # AC: BUDGET-LOW メッセージに「reset 後 5h budget 100% 完全回復」disambiguator を追加
  # RED: 実装前は fail する — 現在の echo メッセージに "100%" が存在しない
  grep -qE 'BUDGET-LOW.*100%|100%.*完全回復|完全回復.*100%' "${BUDGET_DETECT_SCRIPT}"
}

@test "ac5: budget-detect.sh の停止メッセージソースに '完全回復' が含まれる（static grep）" {
  # AC: BUDGET-LOW メッセージに「完全回復」disambiguator を追加
  # RED: 実装前は fail する — 現在の echo メッセージに "完全回復" が存在しない
  grep -qF '完全回復' "${BUDGET_DETECT_SCRIPT}"
}

@test "ac5: budget-detect.sh の停止メッセージソースに 'reset 後 5h budget' フレーズが含まれる（static grep）" {
  # AC: BUDGET-LOW メッセージに「reset 後 5h budget」の文脈説明を追加
  # RED: 実装前は fail する — 現在のメッセージに当該フレーズが存在しない
  grep -qF 'reset 後 5h budget' "${BUDGET_DETECT_SCRIPT}"
}

# ===========================================================================
# AC5: budget-detect.sh 実行時 stdout に disambiguator が含まれる（runtime check）
# RED: 実行時の stdout メッセージに 2 つの disambiguator が含まれないため fail する
# ===========================================================================

@test "ac5: budget-detect.sh 実行時 stdout に '100%' 回復 disambiguator が含まれる" {
  # AC: 実行時に出力される BUDGET-LOW メッセージに "100%" が含まれること
  # RED: 実装前は fail する — stdout の "安全停止シーケンスを開始します" に "100%" が含まれない
  run bash -c "
    export PILOT_WINDOW='test-pilot-window'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    mkdir -p '${SANDBOX}/.supervisor'
    cd '${SANDBOX}'
    bash '${BUDGET_DETECT_SCRIPT}' 2>/dev/null
  "
  # exit code 1 = BUDGET-LOW 発動 (正常)、stdout に disambiguator があること
  echo "$output" | grep -qF '100%' || {
    echo "stdout に '100%' が含まれない。実際の出力:"
    echo "$output"
    return 1
  }
}

@test "ac5: budget-detect.sh 実行時 stdout に '完全回復' disambiguator が含まれる" {
  # AC: 実行時に出力される BUDGET-LOW メッセージに "完全回復" が含まれること
  # RED: 実装前は fail する
  run bash -c "
    export PILOT_WINDOW='test-pilot-window'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    mkdir -p '${SANDBOX}/.supervisor'
    cd '${SANDBOX}'
    bash '${BUDGET_DETECT_SCRIPT}' 2>/dev/null
  "
  echo "$output" | grep -qF '完全回復' || {
    echo "stdout に '完全回復' が含まれない。実際の出力:"
    echo "$output"
    return 1
  }
}
