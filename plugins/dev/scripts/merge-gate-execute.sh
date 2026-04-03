#!/bin/bash
# merge-gate-execute.sh
# merge-gate のマージ実行 / リジェクト（state-write.sh 統合版）
#
# モード:
#   (デフォルト)   squash merge + 状態遷移 + cleanup
#   --reject       リジェクト: merge-ready → failed + retry_count 記録
#   --reject-final 確定失敗: merge-ready → failed（リトライなし）
#
# 必須環境変数:
#   ISSUE      - Issue番号（数値）
#   PR_NUMBER  - PR番号
#   BRANCH     - ブランチ名
#
# オプション環境変数:
#   FINDING_SUMMARY   - リジェクト理由サマリー（--reject / --reject-final 時）
#   FIX_INSTRUCTIONS  - 修正指示テキスト（--reject 時）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "[merge-gate-execute] Error: jq が必要です" >&2
  exit 1
fi

# 必須環境変数バリデーション
if ! [[ "${ISSUE:-}" =~ ^[0-9]+$ ]]; then
  echo "[merge-gate-execute] Error: 不正なISSUE番号: ${ISSUE:-}" >&2
  exit 1
fi
if ! [[ "${PR_NUMBER:-}" =~ ^[0-9]+$ ]]; then
  echo "[merge-gate-execute] Error: 不正なPR_NUMBER: ${PR_NUMBER:-}" >&2
  exit 1
fi
if ! [[ "${BRANCH:-}" =~ ^[a-zA-Z0-9._/-]+$ ]]; then
  echo "[merge-gate-execute] Error: 不正なBRANCH名: ${BRANCH:-}" >&2
  exit 1
fi

MODE="${1:-merge}"
FINDING_SUMMARY="${FINDING_SUMMARY:-}"
FIX_INSTRUCTIONS="${FIX_INSTRUCTIONS:-}"

# クロスリポジトリ: REPO_OWNER/REPO_NAME が設定されていれば -R フラグを構築
GH_REPO_FLAG=""
if [[ -n "${REPO_OWNER:-}" && -n "${REPO_NAME:-}" ]]; then
  # owner/name フォーマット検証（引数インジェクション防止）
  if [[ ! "${REPO_OWNER}" =~ ^[a-zA-Z0-9_-]+$ ]]; then
    echo "[merge-gate-execute] Error: 不正な REPO_OWNER: ${REPO_OWNER}" >&2; exit 1
  fi
  if [[ ! "${REPO_NAME}" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "[merge-gate-execute] Error: 不正な REPO_NAME: ${REPO_NAME}" >&2; exit 1
  fi
  GH_REPO_FLAG="-R ${REPO_OWNER}/${REPO_NAME}"
fi

# CWD ガード: worktrees/ 配下からの実行を拒否（不変条件B/C）
cwd=$(pwd)
if [[ "$cwd" == */worktrees/* ]]; then
  echo "[merge-gate-execute] ERROR: worktrees/ 配下からの実行は禁止されています。main/ worktree から実行してください（不変条件B/C）" >&2
  exit 1
fi

# Worker ロール検出ガード（defense-in-depth）: autopilot Worker（tmux window 名 ap-#N）からの merge を拒否
# 注意: tmux window 名はユーザー変更可能。本ガードは多層防御の補助層であり、単独で認可判定を行わない
CURRENT_WINDOW=$(tmux display-message -p '#W' 2>/dev/null || echo "")
if [[ "$CURRENT_WINDOW" =~ ^ap-#[0-9]+$ ]]; then
  SANITIZED_WINDOW=$(printf '%s' "$CURRENT_WINDOW" | tr -cd '[:alnum:]#_-')
  echo "[merge-gate-execute] ERROR: autopilot Worker（${SANITIZED_WINDOW}）からの merge 実行は禁止されています（不変条件C）" >&2
  exit 1
fi

case "$MODE" in
  --reject)
    echo "[merge-gate] Issue #${ISSUE}: リジェクト（Critical/High 問題検出）" >&2
    # state-write.sh で failed に遷移
    bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE" --role pilot \
      --set status=failed \
      --set "failure={\"reason\":\"merge_gate_rejected\",\"details\":$(printf '%s' "$FINDING_SUMMARY" | jq -Rs .),\"step\":\"merge-gate\",\"retry_count\":1,\"fix_instructions\":$(printf '%s' "$FIX_INSTRUCTIONS" | jq -Rs .)}"
    ;;

  --reject-final)
    echo "[merge-gate] Issue #${ISSUE}: 確定失敗（2回目のリジェクト）" >&2
    bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE" --role pilot \
      --set status=failed \
      --set "failure={\"reason\":\"merge_gate_rejected_final\",\"details\":$(printf '%s' "$FINDING_SUMMARY" | jq -Rs .),\"step\":\"merge-gate\",\"retry_count\":2}"
    ;;

  *)
    # デフォルト: マージ実行

    # REPO_MODE 自動判定: git rev-parse --git-dir が .git 以外を返す場合は worktree
    GIT_DIR_PATH=$(git rev-parse --git-dir 2>/dev/null || echo "")
    if [ -z "$GIT_DIR_PATH" ]; then
      echo "[merge-gate-execute] Error: git リポジトリ外で実行されています" >&2
      exit 1
    elif [ "$GIT_DIR_PATH" = ".git" ]; then
      REPO_MODE="standard"
    else
      REPO_MODE="worktree"
    fi

    echo "[merge-gate] Issue #${ISSUE}: PR #${PR_NUMBER} のマージを実行... (REPO_MODE=${REPO_MODE})"
    MERGE_ERROR_LOG=$(mktemp /tmp/merge-error-XXXXXX.log)
    # shellcheck disable=SC2086
    if gh pr merge "$PR_NUMBER" $GH_REPO_FLAG --squash 2>"$MERGE_ERROR_LOG"; then
      # ブランチクリーンアップ（マージ成功後）
      if [ "$REPO_MODE" = "worktree" ]; then
        # worktree mode: worktree を先に削除してからブランチを削除
        WORKTREE_PATH=$(git worktree list --porcelain | awk -v target="branch refs/heads/${BRANCH}" '/^worktree / { wt=substr($0, 10) } $0 == target { print wt; exit }')
        if [ -n "$WORKTREE_PATH" ]; then
          if git worktree remove --force "$WORKTREE_PATH" 2>/dev/null; then
            echo "[merge-gate] Issue #${ISSUE}: worktree 削除成功: ${WORKTREE_PATH}"
          else
            echo "[merge-gate] Issue #${ISSUE}: ⚠️ worktree 削除失敗（マージは成功）: ${WORKTREE_PATH}" >&2
          fi
        fi
        # リモートブランチ削除
        if git push origin --delete "${BRANCH}" 2>/dev/null; then
          echo "[merge-gate] Issue #${ISSUE}: リモートブランチ削除成功: ${BRANCH}"
        else
          echo "[merge-gate] Issue #${ISSUE}: ⚠️ リモートブランチ削除失敗（マージは成功）: ${BRANCH}" >&2
        fi
      else
        # standard mode: 従来通りローカル+リモートブランチ削除
        git push origin --delete "${BRANCH}" 2>/dev/null || echo "[merge-gate] Issue #${ISSUE}: ⚠️ リモートブランチ削除失敗（マージは成功）" >&2
        git branch -D "${BRANCH}" 2>/dev/null || true
      fi

      # state-write.sh で done に遷移
      bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE" --role pilot \
        --set status=done \
        --set "merged_at=$(date -Is)"
      echo "[merge-gate] Issue #${ISSUE}: マージ + クリーンアップ完了"
      tmux kill-window -t "ap-#${ISSUE}" 2>/dev/null || true
      # Board アーカイブ（ISSUE_NUM が空の場合はスキップ）
      if [[ -n "${ISSUE:-}" ]]; then
        bash "$SCRIPT_DIR/chain-runner.sh" board-archive "$ISSUE" 2>/dev/null || true
      fi
    else
      # エラーメッセージから認証情報をマスキング
      ERROR_RAW=$(cat "$MERGE_ERROR_LOG" 2>/dev/null | sed -E 's/ghp_[a-zA-Z0-9]+/ghp_***MASKED***/g; s/Bearer [^ ]+/Bearer ***MASKED***/g' | head -c 500 || echo "unknown error")
      bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE" --role pilot \
        --set status=failed \
        --set "failure={\"reason\":\"merge_failed\",\"details\":$(printf '%s' "$ERROR_RAW" | jq -Rs .),\"step\":\"merge-gate\",\"pr\":\"#${PR_NUMBER}\"}"
      echo "[merge-gate] Issue #${ISSUE}: マージ失敗 - ${ERROR_RAW}" >&2
      rm -f "$MERGE_ERROR_LOG"
      exit 1
    fi
    rm -f "$MERGE_ERROR_LOG"
    ;;
esac
