#!/usr/bin/env bash
# record-detection-gap.sh — 検知漏れ自動記録 helper (#1187)
# Usage: record-detection-gap.sh --type <gap-type> --detail <text> [--related-issue <#N>] [--severity {low,medium,high}]
set -euo pipefail

TYPE=""
DETAIL=""
RELATED_ISSUE=""
SEVERITY="medium"

usage() {
  cat >&2 <<'EOF'
Usage: record-detection-gap.sh --type <gap-type> --detail <text> [options]

Required:
  --type <gap-type>    free-text (e.g. missing-monitor / pitfall-miss / intervention-fail / proxy-stuck / kill-miss)
  --detail <text>      description of the detection gap

Optional:
  --related-issue <#N> related issue number (e.g. #1179)
  --severity <level>   low|medium|high (default: medium)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type|--detail|--related-issue|--severity)
      if [[ $# -lt 2 ]]; then
        echo "ERROR: $1 requires a value" >&2; usage; exit 1
      fi
      case "$1" in
        --type)           TYPE="$2" ;;
        --detail)         DETAIL="$2" ;;
        --related-issue)  RELATED_ISSUE="$2" ;;
        --severity)       SEVERITY="$2" ;;
      esac
      shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$TYPE" ]]; then
  echo "ERROR: --type is required" >&2
  usage
  exit 1
fi
if [[ -z "$DETAIL" ]]; then
  echo "ERROR: --detail is required" >&2
  usage
  exit 1
fi

# --severity validation
case "$SEVERITY" in
  low|medium|high) ;;
  *) echo "ERROR: --severity must be low|medium|high (got: $SEVERITY)" >&2; usage; exit 1 ;;
esac

# SUPERVISOR_DIR path safety: reject traversal, absolute paths, and forbidden characters
_supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"
if [[ "$_supervisor_dir" == *..* ]]; then
  echo "ERROR: SUPERVISOR_DIR must not contain '..'" >&2; exit 1
fi
if [[ "$_supervisor_dir" =~ ^/ ]]; then
  echo "ERROR: SUPERVISOR_DIR must not be an absolute path (got: ${_supervisor_dir})" >&2; exit 1
fi
if [[ "$_supervisor_dir" =~ [$\;\|\`\&\(\)\<\>] ]]; then
  echo "ERROR: SUPERVISOR_DIR must only contain allowed characters (alphanumeric, dot, hyphen, underscore, slash)" >&2; exit 1
fi

# Sanitize DETAIL: strip newlines and control characters to prevent log injection
DETAIL="${DETAIL//$'\n'/ }"
DETAIL="${DETAIL//$'\r'/ }"

# Action 1: .supervisor/intervention-log.md に追記（flock で race condition 防止 #1250）
mkdir -p "$_supervisor_dir"
_ts="$(date -u +%FT%TZ)"
{
  flock 9
  if [[ -n "$RELATED_ISSUE" ]]; then
    printf '%s [detection-gap] type=%s severity=%s related=%s: %s\n' \
      "$_ts" "$TYPE" "$SEVERITY" "$RELATED_ISSUE" "$DETAIL" >&9
  else
    printf '%s [detection-gap] type=%s severity=%s: %s\n' \
      "$_ts" "$TYPE" "$SEVERITY" "$DETAIL" >&9
  fi
} 9>>"$_supervisor_dir/intervention-log.md"

# Action 2: doobidoo memory_store hint → stderr（MCP は shell から呼出不可のため hint のみ）
{
  echo "[hint] doobidoo memory_store recommended:"
  echo "  content: \"detection-gap: ${DETAIL}\""
  echo "  tags: [\"observer-pitfall\", \"detection-gap\", \"${TYPE}\"]"
  if [[ -n "$RELATED_ISSUE" ]]; then
    echo "  metadata: { \"severity\": \"${SEVERITY}\", \"related_issue\": \"${RELATED_ISSUE}\" }"
  else
    echo "  metadata: { \"severity\": \"${SEVERITY}\" }"
  fi
} >&2

# Action 3: --severity high のみ gh issue create hint → stderr（script 自体は実起票しない）
if [[ "$SEVERITY" == "high" ]]; then
  {
    echo "[hint] gh issue create recommended (pitfalls-catalog.md update PR candidate):"
    printf '  gh issue create \\\n'
    printf '    --title "pitfall: detection-gap type=%s" \\\n' "$TYPE"
    printf '    --body "## 検知漏れ概要\n%s" \\\n' "$DETAIL"
    printf '    --label "scope/plugins-twl,ctx/supervision,enhancement,P1"\n'
  } >&2
fi
