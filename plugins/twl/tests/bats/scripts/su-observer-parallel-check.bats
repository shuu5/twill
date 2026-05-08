#!/usr/bin/env bats
# su-observer-parallel-check.bats - Issue #1116 AC5a/AC5b/AC6 RED テスト
#
# AC5a: observer-parallel-check.sh に _check_parallel_spawn_eligibility() 純関数を新規実装
#       bats test を plugins/twl/tests/bats/scripts/su-observer-parallel-check.bats に配置
#       env var injection、8件以上のシナリオ
# AC5b: observer-parallel-check.sh に 7 helper 関数の production 実装
#       (check_controller_heartbeat_alive, check_observer_mode, count_eligible_controllers,
#        check_monitor_cld_observe_alive, get_controller_states,
#        get_budget_minutes_remaining, get_parallel_spawn_min_remaining_minutes)
# AC6:  spawn-controller.sh 冒頭に _check_parallel_spawn_eligibility() 呼出を追加
#       exit 2/1/0 それぞれの動作
#
# Coverage: unit (env var injection / exit コード仕様 / helper 関数定義確認)
#
# exit コード仕様:
#   0: 全条件 PASS → ≤ 10 並列 OK（#1560 で ≤4→≤10 に緩和）
#   1: precondition 1つでも false → ≤ 2 並列 degrade、stderr に欠落 precondition
#   2: 必須条件 1つでも false → spawn 完全禁止、stderr に欠落必須条件

load '../helpers/common'

PARALLEL_CHECK_LIB=""
SPAWN_CONTROLLER=""

setup() {
  common_setup
  PARALLEL_CHECK_LIB="$REPO_ROOT/scripts/lib/observer-parallel-check.sh"
  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC5a: observer-parallel-check.sh ファイル存在確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: observer-parallel-check.sh が共通ライブラリとして存在する
# WHEN: plugins/twl/scripts/lib/observer-parallel-check.sh を参照する
# THEN: ファイルが存在する
# ---------------------------------------------------------------------------

@test "AC5a: scripts/lib/observer-parallel-check.sh が存在する" {
  # RED: 実装前は fail する（スクリプト未作成）
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"
}

# ---------------------------------------------------------------------------
# Scenario: observer-parallel-check.sh に _check_parallel_spawn_eligibility() が定義されている
# WHEN: observer-parallel-check.sh を source する
# THEN: _check_parallel_spawn_eligibility 関数が定義されている
# ---------------------------------------------------------------------------

@test "AC5a: observer-parallel-check.sh に _check_parallel_spawn_eligibility() が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  grep -q '_check_parallel_spawn_eligibility' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に _check_parallel_spawn_eligibility() が定義されていない"
}

# ---------------------------------------------------------------------------
# Scenario: 全条件 PASS 時に exit 0 を返す（env var injection）
# WHEN: 全必須条件 + 全 precondition を true に設定して呼び出す
# THEN: exit 0（≤ 10 並列 OK）
# ---------------------------------------------------------------------------

@test "AC5a: 全条件 PASS 時に exit 0 を返す（env var injection）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  # 全条件を PASS 状態に env var injection で設定
  # 必須3条件: heartbeat_alive=true, mode=auto, controller_count=2(+1=3≤4)
  # precondition3条件: monitor_cld_alive=true, states=S-2/S-3/S-4のみ, budget_min≥threshold
  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: heartbeat_alive=false 時に exit 2 を返す（必須条件失敗）
# WHEN: heartbeat_alive を false に設定
# THEN: exit 2（spawn 完全禁止）、stderr に欠落必須条件
# ---------------------------------------------------------------------------

@test "AC5a: heartbeat_alive=false 時に exit 2 を返す（必須条件失敗）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（heartbeat_alive=false は必須条件失敗）"
}

# ---------------------------------------------------------------------------
# Scenario: mode=disabled 時に exit 2 を返す（必須条件失敗）
# WHEN: mode を invalid な値（disabled）に設定
# THEN: exit 2（spawn 完全禁止）
# ---------------------------------------------------------------------------

@test "AC5a: mode=disabled 時に exit 2 を返す（必須条件失敗）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=disabled \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（mode=disabled は必須条件失敗）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=10 時に exit 2 を返す（SU-4 ≤10 上限超過）
# #1560: 新閾値 controller_count + 1 > 10 への更新（旧: > 4）
# WHEN: controller_count=10（+1=11>10）に設定
# THEN: exit 2（spawn 完全禁止）
# ---------------------------------------------------------------------------

@test "AC5a: controller_count=10（+1=11>10）時に exit 2 を返す（SU-4 ≤10 上限超過）" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=10 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（controller_count=10 は SU-4 ≤10 上限超過）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=9 時に exit 0 を返す（SU-4 ≤10 boundary PASS）
# #1560: 新閾値 boundary - 9+1=10 ≤ 10 なので PASS
# WHEN: controller_count=9（+1=10≤10）に設定（全条件 PASS）
# THEN: exit 0（≤ 10 並列 OK）
# ---------------------------------------------------------------------------

@test "AC5a: controller_count=9（+1=10≤10）時に exit 0 を返す（SU-4 ≤10 boundary PASS）" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=9 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "exit コードは 0 であるべきだが $status だった（controller_count=9 は SU-4 ≤10 内）"
}

# ---------------------------------------------------------------------------
# Scenario: monitor_cld_alive=false 時に exit 1 を返す（precondition 失敗）
# WHEN: monitor_cld_alive を false に設定（必須条件は全 PASS）
# THEN: exit 1（≤ 2 並列 degrade）、stderr に欠落 precondition
# ---------------------------------------------------------------------------

@test "AC5a: monitor_cld_alive=false 時に exit 1 を返す（precondition 失敗）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=false \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 1 ]] \
    || fail "exit コードは 1 であるべきだが $status だった（monitor_cld_alive=false は precondition 失敗）"
}

# ---------------------------------------------------------------------------
# Scenario: budget_min < budget_threshold 時に exit 1 を返す（precondition 失敗）
# WHEN: budget_min=100, budget_threshold=150（不足）に設定
# THEN: exit 1（≤ 2 並列 degrade）
# ---------------------------------------------------------------------------

@test "AC5a: budget_min=100 < budget_threshold=150 時に exit 1 を返す（precondition 失敗）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=100 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 1 ]] \
    || fail "exit コードは 1 であるべきだが $status だった（budget 不足は precondition 失敗）"
}

# ---------------------------------------------------------------------------
# Scenario: controller state に S-2/S-3/S-4 以外が含まれる時に exit 1 を返す
# WHEN: states に S-0 を含む設定
# THEN: exit 1（≤ 2 並列 degrade）
# ---------------------------------------------------------------------------

@test "AC5a: states に S-0 が含まれる時に exit 1 を返す（precondition 失敗）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-0 S-3' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 1 ]] \
    || fail "exit コードは 1 であるべきだが $status だった（S-0 state は precondition 失敗）"
}

# ---------------------------------------------------------------------------
# Scenario: 必須条件失敗は precondition 失敗より優先（exit 2）
# WHEN: heartbeat_alive=false（必須）かつ monitor_cld_alive=false（precondition）
# THEN: exit 2（必須条件失敗が優先）
# ---------------------------------------------------------------------------

@test "AC5a: 必須条件失敗は precondition 失敗より優先して exit 2 を返す" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=false \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=100 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_failure
  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（必須条件失敗が precondition 失敗より優先されるべき）"
}

# ---------------------------------------------------------------------------
# Scenario: mode=bypass でも全条件 PASS 時に exit 0 を返す
# WHEN: mode=bypass（bypass も valid）
# THEN: exit 0（bypass も auto と同等に許可）
# ---------------------------------------------------------------------------

@test "AC5a: mode=bypass でも全条件 PASS 時に exit 0 を返す" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=bypass \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=1 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-2' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=180 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success
}

# ---------------------------------------------------------------------------
# Scenario: 必須条件失敗時に stderr に欠落条件が出力される
# WHEN: heartbeat_alive=false で呼び出す
# THEN: stderr に heartbeat または必須条件に関するメッセージが出力される
# ---------------------------------------------------------------------------

@test "AC5a: 必須条件失敗時に stderr に欠落条件が出力される" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  " 2>&1

  # stderr（2>&1 でマージされた出力）に失敗条件のメッセージが含まれること
  echo "$output" | grep -qiE 'heartbeat|必須|required|MUST|condition' \
    || fail "heartbeat_alive 失敗時に stderr への欠落条件メッセージが出力されていない（出力: $output）"
}

# ===========================================================================
# AC5b: 7 helper 関数の定義確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: 7 helper 関数が全て定義されている
# WHEN: observer-parallel-check.sh の内容を確認する
# THEN: 7つの helper 関数名が全て grep で発見できる
# ---------------------------------------------------------------------------

@test "AC5b: check_controller_heartbeat_alive 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'check_controller_heartbeat_alive' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に check_controller_heartbeat_alive() が定義されていない"
}

@test "AC5b: check_observer_mode 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'check_observer_mode' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に check_observer_mode() が定義されていない"
}

@test "AC5b: count_eligible_controllers 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'count_eligible_controllers' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に count_eligible_controllers() が定義されていない"
}

@test "AC5b: check_monitor_cld_observe_alive 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'check_monitor_cld_observe_alive' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に check_monitor_cld_observe_alive() が定義されていない"
}

@test "AC5b: get_controller_states 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'get_controller_states' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に get_controller_states() が定義されていない"
}

@test "AC5b: get_budget_minutes_remaining 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'get_budget_minutes_remaining' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に get_budget_minutes_remaining() が定義されていない"
}

@test "AC5b: get_parallel_spawn_min_remaining_minutes 関数が定義されている" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5b 未実装）"

  grep -q 'get_parallel_spawn_min_remaining_minutes' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に get_parallel_spawn_min_remaining_minutes() が定義されていない"
}

# ===========================================================================
# AC6: spawn-controller.sh の _check_parallel_spawn_eligibility() 呼出確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: spawn-controller.sh が _check_parallel_spawn_eligibility を呼び出す
# WHEN: spawn-controller.sh の内容を確認する
# THEN: _check_parallel_spawn_eligibility の呼び出しが冒頭付近に存在する
# ---------------------------------------------------------------------------

@test "AC6: spawn-controller.sh が _check_parallel_spawn_eligibility() を呼び出している" {
  # RED: 実装前は fail する（spawn-controller.sh への呼出追加前）
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  grep -q '_check_parallel_spawn_eligibility' "$SPAWN_CONTROLLER" \
    || fail "spawn-controller.sh に _check_parallel_spawn_eligibility() の呼び出しが存在しない（AC6 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: spawn-controller.sh が observer-parallel-check.sh を source している
# WHEN: spawn-controller.sh の内容を確認する
# THEN: observer-parallel-check.sh を source する記述が存在する
# ---------------------------------------------------------------------------

@test "AC6: spawn-controller.sh が observer-parallel-check.sh を source している" {
  # RED: 実装前は fail する
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  grep -q 'observer-parallel-check' "$SPAWN_CONTROLLER" \
    || fail "spawn-controller.sh に observer-parallel-check.sh の source 記述が存在しない（AC6 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: spawn-controller.sh が _check_parallel_spawn_eligibility exit 2 で abort する
# WHEN: _check_parallel_spawn_eligibility が exit 2 を返す状態で spawn-controller.sh を呼び出す
# THEN: spawn-controller.sh は早期終了し cld-spawn を呼び出さない
# ---------------------------------------------------------------------------

@test "AC6: _check_parallel_spawn_eligibility exit 2 時に spawn-controller.sh が abort する" {
  # RED: 実装前は fail する
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  # observer-parallel-check.sh stub: _check_parallel_spawn_eligibility が exit 2 を返す
  local mock_lib="$SANDBOX/scripts/lib/observer-parallel-check.sh"
  mkdir -p "$(dirname "$mock_lib")"
  cat > "$mock_lib" <<'MOCK_LIB'
#!/usr/bin/env bash
check_controller_heartbeat_alive() { echo "false"; }
check_observer_mode() { echo "auto"; }
count_eligible_controllers() { echo "0"; }
check_monitor_cld_observe_alive() { echo "true"; }
get_controller_states() { echo ""; }
get_budget_minutes_remaining() { echo "200"; }
get_parallel_spawn_min_remaining_minutes() { echo "150"; }
_check_parallel_spawn_eligibility() {
  echo "ERROR: heartbeat_alive=false (必須条件失敗)" >&2
  return 2
}
MOCK_LIB

  # cld-spawn stub: 呼ばれたら log を残す
  local cld_log="$SANDBOX/cld-spawn-called.log"
  stub_command "cld-spawn" "echo 'called' >> '$cld_log'; exit 0"

  # prompt file stub
  local prompt_file="$SANDBOX/test-prompt.txt"
  echo "test prompt content" > "$prompt_file"

  run bash "$SPAWN_CONTROLLER" co-explore "$prompt_file"

  # cld-spawn が呼ばれていないこと
  [[ ! -f "$cld_log" ]] \
    || fail "exit 2 時に cld-spawn が呼ばれてはならないが呼ばれた（AC6 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: spawn-controller.sh の _check_parallel_spawn_eligibility 呼出が bash -n で valid
# WHEN: spawn-controller.sh を bash -n で構文チェックする
# THEN: syntax error なし（exit 0）
# ---------------------------------------------------------------------------

@test "AC6: spawn-controller.sh が bash syntax として valid" {
  # 既存テストとの重複を避けるため、AC6 実装後も syntax 確認
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  run bash -n "$SPAWN_CONTROLLER"
  assert_success
}

# ===========================================================================
# AC7: deps.yaml に observer-parallel-check エントリ確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: deps.yaml に observer-parallel-check script エントリが存在する
# WHEN: plugins/twl/deps.yaml を参照する
# THEN: observer-parallel-check の type:script エントリが存在する
# ---------------------------------------------------------------------------

@test "AC7: deps.yaml に observer-parallel-check script エントリが存在する" {
  # RED: 実装前は fail する（deps.yaml 更新前）
  local deps_yaml
  deps_yaml="$REPO_ROOT/deps.yaml"

  [[ -f "$deps_yaml" ]] \
    || fail "deps.yaml が存在しない: $deps_yaml"

  grep -q 'observer-parallel-check' "$deps_yaml" \
    || fail "deps.yaml に observer-parallel-check エントリが存在しない（AC7 未実装）"
}

# ===========================================================================
# AC1/AC2/AC3: pitfalls-catalog.md §11.3 更新確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §11.3 に「条件成立時 ≤ 4 並列 MUST」が記載されている
# WHEN: pitfalls-catalog.md §11.3 セクションを参照する
# THEN: 4 並列 MUST の記述が存在する
# ---------------------------------------------------------------------------

@test "AC1: pitfalls-catalog.md §11.3 に '≤ 4 並列 MUST' または '4.*MUST' が記載されている" {
  # RED: 実装前は fail する（pitfalls-catalog.md 未更新）
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qE '4.*MUST|MUST.*4|≤.*4.*MUST|4 並列.*MUST' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に '≤ 4 並列 MUST' 記述が存在しない（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §11.3 に判断 flowchart（疑似コード）が追加されている
# WHEN: pitfalls-catalog.md §11.3 セクションを参照する
# THEN: flowchart または pseudocode 相当の記述が存在する
# ---------------------------------------------------------------------------

@test "AC2: pitfalls-catalog.md §11.3 に flowchart/pseudocode が追加されている" {
  # RED: 実装前は fail する（pitfalls-catalog.md 未更新）
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  # flowchart / pseudocode / 疑似コード / exit コード定義のいずれかが存在すること
  grep -qiE 'flowchart|pseudocode|疑似コード|exit.*0|exit.*1|exit.*2|SNAPSHOT_TS|eligible_controller' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に flowchart/pseudocode 相当の記述が存在しない（AC2 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §11.3 末尾に 2026-04-29 ipatho2 の実証パターンが記載されている
# WHEN: pitfalls-catalog.md §11.3 末尾セクションを参照する
# THEN: 5行以上で doobidoo hash (bce7a4b9/e4f97e77/39ade8bd) を含む記述が存在する
# ---------------------------------------------------------------------------

@test "AC3: pitfalls-catalog.md §11.3 末尾に doobidoo hash (bce7a4b9) を含む実証パターンが記載されている" {
  # RED: 実装前は fail する（pitfalls-catalog.md 未更新）
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -q 'bce7a4b9' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に doobidoo hash 'bce7a4b9' が存在しない（AC3 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §11.3 末尾に doobidoo hash e4f97e77 が記載されている
# ---------------------------------------------------------------------------

@test "AC3: pitfalls-catalog.md §11.3 末尾に doobidoo hash (e4f97e77) が記載されている" {
  # RED: 実装前は fail する
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -q 'e4f97e77' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に doobidoo hash 'e4f97e77' が存在しない（AC3 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: su-observer-controller-spawn-playbook.md に「spawn 前条件チェック (§11.3)」セクションが存在する
# WHEN: su-observer-controller-spawn-playbook.md を参照する
# THEN: spawn 前条件チェック または _check_parallel_spawn_eligibility の記述が存在する
# ---------------------------------------------------------------------------

@test "AC4: su-observer-controller-spawn-playbook.md に spawn 前条件チェックセクションが存在する" {
  # RED: 実装前は fail する（playbook 未更新）
  local playbook
  playbook="$REPO_ROOT/skills/su-observer/refs/su-observer-controller-spawn-playbook.md"

  [[ -f "$playbook" ]] \
    || fail "su-observer-controller-spawn-playbook.md が存在しない: $playbook"

  grep -qiE 'spawn.*前.*条件|条件.*チェック.*spawn|_check_parallel_spawn_eligibility|11\.3' "$playbook" \
    || fail "su-observer-controller-spawn-playbook.md に spawn 前条件チェックセクションが存在しない（AC4 未実装）"
}

# ===========================================================================
# Issue #1134: check_observer_mode セクション
# AC3/AC4/AC5/AC6/AC7/AC9/AC10/AC11
# ===========================================================================
# 共通前提:
#   - OBSERVER_PARALLEL_CHECK_MODE は unset して実行（env バイパス防止）
#   - SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor" を各テスト内で export
#   - AC3 前提チェック: ps aux フォールバックブロック (L95-101) が削除済みであること
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario #1134-1: mode=auto 取得
# GIVEN: .supervisor/session.json に {"mode":"auto"} が書かれている
# WHEN: check_observer_mode() を OBSERVER_PARALLEL_CHECK_MODE unset で呼ぶ
# THEN: "auto" を stdout に返す
# RED: AC3（ps aux フォールバック削除）が未実装のため、フォールバック除去後に PASS
# ---------------------------------------------------------------------------

@test "AC9 #1134-1: mode=auto 取得 - session.json から mode=auto を返す" {
  # AC3 前提: ps aux フォールバックブロックが削除されていること
  # RED: 現在 L97 に ps aux フォールバックが残存しているため fail する
  if grep -l 'ps aux' "$PARALLEL_CHECK_LIB" >/dev/null 2>&1; then
    fail "AC3 未実装: observer-parallel-check.sh に ps aux フォールバックブロック (L95-101) が残存している（削除対象: check_observer_mode() 内の ps aux | grep 'cld\\b' | grep -oP ... ブロック）"
  fi

  # SUPERVISOR_DIR を tmpdir に設定（AC11: common_setup は SUPERVISOR_DIR を export しないため個別設定）
  export SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor"
  unset OBSERVER_PARALLEL_CHECK_MODE

  mkdir -p "$SUPERVISOR_DIR"
  echo '{"mode":"auto"}' > "$SUPERVISOR_DIR/session.json"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export SUPERVISOR_DIR='$SUPERVISOR_DIR'
    unset OBSERVER_PARALLEL_CHECK_MODE
    check_observer_mode
  "

  assert_success
  assert_output "auto"
}

# ---------------------------------------------------------------------------
# Scenario #1134-2: mode field 空 → unknown
# GIVEN: .supervisor/session.json に {"mode":""} が書かれている
# WHEN: check_observer_mode() を OBSERVER_PARALLEL_CHECK_MODE unset で呼ぶ
# THEN: "unknown" を stdout に返す
# RED: AC3（ps aux フォールバック削除）が未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC9 #1134-2: mode field 空 → unknown - session.json mode 空のとき unknown を返す" {
  # AC3 前提: ps aux フォールバックブロックが削除されていること
  # RED: 現在 L97 に ps aux フォールバックが残存しているため fail する
  if grep -l 'ps aux' "$PARALLEL_CHECK_LIB" >/dev/null 2>&1; then
    fail "AC3 未実装: observer-parallel-check.sh に ps aux フォールバックブロック (L95-101) が残存している（削除対象: check_observer_mode() 内の ps aux | grep 'cld\\b' | grep -oP ... ブロック）"
  fi

  # SUPERVISOR_DIR を tmpdir に設定（AC11: 個別設定必須）
  export SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor"
  unset OBSERVER_PARALLEL_CHECK_MODE

  mkdir -p "$SUPERVISOR_DIR"
  echo '{"mode":""}' > "$SUPERVISOR_DIR/session.json"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export SUPERVISOR_DIR='$SUPERVISOR_DIR'
    unset OBSERVER_PARALLEL_CHECK_MODE
    check_observer_mode
  "

  assert_success
  assert_output "unknown"
}

# ---------------------------------------------------------------------------
# Scenario #1134-3: file 不在 → unknown
# GIVEN: .supervisor/session.json が存在しない
# WHEN: check_observer_mode() を OBSERVER_PARALLEL_CHECK_MODE unset で呼ぶ
# THEN: "unknown" を stdout に返す
# RED: AC3（ps aux フォールバック削除）が未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC9 #1134-3: file 不在 → unknown - session.json 不在のとき unknown を返す" {
  # AC3 前提: ps aux フォールバックブロックが削除されていること
  # RED: 現在 L97 に ps aux フォールバックが残存しているため fail する
  if grep -l 'ps aux' "$PARALLEL_CHECK_LIB" >/dev/null 2>&1; then
    fail "AC3 未実装: observer-parallel-check.sh に ps aux フォールバックブロック (L95-101) が残存している（削除対象: check_observer_mode() 内の ps aux | grep 'cld\\b' | grep -oP ... ブロック）"
  fi

  # SUPERVISOR_DIR を tmpdir に設定（AC11: 個別設定必須）
  export SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor"
  unset OBSERVER_PARALLEL_CHECK_MODE

  # session.json を作成しない（ディレクトリのみ作成）
  mkdir -p "$SUPERVISOR_DIR"
  # session.json は意図的に作成しない

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export SUPERVISOR_DIR='$SUPERVISOR_DIR'
    unset OBSERVER_PARALLEL_CHECK_MODE
    check_observer_mode
  "

  assert_success
  assert_output "unknown"
}

# ---------------------------------------------------------------------------
# Scenario #1134-4: fail-closed exit 2 with substring assert
# GIVEN: .supervisor/session.json に {} （mode field なし）
# AND: OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true, CONTROLLER_COUNT=2
# AND: OBSERVER_PARALLEL_CHECK_MODE は unset（AC10: env バイパス防止）
# WHEN: _check_parallel_spawn_eligibility() を呼ぶ
# THEN: exit 2 かつ stderr に "bypass または auto mode が必要" を含む
# RED: AC3（ps aux フォールバック削除）が未実装のため fail する
# NOTE: assert_output --partial で substring 一致を確認（AC7 要件）
# ---------------------------------------------------------------------------

# ===========================================================================
# Issue #1223 AC4 (regression): mode=bypass 時に spawn-controller が DENY しない
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario AC4-mode-bypass-passes: session.json mode=bypass → DENY しない
# GIVEN: .supervisor/session.json に {"mode":"bypass"} が書かれている
# AND: OBSERVER_PARALLEL_CHECK_MODE は unset（session.json から実読み）
# AND: heartbeat_alive=true, controller_count=1 （他必須条件 PASS）
# WHEN: _check_parallel_spawn_eligibility() を呼ぶ
# THEN: exit 2 にならない（exit 0 または exit 1 = spawn degrade は許容）
# RED: 現時点では session-init.sh が mode=bypass を記録しないため、
#      session.json に mode=bypass を手動で書いた場合の動作を確認する
# ---------------------------------------------------------------------------

@test "AC4-mode-bypass-passes: session.json mode=bypass 時に _check_parallel_spawn_eligibility が exit 2 にならない" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  export SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor"
  unset OBSERVER_PARALLEL_CHECK_MODE
  mkdir -p "$SUPERVISOR_DIR"
  echo '{"mode":"bypass"}' > "$SUPERVISOR_DIR/session.json"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export SUPERVISOR_DIR='$SUPERVISOR_DIR'
    unset OBSERVER_PARALLEL_CHECK_MODE
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=1 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-2' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  " 2>&1

  [[ "$status" -ne 2 ]] \
    || fail "exit 2（spawn DENY）が返った — mode=bypass は spawn を許可すべきだが DENY された（Issue #1223 regression）"
}

# ---------------------------------------------------------------------------
# Scenario AC4-mode-bypass-check-observer-mode: check_observer_mode が bypass を正しく返す
# GIVEN: .supervisor/session.json に {"mode":"bypass"} が書かれている
# WHEN: check_observer_mode() を OBSERVER_PARALLEL_CHECK_MODE unset で呼ぶ
# THEN: "bypass" を stdout に返す
# ---------------------------------------------------------------------------

@test "AC4-mode-bypass-check-observer-mode: session.json mode=bypass のとき check_observer_mode が 'bypass' を返す" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  export SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor"
  unset OBSERVER_PARALLEL_CHECK_MODE
  mkdir -p "$SUPERVISOR_DIR"
  echo '{"mode":"bypass"}' > "$SUPERVISOR_DIR/session.json"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export SUPERVISOR_DIR='$SUPERVISOR_DIR'
    unset OBSERVER_PARALLEL_CHECK_MODE
    check_observer_mode
  "

  assert_success
  assert_output "bypass"
}

@test "AC9 #1134-4: fail-closed exit 2 - mode 不在で exit 2 かつ stderr substring assert" {
  # AC3 前提: ps aux フォールバックブロックが削除されていること
  # RED: 現在 L97 に ps aux フォールバックが残存しているため fail する
  if grep -l 'ps aux' "$PARALLEL_CHECK_LIB" >/dev/null 2>&1; then
    fail "AC3 未実装: observer-parallel-check.sh に ps aux フォールバックブロック (L95-101) が残存している（削除対象: check_observer_mode() 内の ps aux | grep 'cld\\b' | grep -oP ... ブロック）"
  fi

  # SUPERVISOR_DIR を tmpdir に設定（AC11: 個別設定必須）
  export SUPERVISOR_DIR="$BATS_TEST_TMPDIR/.supervisor"
  unset OBSERVER_PARALLEL_CHECK_MODE

  mkdir -p "$SUPERVISOR_DIR"
  # mode field なし（AC7: mode 不在状態）
  echo '{}' > "$SUPERVISOR_DIR/session.json"

  # AC10: OBSERVER_PARALLEL_CHECK_MODE は unset のまま実行
  # heartbeat と controller_count は pass させる（mode の fail-closed のみ観測）
  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    export SUPERVISOR_DIR='$SUPERVISOR_DIR'
    unset OBSERVER_PARALLEL_CHECK_MODE
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=2 \
    _check_parallel_spawn_eligibility
  " 2>&1

  # exit 2 であること
  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（mode 不在は必須条件失敗）"

  # stderr に "bypass または auto mode が必要" が含まれること（AC7: assert_output --partial）
  assert_output --partial "bypass または auto mode が必要"
}

# ===========================================================================
# Issue #1560: SU-4 並列 controller 制約を 5 → 10 に緩和
# AC1: supervision.md SSoT 定義更新
# AC2: 周辺ドキュメント mirror 同期
# AC3: observer-parallel-check.sh 閾値同期（5→10）
# AC4: spawn-controller.sh エラーメッセージ更新
# AC5: bats テスト新閾値 boundary ケース追加
# AC6: pitfalls-catalog.md 運用 reference 更新
# AC7: 実証検証（env-injection）
# ===========================================================================

# ---------------------------------------------------------------------------
# AC1: supervision.md L190 SU-4 定義に「10 を超えてはならない」が含まれること
# WHEN: plugins/twl/architecture/domain/contexts/supervision.md を参照する
# THEN: SU-4 行に「10」が含まれる（旧値「5」ではなく「10」）
# RED: 実装前は fail する（supervision.md 未更新）
# ---------------------------------------------------------------------------

@test "AC1 #1560: supervision.md L190 SU-4 定義に上限 10 が含まれている" {
  local supervision_md
  supervision_md="$REPO_ROOT/architecture/domain/contexts/supervision.md"

  [[ -f "$supervision_md" ]] \
    || fail "supervision.md が存在しない: $supervision_md"

  # SU-4 行に「10」が含まれること（上限 10 に更新済み）
  grep -qE '^[[:space:]]*\|[[:space:]]*SU-4[[:space:]]*\|' "$supervision_md" \
    || fail "supervision.md に SU-4 テーブル行が存在しない"

  grep -E '^[[:space:]]*\|[[:space:]]*SU-4[[:space:]]*\|' "$supervision_md" \
    | grep -q '10' \
    || fail "supervision.md SU-4 行に上限 '10' が含まれていない（AC1 未実装: 現在は '5'）"
}

# ---------------------------------------------------------------------------
# AC1: supervision.md L206 OB-5 比較注記に「SU-4（上限10）」が含まれること
# WHEN: OB-5 行を参照する
# THEN: 「上限10」または「10）」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC1 #1560: supervision.md OB-5 比較注記に SU-4（上限10）が含まれている" {
  local supervision_md
  supervision_md="$REPO_ROOT/architecture/domain/contexts/supervision.md"

  [[ -f "$supervision_md" ]] \
    || fail "supervision.md が存在しない: $supervision_md"

  # OB-5 行の SU-4 参照に「上限10」または「10）」が含まれること
  grep -E 'OB-5' "$supervision_md" \
    | grep -q '10' \
    || fail "supervision.md OB-5 行に上限 '10' が含まれていない（AC1 未実装: 現在は '上限5'）"
}

# ---------------------------------------------------------------------------
# AC2: su-observer-constraints.md L14 SU-4 定義に「10」が含まれること
# WHEN: plugins/twl/skills/su-observer/refs/su-observer-constraints.md を参照する
# THEN: SU-4 テーブル行に「10」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC2 #1560: su-observer-constraints.md SU-4 行に上限 10 が含まれている" {
  local constraints_md
  constraints_md="$REPO_ROOT/skills/su-observer/refs/su-observer-constraints.md"

  [[ -f "$constraints_md" ]] \
    || fail "su-observer-constraints.md が存在しない: $constraints_md"

  grep -qE '^[[:space:]]*\|[[:space:]]*SU-4[[:space:]]*\|' "$constraints_md" \
    || fail "su-observer-constraints.md に SU-4 テーブル行が存在しない"

  grep -E '^[[:space:]]*\|[[:space:]]*SU-4[[:space:]]*\|' "$constraints_md" \
    | grep -q '10' \
    || fail "su-observer-constraints.md SU-4 行に上限 '10' が含まれていない（AC2 未実装）"
}

# ---------------------------------------------------------------------------
# AC2: su-observer-constraints.md L28 禁止事項に「10」が含まれること
# WHEN: MUST NOT セクションを参照する
# THEN: SU-4 禁止記述に「10」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC2 #1560: su-observer-constraints.md 禁止事項に 10 を超える controller 禁止が含まれている" {
  local constraints_md
  constraints_md="$REPO_ROOT/skills/su-observer/refs/su-observer-constraints.md"

  [[ -f "$constraints_md" ]] \
    || fail "su-observer-constraints.md が存在しない: $constraints_md"

  # 「10 を超える」または「10.*controller」パターンが禁止事項セクションに存在すること
  grep -qE '10.*controller|controller.*10|10.*超' "$constraints_md" \
    || fail "su-observer-constraints.md 禁止事項に上限 '10' の記述が含まれていない（AC2 未実装: 現在は '5'）"
}

# ---------------------------------------------------------------------------
# AC2: su-observer-skill-design.md L142 に「10 を超える」が含まれること
# WHEN: plugins/twl/architecture/designs/su-observer-skill-design.md を参照する
# THEN: MUST NOT リストに「10 を超える」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC2 #1560: su-observer-skill-design.md 禁止事項に 10 を超える controller 記述が含まれている" {
  local design_md
  design_md="$REPO_ROOT/architecture/designs/su-observer-skill-design.md"

  [[ -f "$design_md" ]] \
    || fail "su-observer-skill-design.md が存在しない: $design_md"

  grep -qE '10.*超|10.*controller|controller.*10' "$design_md" \
    || fail "su-observer-skill-design.md に '10 を超える' の記述が含まれていない（AC2 未実装: 現在は '5 を超える'）"
}

# ---------------------------------------------------------------------------
# AC2: observation.md L140 OB-5 注記に「SU-4」参照が上限 10 を示すこと
# WHEN: plugins/twl/architecture/domain/contexts/observation.md を参照する
# THEN: OB-5 注記の SU-4 言及に「10」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC2 #1560: observation.md OB-5 注記の SU-4 言及に上限 10 が含まれている" {
  local observation_md
  observation_md="$REPO_ROOT/architecture/domain/contexts/observation.md"

  [[ -f "$observation_md" ]] \
    || fail "observation.md が存在しない: $observation_md"

  # OB-5 注記セクション内（2行以内）に SU-4 と 10 が含まれること
  # 方式: OB-5 行を grep し、その行に 10 が含まれるか確認
  grep -E 'OB-5' "$observation_md" \
    | grep -qE 'SU-4' \
    || fail "observation.md OB-5 注記に SU-4 参照が存在しない"

  grep -E 'OB-5' "$observation_md" \
    | grep -q '10' \
    || fail "observation.md OB-5 注記の SU-4 言及に上限 '10' が含まれていない（AC2 未実装）"
}

# ---------------------------------------------------------------------------
# AC2: su-observer-wave-management.md L68 に「SU-4 制約（10 controllers 以内）」が含まれること
# WHEN: plugins/twl/skills/su-observer/refs/su-observer-wave-management.md を参照する
# THEN: SU-4 制約の記述に「10」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC2 #1560: su-observer-wave-management.md SU-4 制約記述に 10 が含まれている" {
  local wave_mgmt_md
  wave_mgmt_md="$REPO_ROOT/skills/su-observer/refs/su-observer-wave-management.md"

  [[ -f "$wave_mgmt_md" ]] \
    || fail "su-observer-wave-management.md が存在しない: $wave_mgmt_md"

  grep -qE 'SU-4.*10|10.*SU-4|SU-4.*controller.*10|10.*controller' "$wave_mgmt_md" \
    || fail "su-observer-wave-management.md SU-4 制約記述に上限 '10' が含まれていない（AC2 未実装: 現在は '5 Issue 以内'）"
}

# ---------------------------------------------------------------------------
# AC3: observer-parallel-check.sh の SU-4 判定閾値が 10 に更新されていること
# WHEN: plugins/twl/scripts/lib/observer-parallel-check.sh の必須条件3を参照する
# THEN: `controller_count + 1 > 10` のパターンが存在する（旧: > 4）
# RED: 実装前は fail する（現在は > 4 のまま）
# ---------------------------------------------------------------------------

@test "AC3 #1560: observer-parallel-check.sh 必須条件3 の閾値が 10 に更新されている" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # 新閾値パターンが存在すること
  grep -qE 'controller_count[[:space:]]*\+[[:space:]]*1[[:space:]]*>[[:space:]]*10' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に 'controller_count + 1 > 10' が存在しない（AC3 未実装: 現在は '> 4'）"
}

# ---------------------------------------------------------------------------
# AC3: observer-parallel-check.sh のエラー文言に「SU-4 ≤10」が含まれること
# WHEN: 必須条件3失敗時のエラーメッセージを確認する
# THEN: エラー文言に「≤10」または「10」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC3 #1560: observer-parallel-check.sh 必須条件3 エラー文言に ≤10 が含まれている" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  # エラーメッセージに ≤10 または 10 が含まれること（SU-4 ≤10 整合違反）
  grep -qE '≤10|SU-4.*10|10.*整合|10.*SU-4' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh 必須条件3 エラー文言に '≤10' が含まれていない（AC3 未実装: 現在は '≤5 整合違反'）"
}

# ---------------------------------------------------------------------------
# AC3: observer-parallel-check.sh ヘッダーコメントに「≤ 10 並列 OK」が含まれること
# WHEN: ファイルヘッダーコメントを確認する
# THEN: 「≤ 10 並列 OK」または「≤10 並列 OK」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC3 #1560: observer-parallel-check.sh ヘッダーコメントに ≤ 10 並列 OK が含まれている" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -qE '≤[[:space:]]*10[[:space:]]*並列[[:space:]]*OK|≤10.*並列.*OK' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh ヘッダーに '≤ 10 並列 OK' が含まれていない（AC3 未実装: 現在は '≤ 4 並列 OK'）"
}

# ---------------------------------------------------------------------------
# AC4: spawn-controller.sh のSU-4関連コメント/エラーメッセージが 10 に更新されていること
# WHEN: plugins/twl/skills/su-observer/scripts/spawn-controller.sh を参照する
# THEN: SU-4 または parallel check 関連コメントに「10」が含まれる
# RED: 実装前は fail する
# ---------------------------------------------------------------------------

@test "AC4 #1560: spawn-controller.sh の SU-4 関連コメントまたはエラーメッセージに 10 が含まれている" {
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  # SU-4 または並列チェック関連の行に 10 が含まれること
  grep -qE 'SU-4.*10|10.*SU-4|≤[[:space:]]*10|10.*並列|並列.*10' "$SPAWN_CONTROLLER" \
    || fail "spawn-controller.sh に SU-4 上限 '10' の記述が含まれていない（AC4 未実装）"
}

# ---------------------------------------------------------------------------
# AC4: spawn-controller.sh の SKIP_PARALLEL_CHECK 運用基準が変更されていないこと
# WHEN: spawn-controller.sh を参照する
# THEN: SKIP_PARALLEL_CHECK 関連記述が存在する（削除されていない）
# RED: SKIP_PARALLEL_CHECK が削除されていれば fail する
# ---------------------------------------------------------------------------

@test "AC4 #1560: spawn-controller.sh の SKIP_PARALLEL_CHECK 運用基準が保持されている" {
  [[ -f "$SPAWN_CONTROLLER" ]] \
    || fail "spawn-controller.sh が存在しない: $SPAWN_CONTROLLER"

  grep -q 'SKIP_PARALLEL_CHECK' "$SPAWN_CONTROLLER" \
    || fail "spawn-controller.sh から SKIP_PARALLEL_CHECK が削除されている（AC4 要件: 削除禁止）"
}

# ---------------------------------------------------------------------------
# AC5 #1560: 新閾値 boundary ケース - controller_count=9 → PASS（spawn 後 10 controllers = 上限）
# WHEN: OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=9 で _check_parallel_spawn_eligibility を呼ぶ
# THEN: exit 0（9+1=10 ≤ 10 なので PASS）
# RED: 実装前は fail する（現在の閾値 > 4 では controller_count=9 は exit 2 になる）
# ---------------------------------------------------------------------------

@test "AC5 #1560: controller_count=9（+1=10≤10）時に exit 0 を返す（新閾値 boundary PASS）" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=9 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "exit コードは 0 であるべきだが $status だった（controller_count=9 → +1=10 ≤ 10 なので PASS すべき、AC5 未実装: 現在の閾値は > 4）"
}

# ---------------------------------------------------------------------------
# AC5 #1560: 新閾値 boundary ケース - controller_count=10 → DENY（10+1=11 > 10）
# WHEN: OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=10 で _check_parallel_spawn_eligibility を呼ぶ
# THEN: exit 2（10+1=11 > 10 で SU-4 違反）
# RED: 現在も exit 2 になるが、エラー文言の閾値表記が更新後に正しく「≤10」を示す必要あり
# NOTE: この boundary DENY テストは実装前後で両方 exit 2 だが、エラー文言検証で RED を担保する
# ---------------------------------------------------------------------------

@test "AC5 #1560: controller_count=10（+1=11>10）時に exit 2 を返す（新閾値 boundary DENY）" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=10 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  " 2>&1

  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（controller_count=10 は SU-4 上限超過: 10+1=11 > 10）"

  # エラー文言に新閾値（10）が含まれること（AC3 エラー文言更新の検証）
  echo "$output" | grep -qE '≤10|10.*整合|SU-4.*10|11.*>[[:space:]]*10' \
    || fail "DENY 時エラー文言に新閾値 '10' が含まれていない（AC3/AC5 未実装: 文言が古い '≤5 整合違反' のまま）"
}

# ---------------------------------------------------------------------------
# AC5 #1560: 旧閾値 boundary（controller_count=4）は新閾値では PASS すること
# WHEN: OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=4 で呼ぶ
# THEN: exit 0（4+1=5 ≤ 10 なので新閾値では PASS）
# RED: 実装前は fail する（現在の閾値 > 4 では 4+1=5>4 で exit 2 になる）
# NOTE: 既存テスト "AC5a: controller_count=4（+1=5>4）時に exit 2 を返す" は旧閾値前提のため
#       実装後はそのテスト自体が fail する（旧閾値テストの扱いは実装 Issue で判断）
# ---------------------------------------------------------------------------

@test "AC5 #1560: controller_count=4（+1=5≤10）は新閾値では exit 0 を返す（旧 boundary 動作変更確認）" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=4 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "exit コードは 0 であるべきだが $status だった（controller_count=4 は新閾値 ≤10 では PASS すべき、AC5 未実装）"
}

# ---------------------------------------------------------------------------
# AC6: pitfalls-catalog.md L559 に「≤ 10 並列 MUST」が含まれること
# WHEN: plugins/twl/skills/su-observer/refs/pitfalls-catalog.md §11.3 を参照する
# THEN: 「≤ 10 並列 MUST」または「10.*MUST」が含まれる
# RED: 実装前は fail する（現在は「≤ 4 並列 MUST」）
# ---------------------------------------------------------------------------

@test "AC6 #1560: pitfalls-catalog.md §11.3 に ≤ 10 並列 MUST が含まれている" {
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qE '≤[[:space:]]*10.*MUST|MUST.*≤[[:space:]]*10|10.*並列.*MUST|MUST.*10.*並列' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に '≤ 10 並列 MUST' が含まれていない（AC6 未実装: 現在は '≤ 4 並列 MUST'）"
}

# ---------------------------------------------------------------------------
# AC6: pitfalls-catalog.md L570-583 疑似コードに「count + 1 <= 10」が含まれること
# WHEN: §11.3 flowchart/疑似コードを参照する
# THEN: must_3 の条件式に「<= 10」または「≤ 10」が含まれる
# RED: 実装前は fail する（現在は「count + 1 <= 4」）
# ---------------------------------------------------------------------------

@test "AC6 #1560: pitfalls-catalog.md 疑似コード must_3 の条件式が <= 10 に更新されている" {
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qE 'count[[:space:]]*\+[[:space:]]*1[[:space:]]*(<=|≤)[[:space:]]*10' "$catalog" \
    || fail "pitfalls-catalog.md 疑似コードに 'count + 1 <= 10' が含まれていない（AC6 未実装: 現在は '<= 4'）"
}

# ---------------------------------------------------------------------------
# AC6: pitfalls-catalog.md L589 SU-4 整合記述が「≤10 整合: controller_count + 1 ≤ 10」に更新されていること
# WHEN: 必須条件根拠セクションを参照する
# THEN: 「SU-4 ≤10」または「controller_count + 1 ≤ 10」が含まれる
# RED: 実装前は fail する（現在は「SU-4 ≤5 整合: controller_count + 1 ≤ 4」）
# ---------------------------------------------------------------------------

@test "AC6 #1560: pitfalls-catalog.md SU-4 整合記述が ≤10 に更新されている" {
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qE 'SU-4[[:space:]]*(≤10|≤ 10)|controller_count[[:space:]]*\+[[:space:]]*1[[:space:]]*(≤|<=)[[:space:]]*10' "$catalog" \
    || fail "pitfalls-catalog.md SU-4 整合記述に '≤10' が含まれていない（AC6 未実装: 現在は '≤5 整合: controller_count + 1 ≤ 4'）"
}

# ---------------------------------------------------------------------------
# AC7: 実証検証 - CONTROLLER_COUNT=9 → exit 0
# WHEN: OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=9 を env-injection で渡してスクリプト直接実行
# THEN: exit 0（9+1=10 ≤ 10 なので PASS）
# RED: 実装前は fail する（現在の閾値 > 4 では exit 2 になる）
# NOTE: スクリプト直接実行（bash script.sh）のため source guard 不要
# ---------------------------------------------------------------------------

@test "AC7 #1560: env-injection CONTROLLER_COUNT=9 で observer-parallel-check.sh が exit 0 を返す" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=9 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "AC7 実証: CONTROLLER_COUNT=9 で exit $status が返った（期待: exit 0 / AC3 閾値更新未実装）"
}

# ---------------------------------------------------------------------------
# AC7: 実証検証 - CONTROLLER_COUNT=10 → exit 2
# WHEN: OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=10 を env-injection で渡して実行
# THEN: exit 2（10+1=11 > 10 で DENY）
# RED: 実装前後ともに exit 2 だが、エラー文言に「10」が含まれることで RED を確認する
# ---------------------------------------------------------------------------

@test "AC7 #1560: env-injection CONTROLLER_COUNT=10 で observer-parallel-check.sh が exit 2 を返す" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=10 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  " 2>&1

  [[ "$status" -eq 2 ]] \
    || fail "AC7 実証: CONTROLLER_COUNT=10 で exit $status が返った（期待: exit 2）"

  # エラー文言に新閾値（10）が反映されていること
  echo "$output" | grep -qE '≤10|10.*整合|SU-4.*10|11.*>[[:space:]]*10' \
    || fail "AC7 実証: exit 2 だがエラー文言に新閾値 '10' が含まれていない（AC3 文言更新未実装）"
}

# ---------------------------------------------------------------------------
# AC7: 実証検証 - CONTROLLER_COUNT=11 → exit 2
# WHEN: OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=11 を env-injection で渡して実行
# THEN: exit 2（11+1=12 > 10 で DENY）
# RED: エラー文言に「10」が含まれることで文言更新の RED を確認する
# ---------------------------------------------------------------------------

@test "AC7 #1560: env-injection CONTROLLER_COUNT=11 で observer-parallel-check.sh が exit 2 を返す" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=true \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=11 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3 S-4' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  " 2>&1

  [[ "$status" -eq 2 ]] \
    || fail "AC7 実証: CONTROLLER_COUNT=11 で exit $status が返った（期待: exit 2）"

  # エラー文言に新閾値（10）が反映されていること
  echo "$output" | grep -qE '≤10|10.*整合|SU-4.*10|12.*>[[:space:]]*10' \
    || fail "AC7 実証: exit 2 だがエラー文言に新閾値 '10' が含まれていない（AC3 文言更新未実装）"
}
