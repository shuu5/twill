#!/usr/bin/env bats
# issue-1651-initial-spawn.bats - Issue #1651 RED テスト
#
# bug(spawn-controller): 初回 controller spawn が heartbeat_alive check で
# 構造的に block される (chicken-and-egg)
#
# AC1: _check_parallel_spawn_eligibility に controller_count=0 短絡 path 追加
#      controller_count=0 の場合、必須条件1 (heartbeat_alive) を skip して spawn を許可
# AC2: bats test 追加
#      - controller_count=0 で spawn 成功する test
#      - controller_count>0 + heartbeat 古い → DENY する test (既存挙動維持)
# AC3: pitfalls-catalog §11.3 拡張
#      初回 spawn 例外 path を明記 (chicken-and-egg 回避 logic)

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
# AC1: controller_count=0 短絡 path の実装確認
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: observer-parallel-check.sh に controller_count=0 の短絡 path が存在する
# WHEN: observer-parallel-check.sh の内容を確認する
# THEN: controller_count == 0 の分岐が存在する
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC1 #1651: observer-parallel-check.sh に controller_count=0 短絡 path が存在する" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  grep -qE 'controller_count[[:space:]]*==[[:space:]]*0|controller_count[[:space:]]*-eq[[:space:]]*0' "$PARALLEL_CHECK_LIB" \
    || fail "observer-parallel-check.sh に controller_count=0 の短絡 path が存在しない（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + heartbeat_alive=false → exit 0 (初回 spawn 許可)
# WHEN: controller_count=0, heartbeat_alive=false, mode=auto で呼び出す
# THEN: exit 0（初回 spawn は heartbeat check を skip して許可される）
# RED: 現状は heartbeat_alive=false → exit 2 を返す
# ---------------------------------------------------------------------------

@test "AC1 #1651: controller_count=0 + heartbeat_alive=false → exit 0 (初回 spawn 許可)" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  assert_success \
    || fail "controller_count=0 + heartbeat_alive=false で exit $status が返った（期待: exit 0 / AC1 未実装: 現状は heartbeat check で exit 2）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + heartbeat_alive=false → NOT exit 2 (spawn 完全禁止にならない)
# WHEN: controller_count=0 で heartbeat check をスキップする場合
# THEN: exit 2 にはならない（spawn 許可 or degrade は許容）
# RED: 現状は exit 2 を返す
# ---------------------------------------------------------------------------

@test "AC1 #1651: controller_count=0 + heartbeat_alive=false → spawn が DENY されない" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  " 2>&1

  [[ "$status" -ne 2 ]] \
    || fail "controller_count=0 + heartbeat_alive=false で exit 2（spawn 完全禁止）が返った — 初回 spawn は heartbeat check を skip すべき（AC1 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 で INFO ログが出力される
# WHEN: controller_count=0 で呼び出す
# THEN: stderr に initial spawn に関するログメッセージが出力される
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC1 #1651: controller_count=0 初回 spawn 時に INFO ログが stderr に出力される" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run --separate-stderr bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  echo "$stderr" | grep -qiE 'initial spawn|controller_count=0|初回|heartbeat.*skip|skip.*heartbeat' \
    || fail "controller_count=0 時に初回 spawn に関する INFO ログが出力されていない（AC1 未実装）"
}

# ===========================================================================
# AC2: bats テスト追加（既存挙動維持の回帰テスト）
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: controller_count>0 + heartbeat_alive=false → DENY (exit 2) - 既存挙動維持
# WHEN: controller_count=1, heartbeat_alive=false で呼び出す（Pilot 存在ケース）
# THEN: exit 2（並列 spawn 時は heartbeat check が有効のまま）
# GREEN: 既存動作のため実装前後ともに PASS
# ---------------------------------------------------------------------------

@test "AC2 #1651 regression: controller_count=1 + heartbeat_alive=false → exit 2 (既存挙動維持)" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=auto \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=1 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='S-3' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  [[ "$status" -eq 2 ]] \
    || fail "controller_count=1 + heartbeat_alive=false で exit $status が返った（期待: exit 2 — 並列 spawn 時は heartbeat check を維持すべき）"
}

# ---------------------------------------------------------------------------
# Scenario: controller_count=0 + mode=default → exit 2 (mode 必須条件は適用される)
# WHEN: controller_count=0 でも mode が invalid な場合
# THEN: exit 2（heartbeat check のみ skip、mode check は適用）
# RED: 未実装のため fail する（現状は controller_count で分岐なし）
# ---------------------------------------------------------------------------

@test "AC2 #1651: controller_count=0 + mode=default → mode 必須条件は適用される (exit 2)" {
  [[ -f "$PARALLEL_CHECK_LIB" ]] \
    || fail "observer-parallel-check.sh が存在しない: $PARALLEL_CHECK_LIB"

  run bash -c "
    source '$PARALLEL_CHECK_LIB'
    OBSERVER_PARALLEL_CHECK_SNAPSHOT_TS=1000000 \
    OBSERVER_PARALLEL_CHECK_HEARTBEAT_ALIVE=false \
    OBSERVER_PARALLEL_CHECK_MODE=default \
    OBSERVER_PARALLEL_CHECK_CONTROLLER_COUNT=0 \
    OBSERVER_PARALLEL_CHECK_MONITOR_CLD=true \
    OBSERVER_PARALLEL_CHECK_STATES='' \
    OBSERVER_PARALLEL_CHECK_BUDGET_MIN=200 \
    OBSERVER_PARALLEL_CHECK_BUDGET_THRESHOLD=150 \
    _check_parallel_spawn_eligibility
  "

  [[ "$status" -eq 2 ]] \
    || fail "controller_count=0 + mode=default で exit $status が返った（期待: exit 2 — mode check は controller_count=0 でも適用すべき）"
}

# ===========================================================================
# AC3: pitfalls-catalog §11.3 拡張
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §11.3 に chicken-and-egg 回避の記述が存在する
# WHEN: pitfalls-catalog.md §11.3 セクションを参照する
# THEN: chicken-and-egg または初回 spawn 例外 path の記述が存在する
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC3 #1651: pitfalls-catalog.md §11.3 に chicken-and-egg 回避の記述が存在する" {
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qiE 'chicken.and.egg|初回.*spawn|initial.*spawn|controller_count.*=.*0.*skip|heartbeat.*skip' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に chicken-and-egg 回避の記述が存在しない（AC3 未実装）"
}

# ---------------------------------------------------------------------------
# Scenario: pitfalls-catalog.md §11.3 に controller_count=0 の例外 path が明記されている
# WHEN: pitfalls-catalog.md §11.3 セクションを参照する
# THEN: controller_count=0 の case の記述が存在する
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC3 #1651: pitfalls-catalog.md §11.3 に controller_count=0 例外 path が明記されている" {
  local catalog
  catalog="$REPO_ROOT/skills/su-observer/refs/pitfalls-catalog.md"

  [[ -f "$catalog" ]] \
    || fail "pitfalls-catalog.md が存在しない: $catalog"

  grep -qE 'controller_count[[:space:]]*==[[:space:]]*0|controller_count[[:space:]]*=[[:space:]]*0|初回.*spawn.*例外|#1651' "$catalog" \
    || fail "pitfalls-catalog.md §11.3 に controller_count=0 例外 path の記述が存在しない（AC3 未実装）"
}
