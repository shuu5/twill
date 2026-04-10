#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
[ -d "$SUPERVISOR_DIR" ] || exit 0

echo "## [POST-COMPACT RESTORE] Compaction 完了 — 以下の Working Memory で作業を再開せよ"
echo ""
echo "### 復帰手順（必須）"
echo "1. 以下の Working Memory を読み、処理中タスクと次のステップを把握する"
echo "2. project_session_state.md (auto memory) を確認して全体状態を復元する"
echo "3. mcp__doobidoo__memory_search で関連記憶を取得する（query: 直近のタスク内容）"
echo ""

if [ -f "$SUPERVISOR_DIR/working-memory.md" ]; then
  echo "### Working Memory"
  cat "$SUPERVISOR_DIR/working-memory.md"
else
  echo "### Working Memory"
  echo "(working-memory.md なし — project_session_state.md と doobidoo から復元せよ)"
fi
