#!/usr/bin/env bats
# budget-pause-schema.bats - TDD RED phase tests for Issue #1577 AC8-a
#
# AC3: plugins/twl/skills/su-observer/scripts/budget-detect.sh で
#      budget-pause.json schema を拡張
#      追加フィールド: cycle_reset_minutes_at_pause / expected_reset_at / auto_resume_via
#
# 検証方針:
#   - budget-detect.sh の静的 grep で新フィールドの書き込みコードが存在することを確認
#   - budget-detect.sh を実行して実際に生成される budget-pause.json の内容を確認
#
# RED: 全テストは実装前の状態で fail する
#      現時点で budget-detect.sh は上記 3 フィールドを書き込まない

load '../helpers/common'

setup() {
  common_setup

  BUDGET_DETECT_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/budget-detect.sh"
  export BUDGET_DETECT_SCRIPT

  # tmux スタブ: BUDGET-LOW 発動用の status line を返す（消費率 88%、cycle 3m）
  # 軸2（cycle）発動 → alert=true → budget-pause.json を書き出す
  stub_command "tmux" '
args=("$@")
if [[ "${args[0]}" == "capture-pane" ]]; then
  echo "5h:88%(0h03m)"
elif [[ "${args[0]}" == "list-windows" ]]; then
  echo ""
elif [[ "${args[0]}" == "send-keys" ]]; then
  exit 0
else
  exit 0
fi
'
  # python3 はリアルを使用（json 書き込みが必要なため）
  # .supervisor ディレクトリを sandbox 内に作成
  mkdir -p "${SANDBOX}/.supervisor"

  # PILOT_WINDOW を設定（budget-detect.sh の必須パラメータ）
  export PILOT_WINDOW="test-pilot-window"
  export AUTOPILOT_DIR="${SANDBOX}/.autopilot"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC3: budget-detect.sh に新フィールド書き込みコードが存在する（static grep）
# RED: 現時点では 3 フィールドが budget-detect.sh に存在しないため fail する
# ===========================================================================

@test "ac3: budget-detect.sh に cycle_reset_minutes_at_pause フィールドの書き込みコードが存在する" {
  # AC: budget-pause.json schema に cycle_reset_minutes_at_pause を追加
  # RED: 実装前は fail する — budget-detect.sh に cycle_reset_minutes_at_pause が存在しない
  grep -qF 'cycle_reset_minutes_at_pause' "${BUDGET_DETECT_SCRIPT}"
}

@test "ac3: budget-detect.sh に expected_reset_at フィールドの書き込みコードが存在する" {
  # AC: budget-pause.json schema に expected_reset_at を追加
  # RED: 実装前は fail する — budget-detect.sh に expected_reset_at が存在しない
  grep -qF 'expected_reset_at' "${BUDGET_DETECT_SCRIPT}"
}

@test "ac3: budget-detect.sh に auto_resume_via フィールドの書き込みコードが存在する" {
  # AC: budget-pause.json schema に auto_resume_via を追加
  # RED: 実装前は fail する — budget-detect.sh に auto_resume_via が存在しない
  grep -qF 'auto_resume_via' "${BUDGET_DETECT_SCRIPT}"
}

# ===========================================================================
# AC3: budget-detect.sh を実行して budget-pause.json に新フィールドが含まれる
# RED: 実行後に生成される budget-pause.json に 3 フィールドが存在しないため fail する
# ===========================================================================

@test "ac3: budget-detect.sh 実行後に budget-pause.json が cycle_reset_minutes_at_pause を含む" {
  # AC: budget-pause.json に cycle_reset_minutes_at_pause が書き込まれること
  # RED: 実装前は fail する — 生成される budget-pause.json に当該フィールドが存在しない
  local pause_json="${SANDBOX}/.supervisor/budget-pause.json"

  # budget-detect.sh は PILOT_WINDOW を要求し、tmux capture-pane の返値を使う
  # AUTOPILOT_DIR を sandbox 内に向けて budget-pause.json の書き込み先を制御する
  run bash -c "
    export PILOT_WINDOW='test-pilot-window'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    mkdir -p '${SANDBOX}/.supervisor'
    cd '${SANDBOX}'
    bash '${BUDGET_DETECT_SCRIPT}' 2>/dev/null || true
  "
  # budget-pause.json が生成されていることを確認
  [ -f "${SANDBOX}/.supervisor/budget-pause.json" ] || {
    echo "budget-pause.json が生成されなかった"
    return 1
  }
  grep -qF 'cycle_reset_minutes_at_pause' "${SANDBOX}/.supervisor/budget-pause.json"
}

@test "ac3: budget-detect.sh 実行後に budget-pause.json が expected_reset_at を含む" {
  # AC: budget-pause.json に expected_reset_at が書き込まれること
  # RED: 実装前は fail する
  local pause_json="${SANDBOX}/.supervisor/budget-pause.json"

  run bash -c "
    export PILOT_WINDOW='test-pilot-window'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    mkdir -p '${SANDBOX}/.supervisor'
    cd '${SANDBOX}'
    bash '${BUDGET_DETECT_SCRIPT}' 2>/dev/null || true
  "
  [ -f "${SANDBOX}/.supervisor/budget-pause.json" ] || {
    echo "budget-pause.json が生成されなかった"
    return 1
  }
  grep -qF 'expected_reset_at' "${SANDBOX}/.supervisor/budget-pause.json"
}

@test "ac3: budget-detect.sh 実行後に budget-pause.json が auto_resume_via を含む" {
  # AC: budget-pause.json に auto_resume_via が書き込まれること
  # RED: 実装前は fail する
  local pause_json="${SANDBOX}/.supervisor/budget-pause.json"

  run bash -c "
    export PILOT_WINDOW='test-pilot-window'
    export AUTOPILOT_DIR='${SANDBOX}/.autopilot'
    mkdir -p '${SANDBOX}/.supervisor'
    cd '${SANDBOX}'
    bash '${BUDGET_DETECT_SCRIPT}' 2>/dev/null || true
  "
  [ -f "${SANDBOX}/.supervisor/budget-pause.json" ] || {
    echo "budget-pause.json が生成されなかった"
    return 1
  }
  grep -qF 'auto_resume_via' "${SANDBOX}/.supervisor/budget-pause.json"
}
