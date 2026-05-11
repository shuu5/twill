#!/usr/bin/env bats
# spawn-controller-pilot-gate.bats - Issue #1650 RED → GREEN テスト
#
# Coverage (AC4):
#   - `--with-chain --issue N` default で reject (exit 2) する
#   - stderr に再現コマンド + 正規 pattern + lesson 参照が含まれる
#   - SKIP_PILOT_GATE=1 + SKIP_PILOT_REASON='...' で bypass 可能
#   - SKIP_PILOT_GATE=1 + SKIP_PILOT_REASON 欠落 → still exit 2
#   - SKIP_PILOT_GATE=1 bypass 時は intervention-log に記録される

load '../helpers/common'

SPAWN_CONTROLLER=""
SUPERVISOR_DIR_TEST=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  SUPERVISOR_DIR_TEST="$SANDBOX/.supervisor"
  mkdir -p "$SUPERVISOR_DIR_TEST"

  # cld-spawn stub
  cat > "$STUB_BIN/cld-spawn" <<'STUB'
#!/usr/bin/env bash
echo "spawned"
exit 0
STUB
  chmod +x "$STUB_BIN/cld-spawn"
  export CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn"

  # autopilot-launch.sh stub（--with-chain bypass 後の実行をキャプチャ）
  AUTOPILOT_LAUNCH_LOG="$SANDBOX/autopilot-launch.log"
  cat > "$STUB_BIN/autopilot-launch.sh" <<STUB
#!/usr/bin/env bash
echo "\$@" >> "${AUTOPILOT_LAUNCH_LOG}"
exit 0
STUB
  chmod +x "$STUB_BIN/autopilot-launch.sh"
  export AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh"
  export AUTOPILOT_LAUNCH_LOG

  # tmux stub
  cat > "$STUB_BIN/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message) echo "test-session"; exit 0 ;;
  list-panes) echo "12345"; exit 0 ;;
  show-options) echo "0"; exit 0 ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$STUB_BIN/tmux"

  # gh stub
  cat > "$STUB_BIN/gh" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$STUB_BIN/gh"

  # prompt file（co-autopilot 通常フローで必要）
  PROMPT_FILE="$SANDBOX/prompt.txt"
  echo "test prompt" > "$PROMPT_FILE"
  export PROMPT_FILE

  export SKIP_PARALLEL_CHECK=1
  export SKIP_PARALLEL_REASON="bats spawn-controller-pilot-gate test"
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC4-1: --with-chain --issue N を default で reject (exit 2)
# ===========================================================================

@test "ac4-1: --with-chain --issue N default rejects with exit 2" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  [ "$status" -eq 2 ]
}

# ===========================================================================
# AC2+AC4-2: stderr に再現コマンド + 正規 pattern + lesson 参照が含まれる
# ===========================================================================

@test "ac2+ac4-2: stderr contains reproduction command" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  [ "$status" -eq 2 ]
  # 再現コマンド（--with-chain --issue）が stderr に含まれる
  echo "$output" | grep -q "\-\-with-chain"
}

@test "ac2+ac4-3: stderr contains canonical pattern (co-autopilot without --with-chain)" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  [ "$status" -eq 2 ]
  # 正規 pattern（--with-chain なしの co-autopilot）への言及が stderr に含まれる
  echo "$output" | grep -qE "spawn-controller.*co-autopilot|正規|canonical"
}

@test "ac2+ac4-4: stderr contains lesson reference (pitfalls-catalog 13.5)" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  [ "$status" -eq 2 ]
  # pitfalls-catalog §13.5 への参照が stderr に含まれる
  echo "$output" | grep -q "13.5"
}

# ===========================================================================
# AC4-5: SKIP_PILOT_GATE=1 + SKIP_PILOT_REASON で bypass 可能
# ===========================================================================

@test "ac4-5: SKIP_PILOT_GATE=1 with SKIP_PILOT_REASON allows bypass (autopilot-launch invoked)" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    SKIP_PILOT_GATE=1 \
    SKIP_PILOT_REASON="bats bypass test reason" \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  # bypass 時は exit 0（autopilot-launch.sh が invoked される）
  [ "$status" -eq 0 ]
  # autopilot-launch.sh が呼ばれた証跡
  [ -f "$AUTOPILOT_LAUNCH_LOG" ]
  grep -q "\-\-issue" "$AUTOPILOT_LAUNCH_LOG"
}

# ===========================================================================
# AC4-6: SKIP_PILOT_GATE=1 + SKIP_PILOT_REASON 欠落 → still reject
# ===========================================================================

@test "ac4-6: SKIP_PILOT_GATE=1 without SKIP_PILOT_REASON still rejects with exit 2" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    SKIP_PILOT_GATE=1 \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  [ "$status" -eq 2 ]
  echo "$output" | grep -qiE "SKIP_PILOT_REASON|reason"
}

# ===========================================================================
# AC4-7: SKIP_PILOT_GATE=1 bypass 時は intervention-log に記録される
# ===========================================================================

@test "ac4-7: SKIP_PILOT_GATE=1 bypass is recorded in intervention-log" {
  cd "$SANDBOX"
  run env \
    SUPERVISOR_DIR=".supervisor" \
    SKIP_PARALLEL_CHECK=1 \
    SKIP_PARALLEL_REASON="bats test" \
    SKIP_PILOT_GATE=1 \
    SKIP_PILOT_REASON="dogfooding escape hatch test" \
    CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
    AUTOPILOT_LAUNCH_SH="$STUB_BIN/autopilot-launch.sh" \
    bash "$SPAWN_CONTROLLER" co-autopilot "$PROMPT_FILE" --with-chain --issue 1650 2>&1
  [ "$status" -eq 0 ]
  # intervention-log に SKIP_PILOT_GATE の記録が残る
  [ -f "$SANDBOX/.supervisor/intervention-log.md" ]
  grep -q "SKIP_PILOT_GATE" "$SANDBOX/.supervisor/intervention-log.md"
}
