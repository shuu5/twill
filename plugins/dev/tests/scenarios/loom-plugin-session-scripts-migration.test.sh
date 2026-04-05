#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: scripts-migration.md
# Generated from: openspec/changes/loom-plugin-session/specs/scripts-migration.md
# Coverage level: edge-cases
# Target repo: ~/projects/local-projects/loom-plugin-session/main/
# =============================================================================
set -uo pipefail

# Target repo root (loom-plugin-session)
TARGET_ROOT="${LOOM_PLUGIN_SESSION_ROOT:-/home/shuu5/projects/local-projects/loom-plugin-session/main}"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${TARGET_ROOT}/${file}" ]]
}

assert_file_executable() {
  local file="$1"
  [[ -x "${TARGET_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${TARGET_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${TARGET_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${TARGET_ROOT}/${file}" ]] || return 1
  if grep -qP -- "$pattern" "${TARGET_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

run_test() {
  local name="$1"
  local func="$2"
  local result
  result=0
  $func || result=$?
  if [[ $result -eq 0 ]]; then
    echo "  PASS: ${name}"
    ((PASS++)) || true
  else
    echo "  FAIL: ${name}"
    ((FAIL++)) || true
    ERRORS+=("${name}")
  fi
}

run_test_skip() {
  local name="$1"
  local reason="$2"
  echo "  SKIP: ${name} (${reason})"
  ((SKIP++)) || true
}

SESSION_STATE="scripts/session-state.sh"
SESSION_COMM="scripts/session-comm.sh"
CLD="scripts/cld"
CLD_SPAWN="scripts/cld-spawn"
CLD_OBSERVE="scripts/cld-observe"
CLD_FORK="scripts/cld-fork"
CLAUDE_SESSION_SAVE="scripts/claude-session-save.sh"

# =============================================================================
# Requirement: session-state.sh の移植
# =============================================================================
echo ""
echo "--- Requirement: session-state.sh の移植 ---"

# Scenario: state サブコマンド (line 8)
# WHEN: session-state.sh state <window-name> を実行する
# THEN: idle/input-waiting/processing/error/exited のいずれかの状態を返す

test_session_state_exists() {
  assert_file_exists "$SESSION_STATE"
}
run_test "session-state.sh が存在する" test_session_state_exists

test_session_state_executable() {
  assert_file_executable "$SESSION_STATE"
}
run_test "session-state.sh が実行可能である" test_session_state_executable

test_session_state_subcommand_state() {
  assert_file_exists "$SESSION_STATE" || return 1
  # state サブコマンドが実装されていること
  assert_file_contains "$SESSION_STATE" '\bstate\b' || return 1
  return 0
}
run_test "session-state.sh に state サブコマンドが実装されている" test_session_state_subcommand_state

test_session_state_valid_states() {
  assert_file_exists "$SESSION_STATE" || return 1
  # idle/input-waiting/processing/error/exited の状態定義があること
  assert_file_contains "$SESSION_STATE" 'idle' || return 1
  assert_file_contains "$SESSION_STATE" 'processing' || return 1
  assert_file_contains "$SESSION_STATE" 'exited' || return 1
  return 0
}
run_test "session-state.sh に有効な状態定義がある (idle/processing/exited)" test_session_state_valid_states

# Edge case: input-waiting と error 状態も定義されていること
test_session_state_input_waiting_error() {
  assert_file_exists "$SESSION_STATE" || return 1
  assert_file_contains "$SESSION_STATE" 'input-waiting' || return 1
  assert_file_contains "$SESSION_STATE" 'error' || return 1
  return 0
}
run_test "[edge: session-state.sh に input-waiting/error 状態がある]" test_session_state_input_waiting_error

# Scenario: list サブコマンド (line 12)
# WHEN: session-state.sh list --json を実行する
# THEN: 全 Claude Code ウィンドウの名前と状態を JSON 配列で返す

test_session_state_subcommand_list() {
  assert_file_exists "$SESSION_STATE" || return 1
  assert_file_contains "$SESSION_STATE" '\blist\b' || return 1
  return 0
}
run_test "session-state.sh に list サブコマンドが実装されている" test_session_state_subcommand_list

test_session_state_list_json() {
  assert_file_exists "$SESSION_STATE" || return 1
  # --json オプション処理があること
  assert_file_contains "$SESSION_STATE" '(--json|json_mode)' || return 1
  return 0
}
run_test "session-state.sh の list に --json オプションがある" test_session_state_list_json

# Edge case: list の JSON 出力が配列形式であること
test_session_state_list_json_array() {
  assert_file_exists "$SESSION_STATE" || return 1
  # JSON 配列出力のコード（[ または jq など）があること
  assert_file_contains "$SESSION_STATE" '(\[|\bjq\b|json)' || return 1
  return 0
}
run_test "[edge: session-state.sh の list JSON 出力が配列形式]" test_session_state_list_json_array

# Scenario: wait サブコマンド (line 16)
# WHEN: session-state.sh wait <window-name> idle --timeout 10 を実行する
# THEN: 指定状態に到達するまでポーリングし、タイムアウト時は非ゼロ終了する

test_session_state_subcommand_wait() {
  assert_file_exists "$SESSION_STATE" || return 1
  assert_file_contains "$SESSION_STATE" '\bwait\b' || return 1
  return 0
}
run_test "session-state.sh に wait サブコマンドが実装されている" test_session_state_subcommand_wait

test_session_state_wait_timeout() {
  assert_file_exists "$SESSION_STATE" || return 1
  # --timeout オプション処理があること
  assert_file_contains "$SESSION_STATE" '(--timeout|TIMEOUT)' || return 1
  return 0
}
run_test "session-state.sh の wait に --timeout オプションがある" test_session_state_wait_timeout

test_session_state_wait_nonzero_on_timeout() {
  assert_file_exists "$SESSION_STATE" || return 1
  # タイムアウト時に非ゼロ終了するコード（exit 1 など）があること
  assert_file_contains "$SESSION_STATE" 'exit [1-9]' || return 1
  return 0
}
run_test "session-state.sh wait がタイムアウト時に非ゼロ終了する" test_session_state_wait_nonzero_on_timeout

# Edge case: wait のポーリングループがあること
test_session_state_wait_polling_loop() {
  assert_file_exists "$SESSION_STATE" || return 1
  assert_file_contains "$SESSION_STATE" '(while|sleep|poll)' || return 1
  return 0
}
run_test "[edge: session-state.sh wait にポーリングループがある]" test_session_state_wait_polling_loop

# =============================================================================
# Requirement: session-comm.sh の移植
# =============================================================================
echo ""
echo "--- Requirement: session-comm.sh の移植 ---"

# Scenario: capture サブコマンド (line 25)
# WHEN: session-comm.sh capture <window> --lines 30 を実行する
# THEN: ANSI エスケープを除去したペイン内容を返す

test_session_comm_exists() {
  assert_file_exists "$SESSION_COMM"
}
run_test "session-comm.sh が存在する" test_session_comm_exists

test_session_comm_executable() {
  assert_file_executable "$SESSION_COMM"
}
run_test "session-comm.sh が実行可能である" test_session_comm_executable

test_session_comm_capture_subcommand() {
  assert_file_exists "$SESSION_COMM" || return 1
  assert_file_contains "$SESSION_COMM" '\bcapture\b' || return 1
  return 0
}
run_test "session-comm.sh に capture サブコマンドが実装されている" test_session_comm_capture_subcommand

test_session_comm_capture_lines_option() {
  assert_file_exists "$SESSION_COMM" || return 1
  # --lines オプションがあること
  assert_file_contains "$SESSION_COMM" '(--lines|LINES)' || return 1
  return 0
}
run_test "session-comm.sh の capture に --lines オプションがある" test_session_comm_capture_lines_option

test_session_comm_ansi_strip() {
  assert_file_exists "$SESSION_COMM" || return 1
  # ANSI エスケープ除去処理があること（sed/perl での ESC シーケンス除去）
  assert_file_contains "$SESSION_COMM" '(\\033|\\e\[|\\x1b|\[0-9.*m|ansi|ANSI|strip|sed.*ESC)' || return 1
  return 0
}
run_test "session-comm.sh が ANSI エスケープを除去する" test_session_comm_ansi_strip

# Scenario: inject サブコマンド（状態チェック付き）(line 29)
# WHEN: session-comm.sh inject <window> "text" を実行し、対象が processing 状態
# THEN: エラーを返し、テキストは送信されない

test_session_comm_inject_subcommand() {
  assert_file_exists "$SESSION_COMM" || return 1
  assert_file_contains "$SESSION_COMM" '\binject\b' || return 1
  return 0
}
run_test "session-comm.sh に inject サブコマンドが実装されている" test_session_comm_inject_subcommand

test_session_comm_inject_state_check() {
  assert_file_exists "$SESSION_COMM" || return 1
  # 状態チェックがあること（input-waiting または session-state 呼び出し）
  assert_file_contains "$SESSION_COMM" '(input-waiting|session-state.*state)' || return 1
  return 0
}
run_test "session-comm.sh の inject が状態チェックをする (input-waiting)" test_session_comm_inject_state_check

# Edge case: inject が processing 時にエラーで終了すること
test_session_comm_inject_error_on_processing() {
  assert_file_exists "$SESSION_COMM" || return 1
  # エラー終了またはエラーメッセージがあること
  assert_file_contains "$SESSION_COMM" 'exit [1-9]|Error|error.*inject|not.*input-waiting' || return 1
  return 0
}
run_test "[edge: session-comm.sh inject が processing 時にエラー終了する]" test_session_comm_inject_error_on_processing

# Scenario: inject サブコマンド（--force）(line 33)
# WHEN: session-comm.sh inject <window> "text" --force を実行する
# THEN: 状態チェックをバイパスしてテキストを送信する

test_session_comm_inject_force_option() {
  assert_file_exists "$SESSION_COMM" || return 1
  # --force オプションがあること
  assert_file_contains "$SESSION_COMM" '(--force|FORCE)' || return 1
  return 0
}
run_test "session-comm.sh の inject に --force オプションがある" test_session_comm_inject_force_option

# Edge case: session-state.sh への参照が同一ディレクトリ相対パスであること
test_session_comm_relative_session_state_ref() {
  assert_file_exists "$SESSION_COMM" || return 1
  # session-state.sh への参照（SCRIPT_DIR ベースまたは相対パス）
  assert_file_contains "$SESSION_COMM" '(SCRIPT_DIR.*session-state|session-state\.sh|session-state)' || return 1
  # ハードコードされた絶対パスがないこと
  assert_file_not_contains "$SESSION_COMM" '/home/[^$].*session-state\.sh' || return 1
  return 0
}
run_test "[edge: session-comm.sh の session-state.sh 参照が相対パス]" test_session_comm_relative_session_state_ref

# =============================================================================
# Requirement: cld の移植
# =============================================================================
echo ""
echo "--- Requirement: cld の移植 ---"

# Scenario: plugin 自動検出 (line 40)
# WHEN: cld を実行する
# THEN: $HOME/.claude/plugins/*/ を走査し --plugin-dir 引数を組み立てる

test_cld_exists() {
  assert_file_exists "$CLD"
}
run_test "cld が存在する" test_cld_exists

test_cld_executable() {
  assert_file_executable "$CLD"
}
run_test "cld が実行可能である" test_cld_executable

test_cld_plugin_auto_detect() {
  assert_file_exists "$CLD" || return 1
  # $HOME/.claude/plugins/ 走査があること
  assert_file_contains "$CLD" '(\.claude/plugins|PLUGINS_BASE)' || return 1
  return 0
}
run_test "cld に plugin ディレクトリ自動検出がある" test_cld_plugin_auto_detect

test_cld_plugin_dir_args() {
  assert_file_exists "$CLD" || return 1
  # --plugin-dir 引数を組み立てていること
  assert_file_contains "$CLD" '(--plugin-dir|PLUGIN_ARGS)' || return 1
  return 0
}
run_test "cld が --plugin-dir 引数を組み立てる" test_cld_plugin_dir_args

# Scenario: リソース制限 (line 44)
# WHEN: systemd-run が利用可能な環境で cld を実行する
# THEN: MemoryMax=12G の制限付きで claude が起動する

test_cld_systemd_run() {
  assert_file_exists "$CLD" || return 1
  # systemd-run コマンド使用があること
  assert_file_contains "$CLD" 'systemd-run' || return 1
  return 0
}
run_test "cld が systemd-run を使用する" test_cld_systemd_run

test_cld_memory_limit() {
  assert_file_exists "$CLD" || return 1
  # MemoryMax=12G 設定があること
  assert_file_contains "$CLD" 'MemoryMax=12G' || return 1
  return 0
}
run_test "cld に MemoryMax=12G リソース制限がある" test_cld_memory_limit

# Edge case: systemd-run が unavailable な場合のフォールバックまたはガード
test_cld_systemd_guard() {
  assert_file_exists "$CLD" || return 1
  # systemd-run の存在チェックまたは条件分岐があること
  assert_file_contains "$CLD" '(command.*systemd|which.*systemd|systemd.*available|exec systemd-run)' || return 1
  return 0
}
run_test "[edge: cld に systemd-run の利用可否チェックがある]" test_cld_systemd_guard

# =============================================================================
# Requirement: cld-spawn の移植
# =============================================================================
echo ""
echo "--- Requirement: cld-spawn の移植 ---"

# Scenario: 基本 spawn (line 52)
# WHEN: cld-spawn を引数なしで実行する
# THEN: spawn-HHmmss 形式の新 tmux ウィンドウが作成され、cld が起動する

test_cld_spawn_exists() {
  assert_file_exists "$CLD_SPAWN"
}
run_test "cld-spawn が存在する" test_cld_spawn_exists

test_cld_spawn_executable() {
  assert_file_executable "$CLD_SPAWN"
}
run_test "cld-spawn が実行可能である" test_cld_spawn_executable

test_cld_spawn_window_name_format() {
  assert_file_exists "$CLD_SPAWN" || return 1
  # spawn-HHmmss 形式のウィンドウ名生成があること
  assert_file_contains "$CLD_SPAWN" 'spawn-' || return 1
  return 0
}
run_test "cld-spawn が spawn-HHmmss 形式のウィンドウ名を生成する" test_cld_spawn_window_name_format

test_cld_spawn_tmux_new_window() {
  assert_file_exists "$CLD_SPAWN" || return 1
  # tmux new-window コマンド使用があること
  assert_file_contains "$CLD_SPAWN" '(tmux new-window|new-window)' || return 1
  return 0
}
run_test "cld-spawn が tmux new-window を使用する" test_cld_spawn_tmux_new_window

test_cld_spawn_cld_invocation() {
  assert_file_exists "$CLD_SPAWN" || return 1
  # cld スクリプトを起動していること
  assert_file_contains "$CLD_SPAWN" '\bcld\b' || return 1
  return 0
}
run_test "cld-spawn が cld を起動する" test_cld_spawn_cld_invocation

# Edge case: tmux 外で実行した場合のエラー終了
test_cld_spawn_tmux_check() {
  assert_file_exists "$CLD_SPAWN" || return 1
  # tmux 内チェックがあること
  assert_file_contains "$CLD_SPAWN" 'TMUX|tmux' || return 1
  return 0
}
run_test "[edge: cld-spawn が tmux 外実行を検出してエラー終了する]" test_cld_spawn_tmux_check

# Scenario: --cd オプション (line 56)
# WHEN: cld-spawn --cd /path/to/dir "initial prompt" を実行する
# THEN: 指定ディレクトリに移動してから cld が起動し、初期プロンプトが渡される

test_cld_spawn_cd_option() {
  assert_file_exists "$CLD_SPAWN" || return 1
  # --cd オプション処理があること
  assert_file_contains "$CLD_SPAWN" '(--cd)' || return 1
  return 0
}
run_test "cld-spawn に --cd オプションがある" test_cld_spawn_cd_option

test_cld_spawn_initial_prompt() {
  assert_file_exists "$CLD_SPAWN" || return 1
  # 初期プロンプトが渡される処理（引数の受け渡し）があること
  assert_file_contains "$CLD_SPAWN" '\$@|\$\*|\$1|PROMPT|prompt' || return 1
  return 0
}
run_test "cld-spawn が初期プロンプトを cld に渡す" test_cld_spawn_initial_prompt

# =============================================================================
# Requirement: cld-observe の移植
# =============================================================================
echo ""
echo "--- Requirement: cld-observe の移植 ---"

# Scenario: デフォルト行数 (line 64)
# WHEN: cld-observe <window> を実行する
# THEN: 30 行分のペイン内容をキャプチャし、状態メタデータ付きで出力する

test_cld_observe_exists() {
  assert_file_exists "$CLD_OBSERVE"
}
run_test "cld-observe が存在する" test_cld_observe_exists

test_cld_observe_executable() {
  assert_file_executable "$CLD_OBSERVE"
}
run_test "cld-observe が実行可能である" test_cld_observe_executable

test_cld_observe_default_lines() {
  assert_file_exists "$CLD_OBSERVE" || return 1
  # デフォルト 30 行の定義があること
  assert_file_contains "$CLD_OBSERVE" '(DEFAULT_LINES.*30|30.*DEFAULT|LINES.*30)' || return 1
  return 0
}
run_test "cld-observe のデフォルト行数が 30 である" test_cld_observe_default_lines

test_cld_observe_state_metadata() {
  assert_file_exists "$CLD_OBSERVE" || return 1
  # 状態メタデータ出力があること（session-state or 状態文字列）
  assert_file_contains "$CLD_OBSERVE" '(session-state|state|STATE|STATUS|status)' || return 1
  return 0
}
run_test "cld-observe が状態メタデータ付きで出力する" test_cld_observe_state_metadata

# Scenario: --all オプション (line 68)
# WHEN: cld-observe <window> --all を実行する
# THEN: 全スクロールバックをキャプチャする

test_cld_observe_all_option() {
  assert_file_exists "$CLD_OBSERVE" || return 1
  # --all オプション処理があること
  assert_file_contains "$CLD_OBSERVE" '--all' || return 1
  return 0
}
run_test "cld-observe に --all オプションがある" test_cld_observe_all_option

# Edge case: --all 使用時はスクロールバック全量取得（-S ゼロ等）が使われること
test_cld_observe_all_full_scrollback() {
  assert_file_exists "$CLD_OBSERVE" || return 1
  # tmux capture-pane -S または全取得指定があること
  assert_file_contains "$CLD_OBSERVE" 'CAPTURE_ARGS=.*--all|session-comm.*--all' || return 1
  return 0
}
run_test "[edge: cld-observe --all が全スクロールバックを取得する]" test_cld_observe_all_full_scrollback

# =============================================================================
# Requirement: cld-fork の移植
# =============================================================================
echo ""
echo "--- Requirement: cld-fork の移植 ---"

# Scenario: 基本 fork (line 76)
# WHEN: cld-fork を実行する
# THEN: fork-HHmmss 形式の新 tmux ウィンドウが作成され、--continue --fork-session 付きで cld が起動する

test_cld_fork_exists() {
  assert_file_exists "$CLD_FORK"
}
run_test "cld-fork が存在する" test_cld_fork_exists

test_cld_fork_executable() {
  assert_file_executable "$CLD_FORK"
}
run_test "cld-fork が実行可能である" test_cld_fork_executable

test_cld_fork_window_name_format() {
  assert_file_exists "$CLD_FORK" || return 1
  # fork-HHmmss 形式のウィンドウ名生成があること
  assert_file_contains "$CLD_FORK" 'fork-' || return 1
  return 0
}
run_test "cld-fork が fork-HHmmss 形式のウィンドウ名を生成する" test_cld_fork_window_name_format

test_cld_fork_continue_flag() {
  assert_file_exists "$CLD_FORK" || return 1
  # --continue フラグが使われていること
  assert_file_contains "$CLD_FORK" '--continue' || return 1
  return 0
}
run_test "cld-fork が --continue フラグ付きで cld を起動する" test_cld_fork_continue_flag

test_cld_fork_fork_session_flag() {
  assert_file_exists "$CLD_FORK" || return 1
  # --fork-session フラグが使われていること
  assert_file_contains "$CLD_FORK" '--fork-session' || return 1
  return 0
}
run_test "cld-fork が --fork-session フラグ付きで cld を起動する" test_cld_fork_fork_session_flag

# Edge case: tmux 外で実行した場合のエラー終了
test_cld_fork_tmux_check() {
  assert_file_exists "$CLD_FORK" || return 1
  assert_file_contains "$CLD_FORK" 'TMUX|tmux' || return 1
  return 0
}
run_test "[edge: cld-fork が tmux 外実行を検出してエラー終了する]" test_cld_fork_tmux_check

# =============================================================================
# Requirement: claude-session-save.sh の移植
# =============================================================================
echo ""
echo "--- Requirement: claude-session-save.sh の移植 ---"

# Scenario: セッション ID マッピング (line 84)
# WHEN: SessionStart hook から session_id を含む JSON が stdin で渡される
# THEN: tmux-pane-map.tsv と tmux-session-map.tsv にマッピングが保存される

test_claude_session_save_exists() {
  assert_file_exists "$CLAUDE_SESSION_SAVE"
}
run_test "claude-session-save.sh が存在する" test_claude_session_save_exists

test_claude_session_save_executable() {
  assert_file_executable "$CLAUDE_SESSION_SAVE"
}
run_test "claude-session-save.sh が実行可能である" test_claude_session_save_executable

test_claude_session_save_reads_session_id() {
  assert_file_exists "$CLAUDE_SESSION_SAVE" || return 1
  # stdin から session_id を読み取る処理があること
  assert_file_contains "$CLAUDE_SESSION_SAVE" 'session_id' || return 1
  return 0
}
run_test "claude-session-save.sh が session_id を stdin から読み取る" test_claude_session_save_reads_session_id

test_claude_session_save_pane_map() {
  assert_file_exists "$CLAUDE_SESSION_SAVE" || return 1
  # tmux-pane-map.tsv へのマッピング保存があること
  assert_file_contains "$CLAUDE_SESSION_SAVE" 'tmux-pane-map\.tsv|pane-map' || return 1
  return 0
}
run_test "claude-session-save.sh が tmux-pane-map.tsv に保存する" test_claude_session_save_pane_map

test_claude_session_save_session_map() {
  assert_file_exists "$CLAUDE_SESSION_SAVE" || return 1
  # tmux-session-map.tsv へのマッピング保存があること
  assert_file_contains "$CLAUDE_SESSION_SAVE" 'tmux-session-map\.tsv|session-map' || return 1
  return 0
}
run_test "claude-session-save.sh が tmux-session-map.tsv に保存する" test_claude_session_save_session_map

# Scenario: 排他制御 (line 88)
# WHEN: 複数の Claude ウィンドウが同時に起動する
# THEN: flock による排他制御で TSV ファイルの競合を防ぐ

test_claude_session_save_flock() {
  assert_file_exists "$CLAUDE_SESSION_SAVE" || return 1
  # flock 使用があること
  assert_file_contains "$CLAUDE_SESSION_SAVE" 'flock' || return 1
  return 0
}
run_test "claude-session-save.sh が flock で排他制御する" test_claude_session_save_flock

# Edge case: ロックファイルが明示的に指定されていること
test_claude_session_save_lockfile() {
  assert_file_exists "$CLAUDE_SESSION_SAVE" || return 1
  # ロックファイルの定義があること
  assert_file_contains "$CLAUDE_SESSION_SAVE" 'LOCKFILE|LOCK_FILE|\.lock|lockfile' || return 1
  return 0
}
run_test "[edge: claude-session-save.sh にロックファイルが定義されている]" test_claude_session_save_lockfile

# Edge case: tmux 外実行時はスキップ（$TMUX 未設定）
test_claude_session_save_tmux_guard() {
  assert_file_exists "$CLAUDE_SESSION_SAVE" || return 1
  # TMUX 環境変数チェックがあること
  assert_file_contains "$CLAUDE_SESSION_SAVE" '\$\{?TMUX' || return 1
  return 0
}
run_test "[edge: claude-session-save.sh が tmux 外で早期終了する]" test_claude_session_save_tmux_guard

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "loom-plugin-session-scripts-migration: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
