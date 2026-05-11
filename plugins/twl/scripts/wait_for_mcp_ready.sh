#!/usr/bin/env bash
# MCP server 接続確認スクリプト（standalone / on-demand / mid-session reconnect 対応, #1612）
# SessionStart hook からの起動のほか、mid-session での接続確認・reconnect 待機にも使用可能
# 環境変数 TWL_MCP_WAIT_MAX=N で最大待機秒数（整数）を上書き可能（デフォルト: 30）
#   standalone: cld-spawn eager-warm 後の待機
#   mid-session: MCP server reconnect 確認（#1612 regression fix）

MAX_WAIT="${TWL_MCP_WAIT_MAX:-30}"
# 数値検証: 非整数は危険（bc インジェクション防止）— デフォルト値にフォールバック
if ! [[ "$MAX_WAIT" =~ ^[0-9]+$ ]]; then
  MAX_WAIT=30
fi

# 200ms 間隔でループ（bc 不使用: bash 組み込み算術のみ）
MAX_LOOPS=$(( MAX_WAIT * 5 ))  # 1s = 5 loops (200ms × 5)
loop=0
while (( loop < MAX_LOOPS )); do
  if twl mcp doctor --probe 2>/dev/null; then
    exit 0  # MCP ready
  fi
  sleep 0.2
  (( loop++ )) || true
done
exit 0  # タイムアウト時も non-zero で cld session 起動を妨げない
