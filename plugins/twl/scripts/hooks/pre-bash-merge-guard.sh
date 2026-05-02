#!/usr/bin/env bash
# PreToolUse hook: Worker からの gh pr merge 直接実行を防止 (#671)
#
# Claude Code の PreToolUse フェーズで呼び出される。
# $TOOL_INPUT_command に `gh pr merge` が含まれる場合、
# AUTOPILOT_DIR 設定時（= Worker セッション）のみブロックする。
#
# auto-merge.sh 経由の呼び出しは許可（auto-merge.sh 内のガードに委譲）。
#
# 不変条件 C: Worker は gh pr merge を直接実行してはならない。
#
# 終了コード:
#   0 — 通過
#   2 — ブロック

set -uo pipefail

SHADOW_LOG="${MCP_SHADOW_MERGE_LOG:-/tmp/mcp-shadow-merge-guard.log}"
cmd="${TOOL_INPUT_command:-}"

# コマンドが空 → no-op（shadow log も書かない）
[[ -z "$cmd" ]] && exit 0

# shadow log への追記ヘルパー（mcp-shadow-compare.sh 互換 JSONL、#1276）
_log_shadow() {
  local verdict="$1"
  local event_id="mg-$(date -u +%s 2>/dev/null || echo "0")-$$-${RANDOM}"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "1970-01-01T00:00:00Z")"
  if command -v jq &>/dev/null; then
    jq -nc \
      --arg id "$event_id" \
      --arg ts "$ts" \
      --arg verdict "$verdict" \
      --arg cmd "$cmd" \
      '{"event_id":$id,"ts":$ts,"source":"bash","verdict":$verdict,"command":$cmd}' \
      >> "$SHADOW_LOG" 2>/dev/null || true
  else
    local escaped_cmd
    escaped_cmd=$(printf '%s' "$cmd" | sed 's/\\/\\\\/g; s/"/\\"/g')
    printf '{"event_id":"%s","ts":"%s","source":"bash","verdict":"%s","command":"%s"}\n' \
      "$event_id" "$ts" "$verdict" "$escaped_cmd" \
      >> "$SHADOW_LOG" 2>/dev/null || true
  fi
}

# gh pr merge を含まない → 種別に応じた verdict で shadow log 記録して通過
if ! echo "$cmd" | grep -qE '(^|[;&|]\s*)gh\s+pr\s+merge'; then
  if echo "$cmd" | grep -qE '(^|[;&|]\s*)git\s+merge'; then
    _log_shadow "allow"
  else
    _log_shadow "skip"
  fi
  exit 0
fi

# auto-merge.sh 経由 → 許可（auto-merge.sh 内のガードに委譲）
if echo "$cmd" | grep -qE 'auto-merge\.sh'; then
  _log_shadow "allow"
  exit 0
fi

# AUTOPILOT_DIR 未設定 → 通常セッション、許可
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  _log_shadow "allow"
  exit 0
fi

# Worker セッションからの gh pr merge 直接実行 → ブロック
_log_shadow "block"
echo "不変条件C: Worker からの gh pr merge 直接実行は禁止。auto-merge.sh 経由で実行してください (#671)" >&2
exit 2
