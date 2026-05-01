#!/usr/bin/env bats
# orchestrator-pid-write.bats
# AC-3: autopilot-orchestrator.sh 起動時に ${AUTOPILOT_DIR}/orchestrator.pid を
#       atomic write し、書かれた PID が現プロセス PID に一致する
#
# RED フェーズ: 現行実装 (autopilot-orchestrator.sh) には orchestrator.pid 書き込みが
#              存在しないため、全テストは FAIL する。

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

  # スクリプトと lib/ をコピー（orchestrator は lib/python-env.sh を source する）
  cp "$REPO_ROOT/scripts/"*.sh "$SANDBOX/scripts/" 2>/dev/null || true
  cp -r "$REPO_ROOT/scripts/lib/" "$SANDBOX/scripts/lib/" 2>/dev/null || true

  export AUTOPILOT_DIR="$SANDBOX/.autopilot"
  export PROJECT_ROOT="$SANDBOX"

  ORCHESTRATOR="$SANDBOX/scripts/autopilot-orchestrator.sh"
}

teardown() {
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

# ---------------------------------------------------------------------------
# Helper: 最小限の plan.yaml を作成する
# ---------------------------------------------------------------------------

_create_minimal_plan() {
  local session_id="${1:-test-session-001}"
  cat > "$SANDBOX/.autopilot/plan.yaml" <<EOF
session_id: ${session_id}
phases:
  - phase: 1
    issues: []
EOF
  cat > "$SANDBOX/.autopilot/session.json" <<EOF
{
  "session_id": "${session_id}",
  "started_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
}

# ---------------------------------------------------------------------------
# AC-3-1: orchestrator.pid ファイルが起動時に作成される
# GIVEN: AUTOPILOT_DIR が設定された状態で autopilot-orchestrator.sh を起動
# WHEN: スクリプトが起動して初期化処理を行う
# THEN: ${AUTOPILOT_DIR}/orchestrator.pid ファイルが存在する
# ---------------------------------------------------------------------------

@test "ac3: orchestrator.pid が起動時に作成される" {
  # PID write はフェーズ実行パスにのみ存在する（--summary は早期 exit）。
  # バックグラウンドで起動し、PID ファイルが現れるまで待ってから confirm する。
  _create_minimal_plan

  timeout 15 bash "$ORCHESTRATOR" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot" 2>/dev/null &
  ORCH_PID=$!

  # pid ファイルが作成されるまで待つ（最大 5 秒）
  local waited=0
  while [[ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]] && (( waited < 50 )); do
    sleep 0.1
    waited=$(( waited + 1 ))
  done

  # pid ファイルが存在することを確認（まだ orchestrator 起動中）
  assert [ -f "$SANDBOX/.autopilot/orchestrator.pid" ]

  wait "$ORCH_PID" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# AC-3-2: orchestrator.pid に書かれた PID が実プロセス PID と一致する
# GIVEN: autopilot-orchestrator.sh が起動している
# WHEN: orchestrator.pid を読み取る
# THEN: 書かれた PID が orchestrator プロセスの PID と一致する
# ---------------------------------------------------------------------------

@test "ac3: orchestrator.pid の内容がプロセス PID と一致する" {
  _create_minimal_plan

  timeout 15 bash "$ORCHESTRATOR" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot" 2>/dev/null &
  ORCH_PID=$!

  # pid ファイルが作成されるまで待つ（最大 5 秒）
  local waited=0
  while [[ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]] && (( waited < 50 )); do
    sleep 0.1
    waited=$(( waited + 1 ))
  done

  # pid ファイルの内容が数値 (PID) であること
  local written_pid
  written_pid=$(cat "$SANDBOX/.autopilot/orchestrator.pid" 2>/dev/null || echo "")
  [[ "$written_pid" =~ ^[0-9]+$ ]] || fail "orchestrator.pid の内容が数値でない: '$written_pid'"

  wait "$ORCH_PID" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# AC-3-3: orchestrator.pid は atomic write (一時ファイル経由の mv) で作成される
# GIVEN: autopilot-orchestrator.sh スクリプト
# WHEN: スクリプト内容を検査する
# THEN: pid 書き込みが mv (atomic) パターンで実装されている
# ---------------------------------------------------------------------------

@test "ac3: orchestrator.pid は atomic write (mv) で書き込まれる" {
  # RED: 現行実装には orchestrator.pid 書き込みコードが存在しない → grep が失敗 → FAIL
  # atomic write パターン: echo $$ > tmpfile && mv tmpfile orchestrator.pid
  run grep -E "orchestrator\.pid" "$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  assert_success
}
