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
# shellcheck source=./lib/python-env.sh
source "${SCRIPT_DIR}/lib/python-env.sh"

# AUTOPILOT_DIR を解決（env var 優先、未設定時は main worktree から推定）
resolve_autopilot_dir() {
  if [[ -n "${AUTOPILOT_DIR:-}" ]]; then
    echo "$AUTOPILOT_DIR"
    return
  fi
  # main ブランチの worktree を探す（bare / null-HEAD エントリをスキップ）
  local main_wt
  main_wt=$(git worktree list --porcelain | awk '
    /^worktree /{ wt=substr($0,10) }
    /^HEAD 0{40}$/{ wt="" }
    /^bare$/{ wt="" }
    /^branch refs\/heads\/main$/{ if(wt!="") { print wt; exit } }
  ')
  if [[ -z "$main_wt" ]]; then
    # main ブランチが見つからない場合は最初の real worktree
    main_wt=$(git worktree list --porcelain | awk '
      /^worktree /{ wt=substr($0,10) }
      /^HEAD 0{40}$/{ wt="" }
      /^bare$/{ wt="" }
      /^branch /{ if(wt!="") { print wt; exit } }
    ')
  fi
  echo "${main_wt:-.}/.autopilot"
}

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
# Layer 2.5: Quick mode terminal guard (#671)
# quick mode で current_step=ac-verify の場合、Worker が走り抜けて
# auto-merge を呼んでも拒否する。merge は workflow-pr-merge が担当。
# ============================================================
IS_QUICK=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --field is_quick 2>/dev/null || echo "")
CURRENT_STEP=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --field current_step 2>/dev/null || echo "")
if [[ "$IS_QUICK" == "true" && "$CURRENT_STEP" == "ac-verify" ]]; then
  echo "[auto-merge] GUARD: quick mode terminal step (ac-verify) — auto-merge を拒否 (#671)" >&2
  echo "[auto-merge] merge は workflow-pr-merge が担当します。" >&2
  python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready --set "pr=$PR_NUMBER" --set "branch=$BRANCH" 2>/dev/null || true
  exit 0
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
AUTOPILOT_STATUS=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --field status 2>/dev/null || echo "")
if [[ "$AUTOPILOT_STATUS" == "running" || "$AUTOPILOT_STATUS" == "merge-ready" ]]; then
  IS_AUTOPILOT=true
fi

# 矛盾状態フォールバック: IS_AUTOPILOT=false だが AUTOPILOT_STATUS=running の場合（不変条件C 防御）
# 現行ロジックでは AUTOPILOT_STATUS=running → IS_AUTOPILOT=true のため通常発生しない。
# 将来のリファクタリング時の安全弁として、矛盾を検出した場合は merge を中止する。
if [[ "$IS_AUTOPILOT" == "false" && "$AUTOPILOT_STATUS" == "running" ]]; then
  echo "[auto-merge] ⚠️ 状態矛盾検出: IS_AUTOPILOT=false だが status=running" >&2
  python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready --set "pr=$PR_NUMBER" --set "branch=$BRANCH" 2>/dev/null || true
  echo "[auto-merge] autopilot 配下（状態矛盾検出）: merge-ready 宣言。Pilot による merge-gate を待機。"
  exit 0
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
      python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready --set "pr=$PR_NUMBER" --set "branch=$BRANCH" 2>/dev/null || true
      echo "[auto-merge] autopilot 配下（フォールバック検出）: merge-ready 宣言。Pilot による merge-gate を待機。"
      exit 0
    fi
  fi
fi

# ============================================================
# autopilot 配下: merge-ready 宣言のみ（merge 禁止）
# ============================================================
if [[ "$IS_AUTOPILOT" == "true" ]]; then
  python3 -m twl.autopilot.state write --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --role worker --set status=merge-ready --set "pr=$PR_NUMBER" --set "branch=$BRANCH" 2>/dev/null || true
  echo "[auto-merge] autopilot 配下: merge-ready 宣言。Pilot による merge-gate を待機。"
  exit 0
fi

# ============================================================
# 非 autopilot: squash merge 実行
# ============================================================
echo "[auto-merge] Issue #${ISSUE_NUM}: PR #${PR_NUMBER} の squash merge を実行..."

# #872: DEV_AUTOPILOT_MERGEABILITY_PRECHECK=true 時、mergeStateStatus 事前確認で
# branch protection block を fail-fast (C4 対策)。
if [[ "${DEV_AUTOPILOT_MERGEABILITY_PRECHECK:-false}" == "true" ]]; then
  MERGE_STATE=$(gh pr view "$PR_NUMBER" --json mergeStateStatus --jq '.mergeStateStatus' 2>/dev/null || echo "")
  case "$MERGE_STATE" in
    BLOCKED|UNSTABLE|BEHIND)
      echo "[auto-merge] ⚠️ branch protection block: mergeStateStatus=$MERGE_STATE (Pilot 介入が必要)" >&2
      exit 1
      ;;
  esac
fi

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

if ! git checkout main 2>/dev/null || ! git pull origin main 2>/dev/null; then
  echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ git checkout main / pull 失敗（merge は成功済み）" >&2
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
    # #924: main worktree 保護 guard（Phase Z Wave B 事故の再発防止）
    # sanity check 1: ブランチ名が main なら削除禁止
    if [[ "$BRANCH" == "main" ]]; then
      echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ GUARD: branch=main の worktree 削除をスキップ (#924)" >&2
      WORKTREE_PATH=""
    else
      # sanity check 2: 削除対象パスが primary worktree（bare でない最初のエントリ）と一致したら削除禁止
      # main branch が feat branch にチェックアウト済みの場合も保護できる（#924 事故の直接原因）。
      PRIMARY_WORKTREE_PATH=$(git worktree list --porcelain | awk '
        /^worktree /{ wt=substr($0,10) }
        /^HEAD 0{40}$/{ wt="" }
        /^bare$/{ wt="" }
        /^branch /{ if(wt!="") { print wt; exit } }
      ')
      if [[ -n "$PRIMARY_WORKTREE_PATH" && "$WORKTREE_PATH" == "$PRIMARY_WORKTREE_PATH" ]]; then
        echo "[auto-merge] Issue #${ISSUE_NUM}: ⚠️ GUARD: 削除対象が main worktree (${WORKTREE_PATH}) と一致 — 削除をスキップ (#924)" >&2
        WORKTREE_PATH=""
      fi
    fi
  fi
  if [[ -n "$WORKTREE_PATH" ]]; then
    # #898: Worker window 生存確認 + kill (worktree 削除前の cwd 消失事故防止)
    # 不変条件 B の defensive 実装: 呼び手 (_cleanup_worker) が Worker window kill を
    # skip していた場合でも、auto-merge.sh 自身が safety net として機能する。
    WORKER_WINDOW=$(python3 -m twl.autopilot.state read --autopilot-dir "$(resolve_autopilot_dir)" --type issue --issue "$ISSUE_NUM" --field window 2>/dev/null || echo "")
    if [[ -n "$WORKER_WINDOW" ]] && tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -qxF "$WORKER_WINDOW"; then
      echo "[auto-merge] Issue #${ISSUE_NUM}: Worker window (${WORKER_WINDOW}) 生存確認 — worktree 削除前に kill"
      if ! tmux kill-window -t "$WORKER_WINDOW" 2>/dev/null; then
        echo "[auto-merge] Issue #${ISSUE_NUM}: ERROR: Worker window kill 失敗 — worktree 削除中止 (unsafe state)" >&2
        exit 1
      fi
    fi
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
