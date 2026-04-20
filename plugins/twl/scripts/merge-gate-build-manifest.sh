#!/usr/bin/env bash
# merge-gate-build-manifest.sh - 動的レビュアー構築（merge-gate Step: 動的レビュアー構築）
#
# specialist マニフェストを構築し MANIFEST_FILE, SPAWNED_FILE を export 形式で stdout に出力する。
# bash 実行（サブシェル）を前提とする。
#
# 呼び出し: eval "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-build-manifest.sh")"
#           trap 'rm -f "$MANIFEST_FILE" "$SPAWNED_FILE"' EXIT
set -euo pipefail

# origin/main が解決できない場合のフォールバック付き (Issue #198)
if ! SPECIALISTS=$(git diff --name-only origin/main 2>/dev/null | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate); then
  echo "WARN: origin/main not found, falling back to FETCH_HEAD" >&2
  git fetch origin main
  SPECIALISTS=$(git diff --name-only FETCH_HEAD | bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-review-manifest.sh" --mode merge-gate)
fi
MANIFEST_FILE=$(mktemp /tmp/.specialist-manifest-merge-gate-XXXXXXXX.txt)
chmod 600 "$MANIFEST_FILE"
SPAWNED_FILE=$(mktemp /tmp/.specialist-spawned-XXXXXXXX.txt)
chmod 600 "$SPAWNED_FILE"
echo "$SPECIALISTS" > "$MANIFEST_FILE"
cat <<EOF
export MANIFEST_FILE='${MANIFEST_FILE}'
export SPAWNED_FILE='${SPAWNED_FILE}'
EOF
