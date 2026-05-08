#!/usr/bin/env bash
# PreToolUse hook: Status field (Refined/In Progress option ID) への gh project item-edit 直接実行を
# evidence なし時に deny（ADR-024 Layer D enforcement、#1557 bypass #1 閉鎖）
#
# 動作:
#   - tool_name が "Bash" のときのみ発火
#   - tool_input.command に "gh project item-edit" + 以下のいずれかのオプション ID がマッチする場合:
#     - 47fc9ee4 (In Progress option ID)
#     - 3d983780 (Refined option ID)
#   - マッチしない → 通過（exit 0）
#   - マッチした場合、以下のいずれかの evidence が存在すれば allow:
#     - ${SESSION_TMP_DIR:-/tmp}/.spec-review-session-*.json (Worker セッション内の正規操作)
#     - ${CONTROLLER_ISSUE_DIR:-.controller-issue}/*/Phase4-complete.json (co-issue refine Phase 4 完了)
#   - evidence なし → deny
#
# 注: --bypass-status-gate フラグは autopilot-launch.sh / launcher.py 内部で制御する。
#     hook では bypass フラグパターンをチェックしない（コメント誤マッチのリスクを避けるため）。

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# JSON パース失敗 → no-op
if ! printf '%s' "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

# Bash tool 以外 → no-op
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# コマンド取得
CMD=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
if [[ -z "$CMD" ]]; then
  exit 0
fi

# gh project item-edit で Refined (3d983780) または In Progress (47fc9ee4) option を直接設定しようとしている
MATCHED=0
if printf '%s' "$CMD" | grep -qE 'gh project item-edit' && \
   printf '%s' "$CMD" | grep -qE '\b(47fc9ee4|3d983780)\b'; then
  MATCHED=1
fi

if [[ "$MATCHED" -eq 0 ]]; then
  exit 0
fi

# evidence 確認: spec-review session state ファイル
_SESSION_TMP_DIR="${SESSION_TMP_DIR:-/tmp}"
SPEC_SESSION_FILES=("${_SESSION_TMP_DIR}"/.spec-review-session-*.json)
if [[ -e "${SPEC_SESSION_FILES[0]}" ]]; then
  exit 0
fi

# evidence 確認: co-issue refine Phase 4 完了マーカー
_CONTROLLER_ISSUE_DIR="${CONTROLLER_ISSUE_DIR:-.controller-issue}"
PHASE4_FILES=("${_CONTROLLER_ISSUE_DIR}"/*/Phase4-complete.json)
if [[ -e "${PHASE4_FILES[0]}" ]]; then
  exit 0
fi

# evidence なし → deny
REASON="Status field (Refined / In Progress) への直接遷移は禁止されています（ADR-024 Layer D enforcement、#1557 bypass #1 閉鎖）。

Issue は /twl:co-issue refine #N で Specialist review を完了し、Status=Refined を経由してから In Progress に遷移する必要があります。

【正規の手順】:
  1. /twl:co-issue refine #N で issue-critic / issue-feasibility / worker-codex-reviewer による review を完了する
  2. Review 完了後、Status が自動的に Refined に設定されます
  3. /twl:co-autopilot #N で autopilot を起動すると、Status=Refined の Issue を In Progress に遷移させます

【現状確認】:
  gh project item-list 6 --owner shuu5 --format json | jq -r '.items[] | select(.content.number==<ISSUE_NUM>)'

詳細: ADR-024-refined-status-field-migration.md、親 epic: #1557"
jq -nc \
  --arg reason "$REASON" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
exit 0
