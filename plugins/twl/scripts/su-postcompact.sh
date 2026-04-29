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

# =============================================================================
# Section: Session ID 更新（compaction 後に session ID が変わるため）
# =============================================================================
SESSION_JSON="${SUPERVISOR_DIR}/session.json"
if [[ -f "$SESSION_JSON" ]]; then
    PROJECT_HASH=$(pwd | sed 's|/|-|g')
    # ls -t で最新 JSONL ファイルから session ID を取得
    NEW_SESSION_ID=""
    if compgen -G "${HOME}/.claude/projects/${PROJECT_HASH}/*.jsonl" > /dev/null 2>&1; then
        NEW_SESSION_ID=$(ls -t "${HOME}/.claude/projects/${PROJECT_HASH}/"*.jsonl 2>/dev/null \
            | head -1 | xargs -r basename 2>/dev/null | sed 's|\.jsonl$||' || echo "")
    fi
    if [[ -n "$NEW_SESSION_ID" ]]; then
        # 変数を環境変数経由で渡す（heredoc への文字列展開 injection を防止）
        # ヒアドキュメントのデリミタをシングルクォートで囲みシェル展開を無効化
        SESSION_JSON_PATH="$SESSION_JSON" NEW_SESSION_ID_VAL="$NEW_SESSION_ID" python3 - <<'PYEOF'
import json, os, sys
from pathlib import Path
project_root = Path(os.environ.get("CLAUDE_PROJECT_ROOT", os.getcwd())).resolve()
sup_dir = Path(os.environ.get("SUPERVISOR_DIR", ".supervisor")).resolve()
if not sup_dir.is_relative_to(project_root):
    print(f"SUPERVISOR_DIR outside project root: {sup_dir}", file=sys.stderr)
    sys.exit(1)
path = os.environ["SESSION_JSON_PATH"]
new_id = os.environ["NEW_SESSION_ID_VAL"]
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
echo "4. **Long-term Memory 保存**: Skill(twl:su-compact) を実行して doobidoo への知識外部化を行うこと（SU-6a 準拠）"
echo ""

if [ -f "$SUPERVISOR_DIR/working-memory.md" ]; then
  echo "### Working Memory"
  cat "$SUPERVISOR_DIR/working-memory.md"
else
  echo "### Working Memory"
  echo "(working-memory.md なし — project_session_state.md と doobidoo から復元せよ)"
fi
