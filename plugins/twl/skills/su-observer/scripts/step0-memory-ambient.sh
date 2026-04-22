#!/usr/bin/env bash
# step0-memory-ambient.sh: ambient-hints.md の TTL チェックと書き込み
# Purpose: doobidoo tag 検索結果を .supervisor/ambient-hints.md にキャッシュし、
#          Step 0 で個別 MCP 検索を 1 Read に短縮する
# Environment:
#   SUPERVISOR_DIR  (default: .supervisor)  : ambient-hints.md 出力先
#   AMBIENT_TTL_SEC (default: 86400)        : TTL in seconds (24h)
# Modes:
#   (default / --check)  exit 0=FRESH, exit 1=STALE or MISSING
#   --write              stdin を ambient-hints.md に書き込み（TTL リセット）
# Output (check mode):
#   "FRESH"  : キャッシュ有効
#   "STALE"  : 古いか不在、LLM は mcp__doobidoo__memory_search を実行して --write で保存すること

set -euo pipefail

SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
AMBIENT_TTL_SEC="${AMBIENT_TTL_SEC:-86400}"
HINTS_FILE="${SUPERVISOR_DIR}/ambient-hints.md"
MODE="${1:-}"

_is_fresh() {
  [[ -f "$HINTS_FILE" ]] || return 1
  local file_mtime now elapsed
  file_mtime=$(stat -c %Y "$HINTS_FILE" 2>/dev/null || echo 0)
  now=$(date +%s)
  elapsed=$(( now - file_mtime ))
  [[ $elapsed -lt $AMBIENT_TTL_SEC ]]
}

case "$MODE" in
  --write)
    mkdir -p "$SUPERVISOR_DIR"
    cat > "$HINTS_FILE"
    echo "[step0-memory-ambient] ambient-hints.md を更新しました: $HINTS_FILE"
    exit 0
    ;;
  --check | "")
    if _is_fresh; then
      echo "FRESH"
      exit 0
    else
      echo "STALE"
      exit 1
    fi
    ;;
  *)
    echo "[step0-memory-ambient] 不明なオプション: $MODE" >&2
    echo "Usage: $0 [--check | --write]" >&2
    exit 2
    ;;
esac
