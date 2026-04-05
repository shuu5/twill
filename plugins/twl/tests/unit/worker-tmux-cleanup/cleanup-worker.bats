#!/usr/bin/env bats
# cleanup-worker.bats
# Requirement: cleanup_worker ヘルパー関数
# Spec: openspec/changes/worker-tmux-cleanup/specs/orchestrator-cleanup/spec.md
#
# cleanup_worker() はオーケストレーター本体に埋め込まれるため、
# 関数ロジックのみを抽出した test double スクリプトで動作を検証する。
#
# test double: scripts/cleanup-worker-dispatch.sh
#   Usage: cleanup-worker-dispatch.sh <issue> [<branch>]
#   - <branch> が空文字の場合はブランチ削除をスキップ
#   - tmux kill-window と git push の呼び出し結果を SANDBOX/calls.log に記録

load '../../bats/helpers/common'

# ---------------------------------------------------------------------------
# setup: cleanup_worker ロジックを抽出した test double を生成
# ---------------------------------------------------------------------------

setup() {
  common_setup

  # cleanup_worker の実装相当のスクリプトを生成
  cat > "$SANDBOX/scripts/cleanup-worker-dispatch.sh" << 'DISPATCH_EOF'
#!/usr/bin/env bash
# cleanup-worker-dispatch.sh - cleanup_worker() のロジック test double
# Usage: cleanup-worker-dispatch.sh <issue> [<branch>]
set -uo pipefail

issue="$1"
branch="${2:-}"

# tmux window kill（失敗は無視）
tmux kill-window -t "ap-#${issue}" 2>/dev/null || true

# リモートブランチ削除（branch が空の場合はスキップ）
if [[ -n "$branch" ]]; then
  git push origin --delete "$branch" 2>/dev/null || true
fi
DISPATCH_EOF
  chmod +x "$SANDBOX/scripts/cleanup-worker-dispatch.sh"

  # 呼び出しログファイル
  CALLS_LOG="$SANDBOX/calls.log"
  export CALLS_LOG

  # デフォルト stubs（呼び出しを記録する）
  stub_command "tmux" "echo \"tmux \$*\" >> '$CALLS_LOG'; exit 0"
  stub_command "git"  "echo \"git \$*\"  >> '$CALLS_LOG'; exit 0"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Requirement: cleanup_worker ヘルパー関数
# ---------------------------------------------------------------------------

# Scenario: tmux window の kill
# WHEN cleanup_worker "$issue" が呼ばれる
# THEN tmux kill-window -t "ap-#${issue}" を実行し、失敗時は無視する
@test "cleanup_worker: tmux kill-window を issue 番号付きで実行する" {
  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "42"

  assert_success
  grep -q "tmux kill-window -t ap-#42" "$CALLS_LOG"
}

# Scenario: リモートブランチの削除
# WHEN cleanup_worker "$issue" が呼ばれ、state に branch が記録されている
# THEN git push origin --delete "$branch" を実行し、失敗時は無視する
@test "cleanup_worker: branch が設定されている場合は git push origin --delete を実行する" {
  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "42" "feat/42-my-feature"

  assert_success
  grep -q "git push origin --delete feat/42-my-feature" "$CALLS_LOG"
}

# Scenario: branch 未設定の場合
# WHEN cleanup_worker "$issue" が呼ばれ、state に branch が空
# THEN リモートブランチ削除をスキップし、window kill のみ実行する
@test "cleanup_worker: branch が空の場合は git push を呼ばず tmux kill のみ実行する" {
  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "7" ""

  assert_success
  grep -q "tmux kill-window -t ap-#7" "$CALLS_LOG"
  # git push は呼ばれてはならない
  ! grep -q "git push" "$CALLS_LOG"
}

# Edge case: tmux kill-window が失敗しても終了コード 0
# WHEN tmux kill-window が失敗する（window 不在など）
# THEN || true で無視してスクリプトが正常終了する
@test "cleanup_worker: tmux kill-window が失敗しても終了コード 0 で継続する" {
  stub_command "tmux" "exit 1"

  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "42"

  assert_success
}

# Edge case: git push が失敗しても終了コード 0
# WHEN git push origin --delete が失敗する（リモートブランチ不在など）
# THEN || true で無視してスクリプトが正常終了する
@test "cleanup_worker: git push が失敗しても終了コード 0 で継続する" {
  stub_command "git" "exit 1"

  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "42" "feat/42-my-feature"

  assert_success
}

# ---------------------------------------------------------------------------
# Requirement: cleanup の冪等性
# Scenario: cleanup_worker が同じ issue に対して複数回呼ばれる
# WHEN cleanup_worker が同じ issue に対して複数回呼ばれる
# THEN 2回目以降は tmux kill-window が失敗しても || true で無視する
# ---------------------------------------------------------------------------

@test "cleanup_worker: 2回目の呼び出しで tmux kill-window が失敗しても正常終了する（冪等性）" {
  # 1回目: 成功
  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "99"
  assert_success

  # 2回目: tmux kill-window は失敗（window はすでに消えている）
  stub_command "tmux" "exit 1"
  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "99"
  assert_success
}

@test "cleanup_worker: 2回目の呼び出しで tmux kill-window が失敗してもブランチ削除は実行される" {
  stub_command "tmux" "exit 1"
  stub_command "git" "echo \"git \$*\" >> '$CALLS_LOG'; exit 0"

  run bash "$SANDBOX/scripts/cleanup-worker-dispatch.sh" "99" "feat/99-branch"

  assert_success
  grep -q "git push origin --delete feat/99-branch" "$CALLS_LOG"
}
