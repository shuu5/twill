#!/usr/bin/env bats
# spawn-controller-with-chain.bats - --with-chain オプションのユニットテスト
# Generated from: Issue #835 (spawn-controller.sh 経由 co-autopilot chain 自動開始)
#
# Requirements:
#   - co-autopilot + --with-chain --issue N で autopilot-launch.sh に委譲する
#   - --with-chain なしは従来の cld-spawn 経由（wt-* window）
#   - co-autopilot 以外で --with-chain を指定するとエラー
#   - --with-chain 時に --issue N がなければエラー

load '../helpers/common'

SPAWN_CONTROLLER=""
AUTOPILOT_LAUNCH_ARGS_LOG=""
CLD_SPAWN_ARGS_LOG=""

setup() {
  common_setup

  SPAWN_CONTROLLER="$REPO_ROOT/skills/su-observer/scripts/spawn-controller.sh"
  export SPAWN_CONTROLLER

  AUTOPILOT_LAUNCH_ARGS_LOG="$SANDBOX/autopilot-launch-args.log"
  export AUTOPILOT_LAUNCH_ARGS_LOG

  CLD_SPAWN_ARGS_LOG="$SANDBOX/cld-spawn-args.log"
  export CLD_SPAWN_ARGS_LOG

  # autopilot-launch.sh mock: 引数を記録して正常終了
  cat > "$STUB_BIN/autopilot-launch.sh" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${AUTOPILOT_LAUNCH_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/autopilot-launch.sh"

  # cld-spawn mock: 引数を記録して正常終了
  cat > "$STUB_BIN/cld-spawn" <<'MOCK'
#!/usr/bin/env bash
echo "$@" >> "${CLD_SPAWN_ARGS_LOG:-/dev/null}"
exit 0
MOCK
  chmod +x "$STUB_BIN/cld-spawn"

  # Issue #1644: CLD_SPAWN_OVERRIDE env var で mock 切り替え
  cat > "$SANDBOX/run-spawn-controller.sh" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
_DEFAULT_AUTOPILOT_LAUNCH="$STUB_BIN/autopilot-launch.sh"
_AUTOPILOT_LAUNCH_SH="\${AUTOPILOT_LAUNCH_SH:-\$_DEFAULT_AUTOPILOT_LAUNCH}"
# #1650: --with-chain gate は default-deny のため、このレガシーテスト suite では SKIP_PILOT_GATE=1 で bypass する
exec env CLD_SPAWN_OVERRIDE="$STUB_BIN/cld-spawn" \
  AUTOPILOT_LAUNCH_SH="\$_AUTOPILOT_LAUNCH_SH" \
  SKIP_PARALLEL_CHECK=\${SKIP_PARALLEL_CHECK:-1} \
  SKIP_PARALLEL_REASON="\${SKIP_PARALLEL_REASON:-bats test}" \
  SKIP_PILOT_GATE=1 \
  SKIP_PILOT_REASON="bats spawn-controller-with-chain legacy test (#1650)" \
  bash "$SPAWN_CONTROLLER" "\$@"
WRAPPER
  chmod +x "$SANDBOX/run-spawn-controller.sh"

  # テスト用 prompt ファイル
  echo "context: issue #835 chain test" > "$SANDBOX/prompt.txt"
}

teardown() {
  common_teardown
}

# ===========================================================================
# Requirement: --with-chain で autopilot-launch.sh に委譲する
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: co-autopilot + --with-chain --issue N で autopilot-launch.sh が呼ばれる
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain --issue 835 を実行
# THEN: autopilot-launch.sh が --issue 835 で呼ばれる
# ---------------------------------------------------------------------------

@test "--with-chain: autopilot-launch.sh が --issue 付きで呼ばれる" {
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 835 2>&1

  assert_success
  [[ -f "$AUTOPILOT_LAUNCH_ARGS_LOG" ]] \
    || fail "autopilot-launch.sh が呼ばれなかった（ログファイル未生成）"
  grep -q -- "--issue 835" "$AUTOPILOT_LAUNCH_ARGS_LOG" \
    || fail "autopilot-launch.sh が --issue 835 で呼ばれなかった: $(cat "$AUTOPILOT_LAUNCH_ARGS_LOG" 2>/dev/null)"
}

# ---------------------------------------------------------------------------
# Scenario: --with-chain 時は cld-spawn が呼ばれない
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain --issue 835 を実行
# THEN: cld-spawn が呼ばれない（chain 連携モードで bypass）
# ---------------------------------------------------------------------------

@test "--with-chain: cld-spawn は呼ばれない" {
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 835 2>&1

  assert_success
  [[ ! -f "$CLD_SPAWN_ARGS_LOG" ]] \
    || fail "chain モードなのに cld-spawn が呼ばれた: $(cat "$CLD_SPAWN_ARGS_LOG" 2>/dev/null)"
}

# ===========================================================================
# Requirement: --with-chain のバリデーション
# ===========================================================================

# ---------------------------------------------------------------------------
# Scenario: co-autopilot 以外で --with-chain はエラー
# WHEN: spawn-controller.sh co-explore <prompt> --with-chain --issue 835 を実行
# THEN: exit 2 + "co-autopilot のみ" エラー
# ---------------------------------------------------------------------------

@test "--with-chain: co-autopilot 以外ではエラー" {
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-explore "$SANDBOX/prompt.txt" --with-chain --issue 835 2>&1

  assert_failure
  assert_output --partial "co-autopilot のみ"
}

# ---------------------------------------------------------------------------
# Scenario: --with-chain に --issue がなければエラー
# WHEN: spawn-controller.sh co-autopilot <prompt> --with-chain を実行（--issue 省略）
# THEN: exit 2 + "--issue N が必須" エラー
# ---------------------------------------------------------------------------

@test "--with-chain: --issue 省略でエラー" {
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain 2>&1

  assert_failure
  assert_output --partial "--issue N が必須"
}

# ---------------------------------------------------------------------------
# Scenario: --with-chain なしは従来の cld-spawn 経由（standalone モード）
# WHEN: spawn-controller.sh co-autopilot <prompt> を --with-chain なしで実行
# THEN: cld-spawn が呼ばれ、autopilot-launch.sh は呼ばれない
# ---------------------------------------------------------------------------

@test "standalone モード: --with-chain なしは cld-spawn 経由" {
  run bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --window-name "test-window" 2>&1

  assert_success
  [[ -f "$CLD_SPAWN_ARGS_LOG" ]] \
    || fail "standalone モードで cld-spawn が呼ばれなかった"
  [[ ! -f "$AUTOPILOT_LAUNCH_ARGS_LOG" ]] \
    || fail "standalone モードなのに autopilot-launch.sh が呼ばれた"
}

# ---------------------------------------------------------------------------
# Scenario: --with-chain 時に autopilot-launch.sh が存在しなければエラー
# WHEN: AUTOPILOT_LAUNCH_SH を存在しないパスに設定して実行
# THEN: exit 2 + "not executable" エラー
# ---------------------------------------------------------------------------

@test "--with-chain: autopilot-launch.sh 不在でエラー" {
  run env AUTOPILOT_LAUNCH_SH="/nonexistent/autopilot-launch.sh" \
    bash "$SANDBOX/run-spawn-controller.sh" \
    co-autopilot "$SANDBOX/prompt.txt" --with-chain --issue 835 2>&1

  assert_failure
  assert_output --partial "not executable"
}
