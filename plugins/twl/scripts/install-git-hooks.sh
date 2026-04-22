#!/usr/bin/env bash
# install-git-hooks.sh — twl プロジェクトの git hooks をローカルに設置
#
# Usage:
#   bash plugins/twl/scripts/install-git-hooks.sh        # install (idempotent)
#   bash plugins/twl/scripts/install-git-hooks.sh --dry-run  # 差分のみ表示
#
# Hook: pre-commit
#   - chain.py / deps.yaml / chain-steps.sh 編集時に `twl check --deps-integrity` を実行
#   - errors 発生時 commit を abort (drift 再発防止, #868)
#   - --no-verify で bypass 可能 (user 裁量)
set -euo pipefail

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
  esac
done

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
