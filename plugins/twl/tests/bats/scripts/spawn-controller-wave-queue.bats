#!/usr/bin/env bats
# spawn-controller-wave-queue.bats - Issue #1427
#
# spawn-controller.sh の wave-queue.json 自動 enqueue 強制化を検証する。
#
# Coverage:
#   AC-1: CHAIN_WAVE_QUEUE_ENTRY 未設定でも current_wave が CHAIN_ISSUE で更新される
#   AC-2: wave-queue.json 不在時の初期化が CHAIN_WAVE_QUEUE_ENTRY 有無に関わらず実行され schema 準拠
#   AC-3: 既存 current_wave > 新規 CHAIN_ISSUE 時は stderr に warning、値は overwrite しない
#   AC-4: CHAIN_WAVE_QUEUE_ENTRY 提供時の queue append 動作（後方互換 regression guard）
#   AC-6: 破損 JSON 存在時に WARN を stderr に出して spawn を継続する

load '../helpers/common'

# ---------------------------------------------------------------------------
# Paths (resolved once at load time)
# ---------------------------------------------------------------------------

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
SPAWN_CONTROLLER="${PLUGIN_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
WAVE_QUEUE_SCHEMA="${PLUGIN_ROOT}/skills/su-observer/schemas/wave-queue.schema.json"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# _valid_queue_entry: AC-4/AC-6 テスト用の最小限有効 CHAIN_WAVE_QUEUE_ENTRY
_valid_queue_entry() {
  printf '{"wave":%s,"issues":[1427],"spawn_cmd_argv":["bash","noop.sh"],"depends_on_waves":[%s],"spawn_when":"all_current_wave_idle_completed"}' \
    "$1" "$2"
}

# _run_wave_queue: spawn-controller.sh を wave-queue テスト用最小環境で呼び出す
# 引数: (すべて env var として渡すこと)
#   CHAIN_ISSUE, CHAIN_WAVE_QUEUE_ENTRY (optional), TEST_DIR
# 出力: wave-queue.json は $TEST_DIR/.supervisor/wave-queue.json に作成される
_run_spawn_controller() {
  local test_dir="$1"
  local chain_issue="$2"
  local chain_wave_queue_entry="${3:-}"

  local autopilot_dir="${test_dir}/autopilot"
  local supervisor_dir="${test_dir}/.supervisor"
  mkdir -p "$autopilot_dir" "$supervisor_dir"

  # fake AUTOPILOT_LAUNCH_SH (exec 先を no-op に差し替え)
  local fake_launch="${test_dir}/fake-launch.sh"
  cat > "$fake_launch" << 'LAUNCH_EOF'
#!/usr/bin/env bash
exit 0
LAUNCH_EOF
  chmod +x "$fake_launch"

  # SKIP_PARALLEL_CHECK=1 の intervention-log は $test_dir/.supervisor 配下に落ちるよう
  # CWD を test_dir に変えて spawn-controller.sh を実行する。
  # CHAIN_AUTOPILOT_DIR はスクリプト内で "" にリセットされるため、--autopilot-dir で渡す。
  (
    cd "$test_dir"
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats-test-isolation" \
    AUTOPILOT_LAUNCH_SH="$fake_launch" \
    CHAIN_WAVE_QUEUE_ENTRY="$chain_wave_queue_entry" \
      bash "$SPAWN_CONTROLLER" \
        co-autopilot "${test_dir}/prompt.txt" \
        --with-chain \
        --issue "$chain_issue" \
        --project-dir "$test_dir" \
        --autopilot-dir "$autopilot_dir"
  )
}

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  TEST_DIR="$(mktemp -d)"
  echo "test prompt" > "${TEST_DIR}/prompt.txt"
  WAVE_QUEUE_FILE="${TEST_DIR}/.supervisor/wave-queue.json"
}

teardown() {
  common_teardown
  [[ -n "${TEST_DIR:-}" && -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}

# ---------------------------------------------------------------------------
# AC-1: CHAIN_WAVE_QUEUE_ENTRY 未設定でも current_wave が CHAIN_ISSUE で更新される
# RED: 現行実装では CHAIN_WAVE_QUEUE_ENTRY 未設定時に wave-queue.json を操作しない
# ---------------------------------------------------------------------------

@test "ac1: CHAIN_WAVE_QUEUE_ENTRY 未設定でも current_wave が CHAIN_ISSUE 値で更新される" {
  run _run_spawn_controller "$TEST_DIR" "46"

  # wave-queue.json が作成されていることを確認
  assert [ -f "$WAVE_QUEUE_FILE" ]

  local actual_wave
  actual_wave="$(jq -r '.current_wave' "$WAVE_QUEUE_FILE")"
  assert_equal "$actual_wave" "46"
}

@test "ac1-existing: 既存 wave-queue.json の current_wave が CHAIN_ISSUE で更新される" {
  # 事前に current_wave=40 の wave-queue.json を用意
  mkdir -p "${TEST_DIR}/.supervisor"
  printf '{"version":1,"current_wave":40,"queue":[]}\n' > "$WAVE_QUEUE_FILE"

  run _run_spawn_controller "$TEST_DIR" "46"

  local actual_wave
  actual_wave="$(jq -r '.current_wave' "$WAVE_QUEUE_FILE")"
  assert_equal "$actual_wave" "46"
}

# ---------------------------------------------------------------------------
# AC-2: wave-queue.json 不在時の初期化が schema 準拠で実行される
# RED: 現行実装では CHAIN_WAVE_QUEUE_ENTRY 未設定時にファイルを作成しない
# ---------------------------------------------------------------------------

@test "ac2: wave-queue.json 不在時に schema 準拠の初期 JSON が作成される" {
  run _run_spawn_controller "$TEST_DIR" "46"

  assert [ -f "$WAVE_QUEUE_FILE" ]

  # schema 必須フィールドを検証 (additionalProperties: false 準拠)
  local version current_wave queue_type
  version="$(jq -r '.version' "$WAVE_QUEUE_FILE")"
  current_wave="$(jq -r '.current_wave' "$WAVE_QUEUE_FILE")"
  queue_type="$(jq -r '.queue | type' "$WAVE_QUEUE_FILE")"

  assert_equal "$version" "1"
  assert_equal "$current_wave" "46"
  assert_equal "$queue_type" "array"

  # additionalProperties: false — version/current_wave/queue 以外のキーが存在しないこと
  local extra_keys
  extra_keys="$(jq -r 'keys | map(select(. != "version" and . != "current_wave" and . != "queue")) | length' "$WAVE_QUEUE_FILE")"
  assert_equal "$extra_keys" "0"
}

# ---------------------------------------------------------------------------
# AC-3: existing current_wave > new CHAIN_ISSUE → stderr に warning、overwrite しない
# RED: 現行実装では warning を出力しない（CHAIN_WAVE_QUEUE_ENTRY 未設定時は何もしない）
# ---------------------------------------------------------------------------

@test "ac3: existing current_wave > CHAIN_ISSUE → stderr に warning を出力し値を overwrite しない" {
  # current_wave=50 が存在する状態で CHAIN_ISSUE=46 で spawn
  mkdir -p "${TEST_DIR}/.supervisor"
  printf '{"version":1,"current_wave":50,"queue":[]}\n' > "$WAVE_QUEUE_FILE"

  run _run_spawn_controller "$TEST_DIR" "46"

  # wave-queue.json の current_wave が 50 のまま（overwrite されていない）
  local actual_wave
  actual_wave="$(jq -r '.current_wave' "$WAVE_QUEUE_FILE")"
  assert_equal "$actual_wave" "50"

  # stderr に warning が含まれること
  assert_output --partial "[spawn-controller] WARN: existing current_wave"
}

@test "ac3-no-extra-fields: warning 時に wave-queue.json に追加フィールドが書き込まれない" {
  mkdir -p "${TEST_DIR}/.supervisor"
  printf '{"version":1,"current_wave":50,"queue":[]}\n' > "$WAVE_QUEUE_FILE"

  run _run_spawn_controller "$TEST_DIR" "46"

  local extra_keys
  extra_keys="$(jq -r 'keys | map(select(. != "version" and . != "current_wave" and . != "queue")) | length' "$WAVE_QUEUE_FILE")"
  assert_equal "$extra_keys" "0"
}

# ---------------------------------------------------------------------------
# AC-4: CHAIN_WAVE_QUEUE_ENTRY 提供時の queue append 動作（後方互換 regression guard）
# GREEN: 現行実装でも動作する（regression guard）
# ---------------------------------------------------------------------------

@test "ac4: CHAIN_WAVE_QUEUE_ENTRY 提供時に queue にエントリが append される" {
  local entry
  entry="$(_valid_queue_entry 47 46)"

  run _run_spawn_controller "$TEST_DIR" "46" "$entry"

  assert [ -f "$WAVE_QUEUE_FILE" ]

  local queue_len entry_wave
  queue_len="$(jq -r '.queue | length' "$WAVE_QUEUE_FILE")"
  entry_wave="$(jq -r '.queue[0].wave' "$WAVE_QUEUE_FILE")"

  assert_equal "$queue_len" "1"
  assert_equal "$entry_wave" "47"
}

@test "ac4-existing: 既存 queue への append が既存エントリを保持する" {
  mkdir -p "${TEST_DIR}/.supervisor"
  local existing_entry
  existing_entry="$(_valid_queue_entry 47 46)"
  printf '{"version":1,"current_wave":46,"queue":[%s]}\n' "$existing_entry" > "$WAVE_QUEUE_FILE"

  local new_entry
  new_entry="$(_valid_queue_entry 48 47)"

  run _run_spawn_controller "$TEST_DIR" "46" "$new_entry"

  local queue_len
  queue_len="$(jq -r '.queue | length' "$WAVE_QUEUE_FILE")"
  assert_equal "$queue_len" "2"
}

# ---------------------------------------------------------------------------
# AC-6: 破損 JSON 存在時に WARN を stderr に出して spawn を継続する（exit 0）
# RED (Step 2): 現行実装は CHAIN_WAVE_QUEUE_ENTRY 未設定時に broken JSON を処理しない
# ---------------------------------------------------------------------------

@test "ac6: 破損 JSON + CHAIN_WAVE_QUEUE_ENTRY 未設定 → Step2(current_wave update) が WARN して spawn 継続" {
  mkdir -p "${TEST_DIR}/.supervisor"
  printf '{"invalid\n' > "$WAVE_QUEUE_FILE"

  run _run_spawn_controller "$TEST_DIR" "46"

  # spawn が継続する（exit 0）
  assert_success

  # Step 2 (current_wave update) の失敗 WARN が stderr に出力されること
  # RED: 現行実装は Step 2 が存在しないため、この WARN は出力されない
  assert_output --partial "current_wave"
}

@test "ac6-entry: 破損 JSON + CHAIN_WAVE_QUEUE_ENTRY 設定 → Step3(enqueue) が WARN して spawn 継続" {
  mkdir -p "${TEST_DIR}/.supervisor"
  printf '{"invalid\n' > "$WAVE_QUEUE_FILE"

  local entry
  entry="$(_valid_queue_entry 47 46)"

  run _run_spawn_controller "$TEST_DIR" "46" "$entry"

  assert_success
  # Step 3 (enqueue) の失敗 WARN が stderr に出力されること
  assert_output --partial "[spawn-controller] WARN: wave-queue.json enqueue failed"
}
