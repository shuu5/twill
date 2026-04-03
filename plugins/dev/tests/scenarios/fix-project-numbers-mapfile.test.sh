#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: fix-project-numbers-mapfile
# Generated from: openspec/changes/fix-project-numbers-mapfile/specs/mapfile-pattern/spec.md
# Coverage level: edge-cases
# Requirement: PROJECT_NUMBERS の mapfile パターン統一 + shellcheck 準拠
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

ARCHIVE_SCRIPT="scripts/project-board-archive.sh"
BACKFILL_SCRIPT="scripts/project-board-backfill.sh"
CHAIN_RUNNER="scripts/chain-runner.sh"
AUTOPILOT_BOARD="scripts/autopilot-plan-board.sh"

# =============================================================================
# Requirement: PROJECT_NUMBERS の mapfile パターン統一
# Scenario: project-board-archive.sh のイテレーション
# WHEN: project-board-archive.sh がプロジェクト番号リストを取得してループする
# THEN: mapfile -t PROJECT_NUMS < <(...) で配列に格納し "${PROJECT_NUMS[@]}" でイテレーションすること
# =============================================================================
echo ""
echo "--- Scenario: project-board-archive.sh のイテレーション ---"

test_archive_uses_mapfile() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # mapfile -t で配列格納
  assert_file_contains "$ARCHIVE_SCRIPT" 'mapfile\s+-t\s+PROJECT_NUMS' || return 1
}
run_test "archive [mapfile -t PROJECT_NUMS が使われている]" test_archive_uses_mapfile

test_archive_uses_process_substitution() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # process substitution < <(...) で jq 出力を読み込む
  assert_file_contains "$ARCHIVE_SCRIPT" 'mapfile\s+-t\s+PROJECT_NUMS\s+<\s+<\(' || return 1
}
run_test "archive [mapfile で process substitution < <(...) を使っている]" test_archive_uses_process_substitution

test_archive_iterates_with_quoted_array() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # "${PROJECT_NUMS[@]}" でイテレーション
  assert_file_contains "$ARCHIVE_SCRIPT" '"\$\{PROJECT_NUMS\[@\]\}"' || return 1
}
run_test 'archive ["${PROJECT_NUMS[@]}" でイテレーションしている]' test_archive_iterates_with_quoted_array

test_archive_no_unquoted_wordsplit() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # for X in $VAR (unquoted variable) パターンが PROJECT_NUMBERS に対して使われていない
  # "for PROJECT_NUM in $PROJECT_NUMBERS" 形式が存在しないことを確認
  assert_file_not_contains "$ARCHIVE_SCRIPT" 'for\s+PROJECT_NUM\s+in\s+\$PROJECT_NUMBERS\b' || return 1
}
run_test "archive [edge: unquoted word-split パターン for X in \$VAR が除去されている]" test_archive_no_unquoted_wordsplit

test_archive_bash_syntax_valid() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${ARCHIVE_SCRIPT}" 2>/dev/null
}
run_test "archive [bash 構文エラーなし]" test_archive_bash_syntax_valid

# =============================================================================
# Requirement: PROJECT_NUMBERS の mapfile パターン統一
# Scenario: project-board-backfill.sh のイテレーション
# WHEN: project-board-backfill.sh がプロジェクト番号リストを取得してループする
# THEN: mapfile -t PROJECT_NUMS < <(...) で配列に格納し "${PROJECT_NUMS[@]}" でイテレーションすること
# =============================================================================
echo ""
echo "--- Scenario: project-board-backfill.sh のイテレーション ---"

test_backfill_uses_mapfile() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" 'mapfile\s+-t\s+PROJECT_NUMS' || return 1
}
run_test "backfill [mapfile -t PROJECT_NUMS が使われている]" test_backfill_uses_mapfile

test_backfill_uses_process_substitution() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" 'mapfile\s+-t\s+PROJECT_NUMS\s+<\s+<\(' || return 1
}
run_test "backfill [mapfile で process substitution < <(...) を使っている]" test_backfill_uses_process_substitution

test_backfill_iterates_with_quoted_array() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  assert_file_contains "$BACKFILL_SCRIPT" '"\$\{PROJECT_NUMS\[@\]\}"' || return 1
}
run_test 'backfill ["${PROJECT_NUMS[@]}" でイテレーションしている]' test_backfill_iterates_with_quoted_array

test_backfill_no_unquoted_wordsplit() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  # "for PROJECT_NUM in $PROJECT_NUMBERS" 形式が存在しない
  assert_file_not_contains "$BACKFILL_SCRIPT" 'for\s+PROJECT_NUM\s+in\s+\$PROJECT_NUMBERS\b' || return 1
}
run_test "backfill [edge: unquoted word-split パターン for X in \$VAR が除去されている]" test_backfill_no_unquoted_wordsplit

test_backfill_bash_syntax_valid() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${BACKFILL_SCRIPT}" 2>/dev/null
}
run_test "backfill [bash 構文エラーなし]" test_backfill_bash_syntax_valid

# =============================================================================
# Requirement: PROJECT_NUMBERS の mapfile パターン統一
# Scenario: chain-runner.sh の2箇所のイテレーション
# WHEN: chain-runner.sh 内の board-status-update および関連処理でプロジェクト番号リストをループする
# THEN: 各箇所で mapfile -t project_nums < <(...) で配列に格納し "${project_nums[@]}" でイテレーションすること
# =============================================================================
echo ""
echo "--- Scenario: chain-runner.sh の2箇所のイテレーション ---"

test_chain_runner_uses_mapfile() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  assert_file_contains "$CHAIN_RUNNER" 'mapfile\s+-t\s+project_nums' || return 1
}
run_test "chain-runner [mapfile -t project_nums が使われている]" test_chain_runner_uses_mapfile

test_chain_runner_uses_process_substitution() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  assert_file_contains "$CHAIN_RUNNER" 'mapfile\s+-t\s+project_nums\s+<\s+<\(' || return 1
}
run_test "chain-runner [mapfile で process substitution < <(...) を使っている]" test_chain_runner_uses_process_substitution

test_chain_runner_iterates_with_quoted_array() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  assert_file_contains "$CHAIN_RUNNER" '"\$\{project_nums\[@\]\}"' || return 1
}
run_test 'chain-runner ["${project_nums[@]}" でイテレーションしている]' test_chain_runner_iterates_with_quoted_array

test_chain_runner_has_two_mapfile_locations() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # spec: 2箇所で使われている (board-status-update と board-archive の両方)
  local count
  count=$(grep -cP 'mapfile\s+-t\s+project_nums' "${PROJECT_ROOT}/${CHAIN_RUNNER}" 2>/dev/null) || count=0
  [[ "${count:-0}" -ge 2 ]]
}
run_test "chain-runner [edge: mapfile パターンが2箇所以上存在する]" test_chain_runner_has_two_mapfile_locations

test_chain_runner_board_status_update_no_wordsplit() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # step_board_status_update 関数内でも word-split が除去されている
  # "for pnum in $project_numbers" 形式が存在しない
  assert_file_not_contains "$CHAIN_RUNNER" 'for\s+pnum\s+in\s+\$project_numbers\b' || return 1
}
run_test "chain-runner [edge: step_board_status_update の word-split が除去されている]" test_chain_runner_board_status_update_no_wordsplit

test_chain_runner_board_archive_no_wordsplit() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  # step_board_archive 関数内でも word-split が除去されている
  # project_numbers=$(echo ...) のあと for pnum in $project_numbers 形式が存在しない
  # grep で行数を確認: step_board_archive 関数ブロック内のパターン
  assert_file_not_contains "$CHAIN_RUNNER" 'for\s+pnum\s+in\s+\$project_numbers\b' || return 1
}
run_test "chain-runner [edge: step_board_archive の word-split が除去されている]" test_chain_runner_board_archive_no_wordsplit

test_chain_runner_bash_syntax_valid() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  bash -n "${PROJECT_ROOT}/${CHAIN_RUNNER}" 2>/dev/null
}
run_test "chain-runner [bash 構文エラーなし]" test_chain_runner_bash_syntax_valid

# =============================================================================
# Requirement: PROJECT_NUMBERS の mapfile パターン統一
# Scenario: autopilot-plan-board.sh のイテレーション（バリデーション維持）
# WHEN: autopilot-plan-board.sh がプロジェクト番号リストを取得してループする
# THEN: mapfile -t project_nums < <(...) で配列に格納し "${project_nums[@]}" でイテレーションすること、
#       かつ数値バリデーションガード [[ ! "$pnum" =~ ^[0-9]+$ ]] && continue を維持すること
# =============================================================================
echo ""
echo "--- Scenario: autopilot-plan-board.sh のイテレーション（バリデーション維持） ---"

test_autopilot_board_uses_mapfile() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  assert_file_contains "$AUTOPILOT_BOARD" 'mapfile\s+-t\s+project_nums' || return 1
}
run_test "autopilot-plan-board [mapfile -t project_nums が使われている]" test_autopilot_board_uses_mapfile

test_autopilot_board_uses_process_substitution() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  assert_file_contains "$AUTOPILOT_BOARD" 'mapfile\s+-t\s+project_nums\s+<\s+<\(' || return 1
}
run_test "autopilot-plan-board [mapfile で process substitution < <(...) を使っている]" test_autopilot_board_uses_process_substitution

test_autopilot_board_iterates_with_quoted_array() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  assert_file_contains "$AUTOPILOT_BOARD" '"\$\{project_nums\[@\]\}"' || return 1
}
run_test 'autopilot-plan-board ["${project_nums[@]}" でイテレーションしている]' test_autopilot_board_iterates_with_quoted_array

test_autopilot_board_no_unquoted_wordsplit() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  # "for pnum in $project_numbers" 形式が存在しない
  assert_file_not_contains "$AUTOPILOT_BOARD" 'for\s+pnum\s+in\s+\$project_numbers\b' || return 1
}
run_test "autopilot-plan-board [edge: unquoted word-split パターン for X in \$VAR が除去されている]" test_autopilot_board_no_unquoted_wordsplit

test_autopilot_board_numeric_validation_guard_present() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  # 数値バリデーションガード: [[ ! "$pnum" =~ ^[0-9]+$ ]] && continue が維持されている
  assert_file_contains "$AUTOPILOT_BOARD" '!\s+"\$pnum"\s+=~\s+\^\[0-9\]\+\$' || return 1
}
run_test "autopilot-plan-board [edge: 数値バリデーションガードが維持されている]" test_autopilot_board_numeric_validation_guard_present

test_autopilot_board_numeric_guard_continues() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  # バリデーション失敗時に continue でスキップするガードパターン
  # [[ ! "$pnum" =~ ^[0-9]+$ ]] && continue のいずれかの形式
  assert_file_contains "$AUTOPILOT_BOARD" '\[0-9\]' || return 1
  assert_file_contains "$AUTOPILOT_BOARD" 'continue' || return 1
}
run_test "autopilot-plan-board [edge: バリデーション失敗時に continue でスキップする]" test_autopilot_board_numeric_guard_continues

test_autopilot_board_bash_syntax_valid() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  bash -n "${PROJECT_ROOT}/${AUTOPILOT_BOARD}" 2>/dev/null
}
run_test "autopilot-plan-board [bash 構文エラーなし]" test_autopilot_board_bash_syntax_valid

# =============================================================================
# Requirement: shellcheck 準拠
# Scenario: shellcheck 検証
# WHEN: 修正後の4スクリプトに対して shellcheck を実行する
# THEN: SC2206 / SC2207 / SC2086 等の word-split 関連 WARNING がゼロであること
# =============================================================================
echo ""
echo "--- Scenario: shellcheck 検証 (word-split 関連 WARNING がゼロ) ---"

# shellcheck が使用可能かチェックし、なければスキップ
SHELLCHECK_AVAILABLE=false
if command -v shellcheck >/dev/null 2>&1; then
  SHELLCHECK_AVAILABLE=true
fi

_run_shellcheck_wordsplit() {
  local script="$1"
  # SC2206: 配列をスペース区切りで代入 (mapfile 未使用)
  # SC2207: mapfile/read -a の使用推奨
  # SC2086: double-quote 欠落によるワード分割
  shellcheck --severity=warning --exclude=SC1090,SC1091 "${PROJECT_ROOT}/${script}" 2>&1 \
    | grep -P 'SC2206|SC2207|SC2086' && return 1 || return 0
}

if $SHELLCHECK_AVAILABLE; then
  test_shellcheck_archive() { _run_shellcheck_wordsplit "$ARCHIVE_SCRIPT"; }
  run_test "shellcheck [archive: word-split WARNING (SC2086/SC2206/SC2207) ゼロ]" test_shellcheck_archive

  test_shellcheck_backfill() { _run_shellcheck_wordsplit "$BACKFILL_SCRIPT"; }
  run_test "shellcheck [backfill: word-split WARNING (SC2086/SC2206/SC2207) ゼロ]" test_shellcheck_backfill

  test_shellcheck_chain_runner() { _run_shellcheck_wordsplit "$CHAIN_RUNNER"; }
  run_test "shellcheck [chain-runner: word-split WARNING (SC2086/SC2206/SC2207) ゼロ]" test_shellcheck_chain_runner

  test_shellcheck_autopilot_board() { _run_shellcheck_wordsplit "$AUTOPILOT_BOARD"; }
  run_test "shellcheck [autopilot-plan-board: word-split WARNING (SC2086/SC2206/SC2207) ゼロ]" test_shellcheck_autopilot_board
else
  run_test_skip "shellcheck [archive: word-split WARNING ゼロ]" "shellcheck がインストールされていない"
  run_test_skip "shellcheck [backfill: word-split WARNING ゼロ]" "shellcheck がインストールされていない"
  run_test_skip "shellcheck [chain-runner: word-split WARNING ゼロ]" "shellcheck がインストールされていない"
  run_test_skip "shellcheck [autopilot-plan-board: word-split WARNING ゼロ]" "shellcheck がインストールされていない"
fi

# --- edge: 旧パターン PROJECT_NUMBERS=$(jq ...) のみで for X in $VAR を使う箇所がゼロ ---
echo ""
echo "--- edge-case: 旧 word-split パターン全スクリプト残存チェック ---"

test_no_wordsplit_archive_comprehensive() {
  assert_file_exists "$ARCHIVE_SCRIPT" || return 1
  # "for X in $(command)" 形式もNGパターンとして検出
  # PROJECT_NUMBERS を unquoted for ループで使うパターンがない
  local hits
  hits=$(grep -cP 'for\s+\w+\s+in\s+\$PROJECT_NUMBERS\b' "${PROJECT_ROOT}/${ARCHIVE_SCRIPT}" 2>/dev/null) || hits=0
  [[ "${hits:-0}" -eq 0 ]]
}
run_test "archive [edge: \$PROJECT_NUMBERS を直接 for ループに渡す箇所がゼロ]" test_no_wordsplit_archive_comprehensive

test_no_wordsplit_backfill_comprehensive() {
  assert_file_exists "$BACKFILL_SCRIPT" || return 1
  local hits
  hits=$(grep -cP 'for\s+\w+\s+in\s+\$PROJECT_NUMBERS\b' "${PROJECT_ROOT}/${BACKFILL_SCRIPT}" 2>/dev/null) || hits=0
  [[ "${hits:-0}" -eq 0 ]]
}
run_test "backfill [edge: \$PROJECT_NUMBERS を直接 for ループに渡す箇所がゼロ]" test_no_wordsplit_backfill_comprehensive

test_no_wordsplit_chain_runner_comprehensive() {
  assert_file_exists "$CHAIN_RUNNER" || return 1
  local hits
  hits=$(grep -cP 'for\s+\w+\s+in\s+\$project_numbers\b' "${PROJECT_ROOT}/${CHAIN_RUNNER}" 2>/dev/null) || hits=0
  [[ "${hits:-0}" -eq 0 ]]
}
run_test "chain-runner [edge: \$project_numbers を直接 for ループに渡す箇所がゼロ]" test_no_wordsplit_chain_runner_comprehensive

test_no_wordsplit_autopilot_board_comprehensive() {
  assert_file_exists "$AUTOPILOT_BOARD" || return 1
  local hits
  hits=$(grep -cP 'for\s+\w+\s+in\s+\$project_numbers\b' "${PROJECT_ROOT}/${AUTOPILOT_BOARD}" 2>/dev/null) || hits=0
  [[ "${hits:-0}" -eq 0 ]]
}
run_test "autopilot-plan-board [edge: \$project_numbers を直接 for ループに渡す箇所がゼロ]" test_no_wordsplit_autopilot_board_comprehensive

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "fix-project-numbers-mapfile: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "==========================================="

[[ ${FAIL} -eq 0 ]]
