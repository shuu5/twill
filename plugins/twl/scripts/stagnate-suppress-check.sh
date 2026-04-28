#!/usr/bin/env bash
# stagnate-suppress-check.sh — STAGNATE-600 emit 抑止条件チェック (#1052)
#
# Usage:
#   stagnate-suppress-check.sh \
#     --capture-file <path>    Pilot pane の最終 capture log
#     [--session-json <path>]  .autopilot/session.json パス
#     [--events-dir <path>]    .supervisor/ ディレクトリ（session-end 検索先）
#
# 終了コード:
#   0 — suppress する（STAGNATE emit 不要）
#   1 — suppress しない（STAGNATE emit を許可）
#
# suppress 条件（いずれか 1 つ以上を満たせば suppress）:
#   A. capture に [PHASE-COMPLETE] または >>> 実装完了: が含まれる
#   B. session.json の status が "completed" または "archived"
#   C. events-dir に session-end* ファイルが存在する

set -euo pipefail

CAPTURE_FILE=""
SESSION_JSON=""
EVENTS_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --capture-file) CAPTURE_FILE="$2"; shift 2 ;;
    --session-json) SESSION_JSON="$2"; shift 2 ;;
    --events-dir)   EVENTS_DIR="$2";   shift 2 ;;
    *) echo "[stagnate-suppress-check] WARN: 不明な引数: $1" >&2; shift ;;
  esac
done

# --- 条件 A: capture に完了マーカーが含まれる ---
if [[ -n "$CAPTURE_FILE" && -f "$CAPTURE_FILE" ]]; then
  if grep -qE '\[PHASE-COMPLETE\]|>>> 実装完了:' "$CAPTURE_FILE" 2>/dev/null; then
    echo "[stagnate-suppress-check] suppress: capture に完了マーカーあり (${CAPTURE_FILE})"
    exit 0
  fi
fi

# --- 条件 B: session.json status が completed/archived ---
if [[ -n "$SESSION_JSON" && -f "$SESSION_JSON" ]]; then
  _status=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('status',''))" "$SESSION_JSON" 2>/dev/null || echo "")
  if [[ "$_status" == "completed" || "$_status" == "archived" ]]; then
    echo "[stagnate-suppress-check] suppress: session.json status=${_status}"
    exit 0
  fi
fi

# --- 条件 C: session-end ファイルが存在する ---
if [[ -n "$EVENTS_DIR" && -d "$EVENTS_DIR" ]]; then
  if ls "${EVENTS_DIR}"/session-end* 2>/dev/null | grep -q .; then
    echo "[stagnate-suppress-check] suppress: session-end ファイルあり (${EVENTS_DIR})"
    exit 0
  fi
fi

# suppress しない
exit 1
