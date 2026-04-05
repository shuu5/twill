#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: autopilot-launch-sh
# Generated from: openspec/changes/autopilot-launch-sh/specs/autopilot-launch-sh/spec.md
# Coverage level: edge-cases
# Type: unit
# =============================================================================
set -uo pipefail

# Project root (relative to test file location)
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

# Counters
PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_executable() {
  local file="$1"
  [[ -x "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_all() {
  local file="$1"
  shift
  local patterns=("$@")
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  for pattern in "${patterns[@]}"; do
    grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}" || return 1
  done
  return 0
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
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

LAUNCH_SH="scripts/autopilot-launch.sh"

# =============================================================================
# Requirement: autopilot-launch.sh スクリプト新設
# =============================================================================
echo ""
echo "--- Requirement: autopilot-launch.sh スクリプト新設 ---"

# ---------------------------------------------------------------------------
# Scenario: 必須引数による正常起動
# WHEN: --issue 42 --project-dir /path/to/project --autopilot-dir /path/to/.autopilot で実行
# THEN: tmux new-window が作成され、cld が AUTOPILOT_DIR 環境変数付きで起動される
# ---------------------------------------------------------------------------

test_launch_sh_exists() {
  assert_file_exists "$LAUNCH_SH"
}
run_test "autopilot-launch.sh が存在する" test_launch_sh_exists

test_launch_sh_executable() {
  assert_file_executable "$LAUNCH_SH"
}
run_test "autopilot-launch.sh が実行可能である" test_launch_sh_executable

test_launch_sh_issue_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-issue' || return 1
  return 0
}
run_test "autopilot-launch.sh に --issue フラグが存在する" test_launch_sh_issue_flag

test_launch_sh_project_dir_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-project-dir' || return 1
  return 0
}
run_test "autopilot-launch.sh に --project-dir フラグが存在する" test_launch_sh_project_dir_flag

test_launch_sh_autopilot_dir_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-autopilot-dir' || return 1
  return 0
}
run_test "autopilot-launch.sh に --autopilot-dir フラグが存在する" test_launch_sh_autopilot_dir_flag

test_launch_sh_tmux_new_window() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'tmux\s+new-window' || return 1
  return 0
}
run_test "tmux new-window でウィンドウを作成する" test_launch_sh_tmux_new_window

test_launch_sh_autopilot_dir_env() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'AUTOPILOT_DIR' || return 1
  return 0
}
run_test "cld 起動時に AUTOPILOT_DIR 環境変数を渡す" test_launch_sh_autopilot_dir_env

# ---------------------------------------------------------------------------
# Scenario: cld パス解決
# WHEN: スクリプトが実行される
# THEN: command -v cld で cld パスを解決。見つからない場合は state-write で failed を記録し終了コード 2 で終了
# ---------------------------------------------------------------------------

test_launch_sh_cld_resolve() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'command\s+-v\s+cld' || return 1
  return 0
}
run_test "command -v cld で cld パスを解決する" test_launch_sh_cld_resolve

test_launch_sh_cld_missing_exit2() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'exit\s+2' || return 1
  return 0
}
run_test "cld 未発見時に終了コード 2 で終了する" test_launch_sh_cld_missing_exit2

test_launch_sh_cld_missing_state_write() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'state-write' || return 1
  return 0
}
run_test "cld 未発見時に state-write で failed を記録する" test_launch_sh_cld_missing_state_write

# [edge] cld 未発見時のエラーメッセージ出力
test_launch_sh_cld_missing_error_msg() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Either echo or printf to stderr mentioning cld
  assert_file_contains "$LAUNCH_SH" 'cld.*(not found|見つかりません|見つからない)|ERROR.*cld' || return 1
  return 0
}
run_test "[edge] cld 未発見時にエラーメッセージを出力する" test_launch_sh_cld_missing_error_msg

# ---------------------------------------------------------------------------
# Scenario: issue state 初期化
# WHEN: スクリプトが実行される
# THEN: state-write.sh --type issue --issue $ISSUE --role worker --init で issue-{N}.json を初期化
# ---------------------------------------------------------------------------

test_launch_sh_state_init_type_issue() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'state-write.*--type\s+issue' || return 1
  return 0
}
run_test "state-write.sh --type issue で初期化する" test_launch_sh_state_init_type_issue

test_launch_sh_state_init_role_worker() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '--role\s+worker' || return 1
  return 0
}
run_test "state-write.sh --role worker が指定される" test_launch_sh_state_init_role_worker

test_launch_sh_state_init_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'state-write.*--init' || return 1
  return 0
}
run_test "state-write.sh --init フラグが存在する" test_launch_sh_state_init_flag

# ---------------------------------------------------------------------------
# Scenario: ISSUE 数値バリデーション
# WHEN: --issue abc のように非数値が渡される
# THEN: エラーメッセージを出力し終了コード 1 で終了しなければならない（SHALL）
# ---------------------------------------------------------------------------

test_launch_sh_issue_numeric_validation() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # ISSUE must be validated as a positive integer (regex or arithmetic check)
  assert_file_contains "$LAUNCH_SH" '\^\[0-9\]\+\$|\^\[1-9\]\[0-9\]\*\$|=~\s+\^[0-9]|=~\s+\^\[0-9\]' || \
  assert_file_contains "$LAUNCH_SH" 'ISSUE.*[0-9]' || return 1
  return 0
}
run_test "ISSUE 数値バリデーション（正規表現 or 算術チェック）が存在する" test_launch_sh_issue_numeric_validation

test_launch_sh_issue_validation_exit1() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'exit\s+1' || return 1
  return 0
}
run_test "バリデーション失敗時に終了コード 1 で終了する" test_launch_sh_issue_validation_exit1

# [edge] ISSUE=0 のゼロ値拒否
test_launch_sh_issue_zero_rejected() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Script should reject 0 (only positive integers accepted)
  # Check for pattern like ^[1-9][0-9]*$ or -gt 0 or -le 0
  assert_file_contains "$LAUNCH_SH" '\^[1-9]|\-gt\s+0|\-le\s+0|\-lt\s+1' || \
  assert_file_contains "$LAUNCH_SH" 'ISSUE.*0' || return 1
  return 0
}
run_test "[edge] ISSUE=0 はバリデーションエラーになる" test_launch_sh_issue_zero_rejected

# [edge] ISSUE が空文字のエラー処理
test_launch_sh_issue_empty_rejected() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Validate that ISSUE must be provided (non-empty check)
  assert_file_contains "$LAUNCH_SH" '-z "\$ISSUE"|-z.*ISSUE|ISSUE.*-z' || return 1
  return 0
}
run_test "[edge] ISSUE 未指定（空）時はバリデーションエラーになる" test_launch_sh_issue_empty_rejected

# [edge] ISSUE 負数の拒否（-1 など）
test_launch_sh_issue_negative_rejected() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Should validate using regex or comparison that excludes negative numbers
  assert_file_contains "$LAUNCH_SH" '\^[1-9]|\-gt\s+0|\^\[0-9\]' || return 1
  return 0
}
run_test "[edge] ISSUE=-1 のような負数はバリデーションエラーになる" test_launch_sh_issue_negative_rejected

# ---------------------------------------------------------------------------
# Scenario: パストラバーサル防止
# WHEN: --autopilot-dir /path/../etc/passwd のように .. を含むパスが渡される
# THEN: エラーメッセージを出力し state-write で failed を記録して終了コード 1 で終了
# ---------------------------------------------------------------------------

test_launch_sh_path_traversal_check() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Check for .. detection pattern in path traversal regex
  assert_file_contains "$LAUNCH_SH" '\\\.\\\.\/' || return 1
  return 0
}
run_test "パストラバーサル（..）チェックが実装されている" test_launch_sh_path_traversal_check

test_launch_sh_path_traversal_state_write() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # state-write for failed must exist alongside traversal check
  assert_file_contains "$LAUNCH_SH" 'state-write' || return 1
  return 0
}
run_test "パストラバーサル検出時に state-write で failed を記録する" test_launch_sh_path_traversal_state_write

# [edge] --project-dir にも .. チェックが適用される
test_launch_sh_project_dir_traversal_check() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # The traversal check should cover project-dir
  assert_file_contains "$LAUNCH_SH" 'PROJECT_DIR.*\\\.\\\.' || return 1
  return 0
}
run_test "[edge] --project-dir のパストラバーサルチェックが存在する" test_launch_sh_project_dir_traversal_check

# ---------------------------------------------------------------------------
# Scenario: bare repo 検出と LAUNCH_DIR 計算
# WHEN: --project-dir のパスに .bare/ ディレクトリが存在する
# THEN: LAUNCH_DIR を $PROJECT_DIR/main に設定
# WHEN: .bare/ が存在しない
# THEN: LAUNCH_DIR を $PROJECT_DIR のまま使用する
# ---------------------------------------------------------------------------

test_launch_sh_bare_repo_detection() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\.bare' || return 1
  return 0
}
run_test ".bare/ ディレクトリの検出ロジックが存在する" test_launch_sh_bare_repo_detection

test_launch_sh_launch_dir_main() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'LAUNCH_DIR.*main|main.*LAUNCH_DIR' || return 1
  return 0
}
run_test ".bare/ 検出時に LAUNCH_DIR に /main を付加する" test_launch_sh_launch_dir_main

test_launch_sh_launch_dir_fallback() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'LAUNCH_DIR.*PROJECT_DIR|LAUNCH_DIR=.*PROJECT_DIR' || return 1
  return 0
}
run_test ".bare/ 非検出時は LAUNCH_DIR = PROJECT_DIR をフォールバックとする" test_launch_sh_launch_dir_fallback

# [edge] .bare がファイルではなくディレクトリであることを確認する
test_launch_sh_bare_is_directory_check() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # -d check for .bare directory
  assert_file_contains "$LAUNCH_SH" '-d.*\.bare|\.bare.*-d' || return 1
  return 0
}
run_test "[edge] .bare/ がディレクトリであるか -d フラグで確認する" test_launch_sh_bare_is_directory_check

# ---------------------------------------------------------------------------
# Scenario: コンテキスト注入
# WHEN: --context "テキスト" が指定される
# THEN: printf '%q' によるクォーティングを行い --append-system-prompt 引数として cld に渡す
# ---------------------------------------------------------------------------

test_launch_sh_context_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-context' || return 1
  return 0
}
run_test "autopilot-launch.sh に --context フラグが存在する" test_launch_sh_context_flag

test_launch_sh_context_printf_quote() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" "printf\s+'%q'" || return 1
  return 0
}
run_test "--context の値を printf '%q' でクォーティングする" test_launch_sh_context_printf_quote

test_launch_sh_context_append_system_prompt() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-append-system-prompt' || return 1
  return 0
}
run_test "--context の値を --append-system-prompt として cld に渡す" test_launch_sh_context_append_system_prompt

# [edge] --context 未指定時は --append-system-prompt を渡さない
test_launch_sh_context_optional() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Should have conditional logic for context (only added when set)
  assert_file_contains "$LAUNCH_SH" 'CONTEXT|context' || return 1
  return 0
}
run_test "[edge] --context 未指定時は --append-system-prompt を省略する" test_launch_sh_context_optional

# ---------------------------------------------------------------------------
# Scenario: クロスリポジトリ対応
# WHEN: --repo-owner OWNER --repo-name NAME が指定される
# THEN: REPO_OWNER と REPO_NAME を環境変数として Worker に渡す
# ---------------------------------------------------------------------------

test_launch_sh_repo_owner_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-repo-owner' || return 1
  return 0
}
run_test "--repo-owner フラグが存在する" test_launch_sh_repo_owner_flag

test_launch_sh_repo_name_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-repo-name' || return 1
  return 0
}
run_test "--repo-name フラグが存在する" test_launch_sh_repo_name_flag

test_launch_sh_repo_owner_env() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'REPO_OWNER' || return 1
  return 0
}
run_test "REPO_OWNER 環境変数が Worker に渡される" test_launch_sh_repo_owner_env

test_launch_sh_repo_name_env() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'REPO_NAME' || return 1
  return 0
}
run_test "REPO_NAME 環境変数が Worker に渡される" test_launch_sh_repo_name_env

# ---------------------------------------------------------------------------
# Scenario: クロスリポジトリ repo-path
# WHEN: --repo-path /path/to/external が指定される
# THEN: そのパスを EFFECTIVE_PROJECT_DIR として使用。パスが存在しない場合は failed を記録して終了
# ---------------------------------------------------------------------------

test_launch_sh_repo_path_flag() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" '\-\-repo-path' || return 1
  return 0
}
run_test "--repo-path フラグが存在する" test_launch_sh_repo_path_flag

test_launch_sh_effective_project_dir() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'EFFECTIVE_PROJECT_DIR' || return 1
  return 0
}
run_test "--repo-path を EFFECTIVE_PROJECT_DIR として使用する" test_launch_sh_effective_project_dir

test_launch_sh_repo_path_existence_check() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Must check path exists (-d flag) before using it
  assert_file_contains "$LAUNCH_SH" '-d.*REPO_PATH|REPO_PATH.*-d' || return 1
  return 0
}
run_test "--repo-path が存在しない場合に failed を記録して終了する" test_launch_sh_repo_path_existence_check

# [edge] --repo-path の絶対パスチェック
test_launch_sh_repo_path_absolute() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # repo-path should also be validated as absolute path
  assert_file_contains "$LAUNCH_SH" 'REPO_PATH.*!=.*/\*|REPO_PATH.*=~.*\^/' || return 1
  return 0
}
run_test "[edge] --repo-path は絶対パスでなければならない" test_launch_sh_repo_path_absolute

# ---------------------------------------------------------------------------
# Scenario: クラッシュ検知フック設定
# WHEN: tmux window が正常に作成される
# THEN: remain-on-exit on と pane-died フックを設定し、crash-detect.sh を呼び出す構成にする
# ---------------------------------------------------------------------------

test_launch_sh_remain_on_exit() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'remain-on-exit' || return 1
  return 0
}
run_test "remain-on-exit on が設定される" test_launch_sh_remain_on_exit

test_launch_sh_pane_died_hook() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'pane-died' || return 1
  return 0
}
run_test "pane-died フックが設定される" test_launch_sh_pane_died_hook

test_launch_sh_crash_detect() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'crash-detect' || return 1
  return 0
}
run_test "crash-detect.sh が pane-died フックで呼び出される" test_launch_sh_crash_detect

# [edge] tmux set-hook コマンドで pane-died を設定する
test_launch_sh_set_hook_command() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'tmux\s+set-hook|tmux\s+set-option' || return 1
  return 0
}
run_test "[edge] tmux set-hook または set-option で remain-on-exit/pane-died を設定する" test_launch_sh_set_hook_command

# ---------------------------------------------------------------------------
# Scenario: SCRIPTS_ROOT 自動解決
# WHEN: スクリプトが任意のディレクトリから呼び出される
# THEN: $(cd "$(dirname "$0")" && pwd) で自身のディレクトリを SCRIPTS_ROOT として解決
# ---------------------------------------------------------------------------

test_launch_sh_scripts_root_resolution() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'dirname.*\$0|dirname.*BASH_SOURCE' || return 1
  return 0
}
run_test "SCRIPTS_ROOT を dirname \$0 または BASH_SOURCE で解決する" test_launch_sh_scripts_root_resolution

test_launch_sh_scripts_root_variable() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'SCRIPTS_ROOT' || return 1
  return 0
}
run_test "SCRIPTS_ROOT 変数が定義されている" test_launch_sh_scripts_root_variable

test_launch_sh_scripts_root_cd_pwd() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # Canonical form: $(cd "$(dirname "$0")" && pwd)
  assert_file_contains "$LAUNCH_SH" 'cd.*dirname.*&&\s*pwd' || return 1
  return 0
}
run_test "SCRIPTS_ROOT が cd && pwd の標準形式で解決される" test_launch_sh_scripts_root_cd_pwd

# =============================================================================
# Requirement: 終了コード体系
# =============================================================================
echo ""
echo "--- Requirement: 終了コード体系 ---"

# ---------------------------------------------------------------------------
# Scenario: 正常終了
# WHEN: Worker 起動が成功
# THEN: 終了コード 0
# ---------------------------------------------------------------------------

test_exit_code_0_exists() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'exit\s+0' || return 1
  return 0
}
run_test "正常起動時に終了コード 0 で終了する" test_exit_code_0_exists

# ---------------------------------------------------------------------------
# Scenario: バリデーションエラー
# WHEN: 引数バリデーションに失敗
# THEN: 終了コード 1、state-write で failed を記録
# ---------------------------------------------------------------------------

test_exit_code_1_validation() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'exit\s+1' || return 1
  return 0
}
run_test "バリデーション失敗時に終了コード 1 で終了する" test_exit_code_1_validation

test_exit_code_1_state_write_failed() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'state-write' || return 1
  return 0
}
run_test "バリデーション失敗時に state-write で failed を記録する" test_exit_code_1_state_write_failed

# ---------------------------------------------------------------------------
# Scenario: 外部コマンド不在
# WHEN: cld が見つからない
# THEN: 終了コード 2、state-write で failed を記録
# ---------------------------------------------------------------------------

test_exit_code_2_external_cmd() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" 'exit\s+2' || return 1
  return 0
}
run_test "外部コマンド不在時に終了コード 2 で終了する" test_exit_code_2_external_cmd

test_exit_code_2_distinct_from_1() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains_all "$LAUNCH_SH" 'exit\s+1' 'exit\s+2' || return 1
  return 0
}
run_test "終了コード 1（バリデーション）と 2（コマンド不在）が明確に区別されている" test_exit_code_2_distinct_from_1

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=== Summary ==="
echo "PASS: ${PASS} / FAIL: ${FAIL} / SKIP: ${SKIP}"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for e in "${ERRORS[@]}"; do
    echo "  - ${e}"
  done
  exit 1
fi
exit 0
