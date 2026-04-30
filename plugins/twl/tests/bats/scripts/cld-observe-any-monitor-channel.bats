#!/usr/bin/env bats
# cld-observe-any-monitor-channel.bats
#
# Issue #1144: Tech-debt: observer cld-observe-any Monitor tool 連携経路
#
# AC coverage:
#   Doc-1 - monitor-channel-catalog.md に「Monitor tool 連携経路」セクションが存在する
#   Doc-2 - tee -a 起動例が catalog に記載されている
#   Doc-3 - 5 event grep パターンが catalog に記載されている
#   Doc-4 - Hybrid 検知ポリシー表に MENU-READY 行が追加されている
#   Doc-5 - SKILL.md に Monitor tool 連携経路へのリンクが存在する
#   C1    - MENU-READY イベントが logfile に append される（proxy assert）
#   C2    - --event-dir 指定時に MENU-READY-<win>-*.json が書き出される
#   C3    - --notify-dir は読み取り動作のみ（書き込みなし）
#   C4    - stdout text 形式が正規表現にヒットする
#   Pit-1 - pitfalls-catalog.md に §4.11 エントリが存在する
#
# 全テストは実装前（RED）状態で fail する。
# Doc-1〜5 と Pit-1 はドキュメントが未実装のため fail する。
# C1〜C4 は cld-observe-any + stub の組み合わせで動作を検証する。

load '../helpers/common'

# ===========================================================================
# Setup / Teardown
# ===========================================================================

setup() {
  common_setup

  # ファイルパス定数
  CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  PITFALLS="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  CLD_OBSERVE_ANY="${REPO_ROOT}/../session/scripts/cld-observe-any"
  export CATALOG SKILL_MD PITFALLS CLD_OBSERVE_ANY

  # logfile: C1 の append 確認用
  LOGFILE="${SANDBOX}/cld-observe-any.log"
  export LOGFILE

  # event_dir: C2 の .json 書き出し確認用
  EVENT_DIR="${SANDBOX}/events"
  mkdir -p "${EVENT_DIR}"
  export EVENT_DIR

  # notify_dir: C3 の 読み取り専用動作確認用
  NOTIFY_DIR="${SANDBOX}/notify"
  mkdir -p "${NOTIFY_DIR}"
  export NOTIFY_DIR

  # stub: tmux（MENU-READY 状態を再現）
  # list-windows は -F フラグの内容で出力形式を切り替える:
  #   -F '#{window_name}'                        → "test-win"
  #   -F '#{session_name}:#{window_index} ...'   → "test:0 test-win"
  stub_command "tmux" '
case "$1" in
  list-windows)
    # -F フォーマット引数に応じて出力を切り替える
    if echo "$*" | grep -q "session_name"; then
      # evaluate_window() 内の target 解決用: "session:index window_name" 形式
      echo "test:0 test-win"
    else
      # get_target_windows() 内の --pattern マッチ用: window_name のみ
      echo "test-win"
    fi
    exit 0 ;;
  display-message)
    # #{pane_dead} #{pane_current_command} 形式
    echo "0 bash"
    exit 0 ;;
  capture-pane)
    # MENU-READY トリガー: "Enter to select" を含む
    printf "Some output\nEnter to select\n"
    exit 0 ;;
  *)
    exit 0 ;;
esac
'

  # stub: session-state.sh（SCRIPT_DIR 経由で呼ばれる）
  cat > "${STUB_BIN}/session-state.sh" <<'STUB'
#!/usr/bin/env bash
echo "menu-ready"
exit 0
STUB
  chmod +x "${STUB_BIN}/session-state.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Doc-1: monitor-channel-catalog.md に「Monitor tool 連携経路」セクションが存在する
# ===========================================================================

@test "Doc-1: monitor-channel-catalog.md に Monitor tool 連携経路セクションが存在する" {
  # AC: grep -c "Monitor tool 連携経路" ... ≥ 1
  # RED: セクションがまだ追加されていないため fail
  [ -f "${CATALOG}" ]
  run grep -c "Monitor tool 連携経路" "${CATALOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# Doc-2: tee -a 起動例が catalog に記載されている
# ===========================================================================

@test "Doc-2: tee -a 起動例が monitor-channel-catalog.md に記載されている" {
  # AC: grep -c "tee -a .supervisor/cld-observe-any.log" ... ≥ 1
  # RED: 記載がまだないため fail
  [ -f "${CATALOG}" ]
  run grep -c "tee -a .supervisor/cld-observe-any.log" "${CATALOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# Doc-3: 5 event grep パターンが catalog に記載されている
# ===========================================================================

@test "Doc-3: 5 event grep パターンが Monitor tool 連携経路セクション内に記載されている" {
  # AC: Monitor tool 連携経路セクション内に MENU-READY/REVIEW-READY/FREEFORM-READY/BUDGET-LOW/STAGNATE- の
  #     5 パターン行が ≥5 件含まれる（既存の別セクションの記載は対象外）
  # RED: Monitor tool 連携経路セクション自体が未追加のため fail
  [ -f "${CATALOG}" ]
  # セクションが存在することを前提条件として確認
  run grep -c "Monitor tool 連携経路" "${CATALOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
  # セクション内（次の ## セクションまで）から5パターンを抽出
  run bash -c "
    awk '/Monitor tool 連携経路/,/^## /' '${CATALOG}' \
      | grep -cE '^\[MENU-READY\]|\[REVIEW-READY\]|\[FREEFORM-READY\]|\[BUDGET-LOW\]|\[STAGNATE-'
  "
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 5 ]
}

# ===========================================================================
# Doc-4: Hybrid 検知ポリシー表に MENU-READY 行が追加されている
# ===========================================================================

@test "Doc-4: Hybrid 検知ポリシー表に MENU-READY 行と cld-observe-any.log が追加されている" {
  # AC: grep -c "MENU-READY-\*\.json\|cld-observe-any\.log" ... ≥ 2
  # RED: 行がまだ追加されていないため fail
  [ -f "${CATALOG}" ]
  run grep -cE 'MENU-READY-\*\.json|cld-observe-any\.log' "${CATALOG}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 2 ]
}

# ===========================================================================
# Doc-5: SKILL.md に Monitor tool 連携経路へのリンクが存在する
# ===========================================================================

@test "Doc-5: SKILL.md に Monitor tool 連携経路リンクが存在する" {
  # AC: grep -c "Monitor tool 連携経路\|cld-observe-any.*Monitor tool" SKILL.md ≥ 1
  # RED: リンクがまだ追加されていないため fail
  [ -f "${SKILL_MD}" ]
  run grep -cE 'Monitor tool 連携経路|cld-observe-any.*Monitor tool' "${SKILL_MD}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# Pit-1: pitfalls-catalog.md に §4.11 エントリが存在する
# ===========================================================================

@test "Pit-1: pitfalls-catalog.md に §4.11 エントリが存在する" {
  # AC: grep -c "^#### §4.11 " pitfalls-catalog.md ≥ 1
  # RED: エントリがまだ追加されていないため fail
  [ -f "${PITFALLS}" ]
  run grep -c "^#### §4.11 " "${PITFALLS}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# C1: proxy assert（MENU-READY → logfile append）
# ===========================================================================

@test "C1: MENU-READY 状態の pane を監視すると logfile に [MENU-READY] 行が append される" {
  # AC: MENU-READY 状態の stub pane → --once 実行 → logfile に ^\[MENU-READY\]  行
  # RED: cld-observe-any の MENU-READY 検知 + tee 連携が未実装のため fail
  [ -f "${CLD_OBSERVE_ANY}" ]

  # log_age >= 30 を満たすため LOG_DIR を空のまま（999 を返す）
  run bash -c "
    set -euo pipefail
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    export CLD_OBSERVE_ANY_SCRIPT_DIR='${STUB_BIN}'
    # stdout を logfile に tee -a（Monitor tool 連携経路の起動例と同形式）
    bash '${CLD_OBSERVE_ANY}' --window test-win --once 2>/dev/null \
      | tee -a '${LOGFILE}'
  "
  [ "${status}" -eq 0 ]

  # logfile に [MENU-READY] 行が書き込まれていること
  [ -f "${LOGFILE}" ]
  run grep -cE '^\[MENU-READY\] ' "${LOGFILE}"
  [ "${status}" -eq 0 ]
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# C2: --event-dir → MENU-READY-<win>-*.json が書き出される
# ===========================================================================

@test "C2: --event-dir 指定時に MENU-READY-<win>-*.json が書き出される" {
  # AC: --event-dir 指定 → EVENT_DIR に MENU-READY-<win>-*.json が存在する
  # RED: event-dir 書き出しロジックが MENU-READY イベントに対応していないため fail
  [ -f "${CLD_OBSERVE_ANY}" ]

  run bash -c "
    set -euo pipefail
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    export CLD_OBSERVE_ANY_SCRIPT_DIR='${STUB_BIN}'
    bash '${CLD_OBSERVE_ANY}' --window test-win --once \
      --event-dir '${EVENT_DIR}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]

  # MENU-READY-test-win-*.json が存在すること
  run bash -c "ls '${EVENT_DIR}'/MENU-READY-test-win-*.json 2>/dev/null | wc -l"
  [ "${output}" -ge 1 ]
}

# ===========================================================================
# C3: --notify-dir は読み取り動作のみ（書き込みしない）
# ===========================================================================

@test "C3: --notify-dir は読み取り動作のみ（cld-observe-loop 互換の通知ファイル書き込みをしない）" {
  # AC: --notify-dir 指定時、cld-observe-loop 互換の読み取り専用動作のみを assert する
  #     具体的には: notify_dir への新規ファイル作成と既存ファイルの更新（.seen フラグ設定等）が発生しない
  # RED: AC として「notify_dir への seen フラグ書き戻し実装がないこと」を検証。
  #      cld-observe-any が notify_dir に attention ファイルを書き込まない（読み取り専用）ことを
  #      「attention ファイルを生成した後、seen が true に書き換わらない」で確認する。
  #      この動作確認は実装が正しく「書き込まない」ことを保証するため fail を期待する。
  [ -f "${CLD_OBSERVE_ANY}" ]

  # attention ファイルを事前に配置（seen = false）
  cat > "${NOTIFY_DIR}/test-win:test.json" <<'JSON'
{"state":"attention","seen":false,"ts":1234567890}
JSON

  run bash -c "
    set -euo pipefail
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    export CLD_OBSERVE_ANY_SCRIPT_DIR='${STUB_BIN}'
    bash '${CLD_OBSERVE_ANY}' --window test-win --once \
      --notify-dir '${NOTIFY_DIR}' 2>/dev/null
  "
  [ "${status}" -eq 0 ]

  # seen フラグが書き換えられていないこと（読み取り専用）
  # ファイルが存在し、seen が依然 false のままであること
  [ -f "${NOTIFY_DIR}/test-win:test.json" ]
  run bash -c "jq -r '.seen' '${NOTIFY_DIR}/test-win:test.json'"
  [ "${status}" -eq 0 ]
  # seen は false のまま（cld-observe-any は seen を書き換えない）
  [ "${output}" = "false" ]

  # また notify_dir に新規ファイルが作成されていないこと
  local file_count
  file_count=$(find "${NOTIFY_DIR}" -maxdepth 1 -type f | wc -l)
  # 元の attention ファイル 1 つのみ（新規追加なし）
  [ "${file_count}" -eq 1 ]
}

# ===========================================================================
# C4: stdout text 形式確認
# ===========================================================================

@test "C4: stdout の text 形式行が [MENU-READY] HH:MM:SS window= 形式にヒットする" {
  # AC: stdout に "^\[MENU-READY\] [0-9]{2}:[0-9]{2}:[0-9]{2} window=" が存在する
  # RED: text フォーマット出力が仕様形式に適合していないため fail
  [ -f "${CLD_OBSERVE_ANY}" ]

  run bash -c "
    set -euo pipefail
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    export CLD_OBSERVE_ANY_SCRIPT_DIR='${STUB_BIN}'
    bash '${CLD_OBSERVE_ANY}' --window test-win --once 2>/dev/null
  "
  [ "${status}" -eq 0 ]

  # stdout に text 形式の [MENU-READY] 行が含まれること
  echo "${output}" | grep -qE '^\[MENU-READY\] [0-9]{2}:[0-9]{2}:[0-9]{2} window='
}
