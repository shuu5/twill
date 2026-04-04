#!/usr/bin/env bats
# cleanup-worker-repo-mode.bats
# Requirement: cleanup_worker の REPO_MODE 条件分岐
# Spec: openspec/changes/fix-cleanup-worker-repo-mode/specs/cleanup-worker-repo-mode/spec.md
#
# cleanup_worker() はオーケストレーター本体に埋め込まれるため、
# REPO_MODE 自動判定ロジックを含む test double スクリプトで動作を検証する。
#
# test double: scripts/cleanup-worker-repo-mode-dispatch.sh
#   Usage: cleanup-worker-repo-mode-dispatch.sh <issue> [<branch>]
#   - GIT_DIR_STUB 環境変数で git rev-parse --git-dir の返り値を制御
#   - worktree-delete.sh / tmux kill-window / git push の呼び出しを SANDBOX/calls.log に記録

load '../../bats/helpers/common.bash'

# ---------------------------------------------------------------------------
# setup: REPO_MODE 判定ロジックを含む test double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  # test double: cleanup_worker + REPO_MODE 自動判定ロジック
  cat > "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# cleanup-worker-repo-mode-dispatch.sh
# cleanup_worker() + REPO_MODE 自動判定ロジックの test double
# Usage: <issue> [<branch>]
# Env:
#   GIT_DIR_STUB  - git rev-parse --git-dir の返り値（デフォルト: .git）
#   CALLS_LOG     - 呼び出し記録ファイル
set -uo pipefail

SCRIPTS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
issue="$1"
branch="${2:-}"

# --- REPO_MODE 自動判定 ---
# git rev-parse --git-dir が ".git" を返す → standard
# それ以外（".bare", "worktree" など）  → worktree
git_dir="${GIT_DIR_STUB:-.git}"
if [[ "$git_dir" == ".git" ]]; then
  REPO_MODE="standard"
else
  REPO_MODE="worktree"
fi

# Step 1: tmux window kill（失敗は無視）
tmux kill-window -t "ap-#${issue}" 2>/dev/null || true

# ブランチ名バリデーション（コマンドインジェクション防止）
if [[ -n "$branch" && "$branch" =~ ^[a-zA-Z0-9._/\-]+$ ]]; then
  # Step 2: worktree 削除 — REPO_MODE=standard の場合はスキップ
  if [[ "$REPO_MODE" == "worktree" ]]; then
    bash "$SCRIPTS_ROOT/worktree-delete.sh" "$branch" 2>/dev/null || \
      echo "[orchestrator] Issue #${issue}: worktree削除失敗（クリーンアップは続行）" >&2
  fi
  # （REPO_MODE=standard の場合は worktree-delete.sh を呼ばず、警告も出さない）

  # Step 3: リモートブランチ削除
  git push origin --delete "$branch" 2>/dev/null || true
fi
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh"

  # worktree-delete.sh stub（呼び出しを記録）
  cat > "$SANDBOX/scripts/worktree-delete.sh" << WDEL_EOF
#!/usr/bin/env bash
echo "worktree-delete.sh \$*" >> "${CALLS_LOG}"
exit 0
WDEL_EOF
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  # デフォルト stubs
  stub_command "tmux" "echo \"tmux \$*\" >> '${CALLS_LOG}'; exit 0"
  stub_command "git"  "echo \"git \$*\"  >> '${CALLS_LOG}'; exit 0"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Scenario: standard repo でのクリーンアップ
# WHEN REPO_MODE=standard（git rev-parse --git-dir が ".git" を返す）環境で
#      cleanup_worker が呼ばれる
# THEN worktree-delete.sh を呼び出さずにクリーンアップを続行し、警告を出力しない
# ---------------------------------------------------------------------------

@test "cleanup_worker[repo-mode]: standard repo では worktree-delete.sh を呼ばない" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "42" "feat/42-feature"

  assert_success
  # worktree-delete.sh が呼ばれていないこと
  ! grep -q "worktree-delete.sh" "$CALLS_LOG" 2>/dev/null
}

@test "cleanup_worker[repo-mode]: standard repo では警告メッセージを出力しない" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "42" "feat/42-feature"

  assert_success
  # stderr に worktree削除失敗の警告が出ないこと
  refute_output --partial "worktree削除失敗"
}

@test "cleanup_worker[repo-mode]: standard repo でもリモートブランチ削除は実行する" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "42" "feat/42-feature"

  assert_success
  grep -q "git push origin --delete feat/42-feature" "$CALLS_LOG"
}

@test "cleanup_worker[repo-mode]: standard repo でも tmux kill-window は実行する" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "42" "feat/42-feature"

  assert_success
  grep -q "tmux kill-window -t ap-#42" "$CALLS_LOG"
}

# Edge case: standard repo でブランチ名に特殊文字が含まれる場合もスキップ
@test "cleanup_worker[repo-mode]: standard repo ではブランチが設定されていても worktree-delete.sh を呼ばない" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "100" "feat/100-my-fix-v2"

  assert_success
  ! grep -q "worktree-delete.sh" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Scenario: bare repo（worktree モード）でのクリーンアップ
# WHEN REPO_MODE=worktree（git rev-parse --git-dir が ".git" 以外を返す）環境で
#      cleanup_worker が呼ばれる
# THEN 従来どおり worktree-delete.sh を呼び出す
# ---------------------------------------------------------------------------

@test "cleanup_worker[repo-mode]: bare repo では worktree-delete.sh を呼び出す" {
  GIT_DIR_STUB=".bare" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "55" "feat/55-bare-feature"

  assert_success
  grep -q "worktree-delete.sh feat/55-bare-feature" "$CALLS_LOG"
}

@test "cleanup_worker[repo-mode]: bare repo では worktree-delete.sh にブランチ名を渡す" {
  GIT_DIR_STUB=".bare" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "77" "feat/77-test"

  assert_success
  grep -q "worktree-delete.sh feat/77-test" "$CALLS_LOG"
}

@test "cleanup_worker[repo-mode]: bare repo ではリモートブランチ削除も実行する" {
  GIT_DIR_STUB=".bare" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "55" "feat/55-bare-feature"

  assert_success
  grep -q "git push origin --delete feat/55-bare-feature" "$CALLS_LOG"
}

# Edge case: git rev-parse が ".git" 以外（例: /abs/path/.git/worktrees/xxx）を返す場合も worktree 扱い
@test "cleanup_worker[repo-mode]: git rev-parse が絶対パスを返す場合も worktree モードとして worktree-delete.sh を呼ぶ" {
  GIT_DIR_STUB="/home/user/project/.bare/worktrees/feat-branch" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "88" "feat/88-abs"

  assert_success
  grep -q "worktree-delete.sh feat/88-abs" "$CALLS_LOG"
}

# ---------------------------------------------------------------------------
# Scenario: ブランチが未設定の場合
# WHEN state から branch が取得できない（空文字列）
# THEN REPO_MODE に関わらず worktree 削除ステップをスキップする
# ---------------------------------------------------------------------------

@test "cleanup_worker[repo-mode]: branch 未設定時は REPO_MODE=standard でも worktree-delete.sh を呼ばない" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "10" ""

  assert_success
  ! grep -q "worktree-delete.sh" "$CALLS_LOG" 2>/dev/null
}

@test "cleanup_worker[repo-mode]: branch 未設定時は REPO_MODE=worktree でも worktree-delete.sh を呼ばない" {
  GIT_DIR_STUB=".bare" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "20" ""

  assert_success
  ! grep -q "worktree-delete.sh" "$CALLS_LOG" 2>/dev/null
}

@test "cleanup_worker[repo-mode]: branch 未設定時は git push origin --delete を呼ばない" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "10" ""

  assert_success
  ! grep -q "git push" "$CALLS_LOG" 2>/dev/null
}

@test "cleanup_worker[repo-mode]: branch 未設定時でも tmux kill-window は実行する" {
  GIT_DIR_STUB=".git" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "10" ""

  assert_success
  grep -q "tmux kill-window -t ap-#10" "$CALLS_LOG"
}

# Edge case: branch 未設定（空文字）は worktree モードでも同様
@test "cleanup_worker[repo-mode]: branch 未設定かつ bare repo でも git push を呼ばない（冪等性）" {
  GIT_DIR_STUB=".bare" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "20" ""

  assert_success
  ! grep -q "git push" "$CALLS_LOG" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Edge cases: worktree-delete.sh 失敗でも続行（bare repo のみ）
# ---------------------------------------------------------------------------

@test "cleanup_worker[repo-mode]: bare repo で worktree-delete.sh が失敗してもスクリプトは正常終了する" {
  # worktree-delete.sh を失敗させる
  cat > "$SANDBOX/scripts/worktree-delete.sh" << 'WDEL_FAIL'
#!/usr/bin/env bash
exit 1
WDEL_FAIL
  chmod +x "$SANDBOX/scripts/worktree-delete.sh"

  GIT_DIR_STUB=".bare" \
    run bash "$SANDBOX/scripts/cleanup-worker-repo-mode-dispatch.sh" "33" "feat/33-fail"

  assert_success
}
