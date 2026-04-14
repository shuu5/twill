#!/usr/bin/env bash
# merge-gate-check-spawn.sh - spawn 完了確認（merge-gate Step: spawn 完了確認）
#
# 全 specialist の spawn 完了を確認する。未 spawn があれば ERROR を出力して exit 1。
# 環境変数 MANIFEST_FILE, SPAWNED_FILE が必要（merge-gate-build-manifest.sh で設定済み）。
#
# 呼び出し: bash "${CLAUDE_PLUGIN_ROOT}/scripts/merge-gate-check-spawn.sh"

set -euo pipefail

if [[ -f "$MANIFEST_FILE" ]]; then
  MISSING=$(comm -23 \
    <(grep -v '^#' "$MANIFEST_FILE" | grep -v '^[[:space:]]*$' | sed 's|^twl:twl:||' | sort -u) \
    <(sort -u "$SPAWNED_FILE" 2>/dev/null || true))
  if [[ -n "$MISSING" ]]; then
    echo "ERROR: 以下の specialist が未 spawn:"
    echo "$MISSING"
    echo "未 spawn の specialist を追加 spawn してから結果集約に進むこと"
    exit 1
  fi
  echo "✓ 全 specialist spawn 完了確認済み"
fi
