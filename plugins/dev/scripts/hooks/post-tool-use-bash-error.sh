#!/usr/bin/env bash
# PostToolUseFailure hook: Bash exit_code != 0 → .self-improve/errors.jsonl に記録
# B-7: Self-Improve Review の機械層基盤
#
# Claude Code の PostToolUseFailure hook は stdin に JSON を渡す。
# フィールド: tool_name, tool_input, tool_use_id, error, error_type, is_interrupt, is_timeout

# stdin から JSON を読み取り
INPUT=$(cat)

# error フィールドから exit code を抽出
ERROR_TEXT=$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null)

# exit code 抽出 ("Exit code N" パターン)
EXIT_CODE=0
if printf '%s' "$ERROR_TEXT" | grep -qP 'Exit code (\d+)'; then
  EXIT_CODE=$(printf '%s' "$ERROR_TEXT" | grep -oP 'Exit code \K\d+' | head -1)
fi

# 整数バリデーション
if [[ ! "$EXIT_CODE" =~ ^[0-9]+$ ]]; then
  EXIT_CODE=1  # エラーなのに exit code 不明 → 1 として記録
fi

# exit code 0 なら記録不要（PostToolUseFailure でここに来る時点でエラーだが念のため）
if [[ "$EXIT_CODE" == "0" ]]; then
  EXIT_CODE=1  # PostToolUseFailure なので最低 1
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

# error から stderr_snippet を抽出（先頭500文字）
STDERR_SNIPPET=$(printf '%s' "$ERROR_TEXT" | head -c 500)

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
