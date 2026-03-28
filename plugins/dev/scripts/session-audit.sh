#!/bin/bash
# session-audit.sh
# セッションJSONLから監査サマリーを抽出
# Usage: session-audit.sh <jsonl-path>
#
# 出力: 構造化された監査サマリー（JSON Lines形式）
# - ツール呼び出し（名前+入力200字制限）
# - 結果ステータス（ok/ERROR+内容150字制限）
# - AIテキスト要約（200字制限）
# - Skill呼び出し（名前+引数）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 引数バリデーション ---
if [ $# -lt 1 ]; then
    echo "Usage: session-audit.sh <jsonl-path>" >&2
    exit 1
fi

JSONL_PATH="$1"

if [ ! -f "$JSONL_PATH" ]; then
    echo "Error: File not found: $JSONL_PATH" >&2
    exit 1
fi

if [ ! -r "$JSONL_PATH" ]; then
    echo "Error: Cannot read file: $JSONL_PATH" >&2
    exit 1
fi

if [ ! -s "$JSONL_PATH" ]; then
    echo "Error: File is empty: $JSONL_PATH" >&2
    exit 1
fi

# パス検証: ~/.claude/projects/ 配下のみ許可
REAL_PATH=$(realpath "$JSONL_PATH" 2>/dev/null || echo "$JSONL_PATH")
ALLOWED_PREFIX="$HOME/.claude/projects/"
# テスト時はパス制限を緩和（SESSION_AUDIT_ALLOW_ANY_PATH=1）
if [ "${SESSION_AUDIT_ALLOW_ANY_PATH:-0}" != "1" ] && [[ "$REAL_PATH" != "$ALLOWED_PREFIX"* ]]; then
    echo "Error: Path must be under $ALLOWED_PREFIX" >&2
    exit 1
fi

# --- 有効JSON行フィルタ ---
# 不正なJSON行を除外してjqに渡す
jq_safe() {
    while IFS= read -r line; do
        echo "$line" | jq -e '.' >/dev/null 2>&1 && echo "$line"
    done < "$JSONL_PATH" | jq -c "$@"
}

# --- 文字数制限定数 ---
TOOL_INPUT_LIMIT=200
RESULT_CONTENT_LIMIT=150
AI_TEXT_LIMIT=200

# --- jqフィルタ: ツール呼び出し抽出 ---
# assistant メッセージから tool_use content を抽出
extract_tool_calls() {
    jq_safe --argjson limit "$TOOL_INPUT_LIMIT" '
        select(.type == "assistant" and .message != null) |
        .timestamp as $ts |
        .message.content[]? |
        select(.type == "tool_use") |
        {
            entry_type: "tool_call",
            timestamp: $ts,
            tool_name: .name,
            tool_id: .id,
            input: (
                if .name == "Bash" then
                    (.input.command // "" | .[:$limit])
                elif .name == "Skill" then
                    ((.input.skill // "") + " " + (.input.args // "") | .[:$limit])
                elif .name == "Read" then
                    (.input.file_path // "" | .[:$limit])
                elif .name == "Write" then
                    (.input.file_path // "" | .[:$limit])
                elif .name == "Edit" then
                    (.input.file_path // "" | .[:$limit])
                elif .name == "Grep" then
                    (.input.pattern // "" | .[:$limit])
                elif .name == "Glob" then
                    (.input.pattern // "" | .[:$limit])
                elif .name == "Agent" then
                    ((.input.subagent_type // "") + ": " + (.input.description // "") | .[:$limit])
                else
                    (.input | tostring | .[:$limit])
                end
            )
        }
    ' 2>/dev/null || true
}

# --- jqフィルタ: 結果ステータス抽出 ---
# user メッセージから tool_result content を抽出
extract_tool_results() {
    jq_safe --argjson limit "$RESULT_CONTENT_LIMIT" '
        select(.type == "user" and .message != null) |
        .timestamp as $ts |
        .message.content[]? |
        select(.type == "tool_result") |
        {
            entry_type: "tool_result",
            timestamp: $ts,
            tool_id: .tool_use_id,
            status: (if (.is_error // false) then "ERROR" else "ok" end),
            content: (
                if (.is_error // false) then
                    (
                        if (.content | type) == "array" then
                            ([.content[]? | select(.type == "text") | .text] | join("\n") | .[:$limit])
                        elif (.content | type) == "string" then
                            (.content | .[:$limit])
                        else
                            (.content | tostring | .[:$limit])
                        end
                    )
                else
                    (
                        if (.content | type) == "array" then
                            ([.content[]? | select(.type == "text") | .text] | join("\n") | .[:$limit])
                        elif (.content | type) == "string" then
                            (.content | .[:$limit])
                        else
                            ""
                        end
                    )
                end
            )
        }
    ' 2>/dev/null || true
}

# --- jqフィルタ: AIテキスト抽出 ---
extract_ai_text() {
    jq_safe --argjson limit "$AI_TEXT_LIMIT" '
        select(.type == "assistant" and .message != null) |
        .timestamp as $ts |
        .message.content[]? |
        select(.type == "text" and (.text | length) > 0) |
        {
            entry_type: "ai_text",
            timestamp: $ts,
            text: (.text | .[:$limit])
        }
    ' 2>/dev/null || true
}

# --- jqフィルタ: Skill呼び出し抽出 ---
extract_skill_calls() {
    jq_safe '
        select(.type == "assistant" and .message != null) |
        .timestamp as $ts |
        .message.content[]? |
        select(.type == "tool_use" and .name == "Skill") |
        {
            entry_type: "skill_call",
            timestamp: $ts,
            skill_name: .input.skill,
            skill_args: (.input.args // "")
        }
    ' 2>/dev/null || true
}

# --- メタデータ出力 ---
echo_metadata() {
    local file_size
    file_size=$(wc -c < "$JSONL_PATH")
    local line_count
    line_count=$(wc -l < "$JSONL_PATH")
    # 有効行のみをslurpして解析（不正JSON行を除外）
    local valid_lines
    valid_lines=$(while IFS= read -r line; do echo "$line" | jq -e '.' >/dev/null 2>&1 && echo "$line"; done < "$JSONL_PATH")
    local session_id
    session_id=$(echo "$valid_lines" | jq -rs '[.[] | select(.sessionId != null) | .sessionId] | first // ""' 2>/dev/null || echo "")
    local first_ts
    first_ts=$(echo "$valid_lines" | jq -rs '[.[] | select(.timestamp != null) | .timestamp] | first // ""' 2>/dev/null || echo "")
    local last_ts
    last_ts=$(echo "$valid_lines" | jq -rs '[.[] | select(.timestamp != null) | .timestamp] | last // ""' 2>/dev/null || echo "")

    jq -nc \
        --arg session_id "$session_id" \
        --arg file_size "$file_size" \
        --arg line_count "$line_count" \
        --arg first_ts "$first_ts" \
        --arg last_ts "$last_ts" \
        --arg source "$(basename "$JSONL_PATH")" \
        '{
            entry_type: "metadata",
            session_id: $session_id,
            source: $source,
            file_size_bytes: ($file_size | tonumber),
            line_count: ($line_count | tonumber),
            time_range: { start: $first_ts, end: $last_ts }
        }'
}

# --- メイン処理 ---
echo_metadata
extract_tool_calls
extract_tool_results
extract_ai_text
extract_skill_calls
