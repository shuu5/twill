#!/usr/bin/env bash
# PreToolUse hook: Issue 起票前 co-explore 強制 (ADR-037, 不変条件 P)
#
# 動作:
#   1. tool_name が "Bash" 以外 → no-op (exit 0)
#   2. command が "gh issue create" にマッチしない → no-op (exit 0)
#   3. 以下の condition で allow / deny を判定:
#
#   [allow path]
#   a. SKIP_ISSUE_GATE=1 + SKIP_ISSUE_REASON='<reason>' → log BYPASS, exit 0
#      SKIP_ISSUE_REASON 欠落 → deny + actionable message
#   b. TWL_CALLER_AUTHZ=co-explore-bootstrap + /tmp/.co-explore-bootstrap-*.json (any mtime) → exit 0
#   c. TWL_CALLER_AUTHZ=co-issue-phase4-create + .controller-issue/<sid>/explore-summary.md (mtime < 2h) → exit 0
#      explore-summary 不在 → deny + actionable message
#   d. /tmp/.co-issue-phase3-gate-*.json が存在 → exit 0 (既存 hook が判定済)
#
#   [deny path]
#   - 上記いずれにもマッチしない → deny + actionable error message

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# JSON パース失敗 → no-op
if ! printf '%s' "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

# Bash tool 以外 → no-op
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
if [[ "$tool_name" != "Bash" ]]; then
  exit 0
fi

# コマンド取得
CMD=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
if [[ -z "$CMD" ]]; then
  exit 0
fi

# gh issue create にマッチしない → no-op
if ! printf '%s' "$CMD" | grep -qE '\bgh\s+issue\s+create\b'; then
  exit 0
fi

LOG_FILE="/tmp/issue-create-gate.log"
log_event() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# (a) SKIP_ISSUE_GATE bypass
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])SKIP_ISSUE_GATE=1([[:space:]]|$)'; then
  REASON=$(printf '%s' "$CMD" | grep -oE "SKIP_ISSUE_REASON=['\"]?[^'\"[:space:]]+['\"]?" | head -1 | sed "s/SKIP_ISSUE_REASON=['\"]//;s/['\"]$//" || echo "")
  if [[ -z "$REASON" ]]; then
    DENY_MSG='SKIP_ISSUE_GATE=1 を使う場合は SKIP_ISSUE_REASON を必ず併記してください。

例: SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON='"'"'trivial config: label rename'"'"' gh issue create ...

詳細: ADR-037 / 不変条件 P / 親 epic #1578'
    jq -nc --arg reason "$DENY_MSG" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
    exit 0
  fi
  log_event "BYPASS reason=${REASON} cmd_hash=$(printf '%s' "$CMD" | sha256sum | head -c8)"
  exit 0
fi

_SESSION_TMP_DIR="${SESSION_TMP_DIR:-/tmp}"

# (b) co-explore Step 1 bootstrap path
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])TWL_CALLER_AUTHZ=co-explore-bootstrap([[:space:]]|$)'; then
  BOOTSTRAP_FILES=("${_SESSION_TMP_DIR}"/.co-explore-bootstrap-*.json)
  if [[ -e "${BOOTSTRAP_FILES[0]}" ]]; then
    AGE=$(( $(date +%s) - $(stat -c %Y "${BOOTSTRAP_FILES[0]}" 2>/dev/null || echo 0) ))
    log_event "ALLOW caller=co-explore-bootstrap age=${AGE}s"
  else
    log_event "WARN caller=co-explore-bootstrap-env-only state_file_missing"
  fi
  exit 0
fi

# (c) co-issue Phase 4 create path
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])TWL_CALLER_AUTHZ=co-issue-phase4-create([[:space:]]|$)'; then
  CONTROLLER_DIR="${CONTROLLER_ISSUE_DIR:-.controller-issue}"
  SUMMARY_FILE=$(find "$CONTROLLER_DIR" -name "explore-summary.md" -mmin -120 2>/dev/null | head -1 || echo "")
  if [[ -n "$SUMMARY_FILE" ]]; then
    log_event "ALLOW caller=co-issue-phase4-create summary=${SUMMARY_FILE}"
    exit 0
  fi
  DENY_MSG='co-issue Phase 4 の Issue 起票には explore-summary が必要です。

  .controller-issue/<session-id>/explore-summary.md が見つかりませんでした。

先に /twl:co-explore <topic> を実行して explore-summary を作成してください。

詳細: ADR-037 / 不変条件 P / 親 epic #1578'
  jq -nc --arg reason "$DENY_MSG" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  exit 0
fi

# (d) 既存 phase3-gate file 存在 → 既存 hook に委譲
PHASE3_FILES=("${_SESSION_TMP_DIR}"/.co-issue-phase3-gate-*.json)
if [[ -e "${PHASE3_FILES[0]}" ]]; then
  exit 0
fi

# (deny path)
log_event "DENY no_caller_authz cmd_hash=$(printf '%s' "$CMD" | sha256sum | head -c8)"
DENY_MSG='Issue 起票前に co-explore による explore-summary が必須です。

大原則: co-explore → Todo → co-issue → Refined → co-autopilot (ADR-037, 不変条件 P)

【正規の手順】
  1. /twl:co-explore "<topic>" で問題を探索
  2. .explore/<N>/summary.md が auto-link される
  3. /twl:co-issue refine #<N> で精緻化 → Status=Refined
  4. /twl:co-autopilot で実装

【bypass (軽微 config 等)】
  SKIP_ISSUE_GATE=1 SKIP_ISSUE_REASON="trivial config: ..." gh issue create ...

詳細: ADR-037 / 不変条件 P / 親 epic #1578'

jq -nc --arg reason "$DENY_MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
