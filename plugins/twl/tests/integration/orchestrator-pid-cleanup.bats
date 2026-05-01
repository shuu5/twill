#!/usr/bin/env bats
# orchestrator-pid-cleanup.bats
# AC-4: autopilot-orchestrator.sh の EXIT trap で orchestrator.pid が削除される
#
# RED フェーズ: 現行実装 (autopilot-orchestrator.sh) には orchestrator.pid の
#              EXIT trap クリーンアップが存在しないため、全テストは FAIL する。

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
# Helper
# ---------------------------------------------------------------------------

_create_minimal_plan() {
  local session_id="${1:-test-session-cleanup-001}"
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
# AC-4-1: 正常終了後に orchestrator.pid が削除される
# GIVEN: autopilot-orchestrator.sh が起動し orchestrator.pid が作成されている
# WHEN: スクリプトが正常終了する
# THEN: ${AUTOPILOT_DIR}/orchestrator.pid が削除されている
# ---------------------------------------------------------------------------

@test "ac4: 正常終了後に orchestrator.pid が削除される" {
  # フェーズ実行モード（no issues → 素早く完了）で orchestrator を完走させ、
  # EXIT trap により pid ファイルが削除されることを確認する。
  _create_minimal_plan

  # まず PID ファイルが存在しないことを確認（前提）
  assert [ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]

  # orchestrator を完走させる（issues なし → 素早く exit）
  timeout 30 bash "$ORCHESTRATOR" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot" 2>/dev/null || true

  # 終了後に orchestrator.pid が存在しないことを確認（EXIT trap で削除済み）
  assert [ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]
}

# ---------------------------------------------------------------------------
# AC-4-2: シグナル終了 (SIGTERM) 後にも orchestrator.pid が削除される
# GIVEN: autopilot-orchestrator.sh が起動し pid ファイルが作成されている
# WHEN: SIGTERM でプロセスを終了させる
# THEN: EXIT trap が発火し orchestrator.pid が削除される
# ---------------------------------------------------------------------------

@test "ac4: SIGTERM 後に orchestrator.pid が削除される (EXIT trap)" {
  # RED: 現行実装は EXIT trap で orchestrator.pid を削除しないため FAIL する
  _create_minimal_plan

  # バックグラウンドで起動
  timeout 15 bash "$ORCHESTRATOR" \
    --plan "$SANDBOX/.autopilot/plan.yaml" \
    --phase 1 \
    --session "$SANDBOX/.autopilot/session.json" \
    --project-dir "$SANDBOX" \
    --autopilot-dir "$SANDBOX/.autopilot" 2>/dev/null &
  ORCH_PID=$!

  # orchestrator.pid が作成されるまで待つ（最大 5 秒）
  local waited=0
  while [[ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]] && (( waited < 50 )); do
    sleep 0.1
    waited=$(( waited + 1 ))
  done

  # pid ファイルが存在することを確認（前提条件）
  # RED: 現行実装は pid ファイルを作成しないため、ここで FAIL する
  assert [ -f "$SANDBOX/.autopilot/orchestrator.pid" ]

  # SIGTERM 送信
  kill -TERM "$ORCH_PID" 2>/dev/null || true
  wait "$ORCH_PID" 2>/dev/null || true

  # 終了後に pid ファイルが削除されていることを確認
  assert [ ! -f "$SANDBOX/.autopilot/orchestrator.pid" ]
}

# ---------------------------------------------------------------------------
# AC-4-3: スクリプト内に EXIT trap で orchestrator.pid を削除するコードが存在する
# GIVEN: autopilot-orchestrator.sh スクリプト
# WHEN: スクリプト内容を静的に検査する
# THEN: EXIT trap 内で orchestrator.pid を削除するパターンが存在する
# ---------------------------------------------------------------------------

@test "ac4: EXIT trap で orchestrator.pid を削除するコードが存在する (静的検査)" {
  # RED: 現行実装には orchestrator.pid の EXIT trap クリーンアップが存在しない → FAIL
  # 期待パターン: trap '... rm -f "$AUTOPILOT_DIR/orchestrator.pid" ...' EXIT
  run grep -E "trap.*EXIT" "$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  assert_success

  # trap 内に orchestrator.pid の削除が含まれることを確認
  run grep -E "orchestrator\.pid" "$REPO_ROOT/scripts/autopilot-orchestrator.sh"
  assert_success
}
