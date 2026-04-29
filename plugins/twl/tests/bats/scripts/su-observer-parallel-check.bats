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
#   0: 全条件 PASS → ≤ 4 並列 OK
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
# THEN: exit 0（≤ 4 並列 OK）
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
# Scenario: controller_count >= 4 時に exit 2 を返す（SU-4 上限超過）
# WHEN: controller_count=4（+1=5>4）に設定
# THEN: exit 2（spawn 完全禁止）
# ---------------------------------------------------------------------------

@test "AC5a: controller_count=4（+1=5>4）時に exit 2 を返す（SU-4 上限超過）" {
  # RED: 実装前は fail する
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない（前提条件 AC5a 未実装）"

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

  assert_failure
  [[ "$status" -eq 2 ]] \
    || fail "exit コードは 2 であるべきだが $status だった（controller_count=4 は SU-4 上限超過）"
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
