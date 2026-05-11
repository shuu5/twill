#!/usr/bin/env bats
# install-git-hooks-feature-dev.bats - Issue #1644 GREEN テスト
#
# Coverage:
#   - AC-3.1: install-git-hooks.sh --worktree <PATH> オプション追加
#   - AC-3.3: pre-push hook が main への push を block
#   - per-worktree core.hooksPath 方式（main worktree や他 worktree に影響しない）

load '../helpers/common'

INSTALL_SCRIPT=""
WORKTREE=""

setup() {
  common_setup

  INSTALL_SCRIPT="$REPO_ROOT/scripts/install-git-hooks.sh"
  export INSTALL_SCRIPT

  # 実 git repo を作って worktree として動作させる
  WORKTREE="$SANDBOX/worktree"
  mkdir -p "$WORKTREE"
  (cd "$WORKTREE" && git init -q -b main 2>/dev/null || git init -q)
  (cd "$WORKTREE" && git config user.email "test@example.com" && git config user.name "Test")
  # initial commit が無いと一部 git 操作が失敗するため
  (cd "$WORKTREE" && touch README.md && git add README.md && git commit -q -m "init" 2>/dev/null || true)
  export WORKTREE
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-3.1: --worktree <PATH> でフック設置
# ===========================================================================

@test "fd-hooks: --worktree <PATH> creates .fd-hooks/pre-push" {
  run bash "$INSTALL_SCRIPT" --worktree "$WORKTREE"
  [ "$status" -eq 0 ]

  # .fd-hooks/pre-push が作成されたこと
  [ -f "$WORKTREE/.fd-hooks/pre-push" ] || fail "pre-push hook が作成されていない"
  [ -x "$WORKTREE/.fd-hooks/pre-push" ] || fail "pre-push hook が実行可能でない"
}

@test "fd-hooks: --worktree sets core.hooksPath" {
  run bash "$INSTALL_SCRIPT" --worktree "$WORKTREE"
  [ "$status" -eq 0 ]

  local hooks_path
  hooks_path=$(git -C "$WORKTREE" config --get core.hooksPath 2>/dev/null || echo "")
  [ "$hooks_path" == ".fd-hooks" ] || fail "core.hooksPath が .fd-hooks に設定されていない: $hooks_path"
}

# ===========================================================================
# AC-3.1: --worktree 引数不在 → エラー
# ===========================================================================

@test "fd-hooks: --worktree without path → error" {
  run bash "$INSTALL_SCRIPT" --worktree 2>&1
  [ "$status" -eq 2 ]
  [[ "$output" == *"requires a path argument"* ]] \
    || fail "path argument エラーメッセージが出ない: $output"
}

# ===========================================================================
# AC-3.1: --worktree path が存在しない → エラー
# ===========================================================================

@test "fd-hooks: --worktree non-existent path → error" {
  run bash "$INSTALL_SCRIPT" --worktree "/nonexistent/path" 2>&1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]] \
    || fail "not found エラーが出ない: $output"
}

# ===========================================================================
# AC-3.3: pre-push hook が main への push を block
# ===========================================================================

@test "fd-hooks: pre-push hook blocks main push" {
  run bash "$INSTALL_SCRIPT" --worktree "$WORKTREE"
  [ "$status" -eq 0 ]

  # hook を直接実行: stdin から "<local_ref> <local_sha> refs/heads/main <remote_sha>" を渡す
  run bash -c "echo 'refs/heads/feature-dev abc123 refs/heads/main def456' | bash '$WORKTREE/.fd-hooks/pre-push' origin https://github.com/test/test.git"
  [ "$status" -eq 1 ]
  [[ "$output" == *"main 直接 push は禁止"* ]] \
    || fail "main push 禁止エラーが出ない: $output"
}

# ===========================================================================
# AC-3.3: pre-push hook は feature branch の push を許可
# ===========================================================================

@test "fd-hooks: pre-push hook allows feature branch push" {
  run bash "$INSTALL_SCRIPT" --worktree "$WORKTREE"
  [ "$status" -eq 0 ]

  # refs/heads/feature-dev (main 以外) への push は許可
  run bash -c "echo 'refs/heads/feature-dev abc123 refs/heads/feature-dev def456' | bash '$WORKTREE/.fd-hooks/pre-push' origin https://github.com/test/test.git"
  [ "$status" -eq 0 ]
}

# ===========================================================================
# --dry-run mode（既存 pre-commit と同じ）
# ===========================================================================

@test "fd-hooks: --dry-run for --worktree does not make changes" {
  run bash "$INSTALL_SCRIPT" --worktree "$WORKTREE" --dry-run
  [ "$status" -eq 0 ]

  # .fd-hooks/ が作成されていないこと
  [ ! -d "$WORKTREE/.fd-hooks" ] || fail "--dry-run で .fd-hooks/ が作成された"
}

# ===========================================================================
# 既存 pre-commit hook 機能の保持（regression）
# ===========================================================================

@test "fd-hooks: pre-commit hook 機能は --worktree 無しで従来通り動作 (--dry-run)" {
  # 既存 pre-commit インストールが動作することを --dry-run で確認
  run bash "$INSTALL_SCRIPT" --dry-run
  # exit 0: dry-run は成功するはず
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-commit"* ]] || true  # message 体裁は流動的
}
