#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
[ -d "$SUPERVISOR_DIR" ] || exit 0
echo "## Ambient Hints (session-compact)"
date -Iseconds
echo "### Supervisor Session"
cat "$SUPERVISOR_DIR/session.json" 2>/dev/null || echo "(no session)"
echo ""
echo "### Working Memory"
cat "$SUPERVISOR_DIR/working-memory.md" 2>/dev/null || echo "(empty)"
