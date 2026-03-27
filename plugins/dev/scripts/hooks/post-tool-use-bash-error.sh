#!/usr/bin/env bash
# PostToolUse hook: Bash exit_code != 0 → .self-improve/errors.jsonl に記録
# B-7: Self-Improve Review の機械層基盤

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

# ディレクトリ作成（権限制限: owner のみ読み書き）
mkdir -p -m 700 "$ERRORS_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# TOOL_INPUT から command を抽出（先頭200文字）
COMMAND=""
if [[ -n "${TOOL_INPUT:-}" ]]; then
  COMMAND=$(printf '%s' "$TOOL_INPUT" | head -c 200)
fi

# TOOL_OUTPUT から stderr_snippet を抽出（先頭500文字）
STDERR_SNIPPET=""
if [[ -n "${TOOL_OUTPUT:-}" ]]; then
  STDERR_SNIPPET=$(printf '%s' "$TOOL_OUTPUT" | head -c 500)
fi

# cwd
CWD="${PWD:-}"

# JSON エスケープ（RFC 7159: U+0000-U+001F 制御文字を全て処理）
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  # 残りの制御文字（U+0000-U+001F）を除去
  s=$(printf '%s' "$s" | tr -d '\000-\007\013\016-\037')
  printf '%s' "$s"
}

COMMAND_ESC=$(json_escape "$COMMAND")
STDERR_ESC=$(json_escape "$STDERR_SNIPPET")
CWD_ESC=$(json_escape "$CWD")

# JSONL 行を追記
printf '{"timestamp":"%s","command":"%s","exit_code":%s,"stderr_snippet":"%s","cwd":"%s"}\n' \
  "$TIMESTAMP" "$COMMAND_ESC" "$EXIT_CODE" "$STDERR_ESC" "$CWD_ESC" >> "$ERRORS_FILE"

# MUST: 記録の成功・失敗にかかわらず exit 0 を返す
exit 0
