#!/usr/bin/env bash
# merge-gate-check-merge-override-block.sh — merge-gate FAIL 状態時の Pilot 手動 merge bypass を block
#
# Issue #1613: PR #1608 で merge-gate REJECT 後に Pilot が手動 merge した regression を防ぐ
# defense-in-depth Layer 4 (human gate)。`merge-gate.json` が FAIL 状態の PR で
# `gh pr merge` 実行を block する。
#
# 緊急時 override:
#   TWL_MERGE_GATE_OVERRIDE='<理由>' bash merge-gate-check-merge-override-block.sh ...
#   → 通過 + `<autopilot-dir>/merge-override-audit.log` に理由・時刻・user を記録
#
# Usage:
#   bash merge-gate-check-merge-override-block.sh [--autopilot-dir <dir>]
#
# Exit:
#   0 — pass (merge-gate not FAIL, or override set)
#   1 — block (merge-gate FAIL かつ override 未設定)

set -uo pipefail

AUTOPILOT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --autopilot-dir)
      AUTOPILOT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '1,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//' >&2
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$AUTOPILOT_DIR" ]]; then
  AUTOPILOT_DIR="${AUTOPILOT_DIR_ENV:-${AUTOPILOT_DIR_DEFAULT:-.autopilot}}"
fi

MG_JSON="${AUTOPILOT_DIR}/checkpoints/merge-gate.json"
AUDIT_LOG="${AUTOPILOT_DIR}/merge-override-audit.log"

# merge-gate.json が無ければ判定不能 → 通過 (gate 未実行ケース)
if [[ ! -f "$MG_JSON" ]]; then
  exit 0
fi

# status を取得 (jq があれば優先、無ければ grep フォールバック)
mg_status=""
if command -v jq >/dev/null 2>&1; then
  mg_status=$(jq -r '.status // empty' "$MG_JSON" 2>/dev/null || echo "")
else
  mg_status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$MG_JSON" \
    | sed -E 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
    | head -n1)
fi

# FAIL 以外なら通過
if [[ "$mg_status" != "FAIL" ]]; then
  exit 0
fi

# FAIL 時: override が無ければ block
if [[ -z "${TWL_MERGE_GATE_OVERRIDE:-}" ]]; then
  echo "BLOCK: merge-gate FAIL 状態のため manual merge を禁止します。" >&2
  echo "  merge-gate.json: $MG_JSON" >&2
  echo "  override したい場合: TWL_MERGE_GATE_OVERRIDE='<理由>' を export してください" >&2
  echo "  (override は ${AUDIT_LOG} に記録されます)" >&2
  exit 1
fi

# override あり: audit log に記録して通過
mkdir -p "$(dirname "$AUDIT_LOG")"
ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
user="${USER:-$(id -un 2>/dev/null || echo unknown)}"
printf '%s\tuser=%s\treason=%s\tmerge_gate=%s\n' \
  "$ts" "$user" "$TWL_MERGE_GATE_OVERRIDE" "$MG_JSON" \
  >> "$AUDIT_LOG"

echo "OVERRIDE: merge-gate FAIL を ${user} が override しました (理由: ${TWL_MERGE_GATE_OVERRIDE})" >&2
echo "  audit log: $AUDIT_LOG" >&2
exit 0
