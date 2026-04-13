#!/usr/bin/env bash
# PreToolUse hook: co-issue Phase 3 完了ゲート (Layer C-2)
#
# 動作:
#   - tool_name が "Bash" のときのみ発火
#   - tool_input.command が "gh issue create" または
#     "gh issue edit.*--add-label.*refined" にマッチしない → 通過（exit 0）
#   - gate state ファイルが存在しない → 通過（co-issue 外からの呼び出し）
#   - phase3_completed=false → deny（Phase 3 未完了）
#   - phase3_completed=true → 通過
#
# gate state ファイル: /tmp/.co-issue-phase3-gate-{SESSION_ID_cksum}.json
#   SESSION_ID_cksum: SESSION_ID 環境変数または CLAUDE_SESSION_ID から cksum 算出
#
# 書き込み元: co-issue SKILL.md Phase 2 完了時
# 更新元: issue-lifecycle-orchestrator.sh 完了後（phase3_completed=true）
# クリーンアップ: co-issue SKILL.md 終了時

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

# ゲート対象コマンドのみ処理
# 対象: "gh issue create" または "gh issue edit.*--add-label.*refined"
IS_TARGET=false
if printf '%s' "$CMD" | grep -qE 'gh issue create'; then
  IS_TARGET=true
fi
if printf '%s' "$CMD" | grep -qE 'gh issue edit' && printf '%s' "$CMD" | grep -qE '(--add-label|--label)[^;|&]*\brefined\b'; then
  IS_TARGET=true
fi

if [[ "$IS_TARGET" == "false" ]]; then
  exit 0
fi

# SESSION_ID から cksum 算出（複数のソースを試みる）
SESSION_ID="${CLAUDE_SESSION_ID:-${SESSION_ID:-}}"
if [[ -z "$SESSION_ID" ]]; then
  # SESSION_ID が取得できない場合はゲートをスキップ（フォールバック）
  exit 0
fi

CKSUM=$(printf '%s' "$SESSION_ID" | cksum | awk '{print $1}')
GATE_FILE="/tmp/.co-issue-phase3-gate-${CKSUM}.json"

# gate state ファイルが存在しない → co-issue 外 → 通過
if [[ ! -f "$GATE_FILE" || -L "$GATE_FILE" ]]; then
  exit 0
fi

# phase3_completed を読み取り
PHASE3_COMPLETED=$(jq -r '.phase3_completed // false' "$GATE_FILE" 2>/dev/null || echo "false")

if [[ "$PHASE3_COMPLETED" == "true" ]]; then
  # Phase 3 完了済み → 通過
  exit 0
fi

# Phase 3 未完了 → deny
REASON="co-issue Phase 3 ゲート: Phase 3（orchestrator 経由の specialist review）が未完了です。issue-lifecycle-orchestrator.sh の完了を待ってから再実行してください（Layer C-2 enforcement）。"
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
