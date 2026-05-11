#!/usr/bin/env bash
# install-git-hooks.sh — twl プロジェクトの git hooks をローカルに設置
#
# Usage:
#   bash plugins/twl/scripts/install-git-hooks.sh                 # pre-commit hook install (idempotent)
#   bash plugins/twl/scripts/install-git-hooks.sh --dry-run       # 差分のみ表示
#   bash plugins/twl/scripts/install-git-hooks.sh --worktree PATH # Issue #1644: feature-dev worktree 用 pre-push hook 設置
#
# Hook: pre-commit (default mode)
#   - chain.py / deps.yaml / chain-steps.sh 編集時に `twl check --deps-integrity` を実行
#   - errors 発生時 commit を abort (drift 再発防止, #868)
#   - --no-verify で bypass 可能 (user 裁量)
#
# Hook: pre-push (--worktree mode, Issue #1644)
#   - feature-dev worktree からの main への直接 push を block（incident d6cb9859 再発防止）
#   - per-worktree (core.hooksPath = .fd-hooks/) 方式で対象 worktree のみに適用
#   - --no-verify で bypass 可能 (user 裁量)
set -euo pipefail

DRY_RUN=false
WORKTREE_MODE=false
WORKTREE_PATH=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --worktree)
      WORKTREE_MODE=true
      WORKTREE_PATH="${2:-}"
      if [[ -z "$WORKTREE_PATH" ]]; then
        echo "Error: --worktree requires a path argument" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

# --- Issue #1644: feature-dev worktree mode (pre-push hook) ---
if [[ "$WORKTREE_MODE" == "true" ]]; then
  if [[ ! -d "$WORKTREE_PATH" ]]; then
    echo "✗ worktree path not found: $WORKTREE_PATH" >&2
    exit 1
  fi
  # per-worktree hooks dir（core.hooksPath で指定）
  FD_HOOKS_DIR="$WORKTREE_PATH/.fd-hooks"
  FD_PRE_PUSH="$FD_HOOKS_DIR/pre-push"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] would create: $FD_HOOKS_DIR/"
    echo "[dry-run] would write:  $FD_PRE_PUSH (block main push)"
    echo "[dry-run] would set:    git -C $WORKTREE_PATH config core.hooksPath .fd-hooks"
    exit 0
  fi

  mkdir -p "$FD_HOOKS_DIR"

  cat > "$FD_PRE_PUSH" <<'PREPUSH'
#!/usr/bin/env bash
# pre-push hook: feature-dev worktree での main への直接 push を禁止
# installed by plugins/twl/scripts/install-git-hooks.sh --worktree (Issue #1644)
# bypass: git push --no-verify (user discretion)
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  if [[ "$remote_ref" == "refs/heads/main" ]]; then
    echo "Error: feature-dev worktree からの main 直接 push は禁止されています。" >&2
    echo "       PR (git push origin <branch>) 経由で merge してください。" >&2
    echo "       bypass: git push --no-verify (user discretion)" >&2
    exit 1
  fi
done
exit 0
PREPUSH
  chmod +x "$FD_PRE_PUSH"

  # core.hooksPath を相対パス（.fd-hooks）で設定 — worktree 内で git push 時に有効
  git -C "$WORKTREE_PATH" config core.hooksPath .fd-hooks
  echo "✓ pre-push hook installed: $FD_PRE_PUSH (worktree=$WORKTREE_PATH)"
  echo "  core.hooksPath = .fd-hooks (worktree-local)"
  exit 0
fi

# --- default mode: pre-commit hook (既存動作) ---
REPO_ROOT="$(git rev-parse --show-toplevel)"
GIT_COMMON_DIR="$(git rev-parse --git-common-dir)"
HOOKS_DIR="$GIT_COMMON_DIR/hooks"
HOOK_SOURCE="$REPO_ROOT/plugins/twl/scripts/hooks/git-pre-commit-deps-integrity.sh"
HOOK_TARGET="$HOOKS_DIR/pre-commit"

if [[ ! -f "$HOOK_SOURCE" ]]; then
  echo "✗ Hook source not found: $HOOK_SOURCE" >&2
  exit 1
fi

chmod +x "$HOOK_SOURCE"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "[dry-run] would ensure: $HOOKS_DIR/ exists"
  echo "[dry-run] would symlink: $HOOK_TARGET -> $HOOK_SOURCE"
  if [[ -L "$HOOK_TARGET" ]]; then
    echo "[dry-run] current symlink: $(readlink "$HOOK_TARGET")"
  elif [[ -e "$HOOK_TARGET" ]]; then
    echo "[dry-run] current file exists (non-symlink)"
  else
    echo "[dry-run] no existing hook"
  fi
  exit 0
fi

mkdir -p "$HOOKS_DIR"

if [[ -L "$HOOK_TARGET" ]]; then
  CURRENT="$(readlink "$HOOK_TARGET")"
  if [[ "$CURRENT" == "$HOOK_SOURCE" ]]; then
    echo "✓ pre-commit hook already installed"
    exit 0
  fi
  echo "⚠ existing symlink replaced: $CURRENT -> $HOOK_SOURCE"
  rm "$HOOK_TARGET"
elif [[ -e "$HOOK_TARGET" ]]; then
  BACKUP="$HOOK_TARGET.bak-$(date +%s)"
  echo "⚠ existing pre-commit backed up: $HOOK_TARGET -> $BACKUP"
  mv "$HOOK_TARGET" "$BACKUP"
fi

ln -s "$HOOK_SOURCE" "$HOOK_TARGET"
echo "✓ pre-commit hook installed: $HOOK_TARGET -> $HOOK_SOURCE"
echo ""
echo "To verify: edit cli/twl/src/twl/autopilot/chain.py and run 'git commit'"
echo "To bypass: git commit --no-verify (user discretion)"
