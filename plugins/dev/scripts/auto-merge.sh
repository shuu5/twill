#!/usr/bin/env bash
# auto-merge.sh - autopilot-first auto-merge（4 Layer ガード付き）
#
# 不変条件 C（Worker マージ禁止）を機械的に担保する。
# LLM 解釈実行を排除し、全ロジックを bash で決定的に実行。
#
# Layer 順序（安価なガードを先に配置）:
#   Layer 2: CWD ガード（worktrees/ 配下実行拒否）
#   Layer 3: tmux window ガード（ap-#N パターン検出）
#   Layer 1: IS_AUTOPILOT 判定（state-read.sh）
#   Layer 4: フォールバック（issue-{N}.json 直接存在確認）
#
# Usage:
#   bash scripts/auto-merge.sh --issue N --pr N --branch BRANCH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") --issue <N> --pr <N> --branch <BRANCH>

auto-merge を実行する（autopilot-first、4 Layer ガード付き）。

Options:
  --issue <N>       Issue 番号（正の整数、必須）
  --pr <N>          PR 番号（正の整数、必須）
  --branch <BRANCH> ブランチ名（必須）
  -h, --help        このヘルプを表示
EOF
}

# --- 引数解析 ---
ISSUE_NUM=""
PR_NUMBER=""
BRANCH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)  ISSUE_NUM="$2"; shift 2 ;;
    --pr)     PR_NUMBER="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[auto-merge] Error: 不明な引数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# --- 引数バリデーション ---
if [[ -z "$ISSUE_NUM" || -z "$PR_NUMBER" || -z "$BRANCH" ]]; then
  echo "[auto-merge] Error: --issue, --pr, --branch は全て必須です" >&2
  usage >&2
  exit 1
fi

if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
  echo "[auto-merge] Error: 不正な Issue 番号: $ISSUE_NUM" >&2
  exit 1
fi

if ! [[ "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "[auto-merge] Error: 不正な PR 番号: $PR_NUMBER" >&2
  exit 1
fi

if ! [[ "$BRANCH" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
  echo "[auto-merge] Error: 不正なブランチ名: $BRANCH" >&2
  exit 1
fi

# ============================================================
# Layer 2: CWD ガード（worktrees/ 配下からの実行を拒否）
# ============================================================
cwd=$(pwd)
if [[ "$cwd" == */worktrees/* ]]; then
  echo "[auto-merge] ERROR: worktrees/ 配下からの実行は禁止されています。main/ worktree から実行してください（不変条件B/C）" >&2
  exit 1
fi

# ============================================================
# Layer 3: tmux window ガード（autopilot Worker window からの merge を拒否）
# ============================================================
CURRENT_WINDOW=$(tmux display-message -p '#W' 2>/dev/null || echo "")
if [[ "$CURRENT_WINDOW" =~ ^ap-#[0-9]+$ ]]; then
  SANITIZED_WINDOW=$(printf '%s' "$CURRENT_WINDOW" | tr -cd '[:alnum:]#_-')
  echo "[auto-merge] ERROR: autopilot Worker（${SANITIZED_WINDOW}）からの merge 実行は禁止されています（不変条件C）" >&2
  exit 1
fi

# ============================================================
# Layer 1: IS_AUTOPILOT 判定（state-read.sh）
# ============================================================
IS_AUTOPILOT=false
AUTOPILOT_STATUS=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
if [[ "$AUTOPILOT_STATUS" == "running" ]]; then
  IS_AUTOPILOT=true
fi

# ============================================================
# Layer 4: フォールバックガード（issue-{N}.json 直接存在確認）
# state-read.sh では false だが、issue-{N}.json が存在する場合の安全弁
# ============================================================
if [[ "$IS_AUTOPILOT" == "false" ]]; then
  MAIN_WORKTREE_PATH="$(git worktree list --porcelain | awk '/^worktree / { wt=substr($0,10) } /branch refs\/heads\/main$/ { print wt; exit }')"
  if [[ -n "$MAIN_WORKTREE_PATH" ]]; then
    MAIN_AUTOPILOT_DIR="${MAIN_WORKTREE_PATH}/.autopilot"
    if [[ -f "${MAIN_AUTOPILOT_DIR}/issues/issue-${ISSUE_NUM}.json" ]]; then
      echo "[auto-merge] ⚠️ フォールバックガード発動: issue-${ISSUE_NUM}.json が存在するため merge を禁止" >&2
      bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready
      echo "[auto-merge] autopilot 配下（フォールバック検出）: merge-ready 宣言。Pilot による merge-gate を待機。"
      exit 0
    fi
  fi
fi

# ============================================================
# autopilot 配下: merge-ready 宣言のみ（merge 禁止）
# ============================================================
if [[ "$IS_AUTOPILOT" == "true" ]]; then
  bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready
  echo "[auto-merge] autopilot 配下: merge-ready 宣言。Pilot による merge-gate を待機。"
  exit 0
fi

# ============================================================
# 非 autopilot: squash merge 実行
# ============================================================
echo "[auto-merge] Issue #${ISSUE_NUM}: PR #${PR_NUMBER} の squash merge を実行..."

MERGE_ERROR_LOG=$(mktemp /tmp/auto-merge-error-XXXXXX.log)
trap 'rm -f "${MERGE_ERROR_LOG:-}"' EXIT
if ! gh pr merge "$PR_NUMBER" --squash 2>"$MERGE_ERROR_LOG"; then
  ERROR_RAW=$(sed -E 's/ghp_[a-zA-Z0-9]+/ghp_***MASKED***/g; s/Bearer [^ ]+/Bearer ***MASKED***/g' "$MERGE_ERROR_LOG" | head -c 500)
  echo "[auto-merge] Error: merge 失敗 - ${ERROR_RAW}" >&2
  rm -f "$MERGE_ERROR_LOG"
  exit 1
fi
rm -f "$MERGE_ERROR_LOG"

echo "[auto-merge] Issue #${ISSUE_NUM}: merge 成功"

# ============================================================
# 非 autopilot: OpenSpec archive（存在時のみ）
# ============================================================
if ! git checkout main 2>/dev/null || ! git pull origin main 2>/dev/null; then
  echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ git checkout main / pull 失敗（merge は成功済み）" >&2
fi

CHANGE_ID=$(ls openspec/changes/ 2>/dev/null | grep -v archive | head -1)
if [[ -n "${CHANGE_ID}" ]]; then
  if deltaspec archive "${CHANGE_ID}" --yes --skip-specs 2>/dev/null; then
    echo "[auto-merge] Issue #${ISSUE_NUM}: OpenSpec archive 完了: ${CHANGE_ID}"
  else
    echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ OpenSpec archive 失敗（merge は成功済み）" >&2
  fi
fi

# ============================================================
# 非 autopilot: worktree 削除 + ブランチ削除（cleanup）
# ============================================================
# REPO_MODE 自動判定
GIT_DIR_PATH=$(git rev-parse --git-dir 2>/dev/null || echo "")
if [[ "$GIT_DIR_PATH" == ".git" ]]; then
  REPO_MODE="standard"
else
  REPO_MODE="worktree"
fi

if [[ "$REPO_MODE" == "worktree" ]]; then
  WORKTREE_PATH=$(git worktree list --porcelain | awk -v target="branch refs/heads/${BRANCH}" '/^worktree / { wt=substr($0, 10) } $0 == target { print wt; exit }')
  if [[ -n "$WORKTREE_PATH" ]]; then
    if git worktree remove --force "$WORKTREE_PATH" 2>/dev/null; then
      echo "[auto-merge] Issue #${ISSUE_NUM}: worktree 削除成功: ${WORKTREE_PATH}"
    else
      echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ worktree 削除失敗（merge は成功済み）" >&2
    fi
  fi
  if git push origin --delete "${BRANCH}" 2>/dev/null; then
    echo "[auto-merge] Issue #${ISSUE_NUM}: リモートブランチ削除成功: ${BRANCH}"
  else
    echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ リモートブランチ削除失敗（merge は成功済み）" >&2
  fi
else
  git push origin --delete "${BRANCH}" 2>/dev/null || echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ リモートブランチ削除失敗（merge は成功済み）" >&2
  git branch -D "${BRANCH}" 2>/dev/null || true
fi

echo "[auto-merge] Issue #${ISSUE_NUM}: auto-merge 完了"
