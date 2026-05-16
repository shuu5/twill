#!/usr/bin/env bash
# PostToolUse hook: tool-architect spec verify gap detection (warn-only)
#
# Edit/Write/NotebookEdit tool が architecture/spec/* 配下を編集した直後に発火、
# verify-coverage.sh (lib/) を呼んで inferred/deduced badge の残存を warn 出力する。
#
# Behavior (tool-architecture.html §3.2 層 2 + EXP-027):
#   - exit 0 always (PostToolUse は block 不能、warn-only 設計)
#   - stderr: verify-coverage.sh の warning を pass-through
#
# 参照仕様: tool-architecture.html §3.2 / spec-management-rules.md R-8

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

if ! echo "$payload" | jq empty 2>/dev/null; then
    exit 0
fi

tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
case "$tool_name" in
    Edit|Write|NotebookEdit) ;;
    *) exit 0 ;;
esac

file_path=$(echo "$payload" | jq -r '.tool_input.file_path // empty')
if [[ -z "$file_path" ]]; then
    exit 0
fi

# architecture/spec/*.html 配下のみ verify (sub-dir nest も対象)
if [[ "$file_path" != *architecture/spec/*.html ]]; then
    exit 0
fi

# verify-coverage.sh helper を呼ぶ (lib/ に配置済)
HELPER="${CLAUDE_PLUGIN_ROOT}/scripts/lib/verify-coverage.sh"
if [[ -x "$HELPER" ]]; then
    bash "$HELPER" "$file_path"
fi

exit 0
