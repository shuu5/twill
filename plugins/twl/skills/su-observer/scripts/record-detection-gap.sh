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
    --type)           TYPE="$2";           shift 2 ;;
    --detail)         DETAIL="$2";         shift 2 ;;
    --related-issue)  RELATED_ISSUE="$2";  shift 2 ;;
    --severity)       SEVERITY="$2";       shift 2 ;;
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

# Action 1: .supervisor/intervention-log.md に追記（prior art: spawn-controller.sh L58）
_supervisor_dir="${SUPERVISOR_DIR:-.supervisor}"
mkdir -p "$_supervisor_dir"
_ts="$(date -u +%FT%TZ)"
printf '%s [detection-gap] type=%s severity=%s: %s\n' \
  "$_ts" "$TYPE" "$SEVERITY" "$DETAIL" \
  >> "$_supervisor_dir/intervention-log.md"

# Action 2: doobidoo memory_store hint → stderr（MCP は shell から呼出不可のため hint のみ）
{
  echo "[hint] doobidoo memory_store recommended:"
  echo "  content: \"detection-gap: ${DETAIL}\""
  if [[ -n "$RELATED_ISSUE" ]]; then
    echo "  tags: [\"observer-pitfall\", \"detection-gap\", \"${TYPE}\"]"
    echo "  metadata: { \"severity\": \"${SEVERITY}\", \"related_issue\": \"${RELATED_ISSUE}\" }"
  else
    echo "  tags: [\"observer-pitfall\", \"detection-gap\", \"${TYPE}\"]"
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
