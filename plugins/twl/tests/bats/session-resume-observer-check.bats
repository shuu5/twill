#!/usr/bin/env bats
# session-resume-observer-check.bats
# RED tests for Issue #1147: SessionStart hook - observer resume on session restart
#
# AC coverage:
#   AC4 - session-resume-observer-check.sh が以下を実行:
#          - cwd を git toplevel に移動
#          - .supervisor/session.json 不在 → exit 0 (no-op)
#          - cld_observe_any.pid が kill -0 で生存 → exit 0
#          - PID 死亡 → lock/pid ファイル削除 → respawn
#          - pane_id 有効時 → tmux respawn-pane -k -t "$PANE_ID" "$SPAWN_CMD"
#          - spawn_cmd null → error log + exit 1
#          - pane 消失 → .supervisor/events/daemon-restart-skipped.json 出力
#   AC5 - respawn 失敗時 → .supervisor/events/daemon-startup-failed.json 出力
#          フィールド: {timestamp, reason, pid_old, pid_new, error_log}
#   AC7 - bats test 5 ケース（本ファイル）
#
# テスト設計:
#   - tmux コマンドは STUB_BIN に mock して挙動を制御する
#   - kill コマンドも stub して PID 生死を制御する
#   - session-resume-observer-check.sh は plugins/twl/scripts/hooks/ 配下に新規作成される予定
#   - .supervisor/session.json を SANDBOX に作成して入力とする
#
# RED: session-resume-observer-check.sh が未実装のため全テストが fail する

load 'helpers/common'

RESUME_SCRIPT=""

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  RESUME_SCRIPT="${REPO_ROOT}/scripts/hooks/session-resume-observer-check.sh"

  # .supervisor ディレクトリと events ディレクトリを SANDBOX に作成
  mkdir -p "$SANDBOX/.supervisor/events"

  # kill stub: デフォルト = PID 生存（exit 0）
  stub_command "kill" 'exit 0'

  # git stub: rev-parse --show-toplevel が SANDBOX を返す
  cat > "$STUB_BIN/git" <<GITSTUB
#!/usr/bin/env bash
if [[ "\${*}" == *"rev-parse --show-toplevel"* ]]; then
  echo "${SANDBOX}"
  exit 0
fi
exit 0
GITSTUB
  chmod +x "$STUB_BIN/git"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: session.json を SANDBOX/.supervisor/ に書き出す
# ---------------------------------------------------------------------------
_create_session_json() {
  local pid="${1:-12345}"
  local pane_id="${2:-%42}"
  local spawn_cmd="${3:-cld-observe-any --window observer-test}"
  local lock_path="${4:-/tmp/cld-observe-any.lock}"

  python3 -c "
import json, sys
pid_val = None if '${pid}' == 'null' else int('${pid}')
pane_val = None if '${pane_id}' == 'null' else '${pane_id}'
spawn_val = None if '${spawn_cmd}' == 'null' else '${spawn_cmd}'
data = {
  'session_id': 'test-session-1147',
  'claude_session_id': 'test-claude-id',
  'observer_window': 'observer-test',
  'status': 'active',
  'started_at': '2026-04-30T00:00:00Z',
  'cld_observe_any': {
    'pid': pid_val,
    'pane_id': pane_val,
    'spawn_cmd': spawn_val,
    'started_at': '2026-04-30T00:00:00Z',
    'log_path': '/tmp/cld-observe-any.log',
    'lock_path': '${lock_path}'
  }
}
json.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
print('session.json created')
"
}

# ---------------------------------------------------------------------------
# Helper: session-resume-observer-check.sh を SANDBOX 内で実行する
# ---------------------------------------------------------------------------
_run_resume_check() {
  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
export HOME='${SANDBOX}'
bash '${RESUME_SCRIPT}'
"
}

# ===========================================================================
# AC7 ケース1: session.json 不在 → exit 0 (no-op)
#
# RED: session-resume-observer-check.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - スクリプトが exit 0 で終了する
#   - tmux respawn-pane は呼ばれない
# ===========================================================================

@test "ac7/1: session.json 不在 → exit 0 (no-op)" {
  # AC: .supervisor/session.json 存在確認 → 不在は no-op で exit 0
  # RED: 実装前は fail する（スクリプト不在）

  # session.json を作成しない状態で実行
  rm -f "$SANDBOX/.supervisor/session.json"

  # tmux stub: 呼び出しを記録
  cat > "$STUB_BIN/tmux" <<'TMUXSTUB'
#!/usr/bin/env bash
echo "tmux-stub-called: $*" >&2
exit 0
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"

  _run_resume_check

  assert_success
}

# ===========================================================================
# AC7 ケース2: PID 生存時 → exit 0、再起動なし
#
# RED: session-resume-observer-check.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - kill -0 で PID が生存確認できる（kill stub が exit 0）
#   - スクリプトが exit 0 で終了する
#   - tmux respawn-pane は呼ばれない
# ===========================================================================

@test "ac7/2: PID 生存時 → exit 0、再起動なし" {
  # AC: cld_observe_any.pid が kill -0 で生存確認 → 生存なら exit 0
  # RED: 実装前は fail する（スクリプト不在）

  _create_session_json "12345" "%42" "cld-observe-any --window observer-test"

  # kill stub: exit 0 = PID 生存
  stub_command "kill" 'exit 0'

  # tmux stub: 呼び出しを記録（respawn-pane が呼ばれたらフラグを残す）
  cat > "$STUB_BIN/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
exit 0
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"

  _run_resume_check

  assert_success

  # respawn-pane が呼ばれていないことを確認
  run grep "respawn-pane" "$SANDBOX/tmux.log"
  assert_failure
}

# ===========================================================================
# AC7 ケース3: PID 死亡 + pane 存在 + spawn_cmd あり → lock ファイル削除 → respawn 実行
#
# RED: session-resume-observer-check.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - kill -0 が exit 1 = PID 死亡
#   - lock_path ファイルを削除する
#   - tmux respawn-pane -k -t pane_id spawn_cmd が実行される
# ===========================================================================

@test "ac7/3: PID 死亡 + pane 存在 + spawn_cmd あり → lock 削除 → respawn 実行" {
  # AC: PID 死亡時 → lock ファイル削除 → pane_id 有効なら tmux respawn-pane で再起動
  # RED: 実装前は fail する（スクリプト不在）

  local lock_file="$SANDBOX/cld-observe-any.lock"
  local lock_pid_file="${lock_file}.pid"
  touch "$lock_file"
  touch "$lock_pid_file"

  _create_session_json "99999" "%42" "cld-observe-any --window observer-test" "$lock_file"

  # kill stub: exit 1 = PID 死亡
  stub_command "kill" 'exit 1'

  # tmux stub: list-panes で pane 存在を返し、respawn-pane を記録する
  cat > "$STUB_BIN/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
case "\${1:-}" in
  list-panes)
    # pane %42 が存在する
    echo "%42"
    exit 0
    ;;
  respawn-pane)
    echo "respawn-pane-called: \$*" >> "${SANDBOX}/tmux.log"
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"

  _run_resume_check

  assert_success

  # lock ファイルが削除されていることを確認
  [ ! -f "$lock_file" ] || {
    echo "FAIL: lock_file still exists: $lock_file"
    return 1
  }

  # lock.pid ファイルが削除されていることを確認
  [ ! -f "$lock_pid_file" ] || {
    echo "FAIL: lock.pid file still exists: $lock_pid_file"
    return 1
  }

  # respawn-pane が呼ばれたことを確認
  run grep "respawn-pane" "$SANDBOX/tmux.log"
  assert_success
}

# ===========================================================================
# AC7 ケース4: PID 死亡 + spawn_cmd null → error log 出力、exit 1
#
# RED: session-resume-observer-check.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - kill -0 が exit 1 = PID 死亡
#   - spawn_cmd が null → respawn 不可
#   - error ログを出力し exit 1
# ===========================================================================

@test "ac7/4: PID 死亡 + spawn_cmd null → error log 出力、exit 1" {
  # AC: spawn_cmd が null の場合は error log + exit 1
  # RED: 実装前は fail する（スクリプト不在）

  _create_session_json "99999" "%42" "null"

  # kill stub: exit 1 = PID 死亡
  stub_command "kill" 'exit 1'

  # tmux stub
  cat > "$STUB_BIN/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
exit 0
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"

  _run_resume_check

  # spawn_cmd null → exit 1
  # RED: スクリプト不在時は status=127、実装後は status=1 で fail する
  # 実装後の PASS 条件: exit 1（スクリプトが spawn_cmd null を正しく扱う）
  # かつ stderr に error ログが含まれること
  assert_failure
  # スクリプト不在の exit 127 ではなく、実装後に exit 1 であることを確認する
  # （実装前: status=127 は assert_failure で PASS してしまうが、exit 1 チェックで RED になる）
  [ "$status" -eq 1 ] || {
    echo "RED: status=$status (expected 1 after implementation, got 127 means script missing)"
    return 1
  }
}

# ===========================================================================
# AC7 ケース5: pane 消失 → events ファイル出力、exit 0
#
# RED: session-resume-observer-check.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - kill -0 が exit 1 = PID 死亡
#   - tmux list-panes で pane_id が見つからない = pane 消失
#   - .supervisor/events/daemon-restart-skipped.json を出力
#   - exit 0（再起動不能と記録して graceful exit）
# ===========================================================================

@test "ac7/5: pane 消失 → daemon-restart-skipped.json 出力、exit 0" {
  # AC: pane 自体が消失した場合 → .supervisor/events/daemon-restart-skipped.json を出力
  # RED: 実装前は fail する（スクリプト不在）

  _create_session_json "99999" "%99" "cld-observe-any --window observer-test"

  # kill stub: exit 1 = PID 死亡
  stub_command "kill" 'exit 1'

  # tmux stub: list-panes で pane %99 が存在しない
  cat > "$STUB_BIN/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
case "\${1:-}" in
  list-panes)
    # pane %99 が存在しない（空を返す）
    echo ""
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"

  _run_resume_check

  assert_success

  # daemon-restart-skipped.json が生成されていることを確認
  local skipped_json="$SANDBOX/.supervisor/events/daemon-restart-skipped.json"
  [ -f "$skipped_json" ] || {
    echo "FAIL: daemon-restart-skipped.json が生成されていない"
    ls -la "$SANDBOX/.supervisor/events/" 2>/dev/null || echo "events dir empty"
    return 1
  }
}

# ===========================================================================
# AC5: respawn 失敗時 → daemon-startup-failed.json 出力
#
# RED: session-resume-observer-check.sh が未実装のため fail する
# PASS 条件（実装後）:
#   - kill -0 が exit 1 = PID 死亡
#   - pane_id 有効 = pane 存在
#   - tmux respawn-pane が exit 1（失敗）
#   - .supervisor/events/daemon-startup-failed.json が生成される
#   - JSON フィールド: {timestamp, reason, pid_old, pid_new, error_log}
# ===========================================================================

@test "ac5: respawn 失敗時 → daemon-startup-failed.json 出力" {
  # AC: 再起動 attempt が失敗した場合に .supervisor/events/daemon-startup-failed.json を出力
  # RED: 実装前は fail する（スクリプト不在）

  _create_session_json "99999" "%42" "cld-observe-any --window observer-test"

  # kill stub: exit 1 = PID 死亡
  stub_command "kill" 'exit 1'

  # tmux stub: list-panes で pane 存在を返すが、respawn-pane は失敗
  cat > "$STUB_BIN/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
case "\${1:-}" in
  list-panes)
    echo "%42"
    exit 0
    ;;
  respawn-pane)
    # respawn 失敗
    echo "respawn-pane-failed" >&2
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"

  _run_resume_check

  # daemon-startup-failed.json が生成されていることを確認
  local failed_json
  failed_json=$(find "$SANDBOX/.supervisor/events" -name "daemon-startup-failed.json" 2>/dev/null | head -1)
  [ -n "$failed_json" ] || {
    echo "FAIL: daemon-startup-failed.json が生成されていない"
    ls -la "$SANDBOX/.supervisor/events/" 2>/dev/null || echo "events dir empty"
    return 1
  }

  # 必須フィールド確認: {timestamp, reason, pid_old, error_log}（pid_new は respawn 失敗時 null が正常）
  run jq -e '.timestamp and .reason and (.pid_old | . != null) and (.error_log | . != null)' "$failed_json"
  assert_success
}
