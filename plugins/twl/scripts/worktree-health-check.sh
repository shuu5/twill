#!/usr/bin/env bash
# worktree-health-check.sh — bare repo / worktree の remote.origin.fetch refspec 検査
#
# 責務: refspec 欠落の検出と自動修復（chain停止検知の health-check.sh とは別責務）
#
# Usage:
#   worktree-health-check.sh [--fix] [--bare-root <path>] [--skip-remote-check]
#
# Options:
#   --fix               欠落 refspec を自動修復（git config --replace-all）
#   --bare-root <path>  bare repo パスを明示指定（省略時は自動検出）
#   --skip-remote-check git ls-remote によるリモート tip 比較をスキップ
#
# Exit codes:
#   0  全 OK（または --fix で修復完了）
#   1  refspec 欠落が検出された（--fix なし）

set -uo pipefail

REQUIRED_REFSPEC='+refs/heads/*:refs/remotes/origin/*'
FIX_MODE=0
BARE_ROOT_OVERRIDE=""
SKIP_REMOTE_CHECK=0
WARN_COUNT=0

# ---------------------------------------------------------------------------
# 引数パース
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)                FIX_MODE=1; shift ;;
    --bare-root)          BARE_ROOT_OVERRIDE="$2"; shift 2 ;;
    --skip-remote-check)  SKIP_REMOTE_CHECK=1; shift ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--fix] [--bare-root <path>] [--skip-remote-check]

Checks remote.origin.fetch refspec for bare repo and all worktrees.

Options:
  --fix               Auto-repair missing refspecs (git config --replace-all)
  --bare-root <path>  Override bare repo path (default: auto-detect)
  --skip-remote-check Skip git ls-remote tip comparison
EOF
      exit 0
      ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------------------
# bare root 検出
# ---------------------------------------------------------------------------
_find_bare_root() {
  # 1. 明示指定があればそれを使う
  if [[ -n "$BARE_ROOT_OVERRIDE" ]]; then
    echo "$BARE_ROOT_OVERRIDE"
    return 0
  fi

  # 2. CWD から .git を辿り bare repo を検出
  local current="$PWD"
  while [[ "$current" != "/" ]]; do
    # worktree の .git ファイルが bare repo を指している場合
    if [[ -f "$current/.git" ]]; then
      local gitdir
      local gitdir
      gitdir=$(sed 's/^gitdir: //' "$current/.git" | tr -d '[:space:]')
      # .bare/ 構造: gitdir は絶対パスまたは $current 基準の相対パス
      local bare_candidate
      if [[ "$gitdir" = /* ]]; then
        bare_candidate="$gitdir"
      else
        # 相対パスは .git ファイルが存在する $current を基準に解決する
        bare_candidate="$(cd "$current" && realpath "$gitdir" 2>/dev/null || echo "")"
      fi
      # worktrees/ サブディレクトリを除いた bare root
      bare_candidate="${bare_candidate%/worktrees/*}"
      if [[ -d "$bare_candidate" ]]; then
        echo "$bare_candidate"
        return 0
      fi
    fi
    current="$(dirname "$current")"
  done

  # 3. フォールバック: CWD 自体が bare repo
  if git -C "$PWD" rev-parse --is-bare-repository 2>/dev/null | grep -q "^true$"; then
    echo "$PWD"
    return 0
  fi

  echo ""
  return 1
}

# ---------------------------------------------------------------------------
# 単一ディレクトリの refspec チェック
# ---------------------------------------------------------------------------
_check_refspec() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi

  local current_fetch
  current_fetch=$(git -C "$dir" config --get-all remote.origin.fetch 2>/dev/null || true)

  if echo "$current_fetch" | grep -qF "$REQUIRED_REFSPEC"; then
    echo "OK: $dir — remote.origin.fetch OK"
    return 0
  fi

  if [[ "$FIX_MODE" -eq 1 ]]; then
    git -C "$dir" config --replace-all remote.origin.fetch "$REQUIRED_REFSPEC" 2>/dev/null || true
    echo "FIXED: $dir — remote.origin.fetch set to $REQUIRED_REFSPEC"
    return 0
  else
    echo "WARN: $dir — remote.origin.fetch missing required refspec ($REQUIRED_REFSPEC)"
    WARN_COUNT=$((WARN_COUNT + 1))
    return 0
  fi
}

# ---------------------------------------------------------------------------
# メイン: bare root 検出 → 全 worktree 列挙 → チェック
# ---------------------------------------------------------------------------
BARE_ROOT=$(_find_bare_root || true)

if [[ -z "$BARE_ROOT" ]]; then
  echo "WARN: bare repo root を自動検出できませんでした。CWD のみをチェックします。" >&2
  _check_refspec "$PWD"
else
  # bare repo 本体の config をチェック
  _check_refspec "$BARE_ROOT"

  # git worktree list --porcelain で全 worktree を列挙
  while IFS= read -r line; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
      local_wt="${BASH_REMATCH[1]}"
      # bare root 自体は既にチェック済みなのでスキップ
      [[ "$local_wt" == "$BARE_ROOT" ]] && continue
      _check_refspec "$local_wt"
    fi
  done < <(git -C "$BARE_ROOT" worktree list --porcelain 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# オプション: remote tip との比較（ネットワーク利用可能時のみ）
# ---------------------------------------------------------------------------
if [[ "$SKIP_REMOTE_CHECK" -eq 0 ]]; then
  LOCAL_TIP=$(git -C "${BARE_ROOT:-$PWD}" show-ref refs/remotes/origin/main 2>/dev/null | awk '{print $1}' || true)
  if [[ -n "$LOCAL_TIP" ]]; then
    REMOTE_TIP=$(timeout 5 git -C "${BARE_ROOT:-$PWD}" ls-remote origin main 2>/dev/null | awk '{print $1}' || true)
    if [[ -n "$REMOTE_TIP" && "$LOCAL_TIP" != "$REMOTE_TIP" ]]; then
      echo "WARN: origin/main is stale (local=$LOCAL_TIP remote=$REMOTE_TIP) — run: git fetch origin"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 結果
# ---------------------------------------------------------------------------
if [[ "$WARN_COUNT" -gt 0 ]]; then
  exit 1
fi
exit 0
