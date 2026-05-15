#!/usr/bin/env bash
# PostToolUseFailure hook (Stage A、command hook): Bash 失敗時に LLM に memory_store を促す
#
# 仕様: hooks-mcp-policy.html §5 (Phase I dig Q2 確定、Phase 6 review C-3 で Stage 戦略追記)
#   matcher: "Bash" (Phase 1 PoC scope、narrow)
#   input field: tool_name / tool_input / error / error_type / is_interrupt / is_timeout (公式 verified)
#   error string 最初 200 文字のみ取り込み (§5.3 noise 防止)
#
# Stage 戦略 (Phase I dig + user 確定 2026-05-15):
#   Stage A (本 file、Phase 1 PoC C1): command hook、additionalContext で LLM に学習促進
#   Stage B (Phase 2): EXP-043 で mcp_tool hook template 変数展開 empirical verify
#   Stage C (Phase 2 以降、EXP-043 verified 後): mcp_tool hook 直接 (hooks-mcp-policy.html §5.2 形式)、本 file は archive
#
# 旧 post-tool-use-bash-error.sh (B-7 self-improve、.self-improve/errors.jsonl) は本 hook に置換 (旧 script は archive、rollback 用 hooks.json.bak から参照可)
# script 構造: set -uo pipefail のみ (host-safety/spec-write-boundary と統一)

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")
if ! echo "$payload" | jq empty 2>/dev/null; then
    exit 0
fi

tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
if [[ "$tool_name" != "Bash" ]]; then
    exit 0
fi

command=$(echo "$payload" | jq -r '.tool_input.command // empty' | head -c 200)
error=$(echo "$payload" | jq -r '.error // empty' | head -c 200)
error_type=$(echo "$payload" | jq -r '.error_type // empty')

# additionalContext で LLM に memory_store を促す (Stage A pattern、Migration message は header comment に移動)
jq -nc --arg cmd "$command" --arg err "$error" --arg typ "$error_type" '
{
  hookSpecificOutput: {
    hookEventName: "PostToolUseFailure",
    additionalContext: (
      "[failure-learn] Bash failure detected.\n" +
      "Command: " + $cmd + "\n" +
      "Error: " + $err + " (type: " + $typ + ")\n" +
      "Recommendation: mcp__doobidoo__memory_store with type=feedback + " +
      "tags=[bash-failure, auto-learned] to record this pattern for future avoidance."
    )
  }
}'
exit 0
