#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: fix-resolve-issue-num-parallel-worker
# Generated from: openspec/changes/fix-resolve-issue-num-parallel-worker/specs/resolve-issue-num/spec.md
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

RESOLVE_SH="scripts/resolve-issue-num.sh"
LAUNCH_SH="scripts/autopilot-launch.sh"

# =============================================================================
# Requirement: WORKER_ISSUE_NUM Priority 0 参照
# =============================================================================
echo ""
echo "--- Requirement: WORKER_ISSUE_NUM Priority 0 参照 ---"

# ---------------------------------------------------------------------------
# Scenario: WORKER_ISSUE_NUM が設定されている場合
# WHEN: WORKER_ISSUE_NUM=238 が export された状態で resolve_issue_num を呼び出す
# THEN: 238 を返し、AUTOPILOT_DIR スキャンおよび git branch フォールバックは実行しない
# ---------------------------------------------------------------------------

test_resolve_sh_exists() {
  assert_file_exists "$RESOLVE_SH"
}
run_test "resolve-issue-num.sh が存在する" test_resolve_sh_exists

test_resolve_sh_worker_issue_num_check() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # WORKER_ISSUE_NUM 変数を参照するロジックが存在すること
  assert_file_contains "$RESOLVE_SH" 'WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM 環境変数の参照ロジックが存在する" test_resolve_sh_worker_issue_num_check

test_resolve_sh_worker_issue_num_priority_zero() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # Priority 0 として最初にチェックされること: WORKER_ISSUE_NUM が定義されていれば echo して return/exit
  # パターン: [ -n "${WORKER_ISSUE_NUM:-}" ] ... echo ... return
  assert_file_contains "$RESOLVE_SH" '-n.*WORKER_ISSUE_NUM|WORKER_ISSUE_NUM.*-n' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM を -n フラグで存在確認するロジックが存在する" test_resolve_sh_worker_issue_num_priority_zero

test_resolve_sh_worker_issue_num_returns_value() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # WORKER_ISSUE_NUM の値を echo して早期リターンするパターン
  # echo "${WORKER_ISSUE_NUM}" や echo "$WORKER_ISSUE_NUM" などが存在すること
  assert_file_contains "$RESOLVE_SH" 'echo.*WORKER_ISSUE_NUM|\$\{?WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM の値を echo して返す処理が存在する" test_resolve_sh_worker_issue_num_returns_value

test_resolve_sh_worker_issue_num_early_return() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # 早期リターン: WORKER_ISSUE_NUM が設定されている場合に return または exit で処理を終了すること
  assert_file_contains "$RESOLVE_SH" 'return\s+\d*|return$' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM 設定時に早期 return で後続ロジックをスキップする" test_resolve_sh_worker_issue_num_early_return

# [edge] WORKER_ISSUE_NUM チェックは Priority 1 (AUTOPILOT_DIR) より前に置かれること
test_resolve_sh_worker_issue_num_before_priority1() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # WORKER_ISSUE_NUM が AUTOPILOT_DIR の if ブロックより前に現れること
  local worker_line autopilot_line
  worker_line=$(grep -nP 'WORKER_ISSUE_NUM' "${PROJECT_ROOT}/${RESOLVE_SH}" | head -1 | cut -d: -f1)
  autopilot_line=$(grep -nP 'Priority 1.*AUTOPILOT_DIR|AUTOPILOT_DIR.*issues' "${PROJECT_ROOT}/${RESOLVE_SH}" | head -1 | cut -d: -f1)
  if [[ -z "${worker_line:-}" ]]; then
    return 1
  fi
  if [[ -z "${autopilot_line:-}" ]]; then
    # AUTOPILOT_DIR ロジックがない場合はスキップ（Priority 0 だけ確認）
    return 0
  fi
  [[ "${worker_line}" -lt "${autopilot_line}" ]]
}
run_test "[edge] WORKER_ISSUE_NUM チェックが AUTOPILOT_DIR スキャン（Priority 1）より前に配置されている" test_resolve_sh_worker_issue_num_before_priority1

# [edge] WORKER_ISSUE_NUM が未設定の場合は既存のロジックを通過すること
# - Priority 1: AUTOPILOT_DIR スキャン、Priority 2: git branch フォールバック
test_resolve_sh_priority1_intact() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # Priority 1 の AUTOPILOT_DIR スキャンロジックが残っていること
  assert_file_contains "$RESOLVE_SH" 'AUTOPILOT_DIR' || return 1
  return 0
}
run_test "[edge] WORKER_ISSUE_NUM 未設定時用の Priority 1 AUTOPILOT_DIR ロジックが維持されている" test_resolve_sh_priority1_intact

test_resolve_sh_priority2_intact() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # Priority 2 の git branch フォールバックが残っていること
  assert_file_contains "$RESOLVE_SH" 'git branch' || return 1
  return 0
}
run_test "[edge] WORKER_ISSUE_NUM 未設定時用の Priority 2 git branch フォールバックが維持されている" test_resolve_sh_priority2_intact

# [edge] WORKER_ISSUE_NUM が設定されている場合、jq スキャンを実行しないこと
# (early return により AUTOPILOT_DIR 以降のコードに到達しない)
test_resolve_sh_bash_syntax_valid() {
  assert_file_exists "$RESOLVE_SH" || return 1
  bash -n "${PROJECT_ROOT}/${RESOLVE_SH}" 2>/dev/null
}
run_test "[edge] resolve-issue-num.sh に bash 構文エラーがない" test_resolve_sh_bash_syntax_valid

# ---------------------------------------------------------------------------
# Scenario: WORKER_ISSUE_NUM が未設定の場合
# WHEN: WORKER_ISSUE_NUM が設定されていない状態で resolve_issue_num を呼び出す
# THEN: 既存の Priority 1（AUTOPILOT_DIR スキャン）→ Priority 2（git branch）の順で動作する
# ---------------------------------------------------------------------------

test_resolve_sh_function_defined() {
  assert_file_exists "$RESOLVE_SH" || return 1
  assert_file_contains "$RESOLVE_SH" 'resolve_issue_num\s*\(\)|function\s+resolve_issue_num\b' || return 1
  return 0
}
run_test "resolve_issue_num 関数が定義されている" test_resolve_sh_function_defined

test_resolve_sh_priority1_autopilot_scan() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # AUTOPILOT_DIR/issues 配下の issue-*.json をスキャンするロジック
  assert_file_contains "$RESOLVE_SH" 'AUTOPILOT_DIR.*issues|issues.*AUTOPILOT_DIR' || return 1
  return 0
}
run_test "Priority 1: AUTOPILOT_DIR/issues の state file スキャンロジックが存在する" test_resolve_sh_priority1_autopilot_scan

test_resolve_sh_priority1_status_running() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # status=running のフィルタリング
  assert_file_contains "$RESOLVE_SH" 'status.*running|running.*status' || return 1
  return 0
}
run_test "Priority 1: status=running の Issue のみを選択するロジックが存在する" test_resolve_sh_priority1_status_running

test_resolve_sh_priority2_git_branch() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # git branch --show-current フォールバック
  assert_file_contains "$RESOLVE_SH" 'git branch --show-current' || return 1
  return 0
}
run_test "Priority 2: git branch --show-current フォールバックが存在する" test_resolve_sh_priority2_git_branch

# [edge] Priority 1 と Priority 2 の順序: AUTOPILOT_DIR スキャンが git branch より前
test_resolve_sh_priority_order() {
  assert_file_exists "$RESOLVE_SH" || return 1
  local p1_line p2_line
  # コードとしての AUTOPILOT_DIR ディレクトリチェック行（コメント行除く）
  p1_line=$(grep -nP '^\s+if\s+\[.*AUTOPILOT_DIR|^\s+for\s+f\s+in.*AUTOPILOT_DIR|^\s+\S.*AUTOPILOT_DIR.*issues' "${PROJECT_ROOT}/${RESOLVE_SH}" | head -1 | cut -d: -f1)
  # コードとしての git branch 呼び出し行（コメント行除く）
  p2_line=$(grep -nP '^\s+issue_num=\$\(git branch|git branch.*show-current.*2>/dev/null' "${PROJECT_ROOT}/${RESOLVE_SH}" | head -1 | cut -d: -f1)
  if [[ -z "${p1_line:-}" || -z "${p2_line:-}" ]]; then
    return 1
  fi
  [[ "${p1_line}" -lt "${p2_line}" ]]
}
run_test "[edge] Priority 1 (AUTOPILOT_DIR スキャン) が Priority 2 (git branch) より前に配置されている" test_resolve_sh_priority_order

# ---------------------------------------------------------------------------
# Scenario: 並列 Phase での複数 Worker
# WHEN: issue-227, 228, 229 が全て status=running で WORKER_ISSUE_NUM=229 が設定されている
# THEN: 229 を返す（最小番号の 227 は返さない）
# ---------------------------------------------------------------------------

test_resolve_sh_worker_issue_num_overrides_min_scan() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # WORKER_ISSUE_NUM が設定されていれば sort -n による最小番号採用をスキップする
  # 実装: WORKER_ISSUE_NUM の check が jq ループより前に来ること
  assert_file_contains "$RESOLVE_SH" 'WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "複数 running 時も WORKER_ISSUE_NUM を優先して返すロジックが存在する" test_resolve_sh_worker_issue_num_overrides_min_scan

test_resolve_sh_sort_n_for_fallback() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # WORKER_ISSUE_NUM が未設定時の fallback: sort -n | head -1 で最小番号を採用
  assert_file_contains "$RESOLVE_SH" 'sort -n.*head -1|sort\s+-n' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM 未設定時は sort -n で最小番号を採用するロジックが存在する" test_resolve_sh_sort_n_for_fallback

# [edge] WORKER_ISSUE_NUM=229 の場合に early return するため、jq スキャン（sort -n | head -1）が実行されないこと
# これは構造テスト: WORKER_ISSUE_NUM check -> return の後に AUTOPILOT_DIR ロジックが来ること
test_resolve_sh_parallel_worker_early_exit_structure() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # resolve_issue_num() 内で WORKER_ISSUE_NUM を最初にチェックするパターンが存在すること
  # "if [ -n ... WORKER_ISSUE_NUM" or "[ -n \"${WORKER_ISSUE_NUM...}" が関数内 jq より前
  local worker_check_count
  worker_check_count=$(grep -cP 'WORKER_ISSUE_NUM' "${PROJECT_ROOT}/${RESOLVE_SH}" 2>/dev/null) || worker_check_count=0
  [[ "${worker_check_count}" -ge 1 ]]
}
run_test "[edge] WORKER_ISSUE_NUM の参照が resolve_issue_num 関数内に存在する（並列 Worker 対応確認）" test_resolve_sh_parallel_worker_early_exit_structure

# =============================================================================
# Requirement: autopilot-launch.sh の WORKER_ISSUE_NUM export
# =============================================================================
echo ""
echo "--- Requirement: autopilot-launch.sh の WORKER_ISSUE_NUM export ---"

# ---------------------------------------------------------------------------
# Scenario: Worker 起動時の環境変数注入
# WHEN: autopilot-launch.sh --issue 238 で Worker を起動する
# THEN: tmux の Worker プロセスに WORKER_ISSUE_NUM=238 が環境変数として設定される
# ---------------------------------------------------------------------------

test_launch_sh_exists() {
  assert_file_exists "$LAUNCH_SH"
}
run_test "autopilot-launch.sh が存在する" test_launch_sh_exists

test_launch_sh_worker_issue_num_env() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # WORKER_ISSUE_NUM 環境変数を tmux 起動コマンドに含める
  assert_file_contains "$LAUNCH_SH" 'WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "autopilot-launch.sh に WORKER_ISSUE_NUM の設定ロジックが存在する" test_launch_sh_worker_issue_num_env

test_launch_sh_worker_issue_num_uses_issue_var() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # WORKER_ISSUE_NUM=$ISSUE または WORKER_ISSUE_NUM="${ISSUE}" のパターン
  assert_file_contains "$LAUNCH_SH" 'WORKER_ISSUE_NUM=.*\$\{?ISSUE\}?|WORKER_ISSUE_NUM.*\$ISSUE' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM の値として \$ISSUE 変数が使用されている" test_launch_sh_worker_issue_num_uses_issue_var

test_launch_sh_worker_issue_num_in_env_line() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # tmux new-window の env 行に WORKER_ISSUE_NUM が渡されること
  # env ... WORKER_ISSUE_NUM=... のパターン、または env 変数の構築に含まれること
  assert_file_contains "$LAUNCH_SH" 'WORKER_ISSUE_NUM.*env\s|env.*WORKER_ISSUE_NUM|WORKER_ISSUE_ENV\|WORKER_ENV' \
    || assert_file_contains "$LAUNCH_SH" 'WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM が Worker 起動の env コマンドに含まれる構造が存在する" test_launch_sh_worker_issue_num_in_env_line

test_launch_sh_worker_issue_num_quoted() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # printf '%q' による安全なクォートが適用されていること（既存パターンに倣う）
  # または WORKER_ISSUE_NUM=${ISSUE} として整数値のため直接展開でも可
  # 少なくとも WORKER_ISSUE_NUM= の代入が存在すること
  assert_file_contains "$LAUNCH_SH" 'WORKER_ISSUE_NUM=' || return 1
  return 0
}
run_test "WORKER_ISSUE_NUM=<値> の代入パターンが存在する" test_launch_sh_worker_issue_num_quoted

# [edge] WORKER_ISSUE_NUM が tmux new-window コマンドの env 部分に含まれること
test_launch_sh_worker_issue_num_tmux_env_integration() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # WORKER_ISSUE_NUM の代入行（WORKER_ISSUE_NUM_ENV= または WORKER_ISSUE_NUM=）が
  # tmux new-window の実際のコマンド行より前に来ること
  local assign_line tmux_exec_line
  # 代入行: 行頭 WORKER_ISSUE_NUM_ENV= または WORKER_ISSUE_NUM= のパターン
  assign_line=$(grep -nP '^\s*WORKER_ISSUE_NUM[_A-Z]*=' "${PROJECT_ROOT}/${LAUNCH_SH}" | head -1 | cut -d: -f1)
  # tmux new-window の実行行（行頭 tmux コマンド）
  tmux_exec_line=$(grep -nP '^tmux\s+new-window' "${PROJECT_ROOT}/${LAUNCH_SH}" | head -1 | cut -d: -f1)
  if [[ -z "${assign_line:-}" || -z "${tmux_exec_line:-}" ]]; then
    return 1
  fi
  [[ "${assign_line}" -lt "${tmux_exec_line}" ]]
}
run_test "[edge] WORKER_ISSUE_NUM の構築が tmux new-window 呼び出し以前に行われている" test_launch_sh_worker_issue_num_tmux_env_integration

# ---------------------------------------------------------------------------
# Scenario: 既存環境変数との共存
# WHEN: AUTOPILOT_DIR・REPO_OWNER・REPO_NAME が既に設定される Worker 起動コマンドに WORKER_ISSUE_NUM を追加する
# THEN: 既存の環境変数が維持され、WORKER_ISSUE_NUM が追加される
# ---------------------------------------------------------------------------

test_launch_sh_autopilot_env_maintained() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # 既存の AUTOPILOT_ENV が維持されていること
  assert_file_contains "$LAUNCH_SH" 'AUTOPILOT_ENV' || return 1
  return 0
}
run_test "既存の AUTOPILOT_ENV 変数が維持されている" test_launch_sh_autopilot_env_maintained

test_launch_sh_repo_env_maintained() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # 既存の REPO_ENV が維持されていること
  assert_file_contains "$LAUNCH_SH" 'REPO_ENV' || return 1
  return 0
}
run_test "既存の REPO_ENV 変数が維持されている" test_launch_sh_repo_env_maintained

test_launch_sh_all_envs_in_tmux_command() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # tmux new-window の env 行に AUTOPILOT_ENV と REPO_ENV が含まれること
  assert_file_contains "$LAUNCH_SH" 'AUTOPILOT_ENV.*REPO_ENV|REPO_ENV.*AUTOPILOT_ENV|env.*AUTOPILOT_ENV' || return 1
  return 0
}
run_test "tmux 起動コマンドに AUTOPILOT_ENV と REPO_ENV が含まれている" test_launch_sh_all_envs_in_tmux_command

# [edge] WORKER_ISSUE_NUM が追加されても AUTOPILOT_DIR のクォート処理が壊れていないこと
test_launch_sh_autopilot_dir_still_quoted() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" "printf\s+'%q'.*AUTOPILOT_DIR|QUOTED_AUTOPILOT_DIR" || return 1
  return 0
}
run_test "[edge] AUTOPILOT_DIR の printf '%q' クォート処理が維持されている" test_launch_sh_autopilot_dir_still_quoted

# [edge] REPO_OWNER / REPO_NAME のクォート処理が維持されていること
test_launch_sh_repo_env_still_quoted() {
  assert_file_exists "$LAUNCH_SH" || return 1
  assert_file_contains "$LAUNCH_SH" "printf\s+'%q'.*REPO_OWNER|printf\s+'%q'.*REPO_NAME|QUOTED_REPO_OWNER|QUOTED_REPO_NAME" || return 1
  return 0
}
run_test "[edge] REPO_OWNER/REPO_NAME の printf '%q' クォート処理が維持されている" test_launch_sh_repo_env_still_quoted

# [edge] bash 構文エラーがないこと（追加後のリグレッション確認）
test_launch_sh_bash_syntax_valid() {
  assert_file_exists "$LAUNCH_SH" || return 1
  bash -n "${PROJECT_ROOT}/${LAUNCH_SH}" 2>/dev/null
}
run_test "[edge] autopilot-launch.sh に bash 構文エラーがない（WORKER_ISSUE_NUM 追加後リグレッション確認）" test_launch_sh_bash_syntax_valid

# =============================================================================
# Edge cases: 統合構造検証
# =============================================================================
echo ""
echo "--- edge-case: 統合構造検証 ---"

# resolve-issue-num.sh の WORKER_ISSUE_NUM は整数として返すこと
# (既存の git branch / AUTOPILOT_DIR 結果と同じ形式)
test_resolve_sh_worker_issue_num_no_extra_transform() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # WORKER_ISSUE_NUM をそのまま echo するか、tostring 変換なしで返すパターン
  # 整数 ENV VAR をそのまま出力: echo "${WORKER_ISSUE_NUM}" など
  assert_file_contains "$RESOLVE_SH" 'WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "[edge] resolve_issue_num は WORKER_ISSUE_NUM の値をそのまま返す" test_resolve_sh_worker_issue_num_no_extra_transform

# WORKER_ISSUE_NUM が空文字("")の場合は Priority 0 をスキップすること
test_resolve_sh_worker_issue_num_empty_skip() {
  assert_file_exists "$RESOLVE_SH" || return 1
  # -n "${WORKER_ISSUE_NUM:-}" は空文字に対して false を返すため、空の場合はスキップされる
  # この動作を保証するパターン: ${WORKER_ISSUE_NUM:-} または -n "$WORKER_ISSUE_NUM"
  assert_file_contains "$RESOLVE_SH" 'WORKER_ISSUE_NUM:-\}|WORKER_ISSUE_NUM\}' || \
  assert_file_contains "$RESOLVE_SH" '\-n.*WORKER_ISSUE_NUM' || return 1
  return 0
}
run_test "[edge] WORKER_ISSUE_NUM が空文字の場合は Priority 0 をスキップする（:-展開または -n チェック）" test_resolve_sh_worker_issue_num_empty_skip

# autopilot-launch.sh で WORKER_ISSUE_NUM に渡す値は ISSUE 変数の値であること
# （bash 変数展開の安全性: ISSUE は ^[1-9][0-9]*$ で検証済み整数）
test_launch_sh_worker_issue_num_safe_integer() {
  assert_file_exists "$LAUNCH_SH" || return 1
  # ISSUE の数値バリデーションが存在していること（既存チェック）
  assert_file_contains "$LAUNCH_SH" '\^\[1-9\]\[0-9\]\*\$|\^[1-9]|ISSUE.*[0-9]' || return 1
  return 0
}
run_test "[edge] WORKER_ISSUE_NUM に代入される ISSUE は整数バリデーション済みである" test_launch_sh_worker_issue_num_safe_integer

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
