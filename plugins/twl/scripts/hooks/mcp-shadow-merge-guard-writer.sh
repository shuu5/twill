#!/usr/bin/env bash
# mcp-shadow-merge-guard-writer.sh
#
# merge-guard shadow mode: bash hook と mcp_tool 判定を突合ログに書き込む。
# shadow log は XDG_RUNTIME_DIR または SHADOW_LOG_PATH で指定されたパスに JSONL 形式で追記される。
#
# 使い方:
#   bash mcp-shadow-merge-guard-writer.sh \
#     --command <cmd> --bash-exit <N> --mcp-exit <N> \
#     [--log <path>] [--bash-stderr-match <true|false>] [--mcp-stderr-match <true|false>]
#
# 出力 (JSONL 形式、1 行):
#   {ts, command, bash_exit, mcp_exit, bash_stderr_match, mcp_stderr_match, mismatch}
#
# command フィールドは先頭 CMD_MAX_LEN 文字のみ記録（秘密情報漏洩リスクの軽減）。
#
# mismatch 判定:
#   bash_exit==0 かつ mcp_exit==0 (両方 allow) → mismatch=false
#   bash_exit!=0 かつ mcp_exit!=0 (両方 block/error) → mismatch=false
#   一方のみ非ゼロ → mismatch=true

set -uo pipefail

readonly CMD_MAX_LEN=128

CMD=""
BASH_EXIT=""
MCP_EXIT=""
# SHADOW_LOG_PATH > XDG_RUNTIME_DIR > UID スコープの /tmp パス（symlink attack 対策 #1280）
if [[ -n "${SHADOW_LOG_PATH:-}" ]]; then
  LOG_FILE="$SHADOW_LOG_PATH"
elif [[ -n "${XDG_RUNTIME_DIR:-}" ]]; then
  LOG_FILE="${XDG_RUNTIME_DIR}/mcp-shadow-merge-guard.log"
else
  LOG_FILE="${TMPDIR:-/tmp}/mcp-shadow-merge-guard-$(id -u).log"
fi
BASH_STDERR_MATCH="false"
MCP_STDERR_MATCH="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --command)          CMD="$2";              shift 2 ;;
    --bash-exit)        BASH_EXIT="$2";        shift 2 ;;
    --mcp-exit)         MCP_EXIT="$2";         shift 2 ;;
    --log)              LOG_FILE="$2";         shift 2 ;;
    --bash-stderr-match)
      [[ "$2" == "true" || "$2" == "false" ]] || { echo "ERROR: --bash-stderr-match must be true|false" >&2; exit 1; }
      BASH_STDERR_MATCH="$2"; shift 2 ;;
    --mcp-stderr-match)
      [[ "$2" == "true" || "$2" == "false" ]] || { echo "ERROR: --mcp-stderr-match must be true|false" >&2; exit 1; }
      MCP_STDERR_MATCH="$2";  shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$CMD" ]]       && { echo "ERROR: --command required" >&2; exit 1; }
[[ -z "$BASH_EXIT" ]] && { echo "ERROR: --bash-exit required" >&2; exit 1; }
[[ -z "$MCP_EXIT" ]]  && { echo "ERROR: --mcp-exit required" >&2; exit 1; }

if ! [[ "$BASH_EXIT" =~ ^[0-9]+$ ]] || ! [[ "$MCP_EXIT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --bash-exit / --mcp-exit must be integers" >&2
  exit 1
fi

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# コマンドを先頭 CMD_MAX_LEN 文字に切り詰め（秘密情報漏洩リスクの軽減 #1280）
CMD_TRUNCATED="${CMD:0:${CMD_MAX_LEN}}"

bash_blocked=false
mcp_blocked=false
[[ "$BASH_EXIT" -ne 0 ]] && bash_blocked=true
[[ "$MCP_EXIT" -ne 0 ]]  && mcp_blocked=true

if [[ "$bash_blocked" == "$mcp_blocked" ]]; then
  MISMATCH="false"
else
  MISMATCH="true"
fi

mkdir -p "$(dirname "$LOG_FILE")"
jq -nc \
  --arg    ts                "$TS"               \
  --arg    command           "$CMD_TRUNCATED"    \
  --argjson bash_exit        "$BASH_EXIT"        \
  --argjson mcp_exit         "$MCP_EXIT"         \
  --argjson bash_stderr_match "$BASH_STDERR_MATCH" \
  --argjson mcp_stderr_match  "$MCP_STDERR_MATCH"  \
  --argjson mismatch         "$MISMATCH"         \
  '{ts:$ts, command:$command, bash_exit:$bash_exit, mcp_exit:$mcp_exit,
    bash_stderr_match:$bash_stderr_match, mcp_stderr_match:$mcp_stderr_match,
    mismatch:$mismatch}' \
  >> "$LOG_FILE"
