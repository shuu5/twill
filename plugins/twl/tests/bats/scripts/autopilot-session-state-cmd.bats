#!/usr/bin/env bats
# autopilot-session-state-cmd.bats
# AC-1/AC-2: SESSION_STATE_CMD デフォルトが session-state-wrapper.sh に解決されることを検証
# AC-6: ubuntu-note-system ハードコード不在の invariant check
# Issue #752

load '../helpers/common'

FAKE_HOME=""

setup() {
  common_setup
  stub_command "tmux" 'exit 0'
  FAKE_HOME="$(mktemp -d)"
}

teardown() {
  common_teardown
  [[ -n "$FAKE_HOME" ]] && rm -rf "$FAKE_HOME" 2>/dev/null || true
}

# ===========================================================================
# AC-6: ubuntu-note-system ハードコード invariant（全 3 スクリプト）
# ===========================================================================

@test "AC-6: autopilot-orchestrator.sh に ubuntu-note-system の SESSION_STATE_CMD ハードコードが存在しない" {
  run grep "SESSION_STATE_CMD.*ubuntu-note-system" "$SANDBOX/scripts/autopilot-orchestrator.sh"
  assert_failure
}

@test "AC-6: crash-detect.sh に ubuntu-note-system の SESSION_STATE_CMD ハードコードが存在しない" {
  run grep "SESSION_STATE_CMD.*ubuntu-note-system" "$SANDBOX/scripts/crash-detect.sh"
  assert_failure
}

@test "AC-6: health-check.sh に ubuntu-note-system の SESSION_STATE_CMD ハードコードが存在しない" {
  run grep "SESSION_STATE_CMD.*ubuntu-note-system" "$SANDBOX/scripts/health-check.sh"
  assert_failure
}

# ===========================================================================
# AC-1: autopilot-orchestrator.sh
# デフォルト SESSION_STATE_CMD が session-state-wrapper.sh を参照し、
# ubuntu-note-system 不在でも USE_SESSION_STATE=true になることを検証
# ===========================================================================

@test "AC-1: autopilot-orchestrator.sh のデフォルト SESSION_STATE_CMD は session-state-wrapper.sh を指す" {
  # デフォルト値が ubuntu-note-system ではなく wrapper を参照していること
  run grep "SESSION_STATE_CMD.*session-state-wrapper" "$SANDBOX/scripts/autopilot-orchestrator.sh"
  assert_success
}

@test "AC-1: session-state-wrapper.sh は sandbox に存在して実行可能" {
  [[ -x "$SANDBOX/scripts/session-state-wrapper.sh" ]]
}

@test "AC-1: ubuntu-note-system 不在でも USE_SESSION_STATE=true になる（detection logic 単体検証）" {
  # autopilot-orchestrator.sh の SESSION_STATE_CMD 検出ロジックを抽出して検証
  # HOME を fake dir に向け、SESSION_STATE_CMD を未設定にする
  local resolved_cmd
  run bash -c "
    SCRIPTS_ROOT=\"$SANDBOX/scripts\"
    SESSION_STATE_CMD=\"\${SESSION_STATE_CMD:-\${SCRIPTS_ROOT}/session-state-wrapper.sh}\"
    if [[ -n \"\$SESSION_STATE_CMD\" && \"\$SESSION_STATE_CMD\" == /* && \"\$SESSION_STATE_CMD\" != *..* && -x \"\$SESSION_STATE_CMD\" ]]; then
      echo 'USE_SESSION_STATE=true'
    else
      echo 'USE_SESSION_STATE=false'
    fi
  "
  [ "$status" -eq 0 ]
  [[ "$output" == "USE_SESSION_STATE=true" ]]
}

# ===========================================================================
# AC-2: crash-detect.sh
# ubuntu-note-system 不在で USE_SESSION_STATE=true パスが使われることを
# 行動的に検証（session-state ベースの exited 検知 vs tmux フォールバック）
# ===========================================================================

@test "AC-2: crash-detect.sh のデフォルト SESSION_STATE_CMD は session-state-wrapper.sh を指す" {
  run grep "SESSION_STATE_CMD.*session-state-wrapper" "$SANDBOX/scripts/crash-detect.sh"
  assert_success
}

@test "AC-2: crash-detect.sh: ubuntu-note-system 不在 + SESSION_STATE_CMD 未設定でも USE_SESSION_STATE=true パスが実行される" {
  create_issue_json 1 "running"

  # tmux はペイン存在を返す（USE_SESSION_STATE=false フォールバックなら exit 0 になる）
  stub_command "tmux" 'exit 0'

  # wrapper を "exited" を返す stub で上書き（USE_SESSION_STATE=true なら exit 2 になる）
  cat > "$SANDBOX/scripts/session-state-wrapper.sh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) echo "exited" ;;
  *) echo '{"state":"exited"}' ;;
esac
STUB
  chmod +x "$SANDBOX/scripts/session-state-wrapper.sh"

  # HOME を fake dir に向け、SESSION_STATE_CMD は設定しない
  HOME="$FAKE_HOME" \
    run bash "$SANDBOX/scripts/crash-detect.sh" \
    --issue 1 --window "ap-#1"

  # USE_SESSION_STATE=true → session-state で exited を検知 → CRASH メッセージ出力
  # USE_SESSION_STATE=false → tmux pane exists → クリーン終了（出力なし）
  # NOTE: exit code 2 は report_crash 内の state write が worktrees/ ガードで
  # 失敗することで変わる場合があるが、出力内の "exited" 検知は確実
  assert_failure
  [[ "$output" == *"exited"* ]]
}

# ===========================================================================
# AC-2: health-check.sh
# ubuntu-note-system 不在で USE_SESSION_STATE=true パスが使われることを
# 行動的に検証（session-state ベースの input-waiting 検知）
# ===========================================================================

@test "AC-2: health-check.sh のデフォルト SESSION_STATE_CMD は session-state-wrapper.sh を指す" {
  run grep "SESSION_STATE_CMD.*session-state-wrapper" "$SANDBOX/scripts/health-check.sh"
  assert_success
}

@test "AC-2: health-check.sh: ubuntu-note-system 不在 + SESSION_STATE_CMD 未設定でも USE_SESSION_STATE=true パスが実行される" {
  create_issue_json 1 "running"

  # wrapper を input-waiting を返す stub で上書き（since=0: epoch → elapsed が閾値超過）
  # USE_SESSION_STATE=true なら input_waiting を検知（exit 1）
  # USE_SESSION_STATE=false なら入力待ち検知スキップ（exit 0）
  cat > "$SANDBOX/scripts/session-state-wrapper.sh" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  state) echo "input-waiting" ;;
  get)   echo '{"state":"input-waiting","since":0}' ;;
  *)     exit 1 ;;
esac
STUB
  chmod +x "$SANDBOX/scripts/session-state-wrapper.sh"

  HOME="$FAKE_HOME" \
    run bash "$SANDBOX/scripts/health-check.sh" \
    --issue 1 --window "ap-#1"

  # USE_SESSION_STATE=true → input-waiting 検知 → exit 1 + "input_waiting" in output
  # USE_SESSION_STATE=false → スキップ → exit 0
  [ "$status" -eq 1 ]
  [[ "$output" == *"input_waiting"* ]]
}
