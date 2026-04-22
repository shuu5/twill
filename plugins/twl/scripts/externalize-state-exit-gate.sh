#!/usr/bin/env bash
# externalize-state-exit-gate.sh — exit gate checker for externalize-state
#
# Usage: externalize-state-exit-gate.sh <session_id> <session_json_path>
#
# Returns:
#   0 = pitfall_declaration 記録済
#   1 = 未記録 WARN
#   2 = invalid / session.json 不在

set -uo pipefail

SESSION_ID="${1:-}"
SESSION_JSON_PATH="${2:-}"

if [[ -z "$SESSION_JSON_PATH" ]] || [[ ! -f "$SESSION_JSON_PATH" ]]; then
  echo "⚠️ [exit-gate] session.json が見つかりません: ${SESSION_JSON_PATH:-<未指定>}" >&2
  exit 2
fi

RESULT=$(python3 - <<PYEOF 2>&1
import json, sys

try:
    with open("${SESSION_JSON_PATH}", "r") as f:
        data = json.load(f)
except Exception as e:
    print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(2)

log = data.get("externalization_log", [])
if not log:
    sys.exit(1)

latest = log[-1]
decl = latest.get("pitfall_declaration", "")
if decl:
    hashes = latest.get("new_pitfall_hashes", [])
    print(f"pitfall_declaration={decl} new_pitfall_hashes={hashes}")
    sys.exit(0)
else:
    sys.exit(1)
PYEOF
)
PYTHON_EXIT=$?

if [[ $PYTHON_EXIT -eq 2 ]]; then
  echo "⚠️ [exit-gate] session.json の解析に失敗しました: ${SESSION_JSON_PATH}" >&2
  exit 2
elif [[ $PYTHON_EXIT -eq 0 ]]; then
  echo "✓ [exit-gate] pitfall_declaration 記録済 (session=${SESSION_ID}): ${RESULT}"
  exit 0
else
  echo "⚠️ [exit-gate] pitfall_declaration が未記録です (session=${SESSION_ID})" >&2
  echo "   → 新規 observer-pitfall を doobidoo に保存し、externalize-state Step 4 で宣言してください" >&2
  exit 1
fi
