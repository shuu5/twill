#!/usr/bin/env bash
# worktree-delete.sh - worktree + ブランチ削除（Pilot 専任、不変条件 B）
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") <branch-name>

指定した worktree とブランチを削除する。
Pilot (main/) からのみ実行可能。Worker (worktrees/) からの実行は拒否される。

Options:
  -h, --help  このヘルプを表示
EOF
}

if [[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

branch="$1"

# ── branch 入力バリデーション（パストラバーサル防止） ──
if [[ "$branch" =~ \.\. || "$branch" =~ ^/ || ! "$branch" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
  echo "ERROR: 不正なブランチ名: $branch（パストラバーサルは禁止）" >&2
  exit 1
fi

# ── CWD ガード（不変条件 B: Worktree 削除 Pilot 専任） ──
cwd="$(pwd)"

# worktrees/ 配下からの実行を拒否
if [[ "$cwd" == */worktrees/* ]]; then
  echo "ERROR: Worker (worktrees/ 配下) からの worktree 削除は禁止されています（不変条件 B）" >&2
  echo "  CWD: $cwd" >&2
  echo "  worktree 削除は Pilot (main/) から実行してください" >&2
  exit 1
fi

# main/ 配下であることを確認
if [[ ! -f "$cwd/.git" ]] || ! grep -q "worktrees/main" "$cwd/.git" 2>/dev/null; then
  # .git がファイルで main worktree を指しているか確認（緩い検証）
  if [[ ! -f "$cwd/.git" ]]; then
    echo "WARN: main worktree の確認ができません。続行します" >&2
  fi
fi

# プロジェクトルート検出
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# bare repo のルートを特定（CWD の .git を優先、不在時は git rev-parse fallback）
bare_root=""
if [[ -f "$cwd/.git" ]]; then
  gitdir=$(sed 's/^gitdir: //' "$cwd/.git")
  if [[ "$gitdir" != /* ]]; then
    echo "ERROR: gitdir は絶対パスである必要があります" >&2
    exit 1
  fi
  if [[ "$gitdir" =~ (^|/)\.\.(/|$) ]]; then
    echo "ERROR: gitdir 値に不正なパスコンポーネント (..) が含まれています" >&2
    exit 1
  fi
  # .bare を含むパスからプロジェクトルートを推定
  # gitdir が /path/.bare で終わる場合と /path/.bare/worktrees/xxx の場合の両方に対応
  if [[ "$gitdir" =~ /\.bare$ ]]; then
    bare_root="${gitdir%/.bare}/"
  else
    bare_root=$(echo "$gitdir" | sed 's|/\.bare/.*|/|')
  fi
else
  # fallback: git rev-parse --git-common-dir で bare root を検索
  fb_gitdir=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  if [[ -n "$fb_gitdir" && ! "$fb_gitdir" =~ \.\. ]]; then
    if [[ "$fb_gitdir" =~ /\.bare$ ]]; then
      bare_root="${fb_gitdir%/.bare}/"
    elif [[ "$fb_gitdir" =~ /\.bare/ ]]; then
      bare_root=$(echo "$fb_gitdir" | sed 's|/\.bare/.*|/|')
    fi
  fi
  if [[ -n "$bare_root" ]]; then
    echo "WARN: cwd/.git 不在のため git rev-parse fallback で bare_root を解決: $bare_root" >&2
  fi
fi

worktree_path=""
if [[ -n "$bare_root" ]]; then
  worktree_path="${bare_root}worktrees/${branch}"
else
  echo "ERROR: bare repo ルートを特定できません。worktree 削除を中止します" >&2
  exit 1
fi

# 自身の worktree を削除しようとしていないか確認
if [[ "$cwd" == "$worktree_path"* ]]; then
  echo "ERROR: 自身の CWD が削除対象に含まれています" >&2
  exit 1
fi

# teardown フック実行（削除前）
if [[ -d "$worktree_path" ]]; then
  python3 -m twl.autopilot.worktree teardown-hook "$worktree_path" || true
fi

# worktree 削除
if [[ -d "$worktree_path" ]]; then
  git worktree remove "$worktree_path" --force 2>/dev/null || {
    echo "WARN: git worktree remove に失敗。手動で削除します" >&2
    rm -rf "$worktree_path"
  }
  echo "OK: worktree を削除しました: $worktree_path"
else
  echo "WARN: worktree が存在しません: $worktree_path" >&2
fi

# ブランチ削除（ローカル）
if git branch --list "$branch" | grep -q "$branch"; then
  git branch -D "$branch" 2>/dev/null || echo "WARN: ブランチ削除に失敗: $branch" >&2
  echo "OK: ブランチを削除しました: $branch"
fi
