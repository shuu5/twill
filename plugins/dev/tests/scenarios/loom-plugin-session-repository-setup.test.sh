#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: repository-setup.md
# Generated from: openspec/changes/97-loom-plugin-session/specs/repository-setup.md
# Coverage level: edge-cases
# =============================================================================
set -uo pipefail

# Target repo root (loom-plugin-session)
PROJECT_ROOT="${LOOM_PLUGIN_SESSION_ROOT:-/home/shuu5/projects/local-projects/loom-plugin-session/main}"

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
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_not_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP "$pattern" "${PROJECT_ROOT}/${file}"; then
    return 1
  fi
  return 0
}

assert_dir_exists() {
  local dir="$1"
  [[ -d "${PROJECT_ROOT}/${dir}" ]]
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

CLAUDE_MD="CLAUDE.md"

# =============================================================================
# Requirement: bare repo リポジトリ作成
# =============================================================================
echo ""
echo "--- Requirement: bare repo リポジトリ作成 ---"

# Scenario: リポジトリ初期化 (line 7)
# WHEN: gh repo create shuu5/loom-plugin-session --public でリポジトリを作成し、bare repo 構成でクローンする
# THEN: .bare/ ディレクトリが存在し、main/.git がファイルで .bare を指す

test_bare_dir_exists() {
  # PROJECT_ROOT は main/ worktree。bare repo は ../  .bare/ にある
  local bare_dir
  bare_dir="$(cd "${PROJECT_ROOT}/.." && pwd)/.bare"
  [[ -d "$bare_dir" ]]
}
run_test "bare リポジトリ: .bare/ ディレクトリが存在する" test_bare_dir_exists

test_main_git_is_file() {
  # main/.git がファイル（ディレクトリではない）であること
  local git_path="${PROJECT_ROOT}/.git"
  [[ -f "$git_path" ]] && ! [[ -d "$git_path" ]]
}
run_test "bare リポジトリ: main/.git がファイルである（ディレクトリではない）" test_main_git_is_file

test_main_git_points_to_bare() {
  # main/.git の内容が ../.bare を指していること
  local git_path="${PROJECT_ROOT}/.git"
  [[ -f "$git_path" ]] && grep -q '\.bare' "$git_path"
}
run_test "bare リポジトリ: main/.git が .bare を指している" test_main_git_points_to_bare

# Edge case: .git ディレクトリが存在しないこと（bare repo 構成違反の検出）
test_no_git_dir_in_project_root() {
  local git_path="${PROJECT_ROOT}/.git"
  # ファイルとして存在するはずで、ディレクトリであってはならない
  ! [[ -d "$git_path" ]]
}
run_test "[edge: .git がディレクトリではない（bare repo 構成が壊れていない）]" test_no_git_dir_in_project_root

# Scenario: worktree 構成の検証 (line 11)
# WHEN: リポジトリのルートを確認する
# THEN: main/ ディレクトリが worktree として機能し、git worktree list で表示される

test_git_worktree_list_includes_main() {
  # git worktree list が main worktree を含むこと
  git -C "${PROJECT_ROOT}" worktree list 2>/dev/null | grep -q 'main'
}
run_test "worktree 構成: git worktree list に main が表示される" test_git_worktree_list_includes_main

# Edge case: worktrees/ ディレクトリが存在する（feature worktree 用）
test_worktrees_dir_exists_or_creatable() {
  local parent
  parent="$(cd "${PROJECT_ROOT}/.." && pwd)"
  # worktrees/ が存在するか、または親ディレクトリ配下に作成可能であること
  [[ -d "${parent}/worktrees" ]] || [[ -w "${parent}" ]]
}
run_test "[edge: feature worktree 用 worktrees/ ディレクトリが存在するか作成可能]" test_worktrees_dir_exists_or_creatable

# =============================================================================
# Requirement: CLAUDE.md 作成
# =============================================================================
echo ""
echo "--- Requirement: CLAUDE.md 作成 ---"

# Scenario: CLAUDE.md の内容 (line 19)
# WHEN: CLAUDE.md を確認する
# THEN: bare repo 構造検証ルール、編集フロー、loom CLI 必須ルールが記載されている

test_claude_md_exists() {
  assert_file_exists "$CLAUDE_MD"
}
run_test "CLAUDE.md が存在する" test_claude_md_exists

test_claude_md_bare_repo_rule() {
  assert_file_exists "$CLAUDE_MD" || return 1
  # bare repo 構造検証ルールが記載されていること
  assert_file_contains "$CLAUDE_MD" '(bare|\.bare|worktree)' || return 1
  return 0
}
run_test "CLAUDE.md に bare repo 構造検証ルールが記載されている" test_claude_md_bare_repo_rule

test_claude_md_edit_flow() {
  assert_file_exists "$CLAUDE_MD" || return 1
  # 編集フローが記載されていること
  assert_file_contains "$CLAUDE_MD" '(編集フロー|edit.*flow|loom.*check|check.*loom)' || return 1
  return 0
}
run_test "CLAUDE.md に編集フローが記載されている" test_claude_md_edit_flow

test_claude_md_loom_cli_rule() {
  assert_file_exists "$CLAUDE_MD" || return 1
  # loom CLI 必須ルールが記載されていること
  assert_file_contains "$CLAUDE_MD" 'loom' || return 1
  return 0
}
run_test "CLAUDE.md に loom CLI 必須ルールが記載されている" test_claude_md_loom_cli_rule

# Edge case: CLAUDE.md にセッション起動ルール（main/ 配下）が記載されているか
test_claude_md_session_start_rule() {
  assert_file_exists "$CLAUDE_MD" || return 1
  assert_file_contains "$CLAUDE_MD" '(main/|セッション|CWD)' || return 1
  return 0
}
run_test "[edge: CLAUDE.md にセッション起動ルール（main/ 配下）が記載されている]" test_claude_md_session_start_rule

# Edge case: CLAUDE.md が空でないこと
test_claude_md_not_empty() {
  assert_file_exists "$CLAUDE_MD" || return 1
  [[ -s "${PROJECT_ROOT}/${CLAUDE_MD}" ]]
}
run_test "[edge: CLAUDE.md が空でない]" test_claude_md_not_empty

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================="
echo "loom-plugin-session-repository-setup: Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "Failed tests:"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
fi
echo "============================================="

[[ ${FAIL} -eq 0 ]]
