#!/usr/bin/env bash
# PreToolUse hook: refined ラベル直接付与防止ゲート (Layer D)
#
# 動作:
#   - tool_name が "Bash" のときのみ発火
#   - tool_input.command に "gh issue edit.*(--add-label|--label).*\brefined\b" が
#     マッチしない → 通過（exit 0）
#   - マッチした場合:
#     - /tmp/.spec-review-session-*.json が存在する → allow（Worker セッション内の正規付与）
#     - 存在しない → deny（workflow-issue-lifecycle 経由でのみ付与可能）
#
# 補足: Issue #612（workflow-issue-refine）完了前は deny メッセージに
#   「workflow-issue-refine（準備中）」と補記する。

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

# "gh issue edit" + refined ラベル付与パターンを検出
# パターン: gh issue edit ... (--add-label|--label) ... refined ...
if ! printf '%s' "$CMD" | grep -qE 'gh issue edit'; then
  exit 0
fi

if ! printf '%s' "$CMD" | grep -qE '(--add-label|--label)[^;|&]*\brefined\b'; then
  exit 0
fi

# spec-review session state ファイルの存在確認
# /tmp/.spec-review-session-*.json が存在すれば Worker セッション内の正規付与
SPEC_SESSION_FILES=(/tmp/.spec-review-session-*.json)
if [[ -e "${SPEC_SESSION_FILES[0]}" ]]; then
  # Worker セッション内の正規付与 → allow
  exit 0
fi

# session state なし → deny
REASON="refined ラベルは workflow-issue-lifecycle / workflow-issue-refine（準備中）経由でのみ付与できます。直接 gh issue edit で付与することは禁止されています（Layer D enforcement）。"
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
