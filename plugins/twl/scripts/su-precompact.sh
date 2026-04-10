#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
[ -d "$SUPERVISOR_DIR" ] || exit 0

echo "## [PRE-COMPACT] Working Memory スナップショット"
echo "timestamp: $(date -Iseconds)"
echo ""

if [ -f "$SUPERVISOR_DIR/working-memory.md" ]; then
  cat "$SUPERVISOR_DIR/working-memory.md"
else
  echo "(working-memory.md なし)"
fi
