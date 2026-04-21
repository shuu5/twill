#!/usr/bin/env bash
# budget-monitor-watcher.sh: Monitor tool と並行して budget 閾値を独立ループで監視
# 環境変数:
#   PILOT_WINDOW (必須): Pilot tmux window 名
# 出力: threshold 超過時に [BUDGET-ALERT] を stdout に出力
#       observer が [BUDGET-ALERT] を受信したら budget-detect.sh を即座に実行する（SHALL）

set -euo pipefail

PILOT_WINDOW="${PILOT_WINDOW:-}"

if [[ -z "$PILOT_WINDOW" ]]; then
  echo "[budget-monitor-watcher] ERROR: PILOT_WINDOW が未設定" >&2
  exit 1
fi

while true; do
  PCT=$(tmux capture-pane -t "$PILOT_WINDOW" -p -S -1 2>/dev/null \
    | grep -oP '5h:\K[0-9]+(?=%)' | tail -1 || echo "")
  PCT_THRESHOLD=$(python3 -c "
import json, sys
try:
  cfg = json.load(open('.supervisor/budget-config.json'))
  print(cfg.get('threshold_percent', 90))
except:
  print(90)
" 2>/dev/null || echo "90")
  if [[ -n "$PCT" && "$PCT" =~ ^[0-9]+$ && $PCT -ge $PCT_THRESHOLD ]]; then
    echo "[BUDGET-ALERT] 5h budget ${PCT}% 消費済み (threshold=${PCT_THRESHOLD}%)。BUDGET-LOW シーケンスを実行します。"
  fi
  sleep 60
done
