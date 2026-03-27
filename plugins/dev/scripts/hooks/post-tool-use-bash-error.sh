#!/usr/bin/env bash
# PostToolUse hook: Bash exit_code != 0 → .self-improve/errors.jsonl に記録
# ADR-005: Self-Improve Review の機械層基盤

EXIT_CODE="${1:-0}"

# 整数バリデーション
if [[ ! "$EXIT_CODE" =~ ^[0-9]+$ ]]; then
  exit 0
fi

# 成功時は何もしない
if [[ "$EXIT_CODE" == "0" ]]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ERRORS_DIR="$PLUGIN_ROOT/.self-improve"
ERRORS_FILE="$ERRORS_DIR/errors.jsonl"

# ディレクトリ作成
mkdir -p "$ERRORS_DIR"

# JSON 行を追記
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"timestamp":"%s","exit_code":%s,"tool":"Bash"}\n' \
  "$TIMESTAMP" "$EXIT_CODE" >> "$ERRORS_FILE"
