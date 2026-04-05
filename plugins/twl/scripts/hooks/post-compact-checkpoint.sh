#!/usr/bin/env bash
# PostCompact hook: compaction 後に autopilot 進捗チェックポイントを保存
# AUTOPILOT_DIR 未設定時は何もしない（通常セッション）
set -uo pipefail

# stdin を消費（PostCompact は stdin に JSON を渡す）
cat > /dev/null 2>&1 || true

# AUTOPILOT_DIR 未設定 or 空 → 何もしない
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# AUTOPILOT_DIR が実在するディレクトリでなければ無視
if [[ ! -d "${AUTOPILOT_DIR}" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/python-env.sh
source "${SCRIPTS_ROOT}/lib/python-env.sh"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# state-write.sh で last_compact_at を記録（失敗しても exit 0）
# issue 番号を state から検出
ISSUE_NUM=""
# session.json から現在の issue を検索
for state_file in "${AUTOPILOT_DIR}"/issue-*.json; do
  if [[ -f "$state_file" ]]; then
    STATUS=$(jq -r '.status // ""' "$state_file" 2>/dev/null || echo "")
    if [[ "$STATUS" == "running" ]]; then
      ISSUE_NUM=$(basename "$state_file" | grep -Eo '[0-9]+' | head -1)
      break
    fi
  fi
done

if [[ -n "$ISSUE_NUM" ]]; then
  python3 -m twl.autopilot.state write \
    --type issue --issue "$ISSUE_NUM" --role worker \
    --set "last_compact_at=$TIMESTAMP" 2>/dev/null || true
fi

exit 0
