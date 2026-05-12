#!/usr/bin/env bats
# issue-1663-states-override.bats - Issue #1663 RED テスト
#
# bug(observer-parallel-check): controller_count=0 短絡 path で OBSERVER_PARALLEL_CHECK_STATES
# env-var override が問答無用でリセットされる（L331: controller_states=''）
#
# AC1: _check_parallel_spawn_eligibility の先頭付近に env-var の set 状態を capture する
#      新規ローカル変数 _states_override_set を追加する。
#      controller_count=0 短絡 path で当該フラグが true であれば controller_states='' を実行しない。
#      具体的には [[ -n "${OBSERVER_PARALLEL_CHECK_STATES+x}" ]] && _states_override_set=true の形で
#      local controller_states=... の行より前に配置すること。
#
# AC2: bats test を追加する。最低限以下 3 ケースを含む：
#   (a) controller_count=0 + STATES unset → controller_states='' にリセットされる（現行挙動）
#   (b) controller_count=0 + STATES='S-2' → override が保持され precondition チェック対象になる（exit 0）
#   (c) controller_count=0 + STATES='S-0' → override が保持され precondition 違反として exit 1 (degrade)

bats_require_minimum_version 1.5.0

load '../helpers/common'

PARALLEL_CHECK_LIB=""

setup() {
  common_setup
  PARALLEL_CHECK_LIB="$REPO_ROOT/scripts/lib/observer-parallel-check.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC1: _states_override_set 変数の実装確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: _states_override_set 変数が observer-parallel-check.sh に存在する
# WHEN: observer-parallel-check.sh の内容を確認する
# THEN: _states_override_set という変数宣言が存在する
# RED: 実装前は _states_override_set が不在のため fail する
# ---------------------------------------------------------------------------

@test "AC1 #1663: _states_override_set 変数宣言が observer-parallel-check.sh に存在する" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -qE '_states_override_set' "$PARALLEL_CHECK_LIB" \
    || fail "_states_override_set 変数が observer-parallel-check.sh に存在しない（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: _states_override_set 宣言が local controller_states=... より前に配置されている
# WHEN: observer-parallel-check.sh の行順を確認する
# THEN: _states_override_set の行番号 < local controller_states=... の行番号
# RED: 実装前は _states_override_set が不在のため fail する
# ---------------------------------------------------------------------------

@test "AC1 #1663: _states_override_set 宣言が local controller_states 宣言より前に配置されている" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # _states_override_set が存在するか確認（不在なら即 fail）
  grep -qE '_states_override_set' "$PARALLEL_CHECK_LIB" \
    || fail "_states_override_set 変数が observer-parallel-check.sh に存在しない（AC1 未実装）"

  local states_override_line controller_states_line
  states_override_line=$(grep -n '_states_override_set' "$PARALLEL_CHECK_LIB" | head -1 | cut -d: -f1)
  controller_states_line=$(grep -n 'local controller_states=' "$PARALLEL_CHECK_LIB" | head -1 | cut -d: -f1)

  [[ -n "$states_override_line" ]] \
    || fail "_states_override_set の行番号を取得できなかった"
  [[ -n "$controller_states_line" ]] \
    || fail "local controller_states= の行番号を取得できなかった"

  (( states_override_line < controller_states_line )) \
    || fail "_states_override_set（L${states_override_line}）が local controller_states=（L${controller_states_line}）より後に配置されている（AC1: 前に配置すること）"
}

# ---------------------------------------------------------------------------
# Scenario: _states_override_set が ${VAR+x} パターンで set 状態を capture する
# WHEN: observer-parallel-check.sh の実装を確認する
# THEN: OBSERVER_PARALLEL_CHECK_STATES+x パターンが存在する
# RED: 実装前は不在のため fail する
# NOTE: ${VAR+x} は VAR が unset の場合のみ空文字を返す（明示的 set（空文字含む）を検出可能）
# ---------------------------------------------------------------------------

@test "AC1 #1663: \${OBSERVER_PARALLEL_CHECK_STATES+x} パターンで明示的 set を検出する" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -qE 'OBSERVER_PARALLEL_CHECK_STATES\+x' "$PARALLEL_CHECK_LIB" \
    || fail "OBSERVER_PARALLEL_CHECK_STATES+x パターンが存在しない（AC1: \${VAR+x} パターンで unset/set を区別すること）"
}

# ===========================================================================
# AC2: ケース (a) - STATES unset → controller_states='' にリセットされる（現行挙動維持）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + STATES unset → controller_states='' にリセット（exit 0）
# WHEN: controller_count=0, OBSERVER_PARALLEL_CHECK_STATES unset で呼び出す
# THEN: exit 0（AC3 維持確認 — controller_count=0 初回 spawn は heartbeat check skip で許可）
# NOTE: STATES が unset の場合は _states_override_set=false → controller_states='' リセット実行
#       これは #1651 chicken-and-egg 回避の維持確認（AC3 と同義）
# GREEN: 現行実装も exit 0 を返すため、実装前後ともに PASS することが期待される
# ---------------------------------------------------------------------------

@test "AC2(a) #1663: controller_count=0 + STATES unset → exit 0 (初回 spawn 許可, AC3 維持)" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "controller_count=0 + STATES unset で exit $status が返った（期待: exit 0 / 初回 spawn 許可）"
}

# ===========================================================================
# AC2: ケース (b) - STATES='S-2' override が保持されて precondition PASS (exit 0)
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + STATES='S-2' → override が保持されて exit 0
# WHEN: controller_count=0, OBSERVER_PARALLEL_CHECK_STATES='S-2' で呼び出す
# THEN: exit 0（S-2 は valid state、override が保持されれば precondition PASS）
# RED: 現行実装は controller_states='' に上書きするバグがあるが、
#      exit 0 という結果は一致してしまう（_states_override_set 実装確認テストが先行して FAIL するため全体としては RED）
# NOTE: このケースは AC1 の実装確認テスト群が FAIL することで RED ステータスを保証する
#       このテスト自体は「override 保持後も S-2 が valid で exit 0」という事後条件を検証する
# ---------------------------------------------------------------------------

@test "AC2(b) #1663: controller_count=0 + STATES='S-2' → exit 0 (override 保持, S-2 は valid state)" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # AC1 が実装されていなければ即 fail（_states_override_set 未実装）
  grep -qE '_states_override_set' "$PARALLEL_CHECK_LIB" \
    || fail "_states_override_set が未実装（AC1 の実装が先行条件）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-2' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "controller_count=0 + STATES='S-2' で exit $status が返った（期待: exit 0 / S-2 は valid state）"
}

# ===========================================================================
# AC2: ケース (c) - STATES='S-0' override が保持されて precondition 違反 (exit 1)
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + STATES='S-0' → override が保持されて exit 1 (degrade)
# WHEN: controller_count=0, OBSERVER_PARALLEL_CHECK_STATES='S-0' で呼び出す
# THEN: exit 1（S-0 は ^S-[015] にマッチ → precondition5 違反 → DEGRADE_TO_2）
# RED: 現行実装は controller_states='' に上書き → precondition5 評価スキップ → exit 0 を返す（バグ）
# ---------------------------------------------------------------------------

@test "AC2(c) #1663: controller_count=0 + STATES='S-0' → exit 1 (override 保持, S-0 は precondition 違反)" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-0' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure \
    || fail "controller_count=0 + STATES='S-0' で exit $status が返った（期待: exit 1 / S-0 は precondition 違反 → degrade）"

  [[ "$status" -eq 1 ]] \
    || fail "controller_count=0 + STATES='S-0' で exit $status が返った（期待: exit 1 degrade, exit 2 は mode/heartbeat 違反）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + STATES='S-0' → DEGRADE_TO_2 メッセージが stderr に出力される
# WHEN: controller_count=0, OBSERVER_PARALLEL_CHECK_STATES='S-0' で呼び出す
# THEN: stderr に "DEGRADE_TO_2" が含まれる
# RED: 現行実装は controller_states='' に上書き → precondition5 評価スキップ → DEGRADE_TO_2 が出力されない
# ---------------------------------------------------------------------------

@test "AC2(c) #1663: STATES='S-0' override 時に DEGRADE_TO_2 が stderr に出力される" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run --separate-stderr bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-0' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  echo "$stderr" | grep -qF 'DEGRADE_TO_2' \
    || fail "STATES='S-0' override 時に DEGRADE_TO_2 が stderr に出力されなかった（期待: precondition5 違反で degrade メッセージ）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + STATES='S-0' → stderr に S-0 が含まれる
# WHEN: controller_count=0, OBSERVER_PARALLEL_CHECK_STATES='S-0' で呼び出す
# THEN: stderr に "S-0" が含まれる（controller_states に S-0 が含まれることの明示）
# RED: 現行実装は controller_states='' に上書き → precondition5 評価スキップ → S-0 メッセージが出力されない
# ---------------------------------------------------------------------------

@test "AC2(c) #1663: STATES='S-0' override 時に stderr に S-0 precondition 違反が明示される" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run --separate-stderr bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-0' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  echo "$stderr" | grep -qF 'S-0' \
    || fail "STATES='S-0' override 時に stderr に 'S-0' が含まれなかった（期待: controller_states に S-0 が含まれる旨の precondition 違反メッセージ）"
}
