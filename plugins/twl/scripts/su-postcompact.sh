#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
[ -d "$SUPERVISOR_DIR" ] || exit 0

# =============================================================================
# Section: Session ID 更新（compaction 後に session ID が変わるため）
# =============================================================================
SESSION_JSON="${SUPERVISOR_DIR}/session.json"
if [[ -f "$SESSION_JSON" ]]; then
    PROJECT_HASH=$(pwd | sed 's|/|-|g; s|^-||')
    NEW_SESSION_ID=$(ls -t ~/.claude/projects/${PROJECT_HASH}/*.jsonl 2>/dev/null | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||' || echo "")
    if [[ -n "$NEW_SESSION_ID" ]]; then
        python3 - <<PYEOF
import json
path = "${SESSION_JSON}"
new_id = "${NEW_SESSION_ID}"
try:
    with open(path) as f:
        data = json.load(f)
    old_id = data.get("claude_session_id", "")
    if old_id != new_id:
        data["claude_session_id"] = new_id
        with open(path, "w") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
except Exception:
    pass
PYEOF
    fi
fi
# =============================================================================

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
