#!/usr/bin/env bash
# =============================================================================
# Document Verification Tests: pr-cycle-bare-repo-fix
# Generated from: deltaspec/changes/pr-cycle-bare-repo-fix/specs/pr-cycle-bare-repo-fix/spec.md
# Coverage level: edge-cases
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

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qP -- "$pattern" "${PROJECT_ROOT}/${file}"
}

assert_file_contains_i() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] && grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"
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

assert_file_not_contains_i() {
  local file="$1"
  local pattern="$2"
  [[ -f "${PROJECT_ROOT}/${file}" ]] || return 1
  if grep -qiP -- "$pattern" "${PROJECT_ROOT}/${file}"; then
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

ALL_PASS_CHECK_CMD="commands/all-pass-check.md"
MERGE_GATE_CMD="commands/merge-gate.md"
AC_VERIFY_CMD="commands/ac-verify.md"
STATE_WRITE_SCRIPT="scripts/state-write.sh"
WORKTREE_CREATE_SCRIPT="scripts/worktree-create.sh"

# =============================================================================
# Requirement: state-write.sh 呼び出し形式の修正
# =============================================================================
echo ""
echo "--- Requirement: state-write.sh 呼び出し形式の修正 ---"

# Scenario: all-pass-check が PASS 時に merge-ready へ遷移 (line 7)
# WHEN: 全ステップが PASS または WARN のとき
# THEN: bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=merge-ready" が実行される

test_all_pass_check_merge_ready_named_flags() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  # Named flag形式: --type issue --issue ... --role worker --set "status=merge-ready"
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    'state-write\.sh\s+--type\s+issue' || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '--role\s+worker' || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '--set\s+["\x27]?status=merge-ready' || return 1
  return 0
}
run_test "all-pass-check PASS 時: state-write.sh に --type --issue --role --set 形式で merge-ready を書き込む" \
  test_all_pass_check_merge_ready_named_flags

# Edge case: all-pass-check に旧来の位置引数形式 (state-write.sh issue N status merge-ready) が残っていない
test_all_pass_check_no_positional_merge_ready() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  # 旧形式: state-write.sh issue "${ISSUE_NUM}" status merge-ready
  if grep -qP -- 'state-write\.sh\s+issue\s+["$\{]' "${PROJECT_ROOT}/${ALL_PASS_CHECK_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "all-pass-check [edge: 旧位置引数形式 state-write.sh issue N ... が残っていない]" \
  test_all_pass_check_no_positional_merge_ready

# Scenario: all-pass-check が FAIL 時に failed へ遷移 (line 11)
# WHEN: いずれかのステップが FAIL のとき
# THEN: bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=failed" が実行される

test_all_pass_check_fail_named_flags() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    'state-write\.sh\s+--type\s+issue' || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '--role\s+worker' || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '--set\s+["\x27]?status=failed' || return 1
  return 0
}
run_test "all-pass-check FAIL 時: state-write.sh に --type --issue --role --set 形式で failed を書き込む" \
  test_all_pass_check_fail_named_flags

# Edge case: all-pass-check の PASS/FAIL 両方のパスで --issue フラグにISSUE_NUM変数が渡されている
test_all_pass_check_issue_num_in_flags() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '--issue\s+["\x27]?\$\{?ISSUE_NUM\}?' || return 1
  return 0
}
run_test "all-pass-check [edge: --issue フラグに ISSUE_NUM 変数が渡されている]" \
  test_all_pass_check_issue_num_in_flags

# Scenario: merge-gate が PASS 時に merge-ready を宣言して停止 (#150 fix)
# WHEN: BLOCKING findings が 0 件のとき（autopilot 時）
# THEN: Worker は state-write --role worker --set status=merge-ready を宣言して停止
#       Pilot が merge-gate-execute.sh 経由でマージを実行（merge-gate.md に raw コマンドなし）

test_merge_gate_pass_worker_declares_merge_ready() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # autopilot 時: Worker が --role worker で merge-ready を宣言
  assert_file_contains "$MERGE_GATE_CMD" \
    '--role\s+worker' || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '--set\s+["\x27]?status=merge-ready' || return 1
  return 0
}
run_test "merge-gate PASS 時: Worker が --role worker で merge-ready を宣言する（不変条件C）" \
  test_merge_gate_pass_worker_declares_merge_ready

test_merge_gate_pass_uses_merge_gate_execute() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # 非 autopilot 時（Pilot フロー）: merge-gate-execute.sh 経由でマージ
  assert_file_contains "$MERGE_GATE_CMD" \
    'merge-gate-execute\.sh' || return 1
  return 0
}
run_test "merge-gate PASS 時: 非 autopilot 時は merge-gate-execute.sh 呼び出しを案内する" \
  test_merge_gate_pass_uses_merge_gate_execute

# Edge case: merge-gate PASS パスで raw --role pilot --set status=done が存在しないことを確認
test_merge_gate_pass_no_raw_pilot_done() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # PASS セクションに raw --role pilot --set status=done が含まれないこと（不変条件C #150 fix）
  local pass_section
  pass_section=$(awk '/### PASS 時の状態遷移/,/### REJECT 時/' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null)
  if echo "$pass_section" | grep -qP -- '--role\s+pilot.*status=done'; then
    return 1
  fi
  return 0
}
run_test "merge-gate [edge: PASS セクションに raw --role pilot --set status=done が存在しない]" \
  test_merge_gate_pass_no_raw_pilot_done

# Scenario: merge-gate が REJECT 時（1回目）に状態を更新 (line 19)
# WHEN: BLOCKING findings が 1 件以上かつ retry_count が 0 のとき
# THEN: bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role worker --set "status=failed"
#       に続き、retry_count, fix_instructions, status=running が順に書き込まれる

test_merge_gate_reject_first_failed_named_flags() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '--role\s+worker' || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '--set\s+["\x27]?status=failed' || return 1
  return 0
}
run_test "merge-gate REJECT 1回目: --role worker --set status=failed が存在する" \
  test_merge_gate_reject_first_failed_named_flags

test_merge_gate_reject_fix_instructions_named_flags() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '--set\s+["\x27]?fix_instructions=' || return 1
  return 0
}
run_test "merge-gate REJECT 1回目: --set fix_instructions=... が存在する" \
  test_merge_gate_reject_fix_instructions_named_flags

test_merge_gate_reject_status_running_named_flags() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '--set\s+["\x27]?status=running' || return 1
  return 0
}
run_test "merge-gate REJECT 1回目: --set status=running が存在する" \
  test_merge_gate_reject_status_running_named_flags

# Edge case: retry_count は state-write.sh が failed→running 遷移時に自動インクリメント（L232）
# merge-gate 側で明示的に書き込まない設計（書くと遷移ガード retry_count<1 に引っかかる）
test_merge_gate_reject_no_explicit_retry_count() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # retry_count の明示的な --set 呼び出しが存在しないことを確認
  if grep -qP -- '--set\s+["\x27]?retry_count=' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate [edge: retry_count は state-write.sh 自動インクリメントに委譲（明示書き込みなし）]" \
  test_merge_gate_reject_no_explicit_retry_count

# Scenario: merge-gate が REJECT 時（2回目）に確定失敗 (line 23)
# WHEN: BLOCKING findings が 1 件以上かつ retry_count が 1 以上のとき
# THEN: bash scripts/state-write.sh --type issue --issue "${ISSUE_NUM}" --role pilot --set "status=failed" が実行される

test_merge_gate_reject_final_pilot_failed() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # 2回目の確定失敗: pilot ロールで status=failed
  assert_file_contains "$MERGE_GATE_CMD" \
    '--role\s+pilot' || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '--set\s+["\x27]?status=failed' || return 1
  return 0
}
run_test "merge-gate REJECT 2回目: --role pilot --set status=failed が存在する" \
  test_merge_gate_reject_final_pilot_failed

# Edge case: merge-gate に旧来の位置引数形式が残っていない
test_merge_gate_no_positional_args() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # 旧形式: state-write.sh issue "${ISSUE_NUM}" status done (など)
  if grep -qP -- 'state-write\.sh\s+issue\s+["$\{]' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate [edge: 旧位置引数形式 state-write.sh issue N ... が残っていない]" \
  test_merge_gate_no_positional_args

# =============================================================================
# Requirement: DCI Context セクションの追加
# =============================================================================
echo ""
echo "--- Requirement: DCI Context セクションの追加 ---"

# Scenario: all-pass-check に DCI Context が存在する (line 31)
# WHEN: all-pass-check.md を読み込むとき
# THEN: ファイル先頭に "## Context (auto-injected)" セクションが存在し、
#       BRANCH, ISSUE_NUM, PR_NUMBER が定義されている

test_all_pass_check_has_dci_context_header() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    '## Context \(auto-injected\)' || return 1
  return 0
}
run_test "all-pass-check に '## Context (auto-injected)' セクションが存在する" \
  test_all_pass_check_has_dci_context_header

test_all_pass_check_dci_branch() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    'Branch' || return 1
  return 0
}
run_test "all-pass-check DCI: Branch が定義されている" \
  test_all_pass_check_dci_branch

test_all_pass_check_dci_issue_num() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    'Issue' || return 1
  return 0
}
run_test "all-pass-check DCI: Issue (ISSUE_NUM) が定義されている" \
  test_all_pass_check_dci_issue_num

test_all_pass_check_dci_pr_number() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    'PR' || return 1
  return 0
}
run_test "all-pass-check DCI: PR_NUMBER (PR) が定義されている" \
  test_all_pass_check_dci_pr_number

# Edge case: all-pass-check の DCI セクションが frontmatter または本文先頭近くに配置されている
test_all_pass_check_dci_position() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  # Context セクションが存在し、かつ最初の 30 行以内にある
  local line_num
  line_num=$(grep -n '## Context (auto-injected)' "${PROJECT_ROOT}/${ALL_PASS_CHECK_CMD}" 2>/dev/null | head -1 | cut -d: -f1)
  if [[ -z "$line_num" ]]; then
    return 1
  fi
  if (( line_num > 30 )); then
    echo "  Context セクションが行 ${line_num} にある（30行以内を期待）" >&2
    return 1
  fi
  return 0
}
run_test "all-pass-check [edge: DCI Context セクションが先頭 30 行以内にある]" \
  test_all_pass_check_dci_position

# Scenario: merge-gate に DCI Context が存在する (line 35)
# WHEN: merge-gate.md を読み込むとき
# THEN: ファイル先頭に "## Context (auto-injected)" セクションが存在し、
#       BRANCH, ISSUE_NUM, PR_NUMBER が定義されている

test_merge_gate_has_dci_context_header() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    '## Context \(auto-injected\)' || return 1
  return 0
}
run_test "merge-gate に '## Context (auto-injected)' セクションが存在する" \
  test_merge_gate_has_dci_context_header

test_merge_gate_dci_branch() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    'Branch' || return 1
  return 0
}
run_test "merge-gate DCI: Branch が定義されている" \
  test_merge_gate_dci_branch

test_merge_gate_dci_issue_num() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    'Issue' || return 1
  return 0
}
run_test "merge-gate DCI: Issue (ISSUE_NUM) が定義されている" \
  test_merge_gate_dci_issue_num

test_merge_gate_dci_pr_number() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    'PR' || return 1
  return 0
}
run_test "merge-gate DCI: PR_NUMBER (PR) が定義されている" \
  test_merge_gate_dci_pr_number

# Edge case: merge-gate の DCI セクションが先頭 30 行以内にある
test_merge_gate_dci_position() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  local line_num
  line_num=$(grep -n '## Context (auto-injected)' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null | head -1 | cut -d: -f1)
  if [[ -z "$line_num" ]]; then
    return 1
  fi
  if (( line_num > 30 )); then
    echo "  Context セクションが行 ${line_num} にある（30行以内を期待）" >&2
    return 1
  fi
  return 0
}
run_test "merge-gate [edge: DCI Context セクションが先頭 30 行以内にある]" \
  test_merge_gate_dci_position

# Scenario: ac-verify に DCI Context が存在する (line 39)
# WHEN: ac-verify.md を読み込むとき
# THEN: ファイル先頭に "## Context (auto-injected)" セクションが存在し、
#       ISSUE_NUM が定義されている

test_ac_verify_has_dci_context_header() {
  assert_file_exists "$AC_VERIFY_CMD" || return 1
  assert_file_contains "$AC_VERIFY_CMD" \
    '## Context \(auto-injected\)' || return 1
  return 0
}
run_test "ac-verify に '## Context (auto-injected)' セクションが存在する" \
  test_ac_verify_has_dci_context_header

test_ac_verify_dci_issue_num() {
  assert_file_exists "$AC_VERIFY_CMD" || return 1
  assert_file_contains "$AC_VERIFY_CMD" \
    'Issue' || return 1
  return 0
}
run_test "ac-verify DCI: Issue (ISSUE_NUM) が定義されている" \
  test_ac_verify_dci_issue_num

# Edge case: ac-verify の DCI Context が先頭 30 行以内に存在する
test_ac_verify_dci_position() {
  assert_file_exists "$AC_VERIFY_CMD" || return 1
  local line_num
  line_num=$(grep -n '## Context (auto-injected)' "${PROJECT_ROOT}/${AC_VERIFY_CMD}" 2>/dev/null | head -1 | cut -d: -f1)
  if [[ -z "$line_num" ]]; then
    return 1
  fi
  if (( line_num > 30 )); then
    echo "  Context セクションが行 ${line_num} にある（30行以内を期待）" >&2
    return 1
  fi
  return 0
}
run_test "ac-verify [edge: DCI Context セクションが先頭 30 行以内にある]" \
  test_ac_verify_dci_position

# Edge case: DCI Context の記法が ref-dci.md 準拠（git branch コマンドが含まれる）
test_all_pass_check_dci_uses_git_branch() {
  assert_file_exists "$ALL_PASS_CHECK_CMD" || return 1
  assert_file_contains "$ALL_PASS_CHECK_CMD" \
    'git branch --show-current' || return 1
  return 0
}
run_test "all-pass-check [edge: DCI Context で git branch --show-current を使用]" \
  test_all_pass_check_dci_uses_git_branch

test_merge_gate_dci_uses_git_branch() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_contains "$MERGE_GATE_CMD" \
    'git branch --show-current' || return 1
  return 0
}
run_test "merge-gate [edge: DCI Context で git branch --show-current を使用]" \
  test_merge_gate_dci_uses_git_branch

# =============================================================================
# Requirement: bare repo 互換の merge フロー
# =============================================================================
echo ""
echo "--- Requirement: bare repo 互換の merge フロー ---"

# Scenario: squash merge に --delete-branch が含まれない (line 47)
# WHEN: merge-gate が PASS 判定で squash merge を実行するとき
# THEN: gh pr merge ${PR_NUMBER} --squash が実行され、--delete-branch は含まれない

test_merge_gate_no_delete_branch_flag() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  assert_file_not_contains "$MERGE_GATE_CMD" \
    '--delete-branch' || return 1
  return 0
}
run_test "merge-gate: squash merge コマンドに --delete-branch が含まれない" \
  test_merge_gate_no_delete_branch_flag

test_merge_gate_no_raw_squash_merge_command() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # merge-gate.md に raw gh pr merge コマンドが含まれないこと（不変条件C #150 fix）
  # squash merge は merge-gate-execute.sh で実施
  if grep -qP -- 'gh\s+pr\s+merge\s+.*--squash' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate: gh pr merge --squash の raw コマンドが存在しない（不変条件C）" \
  test_merge_gate_no_raw_squash_merge_command

# Edge case: merge-gate のすべてのコードブロック内に --delete-branch が現れない
test_merge_gate_no_delete_branch_anywhere() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  if grep -qP -- '\-\-delete-branch' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate [edge: ファイル全体で --delete-branch が一切存在しない]" \
  test_merge_gate_no_delete_branch_anywhere

# Scenario: worktree-delete.sh にブランチ名が渡される (line 51)
# WHEN: merge-gate が merge 後に worktree を削除するとき
# THEN: bash scripts/worktree-delete.sh "${BRANCH}" が実行される（フルパスではなくブランチ名）

test_merge_gate_no_direct_worktree_delete() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # merge-gate.md に直接 worktree-delete.sh 呼び出しが存在しないこと
  # worktree 削除は merge-gate-execute.sh 内で実施（#150 fix）
  if grep -qP -- 'worktree-delete\.sh' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate: worktree-delete.sh の直接呼び出しが存在しない（merge-gate-execute.sh に委譲）" \
  test_merge_gate_no_direct_worktree_delete

# Edge case: merge-gate が worktree-delete.sh にフルパス（/home/..., /path/to/...）を渡していない
test_merge_gate_worktree_delete_no_full_path() {
  assert_file_exists "$MERGE_GATE_CMD" || return 1
  # WORKTREE_PATH や /home/ などのフルパスが渡されていないことを確認
  if grep -qP -- 'worktree-delete\.sh\s+["\x27]?/' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  if grep -qP -- 'worktree-delete\.sh\s+["\x27]?\$\{?WORKTREE_PATH\}?' "${PROJECT_ROOT}/${MERGE_GATE_CMD}" 2>/dev/null; then
    return 1
  fi
  return 0
}
run_test "merge-gate [edge: worktree-delete.sh にフルパスが渡されていない]" \
  test_merge_gate_worktree_delete_no_full_path

# Edge case: worktree-delete.sh スクリプト自体がブランチ名引数を受け付けている
test_worktree_delete_accepts_branch_name() {
  local script="scripts/worktree-delete.sh"
  assert_file_exists "$script" || return 1
  # スクリプトが位置引数としてブランチ名を受け取る記述がある
  assert_file_contains "$script" \
    'branch=' || return 1
  return 0
}
run_test "worktree-delete.sh [edge: ブランチ名の位置引数を受け付ける実装がある]" \
  test_worktree_delete_accepts_branch_name

# Edge case: worktree-delete.sh がブランチ名からworktreeパスを構築する
test_worktree_delete_builds_path_from_branch() {
  local script="scripts/worktree-delete.sh"
  assert_file_exists "$script" || return 1
  # worktrees/${branch} のようなパス構築がある
  assert_file_contains "$script" \
    'worktrees.*branch|worktree_path' || return 1
  return 0
}
run_test "worktree-delete.sh [edge: ブランチ名から worktree パスを構築する]" \
  test_worktree_delete_builds_path_from_branch

# =============================================================================
# Requirement: worktree-create.sh の upstream 自動設定
# =============================================================================
echo ""
echo "--- Requirement: worktree-create.sh の upstream 自動設定 ---"

# Scenario: 新規 worktree で upstream が設定される (line 61)
# WHEN: worktree-create.sh で新規ブランチを作成したとき
# THEN: git push -u origin <branch> が実行され、upstream tracking が設定される

test_worktree_create_push_upstream() {
  assert_file_exists "$WORKTREE_CREATE_SCRIPT" || return 1
  # git push -u origin <branch> の形式
  assert_file_contains "$WORKTREE_CREATE_SCRIPT" \
    'git\s+push\s+-u\s+origin' || return 1
  return 0
}
run_test "worktree-create.sh: git push -u origin <branch> で upstream を設定する" \
  test_worktree_create_push_upstream

# Edge case: git push -u origin の引数にブランチ名変数が渡されている
test_worktree_create_push_branch_var() {
  assert_file_exists "$WORKTREE_CREATE_SCRIPT" || return 1
  assert_file_contains "$WORKTREE_CREATE_SCRIPT" \
    'git\s+push\s+-u\s+origin\s+["\x27]?\$\{?BRANCH_NAME\}?' || return 1
  return 0
}
run_test "worktree-create.sh [edge: git push -u origin に BRANCH_NAME が渡されている]" \
  test_worktree_create_push_branch_var

# Scenario: upstream 設定失敗時は警告のみ (line 65)
# WHEN: git push -u origin <branch> が失敗したとき（ネットワークエラー等）
# THEN: 警告メッセージを表示し、worktree 作成自体は成功する

test_worktree_create_push_failure_warn_only() {
  assert_file_exists "$WORKTREE_CREATE_SCRIPT" || return 1
  # push の失敗を || でキャッチし、警告のみで継続する記述がある
  assert_file_contains "$WORKTREE_CREATE_SCRIPT" \
    'git\s+push\s+-u\s+origin.*\|\|' || return 1
  return 0
}
run_test "worktree-create.sh: git push -u 失敗時に || で警告のみ表示して継続する" \
  test_worktree_create_push_failure_warn_only

# Edge case: worktree-create.sh の upstream 設定失敗時に警告メッセージを出力する
test_worktree_create_push_failure_message() {
  assert_file_exists "$WORKTREE_CREATE_SCRIPT" || return 1
  # 失敗時に警告メッセージ（WARN/警告等）を出力する記述がある
  assert_file_contains_i "$WORKTREE_CREATE_SCRIPT" \
    '(WARN|警告).*(push|upstream)|(push.*(失敗|fail))' || return 1
  return 0
}
run_test "worktree-create.sh [edge: upstream push 失敗時に警告メッセージを出力する]" \
  test_worktree_create_push_failure_message

# Edge case: worktree-create.sh が bash 構文チェックを通る
test_worktree_create_syntax_valid() {
  assert_file_exists "$WORKTREE_CREATE_SCRIPT" || return 1
  bash -n "${PROJECT_ROOT}/${WORKTREE_CREATE_SCRIPT}" 2>/dev/null
}
run_test "worktree-create.sh [edge: bash 構文チェック pass]" \
  test_worktree_create_syntax_valid

# Edge case: worktree-create.sh が set -euo pipefail を使用している（エラー耐性）
# 注: push の失敗で中断しないため、push 前後で一時的に set +e が必要な場合もある
test_worktree_create_has_strict_mode() {
  assert_file_exists "$WORKTREE_CREATE_SCRIPT" || return 1
  assert_file_contains "$WORKTREE_CREATE_SCRIPT" \
    'set\s+-.*e.*u.*o|set\s+-euo' || return 1
  return 0
}
run_test "worktree-create.sh [edge: set -euo pipefail が設定されている]" \
  test_worktree_create_has_strict_mode

# =============================================================================
# Integration / Cross-cutting edge cases
# =============================================================================
echo ""
echo "--- Cross-cutting edge cases ---"

# Edge case: state-write.sh 自体が --type, --issue, --role, --set フラグをサポートしている
test_state_write_supports_named_flags() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" \
    '--type' || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" \
    '--issue' || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" \
    '--role' || return 1
  assert_file_contains "$STATE_WRITE_SCRIPT" \
    '--set' || return 1
  return 0
}
run_test "[edge: state-write.sh が --type --issue --role --set フラグをサポート]" \
  test_state_write_supports_named_flags

# Edge case: state-write.sh が位置引数形式を受け付けない（旧 API 非互換の確認）
test_state_write_rejects_unknown_positional() {
  assert_file_exists "$STATE_WRITE_SCRIPT" || return 1
  # 不明なオプション処理でエラー終了する記述がある
  assert_file_contains "$STATE_WRITE_SCRIPT" \
    '(ERROR|エラー).*不明.*オプション|unknown.*option' || return 1
  return 0
}
run_test "[edge: state-write.sh が不明オプションを ERROR で拒否する]" \
  test_state_write_rejects_unknown_positional

# Edge case: 3ファイル全て（all-pass-check, merge-gate, ac-verify）に DCI Context がある
test_all_three_have_dci() {
  local missing=()
  for f in "$ALL_PASS_CHECK_CMD" "$MERGE_GATE_CMD" "$AC_VERIFY_CMD"; do
    if ! grep -qP -- '## Context \(auto-injected\)' "${PROJECT_ROOT}/${f}" 2>/dev/null; then
      missing+=("$f")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "  DCI Context がないファイル: ${missing[*]}" >&2
    return 1
  fi
  return 0
}
run_test "[edge: all-pass-check, merge-gate, ac-verify の全 3 ファイルに DCI Context がある]" \
  test_all_three_have_dci

# Edge case: worktree-create.sh が実行可能権限を持っている
test_worktree_create_is_executable() {
  [[ -x "${PROJECT_ROOT}/${WORKTREE_CREATE_SCRIPT}" ]]
}
run_test "[edge: worktree-create.sh が実行可能]" \
  test_worktree_create_is_executable

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
