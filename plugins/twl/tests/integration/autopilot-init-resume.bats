#!/usr/bin/env bats
# autopilot-init-resume.bats
# AC-6: bash 版 autopilot-init.sh も orchestrator alive check を持つ
#
# RED フェーズ: 現行実装 (autopilot-init.sh) には orchestrator.pid チェックが
#              存在しないため、全テストは FAIL する。
#
# 現行の autopilot-init.sh の挙動:
#   session.json 存在 + < 24h + 未完了 → 常に exit 1 (block)
#   orchestrator.pid の有無・PID の生死を参照しない

_INTEGRATION_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
_TESTS_DIR="$(cd "$_INTEGRATION_DIR/.." && pwd)"
REPO_ROOT="$(cd "$_TESTS_DIR/.." && pwd)"
_LIB_DIR="$_TESTS_DIR/lib"

load "${_LIB_DIR}/bats-support/load"
load "${_LIB_DIR}/bats-assert/load"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

setup() {
  SANDBOX="$(mktemp -d)"
  export SANDBOX

  mkdir -p "$SANDBOX/scripts"
  mkdir -p "$SANDBOX/.autopilot/issues"
  mkdir -p "$SANDBOX/.autopilot/archive"

  # スクリプトをコピー
  cp "$REPO_ROOT/scripts/"*.sh "$SANDBOX/scripts/" 2>/dev/null || true

  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
  export PROJECT_ROOT="$SANDBOX"

  SCRIPT="$SANDBOX/scripts/autopilot-init.sh"
}

teardown() {
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

# ---------------------------------------------------------------------------
# Helper: session.json + running issue を作成する（未完了セッション）
# ---------------------------------------------------------------------------

_create_active_session() {
  local hours_ago="${1:-1}"
  local started_at
  started_at=$(date -u -d "${hours_ago} hours ago" +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$SANDBOX/.autopilot/session.json" <<JSON
{
  "session_id": "test-session-ac6",
  "started_at": "${started_at}"
}
JSON

  # running issue を1件作成（未完了状態）
  cat > "$SANDBOX/.autopilot/issues/issue-9999.json" <<JSON
{
  "issue": 9999,
  "status": "running",
  "branch": "feat/9999-test",
  "started_at": "${started_at}"
}
JSON
}

# ---------------------------------------------------------------------------
# AC-6-1: orchestrator.pid 不在 → init.sh は resume を許可する (exit 0)
# GIVEN: session.json 存在 + < 24h + 未完了 + orchestrator.pid 不在
# WHEN: autopilot-init.sh --check-only を実行
# THEN: exit 0 で resume 許可
# ---------------------------------------------------------------------------

@test "ac6: init_sh_resumes_when_orchestrator_dead" {
  # RED: 現行実装は orchestrator.pid をチェックしないため、
  #      session.json が < 24h + 未完了なら常に exit 1 → FAIL
  _create_active_session 1

  # orchestrator.pid を作らない（不在状態）
  assert [ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]

  run bash "$SCRIPT" --check-only

  # 期待: exit 0 (resume 許可)
  # 現行実装: exit 1 (orchestrator.pid チェックなし → 常に block) → FAIL
  assert_success
}

# ---------------------------------------------------------------------------
# AC-6-2: orchestrator.pid が alive PID を指す → init.sh は block する (exit 1)
# GIVEN: session.json 存在 + orchestrator.pid に alive PID が書かれている
# WHEN: autopilot-init.sh --check-only を実行
# THEN: exit 1 で block（alive orchestrator が存在するため）
# ---------------------------------------------------------------------------

@test "ac6: init_sh_blocks_when_orchestrator_alive" {
  # このテストは現行実装でも偶然 PASS する可能性があるが、
  # AC-6 の意図（alive PID チェックによる block）を検証する。
  # 現行実装は orchestrator.pid を無視して session.json < 24h で block するため、
  # 結果は同じでも「理由」が違う。実装後は alive PID チェックで block されることを期待する。
  _create_active_session 1

  # 現在プロセスの PID を alive PID として書き込む
  echo $$ > "$SANDBOX/.autopilot/orchestrator.pid"

  run bash "$SCRIPT" --check-only

  # 期待: exit 1 (alive orchestrator により block)
  assert_failure
  assert_output --partial "orchestrator"
  # RED: 現行実装は "orchestrator" という語を出力しない → assert_output が FAIL
}

# ---------------------------------------------------------------------------
# AC-6-3: orchestrator.pid が stale PID (dead) を指す → init.sh は resume 許可 (exit 0)
# GIVEN: session.json 存在 + orchestrator.pid に dead PID が書かれている
# WHEN: autopilot-init.sh --check-only を実行
# THEN: exit 0 (stale pid は無視して resume 許可)
# ---------------------------------------------------------------------------

@test "ac6: init_sh_resumes_when_orchestrator_pid_stale" {
  # RED: 現行実装は orchestrator.pid をチェックしないため、
  #      session.json < 24h + 未完了なら常に exit 1 → FAIL
  _create_active_session 1

  # dead な PID を取得して orchestrator.pid に書き込む
  bash -c 'exit 0' &
  DEAD_PID=$!
  wait "$DEAD_PID" 2>/dev/null || true
  echo "$DEAD_PID" > "$SANDBOX/.autopilot/orchestrator.pid"

  # dead PID であることを確認（前提）
  if kill -0 "$DEAD_PID" 2>/dev/null; then
    skip "PID ${DEAD_PID} が予期せず alive のためスキップ"
  fi

  run bash "$SCRIPT" --check-only

  # 期待: exit 0 (stale pid → resume 許可)
  # 現行実装: orchestrator.pid チェックなし → session.json < 24h で exit 1 → FAIL
  assert_success
}

# ---------------------------------------------------------------------------
# AC-6-4: autopilot-init.sh スクリプト内に orchestrator.pid チェックが存在する (静的検査)
# GIVEN: autopilot-init.sh スクリプト
# WHEN: スクリプト内容を静的に検査する
# THEN: orchestrator.pid を参照するコードが存在する
# ---------------------------------------------------------------------------

@test "ac6: autopilot-init.sh に orchestrator.pid チェックが存在する (静的検査)" {
  # RED: 現行実装には orchestrator.pid のチェックが存在しない → FAIL
  run grep -E "orchestrator\.pid" "$REPO_ROOT/scripts/autopilot-init.sh"
  assert_success
}
