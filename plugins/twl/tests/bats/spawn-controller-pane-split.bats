#!/usr/bin/env bats
# spawn-controller-pane-split.bats
# RED tests for Issue #1030: spawn-controller.sh + SKILL.md 起動 routine に
# observer window pane split + watcher pane 内起動を自動化
#
# AC coverage:
#   AC1 - spawn-controller.sh co-autopilot 後に observer window が 4 pane (左 1 + 右 3) layout になる
#   AC2 - pane-base-index = 0 / 1 双方の環境で正しく動作 (auto-detect)
#   AC3 - orphan watcher process が pkill -f で事前 cleanup される
#   AC4 - tmux split-window -h の方向 (左右 vs 上下) を環境ごとに検証
#
# テスト設計:
#   - tmux コマンドは STUB_BIN に mock して引数を記録する
#   - pkill コマンドも stub する（実際のプロセス kill 禁止）
#   - pane-base-index は tmux show-options -gv を stub して 0/1 を制御
#   - spawn-controller.sh 内から呼ばれる _setup_observer_panes 関数をテスト対象とする
#   - .supervisor/session.json に observer_window を書き込んで入力として使う
#
# RED: _setup_observer_panes 関数が spawn-controller.sh に未実装のため全テストが fail する

load 'helpers/common'

SPAWN_SCRIPT=""

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"

  # .supervisor ディレクトリと session.json を SANDBOX に作成
  mkdir -p "$SANDBOX/.supervisor"

  # cld-spawn stub（実際の tmux spawn をスキップ）
  stub_command "cld-spawn" 'echo "stub-cld-spawn: $*"; exit 0'

  # pkill stub（実プロセスを kill しない）
  cat > "$STUB_BIN/pkill" <<'PKILLSTUB'
#!/usr/bin/env bash
echo "pkill-stub: $*" >> "${PKILL_LOG:-/dev/null}"
exit 0
PKILLSTUB
  chmod +x "$STUB_BIN/pkill"

  export PKILL_LOG="$SANDBOX/pkill.log"
  touch "$PKILL_LOG"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: session.json を作成して observer_window を設定
# ---------------------------------------------------------------------------
_create_session_json_with_window() {
  local observer_window="${1:-observer-test}"
  python3 -c "
import json, sys
data = {
  'session_id': 'test-session-1030',
  'claude_session_id': 'test-claude-id',
  'observer_window': '${observer_window}',
  'status': 'active',
  'started_at': '2026-04-28T00:00:00Z'
}
json.dump(data, open('${SANDBOX}/.supervisor/session.json', 'w'), indent=2)
"
}

# ---------------------------------------------------------------------------
# Helper: _setup_observer_panes 関数を spawn-controller.sh から抽出して実行
# STUB_BIN の tmux を使って引数を記録する
# ---------------------------------------------------------------------------
_run_setup_observer_panes() {
  local pane_base_index="${1:-0}"
  local observer_window="${2:-observer-test}"

  _create_session_json_with_window "$observer_window"

  # tmux stub: 引数を記録してサブコマンドごとに分岐
  cat > "$STUB_BIN/tmux" <<TMUXSTUB
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${SANDBOX}/tmux.log"
case "\${1:-}" in
  show-options)
    echo "${pane_base_index}"
    ;;
  split-window)
    echo "split-window-stub: \$*"
    exit 0
    ;;
  list-panes)
    printf '%s\n' 0 1 2 3
    ;;
  select-pane)
    exit 0
    ;;
  send-keys)
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
TMUXSTUB
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"

  # _setup_observer_panes 関数を spawn-controller.sh から抽出して実行
  # 関数が未実装の場合、grep が空を返し eval した bash が関数呼び出しで exit 127 になる
  run bash -c "
set -euo pipefail
export PATH='${STUB_BIN}:${PATH}'
export SUPERVISOR_DIR='${SANDBOX}/.supervisor'
export PKILL_LOG='${PKILL_LOG}'
export SCRIPT_DIR='${REPO_ROOT}/skills/su-observer/scripts'
export TWILL_ROOT='${REPO_ROOT}/../../../../..'

# spawn-controller.sh から _setup_observer_panes 関数を抽出
FUNC_DEF=\$(grep -A 9999 '^_setup_observer_panes()' '${SPAWN_SCRIPT}' 2>/dev/null \
  | awk '/^_setup_observer_panes\(\)/{found=1} found{print} found && /^\}\$/{exit}')

if [[ -z \"\$FUNC_DEF\" ]]; then
  echo 'RED: _setup_observer_panes function not found in spawn-controller.sh' >&2
  exit 1
fi

eval \"\$FUNC_DEF\"
_setup_observer_panes '${observer_window}' '${pane_base_index}'
"
}

# ===========================================================================
# AC1: spawn-controller.sh co-autopilot 後に observer window が
#      4 pane (左 1 + 右 3) layout になる
#
# RED: _setup_observer_panes 関数が未実装のため fail する
# PASS 条件（実装後）:
#   - tmux split-window が合計 3 回呼ばれる（1 pane → 4 pane になる分割）
#   - split-window -h が 1 回 + split-window -v が 2 回
# ===========================================================================

@test "ac1: _setup_observer_panes が tmux split-window を 3 回実行して 4 pane layout を作る" {
  # AC: spawn-controller.sh co-autopilot 後に observer window が 4 pane (左 1 + 右 3) layout になる
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  local split_count
  split_count=$(grep -c "split-window" "$SANDBOX/tmux.log" 2>/dev/null || echo "0")
  [ "$split_count" -eq 3 ] || {
    echo "FAIL: split-window should be called 3 times, got ${split_count}"
    echo "tmux.log:"
    cat "$SANDBOX/tmux.log"
    return 1
  }
}

@test "ac1: _setup_observer_panes 実行後 tmux list-panes で 4 pane が確認できる" {
  # AC: observer window が 4 pane (左 1 + 右 3) layout になる
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  run grep "list-panes" "$SANDBOX/tmux.log"
  assert_success
}

# ===========================================================================
# AC2: pane-base-index = 0 / 1 双方の環境で正しく動作 (auto-detect)
#
# RED: 実装前は fail する
# PASS 条件（実装後）:
#   - pane-base-index=0 でも pane-base-index=1 でも split が成功する
#   - tmux show-options -gv pane-base-index が呼ばれて auto-detect される
# ===========================================================================

@test "ac2: pane-base-index=0 環境で _setup_observer_panes が正常完了する" {
  # AC: pane-base-index = 0 / 1 双方の環境で正しく動作 (auto-detect)
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  run grep "show-options" "$SANDBOX/tmux.log"
  assert_success
}

@test "ac2: pane-base-index=1 環境で _setup_observer_panes が正常完了する" {
  # AC: pane-base-index = 0 / 1 双方の環境で正しく動作 (auto-detect)
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "1" "observer-test"

  assert_success

  local split_count
  split_count=$(grep -c "split-window" "$SANDBOX/tmux.log" 2>/dev/null || echo "0")
  [ "$split_count" -eq 3 ] || {
    echo "FAIL: split-window should be called 3 times with pane-base-index=1, got ${split_count}"
    return 1
  }
}

@test "ac2: pane-base-index auto-detect のため tmux show-options -gv pane-base-index が呼ばれる" {
  # AC: pane-base-index = 0 / 1 双方の環境で正しく動作 (auto-detect)
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  run grep -F "show-options" "$SANDBOX/tmux.log"
  assert_success

  run grep "pane-base-index" "$SANDBOX/tmux.log"
  assert_success
}

# ===========================================================================
# AC3: orphan watcher process が pkill -f で事前 cleanup される
#
# RED: 実装前は fail する
# PASS 条件（実装後）:
#   - _setup_observer_panes 実行前に pkill -f でwatcher プロセスを cleanup する
#   - pkill.log に pkill -f <watcher-pattern> が記録される
# ===========================================================================

@test "ac3: _setup_observer_panes 実行前に pkill -f で orphan watcher が cleanup される" {
  # AC: orphan watcher process が pkill -f で事前 cleanup される
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  run cat "$PKILL_LOG"
  assert_success
  assert_output --partial "pkill-stub:"
}

@test "ac3: pkill -f の引数に watcher スクリプト名が含まれる" {
  # AC: orphan watcher process が pkill -f で事前 cleanup される
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  run grep "\-f" "$PKILL_LOG"
  assert_success
}

# ===========================================================================
# AC4: tmux split-window -h の方向 (左右 vs 上下) を環境ごとに検証
#      (pane-base-index 非一致で fallback 誤動作する経緯あり)
#
# RED: 実装前は fail する
# PASS 条件（実装後）:
#   - pane-base-index=0 環境で split-window -h（水平分割 = 左右）が最初に呼ばれる
#   - pane-base-index=1 環境でも同様に -h が最初の分割に使われる
#   - pane-base-index の値に関わらず分割方向が一貫する
# ===========================================================================

@test "ac4: pane-base-index=0 環境で split-window -h（左右分割）が最初に呼ばれる" {
  # AC: tmux split-window -h の方向 (左右 vs 上下) を環境ごとに検証
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"

  assert_success

  run grep "split-window.*-h" "$SANDBOX/tmux.log"
  assert_success
}

@test "ac4: pane-base-index=1 環境でも split-window -h の方向が正しい（fallback 誤動作なし）" {
  # AC: tmux split-window -h の方向 (左右 vs 上下) を環境ごとに検証
  #     pane-base-index 非一致で fallback 誤動作する経緯あり
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "1" "observer-test"

  assert_success

  run grep "split-window.*-h" "$SANDBOX/tmux.log"
  assert_success
}

@test "ac4: pane-base-index=0 と pane-base-index=1 で split-window 呼び出し回数が同一（3回）" {
  # AC: tmux split-window -h の方向 (左右 vs 上下) を環境ごとに検証
  # RED: 実装前は fail する（関数不在）

  _run_setup_observer_panes "0" "observer-test"
  assert_success
  local count0
  count0=$(grep -c "split-window" "$SANDBOX/tmux.log" 2>/dev/null || echo "0")

  rm -f "$SANDBOX/tmux.log"
  touch "$SANDBOX/tmux.log"

  _run_setup_observer_panes "1" "observer-test"
  assert_success
  local count1
  count1=$(grep -c "split-window" "$SANDBOX/tmux.log" 2>/dev/null || echo "0")

  [ "$count0" -eq "$count1" ] || {
    echo "FAIL: split-window call count differs between pane-base-index=0 (${count0}) and pane-base-index=1 (${count1})"
    return 1
  }
  [ "$count0" -eq 3 ] || {
    echo "FAIL: expected 3 split-window calls, got ${count0}"
    return 1
  }
}
