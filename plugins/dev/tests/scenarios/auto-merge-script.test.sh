#!/usr/bin/env bash
# =============================================================================
# Unit Tests: scripts/auto-merge.sh（4 Layer ガード + squash merge）
# Generated from: openspec/changes/auto-merge-script/specs/auto-merge-sh.md
# Coverage level: edge-cases (happy path + edge cases)
#
# Strategy:
#   1. Structural tests: auto-merge.sh が存在し、必要なガードを含む
#   2. Functional tests: 各 Layer を isolated subshell でテスト
#   3. 引数バリデーションテスト
# =============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

PASS=0
FAIL=0
SKIP=0
ERRORS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

run_test() {
  local name="$1"
  local func="$2"
  local result=0
  "$func" || result=$?
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

assert_file_exists() {
  local file="$1"
  [[ -f "${PROJECT_ROOT}/${file}" ]]
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

TARGET_SCRIPT="scripts/auto-merge.sh"

# =============================================================================
# Requirement: auto-merge.sh 引数解析
# =============================================================================
echo ""
echo "--- Requirement: auto-merge.sh 引数解析 ---"

test_script_exists() {
  assert_file_exists "$TARGET_SCRIPT"
}
run_test "auto-merge.sh が存在する" test_script_exists

test_script_executable() {
  [[ -x "${PROJECT_ROOT}/${TARGET_SCRIPT}" ]]
}
run_test "auto-merge.sh が実行可能権限を持つ" test_script_executable

test_missing_args_exit_nonzero() {
  # 引数なしで実行 → exit 1
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "引数なし → 非ゼロ終了" test_missing_args_exit_nonzero

test_missing_issue_exit_nonzero() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --pr 1 --branch feat/test 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "--issue 未指定 → 非ゼロ終了" test_missing_issue_exit_nonzero

test_missing_pr_exit_nonzero() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --issue 1 --branch feat/test 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "--pr 未指定 → 非ゼロ終了" test_missing_pr_exit_nonzero

test_missing_branch_exit_nonzero() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --issue 1 --pr 1 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "--branch 未指定 → 非ゼロ終了" test_missing_branch_exit_nonzero

test_invalid_issue_num() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --issue abc --pr 1 --branch feat/test 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "--issue に非数値 → 非ゼロ終了" test_invalid_issue_num

test_invalid_pr_num() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --issue 1 --pr abc --branch feat/test 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "--pr に非数値 → 非ゼロ終了" test_invalid_pr_num

test_invalid_branch_name() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --issue 1 --pr 1 --branch 'feat test spaces' 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "--branch に不正文字（スペース）→ 非ゼロ終了" test_invalid_branch_name

test_help_flag() {
  local output
  output=$(bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --help 2>&1)
  echo "$output" | grep -qi "usage"
}
run_test "--help で usage を表示" test_help_flag

test_unknown_arg() {
  bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --unknown 2>/dev/null
  [[ $? -ne 0 ]]
}
run_test "不明な引数 → 非ゼロ終了" test_unknown_arg

# =============================================================================
# Requirement: Layer 2 CWD ガード
# =============================================================================
echo ""
echo "--- Requirement: Layer 2 CWD ガード ---"

test_layer2_structural() {
  assert_file_contains "$TARGET_SCRIPT" 'worktrees/'
}
run_test "auto-merge.sh に worktrees/ CWD ガードが含まれる" test_layer2_structural

test_layer2_cwd_guard() {
  # worktrees/ 配下で実行 → exit 1
  local tmpdir
  tmpdir=$(mktemp -d)
  mkdir -p "${tmpdir}/project/worktrees/feat-test"

  local output rc
  output=$(cd "${tmpdir}/project/worktrees/feat-test" && bash "${PROJECT_ROOT}/${TARGET_SCRIPT}" --issue 1 --pr 1 --branch feat/test 2>&1)
  rc=$?

  rm -rf "${tmpdir}"
  # CWD contains "worktrees/" → should fail with exit 1
  [[ $rc -ne 0 ]]
}
run_test "worktrees/ 配下 CWD → エラー終了" test_layer2_cwd_guard

# =============================================================================
# Requirement: Layer 3 tmux window ガード
# =============================================================================
echo ""
echo "--- Requirement: Layer 3 tmux window ガード ---"

test_layer3_structural() {
  assert_file_contains "$TARGET_SCRIPT" 'ap-#\[0-9\]'
}
run_test "auto-merge.sh に ap-#N tmux ガードが含まれる" test_layer3_structural

# Note: tmux window name テストは実環境依存のため、構造テストのみ
# 実際の tmux ガードは integration test で検証

# =============================================================================
# Requirement: Layer 1 IS_AUTOPILOT 判定
# =============================================================================
echo ""
echo "--- Requirement: Layer 1 IS_AUTOPILOT 判定 ---"

test_layer1_structural() {
  assert_file_contains "$TARGET_SCRIPT" 'state-read\.sh.*--type issue.*--field status'
}
run_test "auto-merge.sh が state-read.sh で status を読み取る" test_layer1_structural

test_layer1_merge_ready_transition() {
  assert_file_contains "$TARGET_SCRIPT" 'state-write\.sh.*merge-ready'
}
run_test "auto-merge.sh が IS_AUTOPILOT=true 時に merge-ready 遷移する" test_layer1_merge_ready_transition

# =============================================================================
# Requirement: Layer 4 フォールバックガード
# =============================================================================
echo ""
echo "--- Requirement: Layer 4 フォールバックガード ---"

test_layer4_structural_file_check() {
  assert_file_contains "$TARGET_SCRIPT" 'issue-\$\{?ISSUE_NUM\}?\.json'
}
run_test "auto-merge.sh に issue-{N}.json 直接ファイル確認がある" test_layer4_structural_file_check

test_layer4_structural_main_worktree() {
  assert_file_contains "$TARGET_SCRIPT" 'git worktree list'
}
run_test "auto-merge.sh が git worktree list で main worktree を特定する" test_layer4_structural_main_worktree

test_layer4_structural_autopilot_dir() {
  assert_file_contains "$TARGET_SCRIPT" '\.autopilot'
}
run_test "auto-merge.sh が .autopilot ディレクトリを参照する" test_layer4_structural_autopilot_dir

# =============================================================================
# Requirement: 非 autopilot 時の squash merge
# =============================================================================
echo ""
echo "--- Requirement: 非 autopilot 時の squash merge ---"

test_squash_merge_structural() {
  assert_file_contains "$TARGET_SCRIPT" 'gh pr merge.*--squash'
}
run_test "auto-merge.sh に gh pr merge --squash が含まれる" test_squash_merge_structural

test_no_auto_rebase() {
  # rebase を自動実行しないこと
  if assert_file_contains "$TARGET_SCRIPT" 'git rebase'; then
    return 1  # rebase があったら FAIL
  fi
  return 0
}
run_test "auto-merge.sh に自動 rebase がない" test_no_auto_rebase

test_worktree_cleanup() {
  assert_file_contains "$TARGET_SCRIPT" 'git worktree remove'
}
run_test "auto-merge.sh に worktree 削除が含まれる" test_worktree_cleanup

test_openspec_archive() {
  assert_file_contains "$TARGET_SCRIPT" 'deltaspec archive'
}
run_test "auto-merge.sh に OpenSpec archive が含まれる" test_openspec_archive

# =============================================================================
# Requirement: auto-merge.md 簡素化
# =============================================================================
echo ""
echo "--- Requirement: auto-merge.md 簡素化 ---"

test_auto_merge_md_calls_script() {
  assert_file_contains "commands/auto-merge.md" 'auto-merge\.sh'
}
run_test "auto-merge.md が auto-merge.sh を呼び出す" test_auto_merge_md_calls_script

test_auto_merge_md_no_direct_gh_pr_merge() {
  # auto-merge.md のコードブロック内に直接 gh pr merge がないこと
  # 説明テキストでの言及は許容（バッククォート内等）
  local in_code=false
  local found=false
  while IFS= read -r line; do
    if [[ "$line" == '```'* ]]; then
      if [[ "$in_code" == true ]]; then in_code=false; else in_code=true; fi
      continue
    fi
    if [[ "$in_code" == true ]] && echo "$line" | grep -qP '^(?!#)\s*gh pr merge'; then
      found=true
      break
    fi
  done < "${PROJECT_ROOT}/commands/auto-merge.md"
  # auto-merge.sh の呼び出しのみがコードブロックに含まれるべき
  [[ "$found" == false ]]
}
run_test "auto-merge.md のコードブロックに直接の gh pr merge がない" test_auto_merge_md_no_direct_gh_pr_merge

test_auto_merge_md_no_direct_state_read() {
  # auto-merge.md のコードブロック内に直接 state-read.sh がないこと
  local in_code=false
  local found=false
  while IFS= read -r line; do
    if [[ "$line" == '```'* ]]; then
      if [[ "$in_code" == true ]]; then in_code=false; else in_code=true; fi
      continue
    fi
    if [[ "$in_code" == true ]] && echo "$line" | grep -qP 'state-read\.sh'; then
      found=true
      break
    fi
  done < "${PROJECT_ROOT}/commands/auto-merge.md"
  [[ "$found" == false ]]
}
run_test "auto-merge.md のコードブロックに直接の state-read.sh がない" test_auto_merge_md_no_direct_state_read

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "==========================================="
echo "Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "==========================================="

if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo ""
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi

exit $FAIL
