#!/usr/bin/env bash
# PreToolUse hook: Status=Refined gate (Layer D)
#
# 動作:
#   - tool_name が "Bash" のときのみ発火
#   - tool_input.command に "gh project item-edit.*47fc9ee4" (In Progress option ID)
#     パターンがマッチしない → 通過（exit 0）
#   - マッチした場合:
#     - /tmp/.spec-review-session-*.json が存在する → allow（Worker セッション内の正規操作）
#     - 存在しない → deny（Status=Refined 経由のみ In Progress 遷移可能）
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

# Pattern 1: gh project item-edit で In Progress option (47fc9ee4) を直接設定しようとしている
MATCHED=0
if printf '%s' "$CMD" | grep -qE 'gh project item-edit' && \
   printf '%s' "$CMD" | grep -qE '\b47fc9ee4\b'; then
  MATCHED=1
fi

if [[ "$MATCHED" -eq 0 ]]; then
  exit 0
fi

# spec-review session state ファイルの存在確認
_SESSION_TMP_DIR="${SESSION_TMP_DIR:-/tmp}"
SPEC_SESSION_FILES=("${_SESSION_TMP_DIR}"/.spec-review-session-*.json)
if [[ -e "${SPEC_SESSION_FILES[0]}" ]]; then
  # Worker セッション内の正規操作 → allow
  exit 0
fi

# session state なし → deny
REASON="Status=In Progress への直接遷移は禁止されています（Layer D enforcement）。

Issue は Status=Refined を経由してから In Progress に遷移する必要があります。

【正規の手順】:
  1. /twl:workflow-issue-refine で Specialist review を完了してください（issue-critic / issue-feasibility / worker-codex-reviewer）
  2. Review 完了後、Status が自動的に Refined に設定されます
  3. その後、co-autopilot が Status=Refined の Issue を In Progress に遷移させます

【現状確認】:
  gh project item-list 6 --owner shuu5 --format json | jq -r '.items[] | select(.content.number==<ISSUE_NUM>)'

詳細: ADR-024-refined-status-field-migration.md"
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
