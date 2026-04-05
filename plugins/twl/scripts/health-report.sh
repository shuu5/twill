#!/usr/bin/env bash
# health-report.sh - Generate structured health report for autopilot anomaly detection
#
# Usage:
#   health-report.sh --issue N --window NAME --pattern PATTERN --elapsed MINUTES --report-dir DIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Argument parsing ---
ISSUE=""
WINDOW=""
PATTERN=""
ELAPSED="0"
REPORT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue)    ISSUE="$2"; shift 2 ;;
    --window)   WINDOW="$2"; shift 2 ;;
    --pattern)  PATTERN="$2"; shift 2 ;;
    --elapsed)  ELAPSED="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# --- Required argument validation ---
if [[ -z "$ISSUE" ]]; then
  echo "Error: --issue is required" >&2
  exit 1
fi

if [[ ! "$ISSUE" =~ ^[0-9]+$ ]]; then
  echo "Error: --issue must be a positive integer: $ISSUE" >&2
  exit 1
fi

if [[ -z "$PATTERN" ]]; then
  echo "Error: --pattern is required" >&2
  exit 1
fi

if [[ -z "$REPORT_DIR" ]]; then
  REPORT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}/health-reports"
fi

if [[ -z "$WINDOW" ]]; then
  WINDOW="ap-#${ISSUE}"
fi

# --- Directory auto-creation ---
mkdir -p "$REPORT_DIR"

# --- Timestamp ---
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
FILENAME_TS=$(date -u +"%Y%m%d-%H%M%S")
REPORT_FILE="${REPORT_DIR}/issue-${ISSUE}-${FILENAME_TS}.md"

# --- tmux capture ---
CAPTURE=""
if command -v tmux &>/dev/null; then
  CAPTURE=$(tmux capture-pane -t "$WINDOW" -p 2>/dev/null || echo "")
fi

# --- Worker number extraction ---
WORKER_NUM=$(echo "$WINDOW" | grep -oE '#[0-9]+' 2>/dev/null | grep -oE '[0-9]+' || echo "$ISSUE")

# --- Action suggestion by pattern ---
get_suggestion() {
  case "$1" in
    chain_stall)
      echo "- Worker の chain 実行が停止している可能性。ログを確認し、手動で再開またはリスタートを検討"
      ;;
    error_output)
      echo "- Worker にエラー出力を検出。tmux capture-pane でエラー内容を確認し、根本原因を調査"
      ;;
    input_waiting)
      echo "- Worker が入力待ち状態で長時間停止。AskUserQuestion への応答が必要か、またはハング状態の可能性"
      ;;
    *)
      echo "- 不明なパターン: $1"
      ;;
  esac
}

SUGGESTION=$(get_suggestion "$PATTERN")

# --- Report generation ---
cat > "$REPORT_FILE" <<EOF
# Health Report: Issue #${ISSUE}

## 検出情報

- **検出パターン**: ${PATTERN}
- **検出時刻**: ${TIMESTAMP}
- **対象ウィンドウ**: ${WINDOW}
- **経過時間**: ${ELAPSED} 分

## tmux capture-pane 出力

\`\`\`
${CAPTURE}
\`\`\`

## Issue Draft

### Title

[autopilot] Worker #${WORKER_NUM}: ${PATTERN} 検出

### 概要

Autopilot Worker #${WORKER_NUM} で ${PATTERN} が検出されました。
経過時間: ${ELAPSED} 分。

### 再現状況

- ウィンドウ: ${WINDOW}
- パターン: ${PATTERN}
- 経過: ${ELAPSED} 分
- 検出時刻: ${TIMESTAMP}

### 対応候補

${SUGGESTION}
EOF

exit 0
