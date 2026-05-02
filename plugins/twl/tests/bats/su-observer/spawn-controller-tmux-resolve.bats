#!/usr/bin/env bats
# spawn-controller-tmux-resolve.bats
# RED tests for Issue #1231: spawn-controller.sh の tmux-resolve.sh 統合
#
# AC coverage:
#   AC1 - spawn-controller.sh が plugins/session/scripts/lib/tmux-resolve.sh を source する
#   AC2 - _setup_observer_panes 内の tmux split-window 3 箇所が _resolve_window_target で解決した target を使う
#   AC3 - 既存の fallback ブランチ（|| 後で bare ${observer_window} を -t に渡す式）の取り扱いが決定されている
#   AC4 - このテストファイル自体が存在する（AC4 は存在確認 AC のため GREEN になる）
#   AC5 - _resolve_window_target 失敗時の log message が [spawn-controller] prefix 付きで stderr に記録される
#   AC6 - L358/L359 の tmux display-message も _resolve_window_target で解決した fully-qualified target を使う
#   AC7 - Wave 17 記録に本 fix の merge 追記が完了している
#
# テスト設計:
#   - tmux コマンドは STUB_BIN に mock して引数を記録する
#   - _resolve_window_target は tmux-resolve.sh の実装を使う（または別途 stub）
#   - spawn-controller.sh から _setup_observer_panes / source 行を grep + awk で抽出してテスト
#   - source guard の挙動: spawn-controller.sh は set -euo pipefail + cld-spawn 存在チェックが
#     先行するため直接 source はリスクあり。関数定義抽出 eval パターンで対処する
#
# WARNING（baseline-bash §9）:
#   このファイル内の heredoc を使う箇所はシングルクォート heredoc（<<'EOF'）を採用。
#   外部変数（$SANDBOX 等）は heredoc 外で bash 変数展開を行うか、
#   非クォート heredoc（<<EOF）を使うこと。
#
# NOTE（baseline-bash §10）:
#   spawn-controller.sh は source guard を持たない（set -euo pipefail 直後に cld-spawn チェック + exit 2
#   が実行される）。テストでは source ではなく grep + awk で関数定義を抽出して eval するパターンを使う。
#   tmux-resolve.sh は source guard あり（BASH_SOURCE チェック L20）。

load '../helpers/common'

SPAWN_SCRIPT=""
TMUX_RESOLVE_SCRIPT=""

# ---------------------------------------------------------------------------
# Setup / Teardown
# ---------------------------------------------------------------------------

setup() {
  common_setup

  SPAWN_SCRIPT="${REPO_ROOT}/skills/su-observer/scripts/spawn-controller.sh"
  TMUX_RESOLVE_SCRIPT="${REPO_ROOT}/../../../../plugins/session/scripts/lib/tmux-resolve.sh"

  # .supervisor ディレクトリと session.json を SANDBOX に作成
  mkdir -p "$SANDBOX/.supervisor"

  # cld-spawn stub
  stub_command "cld-spawn" 'echo "stub-cld-spawn: $*"; exit 0'

  # pkill stub
  cat > "$STUB_BIN/pkill" <<'PKILLEOF'
#!/usr/bin/env bash
echo "pkill-stub: $*" >> "${PKILL_LOG:-/dev/null}"
exit 0
PKILLEOF
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
_create_session_json() {
  local observer_window="${1:-observer-test-1231}"
  # NOTE: 非クォート heredoc を使って $SANDBOX/$observer_window を展開する
  cat > "$SANDBOX/.supervisor/session.json" <<EOF
{
  "session_id": "test-session-1231",
  "claude_session_id": "test-claude-id",
  "observer_window": "${observer_window}",
  "status": "active",
  "started_at": "2026-05-02T00:00:00Z"
}
EOF
}

# ---------------------------------------------------------------------------
# Helper: tmux stub を作成（list-windows で window 解決をシミュレート）
# resolved_target を返す: "<session>:<index>" 形式
# ---------------------------------------------------------------------------
_create_tmux_stub_with_resolve() {
  local observer_window="${1:-observer-test-1231}"
  local pane_base_index="${2:-0}"
  local resolved_target="${3:-test-session:1}"

  # NOTE: SANDBOX, resolved_target, pane_base_index は heredoc 外で展開
  local _sandbox="$SANDBOX"
  local _resolved="$resolved_target"
  local _base="$pane_base_index"
  local _window="$observer_window"

  cat > "$STUB_BIN/tmux" <<EOF
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${_sandbox}/tmux.log"
case "\${1:-}" in
  list-windows)
    # _resolve_window_target が呼ぶ list-windows をシミュレート
    echo "${_resolved} ${_window}"
    ;;
  show-options)
    echo "${_base}"
    ;;
  split-window)
    echo "split-window-stub: \$*"
    exit 0
    ;;
  display-message)
    echo "display-message-stub: \$*"
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
EOF
  chmod +x "$STUB_BIN/tmux"
  touch "$SANDBOX/tmux.log"
}

# ---------------------------------------------------------------------------
# Helper: _setup_observer_panes 関数を spawn-controller.sh から抽出して実行
# tmux-resolve.sh を source した状態で実行する
# ---------------------------------------------------------------------------
_run_setup_observer_panes_with_resolve() {
  local observer_window="${1:-observer-test-1231}"
  local pane_base_index="${2:-0}"
  local resolved_target="${3:-test-session:1}"

  _create_session_json "$observer_window"
  _create_tmux_stub_with_resolve "$observer_window" "$pane_base_index" "$resolved_target"

  local _sandbox="$SANDBOX"
  local _stub_bin="$STUB_BIN"
  local _spawn="$SPAWN_SCRIPT"
  local _resolve="$TMUX_RESOLVE_SCRIPT"

  run bash -c "
set -euo pipefail
export PATH='${_stub_bin}:${PATH}'
export SUPERVISOR_DIR='${_sandbox}/.supervisor'
export PKILL_LOG='${_sandbox}/pkill.log'
export SCRIPT_DIR='$(dirname "${_spawn}")'
export TWILL_ROOT='${REPO_ROOT}/../../../../..'

# tmux-resolve.sh を source
if [[ -f '${_resolve}' ]]; then
  source '${_resolve}'
fi

# _setup_observer_panes 関数を spawn-controller.sh から抽出して eval
FUNC_DEF=\$(grep -A 9999 '^_setup_observer_panes()' '${_spawn}' 2>/dev/null \
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
# AC1: spawn-controller.sh が tmux-resolve.sh を source する（1 行追加）
#
# RED: source 行が spawn-controller.sh に未追加のため fail する
# PASS 条件（実装後）:
#   - spawn-controller.sh に source "$TWILL_ROOT/plugins/session/scripts/lib/tmux-resolve.sh" 行が存在する
# ===========================================================================

@test "ac1: spawn-controller.sh に tmux-resolve.sh の source 行が存在する" {
  # AC: spawn-controller.sh が plugins/session/scripts/lib/tmux-resolve.sh を source する（1 行追加）
  # RED: 実装前は fail する（source 行が未追加）
  run grep -n 'tmux-resolve.sh' "$SPAWN_SCRIPT"
  assert_success
  assert_output --partial 'source'
}

@test "ac1: source 行が TWILL_ROOT 起点の絶対パスで tmux-resolve.sh を参照する" {
  # AC: TWILL_ROOT 起点の絶対パスで参照
  # RED: 実装前は fail する
  run grep -n 'source.*TWILL_ROOT.*tmux-resolve.sh' "$SPAWN_SCRIPT"
  assert_success
}

# ===========================================================================
# AC2: _setup_observer_panes 内の tmux split-window 3 箇所が
#      _resolve_window_target で解決した target を使う
#
# RED: _resolve_window_target 呼び出しが未実装のため fail する
# PASS 条件（実装後）:
#   - 固定 index "${observer_window}:1.${base}" 形式が除去されている
#   - _resolve_window_target の呼び出しが 3 箇所の split-window より前にある
#   - split-window の -t に ${resolved_target}.${base} 形式が使われている
# ===========================================================================

@test "ac2: spawn-controller.sh 内に _resolve_window_target の呼び出しが存在する" {
  # AC: _resolve_window_target で解決した target を使う
  # RED: 実装前は fail する（_resolve_window_target 呼び出しが未追加）
  run grep -n '_resolve_window_target' "$SPAWN_SCRIPT"
  assert_success
}

@test "ac2: 固定 index ':1.\${base}' 形式（廃止パターン）が spawn-controller.sh に残っていない" {
  # AC: ${observer_window}:1.${base} 形式は廃止
  # RED: 実装前は固定 index 形式が残っているため fail する
  run grep -n '"\${observer_window}:1\.' "$SPAWN_SCRIPT"
  # 廃止パターンが存在しないことを確認（grep が 0 件 → exit 1 → assert_failure）
  assert_failure
}

@test "ac2: split-window の -t に resolved_target.base 形式が使われている" {
  # AC: ${resolved_target}.${base} 形式で target を渡す
  # RED: 実装前は fail する
  run grep -n 'split-window.*resolved_target' "$SPAWN_SCRIPT"
  assert_success
}

@test "ac2: _setup_observer_panes 実行時に _resolve_window_target が tmux list-windows を呼ぶ" {
  # AC: _resolve_window_target で解決した session:index 形式 target を使う
  # RED: 実装前は fail する（_resolve_window_target 呼び出しなし）
  _run_setup_observer_panes_with_resolve "observer-test-1231" "0" "test-session:1"

  assert_success

  run grep "list-windows" "$SANDBOX/tmux.log"
  assert_success
}

# ===========================================================================
# AC3: fallback ブランチ（|| 後で bare ${observer_window} を -t に渡す式）の
#      取り扱いが決定されている
#
# RED: fallback ブランチがまだ残っており取り扱いが未決定のため fail する
# PASS 条件（実装後）: 以下の 3 候補のいずれかが選択・実装されている:
#   A) fallback ブランチを完全削除（_resolve_window_target 失敗時は abort）
#   B) fallback を _resolve_window_target の再試行に置き換え
#   C) fallback を残すが bare target 使用に警告ログを追加
# ===========================================================================

@test "ac3: spawn-controller.sh の _setup_observer_panes 内に fallback 取り扱いコメントまたは実装が存在する" {
  # AC: 既存の fallback ブランチの取り扱いが決定されている
  # RED: 実装前は fallback の取り扱いが未決定のため fail する
  #      （旧 || 後の bare observer_window 使用が残っている）

  # 旧スタイルの fallback（-t "${observer_window}" の bare 形式）が除去されていること
  run grep -n '\-t "\${observer_window}"' "$SPAWN_SCRIPT"
  # bare observer_window の fallback が除去されていることを確認（grep 0 件 → exit 1）
  assert_failure
}

@test "ac3: fallback 廃止または代替実装を示す AC3 コメントが spawn-controller.sh に存在する" {
  # AC: 既存の fallback ブランチの取り扱いが決定されている（3 候補から選択・根拠記述済み）
  # RED: 実装前は AC3 の取り扱い決定コメントが未追加のため fail する
  # PASS 条件: "AC3" または "fallback.*廃止" または "resolve.*fail.*abort" 等の明示的なコメントが存在する
  run grep -nE '(# AC3|fallback.*廃止|fallback.*除去|resolve.*fail.*abort|abort.*_resolve)' "$SPAWN_SCRIPT"
  assert_success
}

# ===========================================================================
# AC4: plugins/twl/tests/bats/su-observer/spawn-controller-tmux-resolve.bats が存在する
#
# このテスト自体の存在が AC4 を満たす。実行時点でファイルが存在するため GREEN になる。
# ===========================================================================

@test "ac4: spawn-controller-tmux-resolve.bats ファイルが存在する" {
  # AC: テストファイル自体の存在を確認する（存在すれば GREEN）
  local bats_file
  bats_file="$(cd "$BATS_TEST_DIR" && pwd)/su-observer/spawn-controller-tmux-resolve.bats"
  [ -f "$bats_file" ]
}

# ===========================================================================
# AC5: _resolve_window_target 失敗時の log message が [spawn-controller] prefix
#      付きで stderr に記録される
#
# RED: 実装前は fail する（失敗時のログ出力が未実装）
# PASS 条件（実装後）:
#   - _resolve_window_target が exit 1 を返した場合に stderr へ
#     "[spawn-controller] ..." を含むメッセージが出力される
# ===========================================================================

@test "ac5: _resolve_window_target 失敗時に [spawn-controller] prefix 付き stderr が出力される" {
  # AC: _resolve_window_target 失敗時の log message が [spawn-controller] prefix 付きで記録される
  # RED: 実装前は fail する（ログ出力なし）

  # tmux list-windows が空を返す stub（window が見つからない状態をシミュレート）
  local _sandbox="$SANDBOX"
  local _stub_bin="$STUB_BIN"

  cat > "$_stub_bin/tmux" <<EOF
#!/usr/bin/env bash
echo "tmux-stub: \$*" >> "${_sandbox}/tmux.log"
case "\${1:-}" in
  list-windows)
    # 空を返す（window not found）
    echo ""
    ;;
  show-options)
    echo "0"
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "$_stub_bin/tmux"
  touch "$_sandbox/tmux.log"

  _create_session_json "nonexistent-window"

  local _spawn="$SPAWN_SCRIPT"
  local _resolve="$TMUX_RESOLVE_SCRIPT"

  run bash -c "
export PATH='${_stub_bin}:${PATH}'
export SUPERVISOR_DIR='${_sandbox}/.supervisor'
export SCRIPT_DIR='$(dirname "${_spawn}")'
export TWILL_ROOT='${REPO_ROOT}/../../../../..'

if [[ -f '${_resolve}' ]]; then
  source '${_resolve}'
fi

FUNC_DEF=\$(grep -A 9999 '^_setup_observer_panes()' '${_spawn}' 2>/dev/null \
  | awk '/^_setup_observer_panes\(\)/{found=1} found{print} found && /^\}\$/{exit}')

if [[ -z \"\$FUNC_DEF\" ]]; then
  echo 'RED: _setup_observer_panes function not found' >&2
  exit 1
fi

eval \"\$FUNC_DEF\"
_setup_observer_panes 'nonexistent-window' '0'
" 2>&1

  # stderr に [spawn-controller] prefix が含まれることを確認
  assert_output --partial '[spawn-controller]'
}

@test "ac5: spawn-controller.sh に _resolve_window_target 失敗時の [spawn-controller] ログが記述されている" {
  # AC: [spawn-controller] prefix 付きログが実装されている
  # RED: 実装前は fail する
  run grep -n '\[spawn-controller\].*_resolve_window_target\|_resolve_window_target.*\[spawn-controller\]' "$SPAWN_SCRIPT"
  assert_success
}

# ===========================================================================
# AC6: L358/L359 の tmux display-message も _resolve_window_target で解決した
#      fully-qualified target に書き換えられている
#
# RED: 実装前は固定 "${observer_window}:1.$((base+3))" 形式が残っているため fail する
# PASS 条件（実装後）:
#   - tmux display-message の -t に "${observer_window}:1.$((base+3))" 固定形式がない
#   - _resolve_window_target で解決した target が使われている
# ===========================================================================

@test "ac6: tmux display-message の -t が固定 :1. 形式を使っていない" {
  # AC: display-message も _resolve_window_target で解決した target を使う
  # RED: 実装前は固定 "${observer_window}:1." 形式が残っているため fail する
  run grep -n 'display-message.*"\${observer_window}:1\.' "$SPAWN_SCRIPT"
  assert_failure
}

@test "ac6: tmux display-message の -t に resolved_target 形式が使われている" {
  # AC: split-window と同様の ambiguous リスクを排除
  # RED: 実装前は fail する
  run grep -n 'display-message.*resolved' "$SPAWN_SCRIPT"
  assert_success
}

@test "ac6: _setup_observer_panes 実行時に display-message が tmux log に記録される" {
  # AC: display-message が fully-qualified target を使って呼ばれる
  # RED: 実装前は fail する（_resolve_window_target 未使用）
  _run_setup_observer_panes_with_resolve "observer-test-1231" "0" "test-session:1"

  assert_success

  run grep "display-message" "$SANDBOX/tmux.log"
  assert_success
}

# ===========================================================================
# AC7: Wave 17 記録に本 fix の merge 追記が完了している
#
# RED: Wave 17 記録への追記が未実施のため fail する（false で RED を保持）
# PASS 条件（実装後）:
#   - .autopilot/ 配下の Wave 17 summary ファイルに #1231 の記述が存在する
# ===========================================================================

@test "ac7: Wave 17 記録（.autopilot/ 配下）に Issue #1231 の merge 追記が存在する" {
  # AC: Wave 17 記録に本 fix の merge を追記する
  # RED: ドキュメント更新が未実施のため fail する
  false
}
