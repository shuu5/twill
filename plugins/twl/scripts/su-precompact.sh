#!/usr/bin/env bash
set -euo pipefail
SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
PROJECT_ROOT="${CLAUDE_PROJECT_ROOT:-$(pwd)}"
SUP_REAL="$(realpath -m "${SUPERVISOR_DIR}")"
PROJECT_REAL="$(realpath "$PROJECT_ROOT")"
case "$SUP_REAL" in
  "$PROJECT_REAL"/*|"$PROJECT_REAL") : ;;
  *) echo "SUPERVISOR_DIR outside project root: $SUP_REAL" >&2; exit 1 ;;
esac
[ -d "$SUPERVISOR_DIR" ] || exit 0

# session.json から現在状態を取り出して working-memory.md を更新する
SESSION_JSON="${SUPERVISOR_DIR}/session.json"
if [[ -f "$SESSION_JSON" ]]; then
    SESSION_STATE=$(SESSION_JSON_PATH="$SESSION_JSON" python3 - <<'PYEOF'
import json, os, sys
from pathlib import Path
project_root = Path(os.environ.get("CLAUDE_PROJECT_ROOT", os.getcwd())).resolve()
sup_dir = Path(os.environ.get("SUPERVISOR_DIR", ".supervisor")).resolve()
if not sup_dir.is_relative_to(project_root):
    print(f"SUPERVISOR_DIR outside project root: {sup_dir}", file=sys.stderr)
    sys.exit(1)
path = os.environ.get("SESSION_JSON_PATH", "")
try:
    with open(path) as f:
        d = json.load(f)
    parts = []
    for key in ("session_id", "claude_session_id", "status", "current_task", "current_wave",
                "processing_issue", "next_step", "started_at", "observer_window"):
        if key in d and d[key]:
            parts.append(f"- {key}: {d[key]}")
    print("\n".join(parts) if parts else "(session.json: no fields)")
except Exception as e:
    print(f"(session.json parse error: {e})", file=sys.stderr)
    print("")
PYEOF
) || SESSION_STATE="(session.json 読み取り失敗)"
    {
        echo "# Working Memory — PreCompact Snapshot"
        echo "timestamp: $(date -Iseconds)"
        echo ""
        echo "## Session State (from session.json)"
        echo "$SESSION_STATE"
        echo ""
        if [[ -f "${SUPERVISOR_DIR}/working-memory.md" ]]; then
            echo "## Previous Working Memory"
            cat "${SUPERVISOR_DIR}/working-memory.md"
        fi
    } > "${SUPERVISOR_DIR}/working-memory.md.tmp" && mv "${SUPERVISOR_DIR}/working-memory.md.tmp" "${SUPERVISOR_DIR}/working-memory.md"
else
    # session.json なし: 既存 working-memory.md があればタイムスタンプを更新
    if [[ -f "${SUPERVISOR_DIR}/working-memory.md" ]]; then
        {
            echo "# Working Memory — PreCompact Snapshot"
            echo "timestamp: $(date -Iseconds)"
            echo ""
            cat "${SUPERVISOR_DIR}/working-memory.md"
        } > "${SUPERVISOR_DIR}/working-memory.md.tmp" && mv "${SUPERVISOR_DIR}/working-memory.md.tmp" "${SUPERVISOR_DIR}/working-memory.md"
    else
        {
            echo "# Working Memory — PreCompact Snapshot"
            echo "timestamp: $(date -Iseconds)"
            echo ""
            echo "(session.json なし — 状態復元に project_session_state.md と doobidoo を使用すること)"
        } > "${SUPERVISOR_DIR}/working-memory.md.tmp" && mv "${SUPERVISOR_DIR}/working-memory.md.tmp" "${SUPERVISOR_DIR}/working-memory.md"
    fi
fi

echo "## [PRE-COMPACT] Working Memory スナップショット"
echo "timestamp: $(date -Iseconds)"
echo ""
echo "以下の Working Memory を保存しました。Compaction 後は PostCompact hook の指示に従い復元すること。"
echo ""
if [[ -f "${SUPERVISOR_DIR}/working-memory.md" ]]; then
    cat "${SUPERVISOR_DIR}/working-memory.md"
fi
