#!/usr/bin/env bash
# auto-next-spawn.sh — Wave 候補自動 spawn (#1155)
#
# Usage:
#   bash auto-next-spawn.sh --queue <path> --triggered-by <window> [--dry-run]
#
# 動作:
#   wave-queue.json から次 Wave 1 件 dequeue → spawn_cmd_argv を exec で argv 直接渡し
#   → wave-queue.json 更新 → intervention-log 記録
#
# 引数:
#   --queue <path>         wave-queue.json パス（必須）
#   --triggered-by <win>   kill トリガーの window 名（必須）
#   --dry-run              spawn コマンドの echo のみ（実際の exec なし）
#
# spawn_cmd_argv[0] allowlist: bash / /bin/bash / /usr/bin/bash / cld-spawn
# allowlist 外の場合は abort + intervention-log に拒否ログ

set -uo pipefail

_ANS_SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
# shellcheck source=/dev/null
source "$_ANS_SCRIPT_DIR/../../../scripts/lib/supervisor-dir-validate.sh"
# set -e なしのため || exit 1 パターンで明示的に停止（AC5）
validate_supervisor_dir "${SUPERVISOR_DIR:-.supervisor}" || exit 1

# ---- 引数パース ----
QUEUE_FILE=""
TRIGGERED_BY=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --queue)        QUEUE_FILE="$2"; shift 2 ;;
    --triggered-by) TRIGGERED_BY="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=1; shift ;;
    *) echo "[auto-next-spawn] WARN: unknown argument: $1" >&2; shift ;;
  esac
done

if [[ -z "$QUEUE_FILE" || -z "$TRIGGERED_BY" ]]; then
  echo "[auto-next-spawn] ERROR: --queue and --triggered-by are required" >&2
  exit 1
fi

# ---- intervention-log パス（SUPERVISOR_DIR 環境変数またはデフォルト .supervisor）----
_SUPERVISOR_DIR="${SUPERVISOR_DIR:-.supervisor}"
INTERVENTION_LOG="${_SUPERVISOR_DIR}/intervention-log.md"

_append_log() {
  mkdir -p "$_SUPERVISOR_DIR" 2>/dev/null || true
  {
    printf '%s %s\n' "$(date -u +%FT%TZ)" "$1"
  } >> "$INTERVENTION_LOG" || {
    echo "[auto-next-spawn] WARN: intervention-log append failed (continuing)" >&2
  }
}

# ---- wave-queue.json 不在チェック ----
if [[ ! -f "$QUEUE_FILE" ]]; then
  echo "[auto-next-spawn] WARN: wave-queue.json not found: ${QUEUE_FILE}" >&2
  _append_log "auto-cleanup+next-spawn-skipped: triggered_by=${TRIGGERED_BY}, reason=wave-queue.json not found"
  exit 0
fi

# jq schema validation: version=1, current_wave(int), queue[].wave/issues/spawn_cmd_argv(≥1)/depends_on_waves/spawn_when
_schema_ok=1
if ! jq -e '
  .version == 1 and
  (.current_wave | type == "number") and
  (.queue | type == "array") and
  (
    (.queue | length == 0) or
    (
      .queue[] |
      (.wave | type == "number") and
      (.issues | type == "array") and
      (.spawn_cmd_argv | type == "array" and length >= 1) and
      (.depends_on_waves | type == "array") and
      (.spawn_when == "all_current_wave_idle_completed")
    )
  )
' "$QUEUE_FILE" > /dev/null 2>&1; then
  _schema_ok=0
fi

if [[ "$_schema_ok" -eq 0 ]]; then
  echo "[auto-next-spawn] WARN: JSON Schema validation failed for ${QUEUE_FILE}" >&2
  _append_log "auto-cleanup+next-spawn-skipped: triggered_by=${TRIGGERED_BY}, reason=JSON Schema validation failed"
  exit 0
fi

# ---- queue が空なら skip ----
QUEUE_LEN=$(jq '.queue | length' "$QUEUE_FILE" 2>/dev/null || echo "0")
if [[ "$QUEUE_LEN" -eq 0 ]]; then
  echo "[auto-next-spawn] INFO: queue is empty, no next wave to spawn" >&2
  exit 0
fi

# ---- 次 Wave エントリ取得 ----
NEXT_WAVE=$(jq -r '.queue[0].wave' "$QUEUE_FILE")
NEXT_ISSUES=$(jq -r '[.queue[0].issues[] | tostring] | join(",")' "$QUEUE_FILE")

# spawn_cmd_argv を bash 配列に読み込む
mapfile -t SPAWN_ARGV < <(jq -r '.queue[0].spawn_cmd_argv[]' "$QUEUE_FILE")

# ---- allowlist チェック（shell injection 防止、AC-4）----
CMD0="${SPAWN_ARGV[0]:-}"
_ALLOWED=0
case "$CMD0" in
  bash|/bin/bash|/usr/bin/bash) _ALLOWED=1 ;;
  *) [[ "$(basename "$CMD0")" == "cld-spawn" ]] && _ALLOWED=1 ;;
esac

if [[ "$_ALLOWED" -eq 0 ]]; then
  echo "[auto-next-spawn] ABORT: spawn_cmd_argv[0] not in allowlist: ${CMD0}" >&2
  _append_log "auto-cleanup+next-spawn-aborted: triggered_by=${TRIGGERED_BY}, reason=spawn_cmd_argv[0] not in allowlist: ${CMD0}"
  exit 1
fi

# ---- dry-run モード（AC-8）----
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[auto-next-spawn] DRY-RUN: would exec: ${SPAWN_ARGV[*]}"
  _append_log "auto-cleanup+next-spawn-dryrun: triggered_by=${TRIGGERED_BY}, next_wave=${NEXT_WAVE}, spawned=[${NEXT_ISSUES}]"
  exit 0
fi

# ---- actual spawn ----
# dequeue + current_wave 更新（spawn 前に永続化）
ORIGINAL_JSON=$(cat "$QUEUE_FILE")
UPDATED_JSON=$(jq --argjson nw "$NEXT_WAVE" '
  .current_wave = $nw |
  .queue = .queue[1:]
' "$QUEUE_FILE") && printf '%s\n' "$UPDATED_JSON" > "$QUEUE_FILE" || {
  echo "[auto-next-spawn] ERROR: failed to update wave-queue.json" >&2
  exit 1
}

echo "[auto-next-spawn] spawning wave ${NEXT_WAVE}: ${SPAWN_ARGV[*]}"
_append_log "auto-cleanup+next-spawn: triggered_by=${TRIGGERED_BY}, killed=${TRIGGERED_BY}, next_wave=${NEXT_WAVE}, spawned=[${NEXT_ISSUES}]"

exec "${SPAWN_ARGV[@]}"
# exec 失敗時（通常ここには到達しない）
printf '%s\n' "$ORIGINAL_JSON" > "$QUEUE_FILE"
_append_log "auto-cleanup+next-spawn-failed: triggered_by=${TRIGGERED_BY}, next_wave=${NEXT_WAVE}, reason=exec failed"
exit 1
