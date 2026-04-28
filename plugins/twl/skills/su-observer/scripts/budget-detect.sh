#!/usr/bin/env bash
# budget-detect.sh: [BUDGET-LOW] 検知・安全停止シーケンス
# 環境変数:
#   PILOT_WINDOW (必須): Pilot tmux window 名
#   AUTOPILOT_DIR (default: .autopilot): autopilot state ディレクトリ
# exit code: 0 = 通常/スキップ, 1 = BUDGET-LOW 発動
# 出力: [BUDGET-LOW] プレフィックス付きステータスメッセージを stdout

set -euo pipefail

PILOT_WINDOW="${PILOT_WINDOW:-}"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-.autopilot}"

if [[ -z "$PILOT_WINDOW" ]]; then
  echo "[budget-detect] ERROR: PILOT_WINDOW が未設定" >&2
  exit 0
fi

# status line から budget 残量を抽出（実フォーマット: 5h:XX%(YYm)）
_PANE=$(tmux capture-pane -t "$PILOT_WINDOW" -p -S -1 2>/dev/null || echo "")
BUDGET_PCT=$(echo "$_PANE" | grep -oP '5h:\K[0-9]+(?=%)' | tail -1 || echo "")
BUDGET_RAW=$(echo "$_PANE" | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1 || echo "")
unset _PANE

# フォールバック: session-comm.sh capture による full pane 取得
if [[ -z "$BUDGET_RAW" && -z "$BUDGET_PCT" ]]; then
  _FALLBACK_PANE=$(plugins/session/scripts/session-comm.sh capture "$PILOT_WINDOW" 2>/dev/null || echo "")
  BUDGET_PCT=$(echo "$_FALLBACK_PANE" | grep -oP '5h:\K[0-9]+(?=%)' | tail -1 || echo "")
  BUDGET_RAW=$(echo "$_FALLBACK_PANE" | grep -oP '5h:[0-9]+%\(\K[^\)]+' | tail -1 || echo "")
fi

if [[ -z "$BUDGET_RAW" && -z "$BUDGET_PCT" ]]; then
  echo "[BUDGET-LOW] WARN: budget 情報を取得できません。スキップします。" >&2
  exit 0
fi

# 分換算（例: "21m" → 21、"4h21m" → 261、"1h" → 60）
BUDGET_MIN=-1
if [[ "$BUDGET_RAW" =~ ^([0-9]+)h([0-9]+)m$ ]]; then
  BUDGET_MIN=$(( ${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]} ))
elif [[ "$BUDGET_RAW" =~ ^([0-9]+)h$ ]]; then
  BUDGET_MIN=$(( ${BASH_REMATCH[1]} * 60 ))
elif [[ "$BUDGET_RAW" =~ ^([0-9]+)m$ ]]; then
  BUDGET_MIN=${BASH_REMATCH[1]}
fi

# 閾値読み込み（.supervisor/budget-config.json または デフォルト値）
# 軸1 (consumption-based): 5h budget の token 残量 = 300 × (100 - pct%) / 100 が閾値以下
# 軸2 (cycle-based): (YYm) = cycle reset までの wall-clock が閾値以下
# ※ (YYm) は cycle reset wall-clock であり token 残量ではない（#1022）
_THRESHOLDS=$(python3 -c "
import json
try:
  with open('.supervisor/budget-config.json') as f:
    cfg = json.load(f)
  print(cfg.get('threshold_remaining_minutes', 40), cfg.get('threshold_cycle_minutes', 5))
except Exception:
  print(40, 5)
" 2>/dev/null || echo "40 5")
BUDGET_THRESHOLD_REMAINING="${_THRESHOLDS%% *}"
BUDGET_THRESHOLD_CYCLE="${_THRESHOLDS##* }"
unset _THRESHOLDS

[[ ! "$BUDGET_THRESHOLD_REMAINING" =~ ^[0-9]+$ ]] && BUDGET_THRESHOLD_REMAINING=40
[[ ! "$BUDGET_THRESHOLD_CYCLE" =~ ^[0-9]+$ ]] && BUDGET_THRESHOLD_CYCLE=5

# 軸1: token 残量計算 = 300分 × (100 - 消費%) / 100
BUDGET_REMAINING_MIN=-1
if [[ -n "$BUDGET_PCT" && "$BUDGET_PCT" =~ ^[0-9]+$ ]]; then
  BUDGET_REMAINING_MIN=$(( 300 * (100 - BUDGET_PCT) / 100 ))
fi

# 軸2: cycle reset wall-clock (BUDGET_RAW = YYm の値)
BUDGET_CYCLE_MIN=$BUDGET_MIN

BUDGET_ALERT=false
# 軸1 (consumption-based): token 残量 ≤ threshold_remaining_minutes
if [[ $BUDGET_REMAINING_MIN -ge 0 && $BUDGET_REMAINING_MIN -le $BUDGET_THRESHOLD_REMAINING ]]; then
  BUDGET_ALERT=true
fi
# 軸2 (cycle-based): cycle reset wall-clock ≤ threshold_cycle_minutes
if [[ $BUDGET_CYCLE_MIN -ge 0 && $BUDGET_CYCLE_MIN -le $BUDGET_THRESHOLD_CYCLE ]]; then
  BUDGET_ALERT=true
fi

if [[ "$BUDGET_ALERT" != "true" ]]; then
  exit 0
fi

echo "[BUDGET-LOW] 5h budget: token残量 ${BUDGET_REMAINING_MIN:-?}分 (${BUDGET_PCT:-?}% 消費), cycle reset まで ${BUDGET_CYCLE_MIN:-?}分。安全停止シーケンスを開始します。"

# 1. orchestrator 停止（PID 数値バリデーション必須: kill 0 はプロセスグループ全体を対象とするため禁止）
ORCH_PID=$(cat "${AUTOPILOT_DIR}/orchestrator.pid" 2>/dev/null || pgrep -f 'autopilot-orchestrator' | head -1 || echo "")
if [[ "$ORCH_PID" =~ ^[1-9][0-9]*$ ]]; then
  kill -0 "$ORCH_PID" 2>/dev/null && kill "$ORCH_PID" 2>/dev/null && echo "[BUDGET-LOW] orchestrator (PID $ORCH_PID) を停止しました。"
fi

# 2. 全 ap-* window に Escape を送信（kill 禁止 — Escape のみ。不変条件）
PAUSED_WORKERS=()
for win in $(tmux list-windows -a -F '#{window_name}' 2>/dev/null | grep -E '^ap-'); do
  tmux send-keys -t "$win" Escape 2>/dev/null
  PAUSED_WORKERS+=("$win")
  echo "[BUDGET-LOW] Escape を送信: $win"
done

# 3. 停止状態を budget-pause.json に記録（環境変数経由で python に渡す — soft_deny 回避）
mkdir -p .supervisor
PAUSED_WORKERS_RAW=$(printf '%s\n' "${PAUSED_WORKERS[@]:-}")
WORKERS_JSON=$(PAUSED_WORKERS_RAW="$PAUSED_WORKERS_RAW" python3 -c \
  'import os, json; lines = os.environ.get("PAUSED_WORKERS_RAW", "").splitlines(); print(json.dumps([l.strip() for l in lines if l.strip()]))')
ORCH_PID_SAFE="${ORCH_PID:-}"
python3 -c "
import json, datetime, os
workers = json.loads(os.environ.get('WORKERS_JSON', '[]'))
orch_pid_str = os.environ.get('ORCH_PID_SAFE', '')
orch_pid = int(orch_pid_str) if orch_pid_str.isdigit() else None
data = {
  'status': 'paused',
  'paused_at': datetime.datetime.utcnow().isoformat() + 'Z',
  'estimated_recovery': (datetime.datetime.utcnow() + datetime.timedelta(minutes=90)).isoformat() + 'Z',
  'paused_workers': workers,
  'orchestrator_pid': orch_pid
}
json.dump(data, open('.supervisor/budget-pause.json', 'w'), indent=2)
" 2>/dev/null

# 4. CronCreate で回復時刻に自動再開をスケジュール（LLM が文脈で実行する）
echo "[BUDGET-LOW] CronCreate で budget 回復後の自動再開をスケジュールしてください（90 分後）。"

exit 1
