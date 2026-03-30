#!/usr/bin/env bash
# state-read.sh - issue-{N}.json / session.json の読み取り
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AUTOPILOT_DIR="${AUTOPILOT_DIR:-$PROJECT_ROOT/.autopilot}"

# jq 存在チェック
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq が必要です。インストールしてください: sudo apt install jq" >&2
  exit 1
fi

usage() {
  cat <<EOF
Usage: $(basename "$0") --type <issue|session> [--issue N] [--field <name>]

状態ファイルからフィールドを読み取る。

Options:
  --type <issue|session>  対象ファイルタイプ（必須）
  --issue N               Issue番号（type=issue 時必須）
  --field <name>          取得するフィールド名（省略時は全JSON出力）
  -h, --help              このヘルプを表示

存在しないファイルへのアクセス時は空文字列を出力し exit 0 で終了する。
EOF
}

type=""
issue=""
field=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type) type="$2"; shift 2 ;;
    --issue) issue="$2"; shift 2 ;;
    --field) field="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: 不明なオプション: $1" >&2; exit 1 ;;
  esac
done

# バリデーション
if [[ -z "$type" ]]; then
  echo "ERROR: --type は必須です" >&2
  exit 1
fi

if [[ "$type" != "issue" && "$type" != "session" ]]; then
  echo "ERROR: --type は issue または session を指定してください" >&2
  exit 1
fi

if [[ "$type" == "issue" && -z "$issue" ]]; then
  echo "ERROR: type=issue の場合 --issue は必須です" >&2
  exit 1
fi

# issue番号の数値バリデーション
if [[ "$type" == "issue" && -n "$issue" && ! "$issue" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --issue は正の整数を指定してください: $issue" >&2
  exit 1
fi

# field ホワイトリスト検証（jq インジェクション防止）
if [[ -n "$field" && ! "$field" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
  echo "ERROR: 不正なフィールド名: $field（英数字とアンダースコアのみ許可）" >&2
  exit 1
fi

# ファイルパスの決定
if [[ "$type" == "issue" ]]; then
  file="$AUTOPILOT_DIR/issues/issue-${issue}.json"
elif [[ "$type" == "session" ]]; then
  file="$AUTOPILOT_DIR/session.json"
fi

# ファイル存在チェック — 存在しない場合は空文字列 + exit 0
if [[ ! -f "$file" ]]; then
  echo ""
  exit 0
fi

# 読み取り
if [[ -z "$field" ]]; then
  # 全フィールド出力
  jq '.' "$file"
else
  # 単一フィールド出力（存在しないフィールドは空文字列）
  value=$(jq -r ".$field // empty" "$file" 2>/dev/null)
  echo "$value"
fi
