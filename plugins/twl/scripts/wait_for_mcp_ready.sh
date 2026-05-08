#!/usr/bin/env bash
# SessionStart hook から呼び出される MCP 接続確認スクリプト
# twl mcp doctor --probe で stdio_probe 成功するまで poll (最大 30s、200ms 間隔)
MAX_WAIT=30
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
