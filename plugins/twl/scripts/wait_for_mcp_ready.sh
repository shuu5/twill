#!/usr/bin/env bash
# MCP server 接続確認スクリプト（standalone / on-demand / mid-session reconnect 対応, #1612）
# SessionStart hook からの起動のほか、mid-session での接続確認・reconnect 待機にも使用可能
# Usage: wait_for_mcp_ready.sh [--max-wait N]
#   standalone: cld-spawn eager-warm 後の待機
#   mid-session: MCP server reconnect 確認（#1612 regression fix）
MAX_WAIT="${TWL_MCP_WAIT_MAX:-30}"
INTERVAL=0.2
elapsed=0
while (( $(echo "$elapsed < $MAX_WAIT" | bc -l) )); do
  if twl mcp doctor --probe 2>/dev/null; then
    exit 0  # MCP ready
  fi
  sleep "$INTERVAL"
  elapsed=$(echo "$elapsed + $INTERVAL" | bc)
done
exit 0  # タイムアウト時も non-zero で cld session 起動を妨げない
