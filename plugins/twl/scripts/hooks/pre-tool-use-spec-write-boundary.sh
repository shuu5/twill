#!/usr/bin/env bash
# PreToolUse hook: architecture/spec/* write boundary enforce (tool-architect 専任)
#
# Edit/Write/NotebookEdit tool が architecture/spec/* 配下に書き込もうとする際、
# caller が tool-architect / user (env unset) 以外であれば JSON deny を返す。
#
# caller 識別 (確定 2026-05-14、Phase C):
#   TWL_TOOL_CONTEXT env var を canonical caller marker として使用。
#     unset           → user manual edit (allow)
#     tool-architect  → tool-architect skill 経由 (allow)
#     その他           → deny (phaser-* / admin / tool-project / worker-* 等)
#
# 参照仕様: tool-architecture.html §3.4 + experiment-index.html#EXP-028

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

if [[ "$file_path" != *architecture/spec/* ]]; then
    exit 0
fi

caller="${TWL_TOOL_CONTEXT:-}"
case "$caller" in
    ""|tool-architect)
        exit 0
        ;;
    *)
        jq -nc --arg fp "$file_path" --arg c "$caller" '
        {
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason:
              ("spec write boundary: " + $fp + " は tool-architect 専任 (caller=" + $c + " は read-only、TWL_TOOL_CONTEXT=tool-architect で再実行してください)")
          }
        }'
        exit 0
        ;;
esac
