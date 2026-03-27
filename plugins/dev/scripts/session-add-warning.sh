#!/usr/bin/env bash
# session-add-warning.sh - cross-issue 警告を session.json に追加
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="$PROJECT_ROOT/.autopilot"
SESSION_FILE="$AUTOPILOT_DIR/session.json"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --issue N --target-issue M --file <path> --reason <text>

cross-issue 警告を session.json の cross_issue_warnings に追加する。

Options:
  --issue N             警告元の Issue番号（必須）
  --target-issue M      警告対象の Issue番号（必須）
  --file <path>         重複ファイルパス（必須）
  --reason <text>       警告理由（必須）
  -h, --help            このヘルプを表示
EOF
}

issue=""
target_issue=""
file=""
reason=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) issue="$2"; shift 2 ;;
    --target-issue) target_issue="$2"; shift 2 ;;
    --file) file="$2"; shift 2 ;;
    --reason) reason="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$issue" || -z "$target_issue" || -z "$file" || -z "$reason" ]]; then
  echo "ERROR: --issue, --target-issue, --file, --reason は全て必須です" >&2
  exit 1
fi

if [[ ! -f "$SESSION_FILE" ]]; then
  echo "ERROR: session.json が存在しません" >&2
  exit 1
fi

# 警告を追加
jq \
  --argjson issue "$issue" \
  --argjson target "$target_issue" \
  --arg file "$file" \
  --arg reason "$reason" \
  '.cross_issue_warnings += [{ issue: $issue, target_issue: $target, file: $file, reason: $reason }]' \
  "$SESSION_FILE" > "$SESSION_FILE.tmp" && mv "$SESSION_FILE.tmp" "$SESSION_FILE"

echo "OK: cross-issue 警告を追加しました (Issue #$issue → #$target_issue: $file)"
