#!/usr/bin/env bash
# PostToolUse hook: Bash exit_code != 0 → .self-improve/errors.jsonl に記録
# B-7: Self-Improve Review の機械層基盤
#
# Claude Code PostToolUse hook は stdin に JSON を渡す。
# tool_response から exit code を抽出する。

# stdin から JSON を読み取り
INPUT=$(cat)

# tool_response の stdout/stderr から exit code を抽出
# Bash tool の tool_response format: "Exit code N\n..." or 正常出力
EXIT_CODE=0
TOOL_RESPONSE=$(printf '%s' "$INPUT" | jq -r '.tool_response // empty' 2>/dev/null)
if printf '%s' "$TOOL_RESPONSE" | grep -qP '^Exit code (\d+)'; then
  EXIT_CODE=$(printf '%s' "$TOOL_RESPONSE" | grep -oP '^Exit code \K\d+' | head -1)
fi

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

# stdin JSON から command を抽出
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null | head -c 200)

# tool_response から stderr_snippet を抽出（先頭500文字）
STDERR_SNIPPET=$(printf '%s' "$TOOL_RESPONSE" | head -c 500)

# cwd
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
if [[ -z "$CWD" ]]; then
  CWD="${PWD:-}"
fi

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
