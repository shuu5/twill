#!/bin/bash
# merge-gate-init.sh
# merge-gate の初期化: ISSUE バリデーション + 状態ファイル読み取り + PR差分取得
#
# 必須環境変数:
#   ISSUE      - Issue番号（数値）
#
# 出力:
#   stdout に eval 可能な変数定義を出力:
#     PR_NUMBER, BRANCH, RETRY_COUNT, PR_DIFF_FILE, PR_FILES, GATE_TYPE, PLUGIN_NAMES

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ISSUE バリデーション
if ! [[ "${ISSUE:-}" =~ ^[0-9]+$ ]]; then
  echo "[merge-gate] Error: 不正なISSUE番号: ${ISSUE:-}" >&2
  exit 1
fi

# state-read.sh で status 確認
STATUS=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE" --field status 2>/dev/null || true)

if [ "$STATUS" != "merge-ready" ]; then
  echo "[merge-gate] Error: Issue #${ISSUE} の status が merge-ready ではありません (status=${STATUS:-unknown})" >&2
  exit 1
fi

# PR番号・ブランチ名を state-read.sh で取得
PR_NUMBER=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE" --field pr 2>/dev/null || true)
BRANCH_RAW=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE" --field branch 2>/dev/null || true)

# BRANCH バリデーション（英数字、ハイフン、スラッシュ、ドット、アンダースコアのみ許可）
if [[ "$BRANCH_RAW" =~ ^[a-zA-Z0-9/_.-]+$ ]]; then
  BRANCH="$BRANCH_RAW"
else
  echo "[merge-gate] Warning: BRANCH に不正文字検出、サニタイズ適用" >&2
  BRANCH=$(printf '%s' "$BRANCH_RAW" | tr -cd 'a-zA-Z0-9/_.-')
fi

if [ -z "$PR_NUMBER" ]; then
  echo "[merge-gate] Error: PR番号取得失敗 (Issue #${ISSUE})" >&2
  bash "$SCRIPT_DIR/state-write.sh" --type issue --issue "$ISSUE" --role pilot \
    --set status=failed \
    --set 'failure={"reason":"merge_failed","details":"PR number not found in state file","step":"merge-gate"}' 2>/dev/null || true
  exit 1
fi

# リトライカウント確認
RETRY_COUNT=$(bash "$SCRIPT_DIR/state-read.sh" --type issue --issue "$ISSUE" --field retry_count 2>/dev/null || echo "0")
if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]]; then
  RETRY_COUNT=0
fi

echo "[merge-gate] Issue #${ISSUE}: PR #${PR_NUMBER} のインテリジェントレビューを開始..." >&2

# PR差分取得
PR_DIFF_FILE="/tmp/merge-gate-diff-${ISSUE}.txt"
PR_FILES_RAW=""

if gh pr diff "$PR_NUMBER" > "$PR_DIFF_FILE" 2>/tmp/merge-gate-diff-error-${ISSUE}.log; then
  PR_FILES_RAW=$(gh pr diff "$PR_NUMBER" --name-only 2>/dev/null || true)
else
  echo "[merge-gate] Warning: PR差分取得失敗 — フォールバック可能" >&2
  : > "$PR_DIFF_FILE"
fi

# GATE_TYPE 判定（PR差分のファイルパスからプロジェクトタイプを自動検出）
GATE_TYPE="standard"
if [ -n "$PR_FILES_RAW" ]; then
  # PLUGIN_NAMES バリデーション（英数字、ハイフン、アンダースコアのみ許可）
  PLUGIN_NAMES=$(echo "$PR_FILES_RAW" | grep -oP 'plugins/\K[^/]+' | sort -u | grep -E '^[a-zA-Z0-9_-]+$' || true)
  for name in $PLUGIN_NAMES; do
    if [ -f "plugins/${name}/deps.yaml" ]; then
      GATE_TYPE="plugin"
      break
    fi
  done
  if [ "$GATE_TYPE" = "plugin" ]; then
    echo "[merge-gate] GATE_TYPE=plugin 対象プラグイン: ${PLUGIN_NAMES}" >&2
  else
    echo "[merge-gate] GATE_TYPE=standard" >&2
  fi
else
  PLUGIN_NAMES=""
fi

# eval 可能な形式で出力（printf %q で安全にエスケープ）
PR_FILES_FLAT=$(printf '%s' "$PR_FILES_RAW" | tr '\n' ' ')
printf 'PR_NUMBER=%q\n' "$PR_NUMBER"
printf 'BRANCH=%q\n' "$BRANCH"
printf 'RETRY_COUNT=%q\n' "$RETRY_COUNT"
printf 'PR_DIFF_FILE=%q\n' "$PR_DIFF_FILE"
printf 'PR_FILES=%q\n' "$PR_FILES_FLAT"
printf 'GATE_TYPE=%q\n' "$GATE_TYPE"
printf 'PLUGIN_NAMES=%q\n' "$PLUGIN_NAMES"
