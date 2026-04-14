#!/usr/bin/env bash
# merge-gate-build-manifest.sh - 動的レビュアー構築（merge-gate Step: 動的レビュアー構築）
#
# specialist マニフェストを構築し MANIFEST_FILE, CONTEXT_ID, SPAWNED_FILE を設定する。
# このスクリプトは source で読み込むこと（変数を親シェルへ export するため）。
#
# 呼び出し: source "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-build-manifest.sh"

# origin/main が解決できない場合のフォールバック付き (Issue #198)
if ! SPECIALISTS=$(git diff --name-only origin/main 2>/dev/null | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate); then
  echo "WARN: origin/main not found, falling back to FETCH_HEAD" >&2
  git fetch origin main
  SPECIALISTS=$(git diff --name-only FETCH_HEAD | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate)
fi
MANIFEST_FILE=$(mktemp /tmp/.specialist-manifest-merge-gate-XXXXXXXX.txt)
chmod 600 "$MANIFEST_FILE"
CONTEXT_ID=$(basename "$MANIFEST_FILE" .txt | sed 's/^\.specialist-manifest-//')
SPAWNED_FILE="/tmp/.specialist-spawned-${CONTEXT_ID}.txt"
echo "$SPECIALISTS" > "$MANIFEST_FILE"
trap 'rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"' EXIT
