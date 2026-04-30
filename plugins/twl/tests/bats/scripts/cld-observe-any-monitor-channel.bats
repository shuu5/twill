#!/usr/bin/env bats
# cld-observe-any-monitor-channel.bats - Issue #1144 AC2-AC16 RED テスト
#
# Issue #1144: Tech-debt: observer cld-observe-any Monitor tool 連携経路の明文化
#
# AC coverage:
#   AC2  - monitor-channel-catalog.md に「Monitor tool 連携経路」セクション新設
#   AC3  - tee -a .supervisor/cld-observe-any.log 起動例の記載
#   AC4  - [MENU-READY]/[REVIEW-READY]/[FREEFORM-READY]/[BUDGET-LOW]/[STAGNATE-N] grep パターン記載
#   AC5  - Hybrid 検知ポリシー表の MENU-READY/REVIEW-READY/FREEFORM-READY 行追加
#   AC6  - SKILL.md Step 1 に catalog セクションへのリンクと SHOULD 注記追記
#   AC7  - bats C1: 模擬 logfile append → 1 秒以内に [MENU-READY] 行が append される
#   AC8  - bats C2: --event-dir 指定時に MENU-READY-<win>-*.json が生成される
#   AC9  - bats C3: --notify-dir 指定時はディレクトリへの書き込みが発生しない
#   AC10 - bats C4: stdout text 形式の行が grep でヒットする
#   AC11 - bats 全 PASS（実装後の GREEN 確認、scaffold 時点では RED で可）
#   AC12 - pitfalls-catalog.md に §4.11 新エントリ追加
#   AC13 - §4.11 に 3 経路意味論差・方式 A 参照・方式 A 運用上の懸念（4 項目）記載
#   AC14 - §4.11 に本 Issue 事象（2026-04-29 22:57 〜 2026-04-30 02:39）記録
#   AC15 - grep 結果記録（プロセス AC）
#   AC16 - 不整合対応判定（プロセス AC）
#
# RED: 全テストは実装前の状態で fail する。
#      AC2-AC6, AC12-AC14 は docs 未更新のため fail。
#      AC7-AC10 は cld-observe-any の logfile redirect / --once 動作確認。
#
# テストフレームワーク: bats-core（bats-support + bats-assert）

load '../helpers/common'

MONITOR_CATALOG=""
PITFALLS_CATALOG=""
SKILL_MD=""
CLD_OBSERVE_ANY=""

setup() {
  common_setup
  MONITOR_CATALOG="${REPO_ROOT}/skills/su-observer/refs/monitor-channel-catalog.md"
  PITFALLS_CATALOG="${REPO_ROOT}/skills/su-observer/refs/pitfalls-catalog.md"
  SKILL_MD="${REPO_ROOT}/skills/su-observer/SKILL.md"
  # cld-observe-any は plugins/session 配下
  # REPO_ROOT = plugins/twl → ../../plugins/session/scripts/cld-observe-any
  CLD_OBSERVE_ANY="$(cd "${REPO_ROOT}/../.." && pwd)/plugins/session/scripts/cld-observe-any"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: 方式選定（プロセス AC — 本 Issue では選定のみ、bats 検証対象外）
# ===========================================================================
# AC1 は「方式 A 採用の選定」のみで実装を伴わない。
# docs 系 AC（AC2〜AC6 等）の内容が存在することで間接的に確認する。

# ===========================================================================
# AC2: monitor-channel-catalog.md — 「Monitor tool 連携経路」セクション新設
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: monitor-channel-catalog.md を grep する
# THEN: "Monitor tool 連携経路" の見出しが 1 件以上存在する
# ---------------------------------------------------------------------------

@test "AC2: monitor-channel-catalog.md に「Monitor tool 連携経路」セクションが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  local count
  count=$(grep -c "Monitor tool 連携経路" "$MONITOR_CATALOG" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]] \
    || fail "monitor-channel-catalog.md に「Monitor tool 連携経路」セクションが存在しない（AC2 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: monitor-channel-catalog.md を grep する
# THEN: "方式 A" または "共有 logfile tail" への言及が存在する
# ---------------------------------------------------------------------------

@test "AC2: monitor-channel-catalog.md に「方式 A: 共有 logfile tail」への言及が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "方式 A|共有 logfile tail|logfile.*tail|tail.*logfile" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に「方式 A: 共有 logfile tail」への言及がない（AC2 未実装）"
}

# ===========================================================================
# AC3: monitor-channel-catalog.md — tee -a スニペット記載
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: monitor-channel-catalog.md を grep する
# THEN: "tee -a .supervisor/cld-observe-any.log" の起動例が存在する
# ---------------------------------------------------------------------------

@test "AC3: monitor-channel-catalog.md に tee -a .supervisor/cld-observe-any.log の起動例が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  local count
  count=$(grep -c "tee -a .supervisor/cld-observe-any.log" "$MONITOR_CATALOG" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]] \
    || fail "monitor-channel-catalog.md に 'tee -a .supervisor/cld-observe-any.log' の起動例がない（AC3 未実装）"
}

# ===========================================================================
# AC4: monitor-channel-catalog.md — event grep パターン記載
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: monitor-channel-catalog.md の Monitor tool 連携経路セクションを確認する
# THEN: [MENU-READY] / [REVIEW-READY] / [FREEFORM-READY] / [BUDGET-LOW] / [STAGNATE-N]
#       の grep パターンが 5 件以上存在する
# ---------------------------------------------------------------------------

@test "AC4: monitor-channel-catalog.md に event grep パターン 5 件以上が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  local count
  count=$(grep -cE "^\[MENU-READY\]|^\[REVIEW-READY\]|^\[FREEFORM-READY\]|^\[BUDGET-LOW\]|^\[STAGNATE-" "$MONITOR_CATALOG" 2>/dev/null || echo 0)
  [[ "$count" -ge 5 ]] \
    || fail "monitor-channel-catalog.md に event grep パターンが ${count} 件しかない（5 件以上必要）（AC4 未実装）"
}

# ---------------------------------------------------------------------------
# 個別パターン確認（補助 assert）
# ---------------------------------------------------------------------------

@test "AC4: monitor-channel-catalog.md に [MENU-READY] grep パターンが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "^\[MENU-READY\]" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に [MENU-READY] grep パターンがない（AC4 未実装）"
}

@test "AC4: monitor-channel-catalog.md に [REVIEW-READY] grep パターンが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "^\[REVIEW-READY\]" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に [REVIEW-READY] grep パターンがない（AC4 未実装）"
}

@test "AC4: monitor-channel-catalog.md に [FREEFORM-READY] grep パターンが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "^\[FREEFORM-READY\]" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に [FREEFORM-READY] grep パターンがない（AC4 未実装）"
}

@test "AC4: monitor-channel-catalog.md に [BUDGET-LOW] grep パターンが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "^\[BUDGET-LOW\]" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に [BUDGET-LOW] grep パターンがない（AC4 未実装）"
}

@test "AC4: monitor-channel-catalog.md に [STAGNATE-N] grep パターンが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "^\[STAGNATE-" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md に [STAGNATE-N] grep パターンがない（AC4 未実装）"
}

# ===========================================================================
# AC5: monitor-channel-catalog.md — Hybrid 検知ポリシー表更新
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: monitor-channel-catalog.md の Hybrid 検知ポリシー表を確認する
# THEN: MENU-READY-*.json / cld-observe-any.log への言及が 2 件以上存在する
# ---------------------------------------------------------------------------

@test "AC5: monitor-channel-catalog.md の Hybrid 検知ポリシー表に MENU-READY-*.json または cld-observe-any.log が 2 件以上存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  local count
  count=$(grep -cE "MENU-READY-\*\.json|cld-observe-any\.log" "$MONITOR_CATALOG" 2>/dev/null || echo 0)
  [[ "$count" -ge 2 ]] \
    || fail "monitor-channel-catalog.md の Hybrid 検知ポリシー表に MENU-READY-*.json または cld-observe-any.log が ${count} 件しかない（2 件以上必要）（AC5 未実装）"
}

# ---------------------------------------------------------------------------
# Hybrid ポリシー表に REVIEW-READY の行が追加されている
# ---------------------------------------------------------------------------

@test "AC5: monitor-channel-catalog.md の Hybrid 検知ポリシー表に REVIEW-READY の行が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "REVIEW-READY" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md の Hybrid 検知ポリシー表に REVIEW-READY 行がない（AC5 未実装）"
}

@test "AC5: monitor-channel-catalog.md の Hybrid 検知ポリシー表に FREEFORM-READY の行が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$MONITOR_CATALOG" ]] \
    || fail "monitor-channel-catalog.md が存在しない: $MONITOR_CATALOG"

  grep -qE "FREEFORM-READY" "$MONITOR_CATALOG" \
    || fail "monitor-channel-catalog.md の Hybrid 検知ポリシー表に FREEFORM-READY 行がない（AC5 未実装）"
}

# ===========================================================================
# AC6: SKILL.md — Monitor tool 連携経路リンク追記
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: SKILL.md を grep する
# THEN: "Monitor tool 連携経路" または "cld-observe-any.*Monitor tool" への言及が存在する
# ---------------------------------------------------------------------------

@test "AC6: SKILL.md に Monitor tool 連携経路への言及が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"

  local count
  count=$(grep -c "Monitor tool 連携経路\|cld-observe-any.*Monitor tool" "$SKILL_MD" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]] \
    || fail "SKILL.md に Monitor tool 連携経路への言及がない（AC6 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: SKILL.md Step 1 のセクションを確認する
# THEN: monitor-channel-catalog.md の Monitor tool 連携経路セクションへのリンクが含まれる
# ---------------------------------------------------------------------------

@test "AC6: SKILL.md Step 1 に monitor-channel-catalog.md への参照が含まれる" {
  # RED: docs 未更新のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"

  grep -qE "monitor-channel-catalog.*Monitor tool 連携経路|Monitor tool 連携経路.*monitor-channel-catalog" "$SKILL_MD" \
    || fail "SKILL.md Step 1 に monitor-channel-catalog.md の Monitor tool 連携経路へのリンクがない（AC6 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: SKILL.md Step 1 のセクションを確認する
# THEN: SHOULD 注記（または SHOULD 相当の表現）が含まれる
# ---------------------------------------------------------------------------

@test "AC6: SKILL.md の Monitor tool 連携経路参照箇所に SHOULD 注記が含まれる" {
  # RED: docs 未更新のため fail する
  [[ -f "$SKILL_MD" ]] \
    || fail "SKILL.md が存在しない: $SKILL_MD"

  # Monitor tool 連携経路の言及と同一行 or 近接行に SHOULD が存在することを確認
  # (単独 SHOULD grep では既存キーワードにマッチするため、連携経路言及と組み合わせて確認)
  local linkline
  linkline=$(grep -n "Monitor tool 連携経路\|cld-observe-any.*Monitor tool" "$SKILL_MD" | head -1 | cut -d: -f1)
  [[ -n "$linkline" ]] \
    || fail "SKILL.md に Monitor tool 連携経路への言及がない（AC6 未実装: リンク追記なし）"

  # 連携経路リンク行から ±5 行以内に SHOULD が存在すること
  local start=$(( linkline > 5 ? linkline - 5 : 1 ))
  local end=$(( linkline + 5 ))
  sed -n "${start},${end}p" "$SKILL_MD" | grep -qE "SHOULD|推奨|should" \
    || fail "SKILL.md の Monitor tool 連携経路参照箇所（L${linkline}±5行）に SHOULD 相当の注記がない（AC6 未実装）"
}

# ===========================================================================
# AC7 (bats C1): 模擬 logfile append — [MENU-READY] 行が 1 秒以内に append される
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: MENU-READY 状態を模擬した pane 出力を用意し cld-observe-any --once で stdout を
#       logfile に redirect する
# THEN: 1 秒以内に logfile に "[MENU-READY] " で始まる行が append される
# ---------------------------------------------------------------------------

@test "AC7 (C1): cld-observe-any --once が logfile に [MENU-READY] 行を 1 秒以内に append する" {
  # RED: 実装未完了 or テスト環境で tmux が利用できない場合は fail
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  local log_dir
  log_dir="$(mktemp -d)"
  local logfile="${log_dir}/cld-observe-any.log"

  # stub: tmux capture-pane → MENU-READY 状態を模擬（Enter to select 表示）
  # list-windows は "session:index window_name" 形式で返す（awk が $2 でマッチ）
  stub_command "tmux" '
case "$1" in
  list-windows)
    echo "test-session:0 test-worker-1144"
    exit 0
    ;;
  display-message)
    # #{pane_dead} #{pane_current_command}
    echo "0 bash"
    exit 0
    ;;
  capture-pane)
    # MENU-READY: AskUserQuestion メニュー表示を模擬
    printf "? Choose an option\n1. Continue\n2. Skip\n  > Enter to select\n"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  local start_ts end_ts elapsed
  start_ts=$(date +%s)

  # --once モードで実行し stdout を logfile に redirect（tee -a 模擬）
  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    '${CLD_OBSERVE_ANY}' \
      --window test-worker-1144 \
      --once \
      --format text \
      2>/dev/null \
    | tee -a '${logfile}'
  "

  end_ts=$(date +%s)
  elapsed=$(( end_ts - start_ts ))

  # 1 秒以内に完了すること
  [[ "$elapsed" -lt 2 ]] \
    || fail "cld-observe-any --once の実行に ${elapsed} 秒かかった（1 秒以内の期待に違反）"

  # logfile に [MENU-READY] 行が存在すること
  [[ -f "$logfile" ]] \
    || fail "logfile が作成されていない: ${logfile}"

  grep -q "^\[MENU-READY\] " "$logfile" \
    || fail "logfile に [MENU-READY] 行が存在しない（AC7 / C1 未実装）"

  rm -rf "$log_dir"
}

# ===========================================================================
# AC8 (bats C2): --event-dir で MENU-READY-<win>-*.json が生成される
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: cld-observe-any を --event-dir 指定で実行する
# THEN: .supervisor/events/MENU-READY-<win>-*.json が .json 拡張子で生成される
# ---------------------------------------------------------------------------

@test "AC8 (C2): --event-dir 指定時に MENU-READY-<win>-*.json が生成される" {
  # RED: tmux stub または実装に問題がある場合は fail
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  local event_dir
  event_dir="$(mktemp -d)/events"

  # stub: MENU-READY 状態を模擬
  stub_command "tmux" '
case "$1" in
  list-windows)
    echo "test-session:0 test-worker-1144"
    exit 0
    ;;
  display-message)
    echo "0 bash"
    exit 0
    ;;
  capture-pane)
    printf "? Choose an option\n1. Continue\n  > Enter to select\n"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    '${CLD_OBSERVE_ANY}' \
      --window test-worker-1144 \
      --once \
      --event-dir '${event_dir}' \
      2>/dev/null
  "

  # event_dir に MENU-READY-*.json が生成されていること
  local json_count
  json_count=$(find "$event_dir" -maxdepth 1 -name "MENU-READY-test-worker-1144-*.json" 2>/dev/null | wc -l)
  [[ "$json_count" -ge 1 ]] \
    || fail "event_dir ${event_dir} に MENU-READY-test-worker-1144-*.json が生成されていない（AC8 / C2 未実装）"

  # 生成されたファイルが .json 拡張子であること（ファイル名確認）
  local found_file
  found_file=$(find "$event_dir" -maxdepth 1 -name "MENU-READY-test-worker-1144-*.json" 2>/dev/null | head -1)
  [[ "$found_file" == *.json ]] \
    || fail "生成されたファイルが .json 拡張子でない: ${found_file}（AC8 / C2 未実装）"

  rm -rf "$(dirname "$event_dir")"
}

# ===========================================================================
# AC9 (bats C3): --notify-dir は読み取り専用（書き込みが発生しない）
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: --notify-dir を指定して cld-observe-any を実行する
# THEN: notify-dir への書き込みが発生しない（ファイルが増えていない）
# ---------------------------------------------------------------------------

@test "AC9 (C3): --notify-dir 指定時はディレクトリへの書き込みが発生しない（regression）" {
  # RED: notify-dir に誤って書き込む実装がある場合は fail
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  local notify_dir
  notify_dir="$(mktemp -d)/notifications"
  mkdir -p "$notify_dir"

  # 初期ファイル数を実際に計測（空ディレクトリ前提だが防御的に計測）
  local before_count
  before_count=$(find "$notify_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)

  # stub: window なし → 何も検出しない状態
  stub_command "tmux" '
case "$1" in
  list-windows)
    echo "test-worker-1144"
    exit 0
    ;;
  capture-pane)
    # idle 状態（何も検出されない）
    printf "user@host:~$ \n"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    '${CLD_OBSERVE_ANY}' \
      --window test-worker-1144 \
      --once \
      --notify-dir '${notify_dir}' \
      2>/dev/null
  " 2>/dev/null || true

  # notify-dir 内のファイル数が増えていないこと
  local after_count
  after_count=$(find "$notify_dir" -maxdepth 1 -type f 2>/dev/null | wc -l)

  [[ "$after_count" -le "$before_count" ]] \
    || fail "--notify-dir ${notify_dir} に ${after_count} 件の書き込みが発生した（regression: AC9 / C3 違反）"

  rm -rf "$(dirname "$notify_dir")"
}

# ===========================================================================
# AC10 (bats C4): stdout text 形式の確認
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: cld-observe-any --once --format text で MENU-READY 状態を検出する
# THEN: stdout に "^[MENU-READY] [0-9]{2}:[0-9]{2}:[0-9]{2} window=" パターンでヒットする
# ---------------------------------------------------------------------------

@test "AC10 (C4): stdout の text 形式行が ^\[MENU-READY\] [0-9]{2}:[0-9]{2}:[0-9]{2} window= にマッチする" {
  # RED: cld-observe-any の text 形式出力が期待形式でない場合は fail
  [[ -f "$CLD_OBSERVE_ANY" ]] \
    || fail "cld-observe-any が存在しない: $CLD_OBSERVE_ANY"

  # stub: MENU-READY 状態を模擬
  stub_command "tmux" '
case "$1" in
  list-windows)
    echo "test-session:0 test-worker-1144"
    exit 0
    ;;
  display-message)
    echo "0 bash"
    exit 0
    ;;
  capture-pane)
    printf "? Choose an option\n1. Continue\n  > Enter to select\n"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
'

  run bash -c "
    export PATH='${STUB_BIN}:${PATH}'
    export _TEST_MODE=1
    '${CLD_OBSERVE_ANY}' \
      --window test-worker-1144 \
      --once \
      --format text \
      2>/dev/null
  "

  # stdout に [MENU-READY] HH:MM:SS window=... パターンがあること
  echo "$output" | grep -qE "^\[MENU-READY\] [0-9]{2}:[0-9]{2}:[0-9]{2} window=" \
    || fail "stdout に [MENU-READY] HH:MM:SS window= 形式の行がない（AC10 / C4 未実装または text 形式の問題）
実際の出力:
${output}"
}

# ===========================================================================
# AC11: bats 全 PASS — 実装後の GREEN 確認（scaffold 時点では RED で可）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 本ファイルの全テストが実装後に PASS すること
# NOTE: このテスト自体は常に PASS する（実装完了判定はこのファイル全体の実行結果で行う）
# ---------------------------------------------------------------------------

@test "AC11: (meta) 本 bats ファイルが存在し実行可能である（全 PASS は実装後確認）" {
  # GREEN: このテスト自体は PASS する。全テスト PASS は実装後に確認
  local bats_file
  bats_file="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)/$(basename "${BATS_TEST_FILENAME}")"
  [[ -f "$bats_file" ]] \
    || fail "bats ファイルが存在しない: ${bats_file}"
  [[ -r "$bats_file" ]] \
    || fail "bats ファイルが読み取れない: ${bats_file}"
}

# ===========================================================================
# AC12: pitfalls-catalog.md — §4.11 新エントリ
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md を grep する
# THEN: "^#### §4.11 " で始まる行が 1 件以上存在する
# ---------------------------------------------------------------------------

@test "AC12: pitfalls-catalog.md に §4.11 エントリが存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  local count
  count=$(grep -c "^#### §4\.11 " "$PITFALLS_CATALOG" 2>/dev/null || echo 0)
  [[ "$count" -ge 1 ]] \
    || fail "pitfalls-catalog.md に '#### §4.11 ' で始まる行がない（AC12 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md §4.11 の見出しを確認する
# THEN: "cld-observe-any と Monitor tool" または "Monitor tool の連携落とし穴" が含まれる
# ---------------------------------------------------------------------------

@test "AC12: pitfalls-catalog.md の §4.11 見出しに cld-observe-any と Monitor tool が含まれる" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  grep -qE "^#### §4\.11 .*(cld-observe-any|Monitor tool)" "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md の §4.11 見出しに cld-observe-any または Monitor tool が含まれない（AC12 未実装）"
}

# ===========================================================================
# AC13: pitfalls §4.11 内容確認 — 3 経路・方式 A 参照・運用上の懸念
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md §4.11 セクションを確認する
# THEN: 3 経路意味論差への言及が存在する（stdout/event-dir/notify-dir の 3 経路）
# ---------------------------------------------------------------------------

@test "AC13: pitfalls-catalog.md §4.11 に 3 経路意味論差への言及が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  # §4.11 セクションが存在すること（AC12 前提）
  grep -qE "^#### §4\.11 " "$PITFALLS_CATALOG" \
    || fail "§4.11 が存在しない（AC12 前提未実装）"

  # §4.11 セクション内に 3 経路への言及があること
  # stdout / event-dir / notify-dir の 3 つが言及されていること
  grep -qE "stdout|event.dir|notify.dir|3.*経路|経路.*3" "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md §4.11 に 3 経路意味論差への言及がない（AC13 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md §4.11 セクションを確認する
# THEN: 方式 A（正規パス）への参照が存在する
# ---------------------------------------------------------------------------

@test "AC13: pitfalls-catalog.md §4.11 に方式 A 正規パスへの参照が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  grep -qE "^#### §4\.11 " "$PITFALLS_CATALOG" \
    || fail "§4.11 が存在しない（AC12 前提未実装）"

  grep -qE "方式 A|logfile tail|共有 logfile" "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md §4.11 に方式 A 正規パスへの参照がない（AC13 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md §4.11 セクションを確認する
# THEN: 方式 A 運用上の懸念（4 項目相当）が記載されている
# ---------------------------------------------------------------------------

@test "AC13: pitfalls-catalog.md §4.11 に方式 A 運用上の懸念（複数項目）が記載されている" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  grep -qE "^#### §4\.11 " "$PITFALLS_CATALOG" \
    || fail "§4.11 が存在しない（AC12 前提未実装）"

  # §4.11 セクション内の運用上の懸念（logfile rotation / ディスク圧迫 / 競合 / 遅延等）への言及
  # §4.11 から次の "---" または "## " セクション区切りまでを抽出して確認
  local section411
  section411=$(awk '/^#### §4\.11 /{found=1} found{print} found && /^---/{exit}' "$PITFALLS_CATALOG")
  local concern_count
  concern_count=$(echo "$section411" | grep -cE "logfile|rotation|ディスク|競合|遅延|tail.*race|多重|truncate|buffering|flush" 2>/dev/null || echo 0)
  [[ "$concern_count" -ge 2 ]] \
    || fail "pitfalls-catalog.md §4.11 内に方式 A 運用上の懸念が ${concern_count} 件しかない（4 項目の記載が必要）（AC13 未実装）"
}

# ===========================================================================
# AC14: pitfalls §4.11 — 本 Issue 事象記録
# ===========================================================================

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md §4.11 セクションを確認する
# THEN: 2026-04-29 または 2026-04-30 の日付記録が存在する
# ---------------------------------------------------------------------------

@test "AC14: pitfalls-catalog.md §4.11 に 2026-04-29 〜 2026-04-30 の事象記録が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  grep -qE "^#### §4\.11 " "$PITFALLS_CATALOG" \
    || fail "§4.11 が存在しない（AC12 前提未実装）"

  grep -qE "2026-04-29|2026-04-30" "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md §4.11 に 2026-04-29 〜 2026-04-30 の日付記録がない（AC14 未実装）"
}

# ---------------------------------------------------------------------------
# WHEN: pitfalls-catalog.md §4.11 セクションを確認する
# THEN: 3h45m / 無音 / 遅延 への言及が存在する
# ---------------------------------------------------------------------------

@test "AC14: pitfalls-catalog.md §4.11 に 3h45m 無音または遅延の記録が存在する" {
  # RED: docs 未更新のため fail する
  [[ -f "$PITFALLS_CATALOG" ]] \
    || fail "pitfalls-catalog.md が存在しない: $PITFALLS_CATALOG"

  grep -qE "^#### §4\.11 " "$PITFALLS_CATALOG" \
    || fail "§4.11 が存在しない（AC12 前提未実装）"

  grep -qE "3h45m|3.*45.*分|無音|silent|遅延|5.*分.*遅延|delay" "$PITFALLS_CATALOG" \
    || fail "pitfalls-catalog.md §4.11 に 3h45m 無音または遅延の記録がない（AC14 未実装）"
}

# ===========================================================================
# AC15/AC16: プロセス AC — impl_files: [] （bats テスト不要の判定）
# ===========================================================================
# AC15: grep 結果記録（技術メモへの付与）— 出力物は .md への追記であり bats 検証不要
# AC16: 不整合対応判定（2 ファイル以内 → 本 Issue 内 fix、3 ファイル以上 → defer）
#       判定ロジックは LLM が実施するため bats 検証不要
