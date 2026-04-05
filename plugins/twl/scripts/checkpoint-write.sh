#!/usr/bin/env bash
# checkpoint-write.sh
# composite 完了時に specialist findings を checkpoint ファイルに書き出す。
#
# Usage: bash checkpoint-write.sh --step <step_name> --status <PASS|WARN|FAIL> [--findings <json_array>]
#
# Output: .autopilot/checkpoints/<step>.json
#
# checkpoint format:
#   {
#     "step": "phase-review",
#     "status": "WARN",
#     "findings_summary": "2 CRITICAL, 3 WARNING",
#     "critical_count": 2,
#     "findings": [...],
#     "timestamp": "2026-04-05T12:00:00Z"
#   }
#
# findings が省略された場合は空配列として扱う。

set -euo pipefail

# ── 引数パース ──
STEP=""
STATUS=""
FINDINGS="[]"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step)
      STEP="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
      shift 2
      ;;
    --findings)
      FINDINGS="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── バリデーション ──
if [[ -z "$STEP" ]]; then
  echo "ERROR: --step is required" >&2
  exit 1
fi

if [[ ! "$STEP" =~ ^[a-z0-9-]+$ ]]; then
  echo "ERROR: --step contains invalid characters: $STEP" >&2
  exit 1
fi

if [[ ! "$STATUS" =~ ^(PASS|WARN|FAIL)$ ]]; then
  echo "ERROR: --status must be PASS, WARN, or FAIL: $STATUS" >&2
  exit 1
fi

# findings が有効な JSON 配列か検証
if ! echo "$FINDINGS" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "ERROR: --findings must be a valid JSON array" >&2
  exit 1
fi

# ── ディレクトリ作成 ──
CHECKPOINT_DIR=".autopilot/checkpoints"
mkdir -p "$CHECKPOINT_DIR"

# ── findings_summary と critical_count を算出 ──
CRITICAL_COUNT=$(echo "$FINDINGS" | jq '[.[] | select(.severity == "CRITICAL")] | length')
WARNING_COUNT=$(echo "$FINDINGS" | jq '[.[] | select(.severity == "WARNING")] | length')
FINDINGS_SUMMARY="${CRITICAL_COUNT} CRITICAL, ${WARNING_COUNT} WARNING"

# ── timestamp ──
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# ── JSON 書き出し ──
jq -n \
  --arg step "$STEP" \
  --arg status "$STATUS" \
  --arg findings_summary "$FINDINGS_SUMMARY" \
  --argjson critical_count "$CRITICAL_COUNT" \
  --argjson findings "$FINDINGS" \
  --arg timestamp "$TIMESTAMP" \
  '{
    step: $step,
    status: $status,
    findings_summary: $findings_summary,
    critical_count: $critical_count,
    findings: $findings,
    timestamp: $timestamp
  }' > "${CHECKPOINT_DIR}/${STEP}.json"

echo "checkpoint written: ${CHECKPOINT_DIR}/${STEP}.json (${STATUS}, ${FINDINGS_SUMMARY})"
