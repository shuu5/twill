#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
[ -d "$SUPERVISOR_DIR" ] || exit 0
echo "## Working Memory (post-compact restore)"
date -Iseconds
cat "$SUPERVISOR_DIR/working-memory.md" 2>/dev/null || echo "(empty)"
