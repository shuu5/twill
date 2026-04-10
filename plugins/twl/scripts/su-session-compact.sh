#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
[ -d "$SUPERVISOR_DIR" ] || exit 0

echo "## [SESSION RESUME after COMPACT] 前回 compaction からの復帰"
echo "timestamp: $(date -Iseconds)"
echo ""
echo "### 復帰手順（必須）"
echo "1. 以下の Working Memory と Session 状態を読み、前回の作業を把握する"
echo "2. project_session_state.md (auto memory) を確認して全体状態を復元する"
echo "3. mcp__doobidoo__memory_search で関連記憶を取得する（query: 直近のタスク内容）"
echo "4. 復元後、Working Memory の「次のステップ」に従って作業を再開する"
echo ""

echo "### Supervisor Session"
if [ -f "$SUPERVISOR_DIR/session.json" ]; then
  cat "$SUPERVISOR_DIR/session.json"
else
  echo "(no session)"
fi
echo ""

echo "### Working Memory"
if [ -f "$SUPERVISOR_DIR/working-memory.md" ]; then
  cat "$SUPERVISOR_DIR/working-memory.md"
else
  echo "(working-memory.md なし — project_session_state.md と doobidoo から復元せよ)"
fi
