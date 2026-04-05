#!/usr/bin/env bash
# session-archive.sh - セッション完了時のアーカイブ
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"
SESSION_FILE="$AUTOPILOT_DIR/session.json"
ISSUES_DIR="$AUTOPILOT_DIR/issues"
ARCHIVE_DIR="$AUTOPILOT_DIR/archive"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0")

session.json と全 issue-{N}.json を archive/<session_id>/ に移動する。

Options:
  -h, --help  このヘルプを表示
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$SESSION_FILE" ]]; then
  echo "ERROR: session.json が存在しません" >&2
  exit 1
fi

session_id=$(jq -r '.session_id' "$SESSION_FILE")

# session_id のバリデーション（パストラバーサル防止）
if [[ ! "$session_id" =~ ^[a-zA-Z0-9]+$ ]]; then
  echo "ERROR: 不正な session_id: $session_id（英数字のみ許可）" >&2
  exit 1
fi

archive_dest="$ARCHIVE_DIR/$session_id"

mkdir -p "$archive_dest/issues"

# session.json を移動
mv "$SESSION_FILE" "$archive_dest/session.json"

# issue-{N}.json を移動
if [[ -d "$ISSUES_DIR" ]]; then
  for issue_file in "$ISSUES_DIR"/issue-*.json; do
    [[ -f "$issue_file" ]] || continue
    mv "$issue_file" "$archive_dest/issues/"
  done
fi

echo "OK: セッション $session_id をアーカイブしました → $archive_dest"
