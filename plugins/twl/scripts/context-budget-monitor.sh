#!/usr/bin/env bash
# context-budget-monitor.sh — observer context 消費量監視 + 80% 到達時の自動 stop 提案 (#1052)
#
# Usage:
#   context-budget-monitor.sh --usage-pct N [--events-dir DIR] [--check-only]
#   context-budget-monitor.sh [--events-dir DIR]
#
# 引数:
#   --usage-pct N    context 使用率（0-100）を直接指定（ccusage フォールバック）
#   --events-dir DIR watcher 停止対象の .supervisor/ ディレクトリ
#   --check-only     watcher 停止アクションを実行せず判定のみ
#
# 終了コード:
#   0 — 80% 未満（正常継続）
#   1 — 80% 以上（停止提案フラグ）
#
# 閾値:
#   BUDGET_THRESHOLD=80（%）— SU-5 規約に準拠

set -euo pipefail

BUDGET_THRESHOLD=80
USAGE_PCT=""
EVENTS_DIR="${EVENTS_DIR:-.supervisor}"
CHECK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --usage-pct)   USAGE_PCT="$2";   shift 2 ;;
    --events-dir)  EVENTS_DIR="$2";  shift 2 ;;
    --check-only)  CHECK_ONLY=true;  shift   ;;
    *) echo "[context-budget-monitor] WARN: 不明な引数: $1" >&2; shift ;;
  esac
done

# --- context 使用率取得 ---
# --usage-pct 未指定の場合は ccusage または claude 同等 API から取得
if [[ -z "$USAGE_PCT" ]]; then
  if command -v ccusage >/dev/null 2>&1; then
    USAGE_PCT=$(ccusage --json 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(int(d.get('usage_pct', 0)))" 2>/dev/null || echo "0")
  else
    # ccusage 不在時はフォールバック（監視不可 → 0% と見なす）
    echo "[context-budget-monitor] WARN: ccusage が見つかりません — context 使用率取得をスキップ" >&2
    USAGE_PCT=0
  fi
fi

USAGE_PCT="${USAGE_PCT:-0}"
echo "[context-budget-monitor] context 使用率: ${USAGE_PCT}% (閾値: ${BUDGET_THRESHOLD}%)"

# --- 閾値判定 ---
if [[ "$USAGE_PCT" -ge "$BUDGET_THRESHOLD" ]]; then
  echo "[context-budget-monitor] ALERT: context ${USAGE_PCT}% ≥ ${BUDGET_THRESHOLD}% — watcher 一時停止 + compaction 提案"

  if [[ "$CHECK_ONLY" == "false" ]]; then
    # watcher プロセスを一時停止
    if [[ -d "$EVENTS_DIR" ]]; then
      for _pid_file in "${EVENTS_DIR}"/watcher-pid-*; do
        [[ -f "$_pid_file" ]] || continue
        _pid=$(cat "$_pid_file" 2>/dev/null || echo "")
        # 数値バリデーション — 非数値 PID は無視してコマンドインジェクションを防ぐ
        [[ "$_pid" =~ ^[0-9]+$ ]] || continue
        if [[ -n "$_pid" ]] && kill -0 "$_pid" 2>/dev/null; then
          echo "[context-budget-monitor] watcher stop: kill -TERM PID=${_pid}"
          kill -TERM "$_pid" 2>/dev/null || true
        fi
      done
    fi
    echo "[context-budget-monitor] watcher 一時停止完了 (pause)"
    echo "[context-budget-monitor] 推奨: /twl:su-compact で外部化 + compaction を実行してください"
  fi

  exit 1
fi

# 80% 未満 — 正常継続
exit 0
