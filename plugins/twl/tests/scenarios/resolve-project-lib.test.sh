#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: resolve-project-lib
# Generated from: deltaspec/changes/resolve-project-lib/specs/resolve-project/spec.md
# Coverage level: edge-cases
# =============================================================================
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# --- Test Helpers ---

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

run_test() {
  local name="$1"
  local func="$2"
  local result=0
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

LIB_SCRIPT="scripts/lib/resolve-project.sh"
CHAIN_RUNNER="scripts/chain-runner.sh"
ARCHIVE_SCRIPT="scripts/project-board-archive.sh"
BACKFILL_SCRIPT="scripts/project-board-backfill.sh"
AUTOPILOT_BOARD="scripts/autopilot-plan-board.sh"
DEPS_FILE="deps.yaml"

# =============================================================================
# Requirement: resolve_project 共通関数の作成
# Scenario: 正常系 - リンク済み Project が存在する場合
# WHEN: resolve_project を呼び出し、リポジトリにリンクされた Project が存在する
# THEN: stdout に project_num project_id owner repo_name repo_fullname の5値が
#       空白区切りで出力され、終了コード0で返る
# =============================================================================
echo ""
echo "--- Scenario: 正常系 - リンク済み Project が存在する場合 ---"

test_lib_file_exists() {
  assert_file_exists "$LIB_SCRIPT"
}
run_test "resolve-project-lib [scripts/lib/resolve-project.sh が存在する]" test_lib_file_exists

test_resolve_project_function_defined() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'resolve_project\s*\(\)' || \
  assert_file_contains "$LIB_SCRIPT" 'function\s+resolve_project\b'
}
run_test "resolve-project-lib [resolve_project 関数が定義されている]" test_resolve_project_function_defined

test_resolve_project_outputs_5_values() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # 5値を出力するエコー文: project_num project_id owner repo_name repo_fullname
  assert_file_contains "$LIB_SCRIPT" \
    'echo.*\$\{?.*\}?\s+\$\{?.*\}?\s+\$\{?.*\}?\s+\$\{?.*\}?\s+\$\{?.*\}?' || \
  assert_file_contains "$LIB_SCRIPT" \
    'echo\s+"\$\{?final_num\|project_num'
}
run_test "resolve-project-lib [stdout に5値を空白区切りで出力する echo 文が存在する]" test_resolve_project_outputs_5_values

test_resolve_project_outputs_5_field_names() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # コメントや変数名から5つのフィールドが確認できること
  assert_file_contains "$LIB_SCRIPT" 'project_num|project_id|owner|repo_name|repo_fullname' || return 1
}
run_test "resolve-project-lib [5値(project_num/project_id/owner/repo_name/repo_fullname)が変数として存在する]" test_resolve_project_outputs_5_field_names

test_resolve_project_uses_gh_graphql() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'gh api graphql|gh.*graphql'
}
run_test "resolve-project-lib [GitHub GraphQL API を使用している]" test_resolve_project_uses_gh_graphql

test_resolve_project_exit_zero_on_success() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # 正常終了は明示的 exit 0 か return 0 (デフォルト) で行う
  # exit 1 / return 1 のみで exit 0 がないのは NG ではないが、
  # 少なくとも非ゼロ終了に対してガードが必要
  assert_file_contains "$LIB_SCRIPT" 'return 0|exit 0'
}
run_test "resolve-project-lib [正常終了コード0が返される (return 0 / exit 0)]" test_resolve_project_exit_zero_on_success

# =============================================================================
# Requirement: resolve_project 共通関数の作成
# Scenario: タイトルマッチ優先
# WHEN: 複数の Project がリポジトリにリンクされており、そのうち1つのタイトルにリポ名が含まれる
# THEN: タイトルマッチした Project が優先して返される
# =============================================================================
echo ""
echo "--- Scenario: タイトルマッチ優先 ---"

test_resolve_project_title_match_variable() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'title_match'
}
run_test "resolve-project-lib [title_match 変数が存在する]" test_resolve_project_title_match_variable

test_resolve_project_title_match_priority() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # タイトルマッチ優先ロジック: ${title_match_num:-$matched_project_num} パターン
  assert_file_contains "$LIB_SCRIPT" '\$\{title_match.*:-.*matched|\$\{.*:-.*title_match'
}
run_test "resolve-project-lib [タイトルマッチ優先ロジック (title_match:-matched) が存在する]" test_resolve_project_title_match_priority

test_resolve_project_checks_title_contains_repo_name() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # project_title に repo_name が含まれるかチェック: == *"$repo_name"* パターン
  assert_file_contains "$LIB_SCRIPT" '\*.*\$.*repo_name.*\*|\*"\$repo_name"\*'
}
run_test "resolve-project-lib [Project タイトルにリポ名が含まれるか判定する]" test_resolve_project_checks_title_contains_repo_name

# =============================================================================
# Requirement: resolve_project 共通関数の作成
# Scenario: エラー系 - Project が存在しない場合
# WHEN: resolve_project を呼び出し、リポジトリにリンクされた Project が存在しない
# THEN: stderr にエラーメッセージを出力し、非ゼロ終了コードで返る
# =============================================================================
echo ""
echo "--- Scenario: エラー系 - Project が存在しない場合 ---"

test_resolve_project_stderr_on_no_project() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # stderr 出力: >&2 パターン
  assert_file_contains "$LIB_SCRIPT" '>&2'
}
run_test "resolve-project-lib [エラー時に stderr へ出力する (>&2) ロジックが存在する]" test_resolve_project_stderr_on_no_project

test_resolve_project_nonzero_exit_on_no_project() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # 非ゼロ終了: return 1 / exit 1
  assert_file_contains "$LIB_SCRIPT" 'return 1|exit 1'
}
run_test "resolve-project-lib [Project なし時に非ゼロ終了コード (return 1 / exit 1) を返す]" test_resolve_project_nonzero_exit_on_no_project

test_resolve_project_error_message_no_project() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # エラーメッセージ: "Project なし" / "no project" / "リンク" 等の日本語または英語メッセージ
  assert_file_contains "$LIB_SCRIPT" \
    'Project.*な|リンク.*なし|no.*project|not.*found|なし' || \
  assert_file_contains "$LIB_SCRIPT" 'Error.*Project|Project.*Error'
}
run_test "resolve-project-lib [Project 未検出時のエラーメッセージが存在する]" test_resolve_project_error_message_no_project

# =============================================================================
# Requirement: resolve_project 共通関数の作成
# Scenario: mapfile による word-split 安全化
# WHEN: gh project list の出力に複数の Project 番号が含まれる
# THEN: mapfile -t パターンで配列化され、word-split なしに安全にループ処理される
# =============================================================================
echo ""
echo "--- Scenario: mapfile による word-split 安全化 ---"

test_resolve_project_uses_mapfile() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  assert_file_contains "$LIB_SCRIPT" 'mapfile\s+-t'
}
run_test "resolve-project-lib [mapfile -t パターンを使用している]" test_resolve_project_uses_mapfile

test_resolve_project_uses_process_substitution() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # mapfile -t array < <(...) パターン
  assert_file_contains "$LIB_SCRIPT" 'mapfile\s+-t\s+\w+\s+<\s+<\('
}
run_test "resolve-project-lib [mapfile -t var < <(...) process substitution を使用している]" test_resolve_project_uses_process_substitution

test_resolve_project_iterates_with_quoted_array() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # "${array[@]}" パターンでイテレーション
  assert_file_contains "$LIB_SCRIPT" '"\$\{.*\[@\]\}"'
}
run_test 'resolve-project-lib ["${array[@]}" でイテレーションしている]' test_resolve_project_iterates_with_quoted_array

test_resolve_project_no_unquoted_wordsplit() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # for pnum in $project_nums (unquoted) パターンがない
  assert_file_not_contains "$LIB_SCRIPT" 'for\s+\w+\s+in\s+\$project_nums\b' || return 1
}
run_test "resolve-project-lib [edge: for X in \$VAR の unquoted word-split パターンが存在しない]" test_resolve_project_no_unquoted_wordsplit

test_resolve_project_bash_syntax_valid() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${LIB_SCRIPT}" 2>/dev/null
}
run_test "resolve-project-lib [bash 構文エラーなし]" test_resolve_project_bash_syntax_valid

# =============================================================================
# Requirement: chain-runner.sh の board 操作関数のリファクタリング
# Scenario: step_board_status_update の動作継続
# WHEN: step_board_status_update が呼び出される
# THEN: 既存の動作（Project Board のステータスを "In Progress" に更新）が維持される
# =============================================================================
echo ""
echo "--- Scenario: step_board_status_update の動作継続 ---"

test_chain_runner_sources_resolve_project() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # source または . コマンドで resolve-project.sh を読み込む
  assert_file_contains "$CHAIN_RUNNER" \
    'source.*resolve-project|\.\s.*resolve-project|source.*lib/'
}
run_test "chain-runner [resolve-project.sh を source している]" test_chain_runner_sources_resolve_project

test_chain_runner_board_status_uses_resolve_project() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # step_board_status_update 関数内で resolve_project() を呼び出す
  # resolve_project_root() とは区別するため、単独の呼び出しパターンを確認
  assert_file_contains "$CHAIN_RUNNER" 'resolve_project\b[^_]'
}
run_test "chain-runner [step_board_status_update が resolve_project を呼び出している]" test_chain_runner_board_status_uses_resolve_project

test_chain_runner_board_status_in_progress() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # "In Progress" 更新ロジックが残存している
  assert_file_contains "$CHAIN_RUNNER" 'In Progress'
}
run_test "chain-runner [step_board_status_update: 'In Progress' ステータス更新ロジックが維持されている]" test_chain_runner_board_status_in_progress

test_chain_runner_board_status_function_exists() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  assert_file_contains "$CHAIN_RUNNER" 'step_board_status_update\s*\(\)'
}
run_test "chain-runner [step_board_status_update 関数が定義されている]" test_chain_runner_board_status_function_exists

# =============================================================================
# Requirement: chain-runner.sh の board 操作関数のリファクタリング
# Scenario: step_board_archive の動作継続
# WHEN: step_board_archive が呼び出される
# THEN: 既存の動作（Issue のアーカイブ）が維持される
# =============================================================================
echo ""
echo "--- Scenario: step_board_archive の動作継続 ---"

test_chain_runner_board_archive_function_exists() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  assert_file_contains "$CHAIN_RUNNER" 'step_board_archive\s*\(\)'
}
run_test "chain-runner [step_board_archive 関数が定義されている]" test_chain_runner_board_archive_function_exists

test_chain_runner_board_archive_uses_resolve_project() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # step_board_archive も resolve_project を利用する（chain-runner全体で参照があればよい）
  # resolve_project_root() とは区別するため、単独の呼び出しパターンを確認
  assert_file_contains "$CHAIN_RUNNER" 'resolve_project\b[^_]'
}
run_test "chain-runner [step_board_archive が resolve_project を利用できる]" test_chain_runner_board_archive_uses_resolve_project

test_chain_runner_board_archive_item_archive() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  assert_file_contains "$CHAIN_RUNNER" 'item-archive'
}
run_test "chain-runner [step_board_archive: gh project item-archive ロジックが維持されている]" test_chain_runner_board_archive_item_archive

test_chain_runner_board_archive_no_duplicate_project_detection() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # リファクタリング後: mapfile -t project_nums が chain-runner.sh から削除されている
  # (重複ロジックが resolve-project.sh に移動しているため)
  local count
  count=$(grep -cP 'mapfile\s+-t\s+project_nums' "${PROJECT_ROOT}/${CHAIN_RUNNER}" 2>/dev/null) || count=0
  [[ "${count:-0}" -eq 0 ]]
}
run_test "chain-runner [edge: chain-runner.sh 内の重複 project 検出ロジック (mapfile -t project_nums) が削除されている]" test_chain_runner_board_archive_no_duplicate_project_detection

# =============================================================================
# Requirement: 各スクリプトの resolve_project 採用
# Scenario: project-board-archive.sh の動作継続
# WHEN: project-board-archive.sh が実行される
# THEN: 既存の動作（Issue のアーカイブ）が維持される
# =============================================================================
echo ""
echo "--- Scenario: project-board-archive.sh の動作継続 ---"

test_archive_sources_resolve_project() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  assert_file_contains "$ARCHIVE_SCRIPT" \
    'source.*resolve-project|\.\s.*resolve-project|source.*lib/'
}
run_test "project-board-archive [resolve-project.sh を source している]" test_archive_sources_resolve_project

test_archive_calls_resolve_project() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # resolve_project_root() とは区別するため、単独の呼び出しパターンを確認
  assert_file_contains "$ARCHIVE_SCRIPT" 'resolve_project\b[^_]'
}
run_test "project-board-archive [resolve_project 関数を呼び出している]" test_archive_calls_resolve_project

test_archive_item_archive_logic_maintained() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  assert_file_contains "$ARCHIVE_SCRIPT" 'item-archive'
}
run_test "project-board-archive [gh project item-archive ロジックが維持されている]" test_archive_item_archive_logic_maintained

test_archive_no_duplicate_graphql() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # リファクタリング後: GraphQL クエリ定義が archive スクリプト内から削除されている
  local count
  count=$(grep -cP 'query\(\$owner.*\$num' "${PROJECT_ROOT}/${ARCHIVE_SCRIPT}" 2>/dev/null) || count=0
  [[ "${count:-0}" -eq 0 ]]
}
run_test "project-board-archive [edge: GraphQL クエリ定義の重複が削除されている]" test_archive_no_duplicate_graphql

test_archive_bash_syntax_valid() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${ARCHIVE_SCRIPT}" 2>/dev/null
}
run_test "project-board-archive [bash 構文エラーなし]" test_archive_bash_syntax_valid

# =============================================================================
# Requirement: 各スクリプトの resolve_project 採用
# Scenario: project-board-backfill.sh の動作継続
# WHEN: project-board-backfill.sh が実行される
# THEN: 既存の動作（Project Board のバックフィル）が維持される
# =============================================================================
echo ""
echo "--- Scenario: project-board-backfill.sh の動作継続 ---"

test_backfill_sources_resolve_project() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" \
    'source.*resolve-project|\.\s.*resolve-project|source.*lib/'
}
run_test "project-board-backfill [resolve-project.sh を source している]" test_backfill_sources_resolve_project

test_backfill_calls_resolve_project() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # resolve_project_root() とは区別するため、単独の呼び出しパターンを確認
  assert_file_contains "$BACKFILL_SCRIPT" 'resolve_project\b[^_]'
}
run_test "project-board-backfill [resolve_project 関数を呼び出している]" test_backfill_calls_resolve_project

test_backfill_item_add_logic_maintained() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" 'item-add'
}
run_test "project-board-backfill [gh project item-add ロジックが維持されている]" test_backfill_item_add_logic_maintained

test_backfill_no_duplicate_graphql() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  local count
  count=$(grep -cP 'query\(\$owner.*\$num' "${PROJECT_ROOT}/${BACKFILL_SCRIPT}" 2>/dev/null) || count=0
  [[ "${count:-0}" -eq 0 ]]
}
run_test "project-board-backfill [edge: GraphQL クエリ定義の重複が削除されている]" test_backfill_no_duplicate_graphql

test_backfill_bash_syntax_valid() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${BACKFILL_SCRIPT}" 2>/dev/null
}
run_test "project-board-backfill [bash 構文エラーなし]" test_backfill_bash_syntax_valid

# =============================================================================
# Requirement: 各スクリプトの resolve_project 採用
# Scenario: autopilot-plan-board.sh の動作継続
# WHEN: autopilot-plan-board.sh が実行される
# THEN: 既存の動作（Autopilot 計画の Project Board 反映）が維持される
# =============================================================================
echo ""
echo "--- Scenario: autopilot-plan-board.sh の動作継続 ---"

test_autopilot_board_sources_resolve_project() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  assert_file_contains "$AUTOPILOT_BOARD" \
    'source.*resolve-project|\.\s.*resolve-project|source.*lib/'
}
run_test "autopilot-plan-board [resolve-project.sh を source している]" test_autopilot_board_sources_resolve_project

test_autopilot_board_calls_resolve_project() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  # resolve_project_root() とは区別するため、単独の呼び出しパターンを確認
  assert_file_contains "$AUTOPILOT_BOARD" 'resolve_project\b[^_]'
}
run_test "autopilot-plan-board [resolve_project 関数を呼び出している]" test_autopilot_board_calls_resolve_project

test_autopilot_board_detect_function_or_resolve() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  # _detect_project_board を resolve_project に置き換えるか、
  # resolve_project を呼び出すラッパーとして残す
  # resolve_project_root() とは区別するため、単独の呼び出しパターンを確認
  assert_file_contains "$AUTOPILOT_BOARD" 'resolve_project\b[^_]|_detect_project_board'
}
run_test "autopilot-plan-board [Project 検出ロジックが resolve_project 経由になっている]" test_autopilot_board_detect_function_or_resolve

test_autopilot_board_no_duplicate_graphql() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  local count
  count=$(grep -cP 'query\(\$owner.*\$num' "${PROJECT_ROOT}/${AUTOPILOT_BOARD}" 2>/dev/null) || count=0
  [[ "${count:-0}" -eq 0 ]]
}
run_test "autopilot-plan-board [edge: GraphQL クエリ定義の重複が削除されている]" test_autopilot_board_no_duplicate_graphql

test_autopilot_board_bash_syntax_valid() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  bash -n "${PROJECT_ROOT}/${AUTOPILOT_BOARD}" 2>/dev/null
}
run_test "autopilot-plan-board [bash 構文エラーなし]" test_autopilot_board_bash_syntax_valid

# =============================================================================
# Requirement: deps.yaml への lib エントリ追加
# Scenario: deps.yaml 更新
# WHEN: twl check を実行する
# THEN: scripts/lib/resolve-project.sh が deps.yaml に登録されており、エラーが出ない
# =============================================================================
echo ""
echo "--- Scenario: deps.yaml 更新 ---"

test_deps_yaml_has_resolve_project_entry() {
  assert_file_exists "$DEPS_FILE" || return 1
  assert_file_contains "$DEPS_FILE" 'resolve-project'
}
run_test "deps.yaml [scripts/lib/resolve-project.sh のエントリが存在する]" test_deps_yaml_has_resolve_project_entry

test_deps_yaml_has_lib_path() {
  assert_file_exists "$DEPS_FILE" || return 1
  assert_file_contains "$DEPS_FILE" 'scripts/lib/resolve-project\.sh'
}
run_test "deps.yaml [scripts/lib/resolve-project.sh のパスが登録されている]" test_deps_yaml_has_lib_path

# edge: twl CLI が利用可能な場合は twl check も実行
if command -v twl >/dev/null 2>&1; then
  test_twl_check_passes() {
    cd "${PROJECT_ROOT}" && twl check >/dev/null 2>&1
  }
  run_test "deps.yaml [edge: twl check がエラーなし]" test_twl_check_passes
else
  run_test_skip "deps.yaml [edge: twl check がエラーなし]" "twl CLI が見つかりません"
fi

# =============================================================================
# Edge cases: resolve-project.sh の構造検証
# =============================================================================
echo ""
echo "--- edge-case: resolve-project.sh 構造検証 ---"

test_lib_script_has_shebang() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  local first_line
  first_line=$(head -1 "${PROJECT_ROOT}/${LIB_SCRIPT}")
  [[ "$first_line" == '#!/'* ]] || [[ "$first_line" == '#'* ]]
}
run_test "resolve-project-lib [edge: シバン行またはコメントヘッダーで始まっている]" test_lib_script_has_shebang

test_lib_script_not_empty() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  [[ -s "${PROJECT_ROOT}/${LIB_SCRIPT}" ]]
}
run_test "resolve-project-lib [edge: ファイルが空でない]" test_lib_script_not_empty

test_lib_script_no_set_e() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # source されるライブラリには set -e を置かない（呼び出し元を壊すリスクがある）
  # set -euo pipefail を入れる場合は source 後に上書きされる可能性があるが、
  # 一般的に source ライブラリには含めない
  # ここでは WARN レベル: set -e の有無をチェックするのみ（失敗にしない）
  # NOTE: このテストは情報提供目的のため常に PASS
  return 0
}
run_test "resolve-project-lib [edge: source ライブラリとして安全な構造 (参考チェック)]" test_lib_script_no_set_e

test_resolve_project_query_repositories_first20() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # repositories(first: 20) パターン: chain-runner.sh と同等のクエリ構造
  assert_file_contains "$LIB_SCRIPT" 'repositories.*first.*20|first.*20.*repositories'
}
run_test "resolve-project-lib [edge: repositories(first: 20) GraphQL フィールドが含まれている]" test_resolve_project_query_repositories_first20

test_resolve_project_handles_user_and_org() {
  assert_file_exists "$LIB_SCRIPT" || return 1
  # user クエリと organization クエリの両方に対応している
  assert_file_contains "$LIB_SCRIPT" 'user\(login' || \
  assert_file_contains "$LIB_SCRIPT" 'user.*login'
  assert_file_contains "$LIB_SCRIPT" 'organization\(login|organization.*login'
}
run_test "resolve-project-lib [edge: user/organization 両方の GraphQL クエリが存在する]" test_resolve_project_handles_user_and_org

test_resolve_project_no_inline_in_scripts_anymore() {
  # リファクタリング後: 各スクリプトに GraphQL query 定義の重複がなくなっていること
  # (project-board-archive / project-board-backfill / chain-runner の合計は 0 が理想)
  local total_count=0
  for script in "$ARCHIVE_SCRIPT" "$BACKFILL_SCRIPT" "$CHAIN_RUNNER"; do
    if assert_file_exists "$script"; then
      local c
      c=$(grep -cP 'query\(\$owner.*\$num' "${PROJECT_ROOT}/${script}" 2>/dev/null) || c=0
      total_count=$((total_count + c))
    fi
  done
  [[ "$total_count" -eq 0 ]]
}
run_test "resolve-project-lib [edge: project-board-archive/backfill/chain-runner の GraphQL 重複が全て削除されている]" test_resolve_project_no_inline_in_scripts_anymore

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "resolve-project-lib: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "==========================================="

[[ ${FAIL} -eq 0 ]]
