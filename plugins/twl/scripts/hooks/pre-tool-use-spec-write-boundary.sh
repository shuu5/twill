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
    "")
        # user manual edit、warning skip (人間の判断を尊重)
        exit 0
        ;;
    tool-architect)
        # === R-14 時系列パターン warning (2026-05-16 追加、change 001-spec-purify C9b) ===
        # tool-architect caller の場合、content semantic warning を返す
        # deny ではなく allow + additionalContext (Phase E twl_spec_content_check との連携)

        # 例外パス (R-14 例外: changelog.html / archive/ / changes/ / decisions/ は narrative 許容)
        case "$file_path" in
            */architecture/spec/changelog.html|*/architecture/archive/*|*/architecture/changes/*|*/architecture/decisions/*)
                exit 0
                ;;
        esac

        # tool_input から content 取得 (Edit: new_string / Write: content)
        content=$(echo "$payload" | jq -r '.tool_input.new_string // .tool_input.content // empty')
        if [[ -z "$content" ]]; then
            exit 0
        fi

        # 時系列マーカー / 未完了マーカー / 過去形 narration 検出 (Vale rule と同期)
        if echo "$content" | grep -qE '\([0-9]{4}-[0-9]{1,2}-[0-9]{1,2}\)|Phase [0-9]+ で|以前は|を確認した|により実施した|を行った|であった|していた|\bTODO\b|\bFIXME\b|\bWIP\b|未作成|\bstub\b|未完了|未決定|未確定'; then
            jq -nc '
            {
              hookSpecificOutput: {
                hookEventName: "PreToolUse",
                permissionDecision: "allow",
                additionalContext: "R-14 warning (spec content semantic): 時系列マーカー / 未完了マーカー / 過去形 narration を検出。現在形 declarative に書き換えるか、archive/ または changes/<NNN>-<slug>/ に移動を検討。Phase E で twl_spec_content_check を実行して詳細確認推奨。"
              }
            }'
        fi
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
