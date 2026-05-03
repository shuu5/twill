#!/usr/bin/env bash
# mcp-shadow-compare.sh
#
# deps-yaml-guard shadow mode: bash hook と mcp_tool 判定を突合し mismatch を検出する。
# JSONL shadow log を読み込み、同一 event_id の bash/mcp_tool エントリを対比する。
#
# 使い方:
#   bash mcp-shadow-compare.sh --log-file <path>
#
# 出力:
#   mismatch がない場合: exit 0 (出力なし)
#   mismatch がある場合: exit 1、stderr に MISMATCH エントリを出力

set -euo pipefail

LOG_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --log-file)
      LOG_FILE="$2"
      shift 2
      ;;
    *)
      echo "Usage: $0 --log-file <path>" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$LOG_FILE" ]]; then
  echo "ERROR: --log-file が必要です" >&2
  exit 1
fi

if [[ ! -f "$LOG_FILE" ]]; then
  echo "ERROR: ログファイルが存在しません: $LOG_FILE" >&2
  exit 1
fi

# ファイルが空なら mismatch なし
if [[ ! -s "$LOG_FILE" ]]; then
  exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です" >&2
  exit 1
fi

# event_id ごとに bash/mcp_tool の verdict を収集して突合する
declare -A BASH_VERDICT
declare -A MCP_VERDICT

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  event_id=$(echo "$line" | jq -r '.event_id // empty' 2>/dev/null) || continue
  source=$(echo "$line" | jq -r '.source // empty' 2>/dev/null)       || continue
  verdict=$(echo "$line" | jq -r '.verdict // empty' 2>/dev/null)     || continue
  [[ -z "$event_id" || -z "$source" || -z "$verdict" ]] && continue
  case "$source" in
    bash)     BASH_VERDICT["$event_id"]="$verdict" ;;
    mcp_tool) MCP_VERDICT["$event_id"]="$verdict"  ;;
  esac
done < "$LOG_FILE"

MISMATCH_COUNT=0

for event_id in "${!BASH_VERDICT[@]}"; do
  bash_v="${BASH_VERDICT[$event_id]}"
  mcp_v="${MCP_VERDICT[$event_id]:-}"
  if [[ -z "$mcp_v" ]]; then
    continue
  fi
  if [[ "$bash_v" != "$mcp_v" ]]; then
    echo "MISMATCH event_id=${event_id} bash=${bash_v} mcp_tool=${mcp_v}" >&2
    MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
  fi
done

if [[ "$MISMATCH_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
