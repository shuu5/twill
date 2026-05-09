#!/usr/bin/env bash
# PreToolUse hook: merge-gate FAIL 状態で gh pr merge / auto-merge.sh を block (Issue #1626 AC3)
#
# 動作:
#   1. tool_name が "Bash" 以外 → no-op (exit 0)
#   2. command に gh pr merge または auto-merge.sh を含まない → no-op (exit 0)
#   3. 以下の condition で allow / deny を判定:
#
#   [allow path]
#   a. command に TWL_MERGE_GATE_OVERRIDE='<理由>' プレフィックスがある
#      → audit log に記録して通過 (stall recovery のみ許可、不変条件 R)
#   b. merge-gate.json 不在 → graceful passthrough (gate 未実行ケース、非 autopilot PR)
#   c. merge-gate.json status != FAIL → 通過
#
#   [deny path]
#   - merge-gate.json status=FAIL かつ override 未設定 → deny + actionable message
#
# 既存 pre-bash-merge-guard.sh との関係:
#   - merge-guard: Worker からの merge を AUTOPILOT_DIR 設定時に block (Pilot/main は素通り)
#   - merge-gate-block (本 hook): Pilot/main session からの merge も merge-gate verify
#   - 両者は AND 評価 (hooks 配列を順次評価) なので相互補完

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

CMD=$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')
if [[ -z "$CMD" ]]; then
  exit 0
fi

# gh pr merge または auto-merge.sh にマッチしない → no-op
if ! printf '%s' "$CMD" | grep -qE '(gh[[:space:]]+pr[[:space:]]+merge|auto-merge\.sh)'; then
  exit 0
fi

LOG_FILE="/tmp/merge-gate-block.log"
log_event() {
  printf '[%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG_FILE" 2>/dev/null || true
}

# autopilot dir 解決:
#   1. AUTOPILOT_DIR env (Worker session)
#   2. <git-common-dir>/../main/.autopilot (Pilot session、main worktree の autopilot を参照)
#   3. .autopilot (CWD 相対デフォルト)
_resolve_autopilot_dir() {
  if [[ -n "${AUTOPILOT_DIR:-}" ]]; then
    echo "$AUTOPILOT_DIR"
    return
  fi
  local common_dir
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null || echo "")
  if [[ -n "$common_dir" && -d "${common_dir}/../main/.autopilot" ]]; then
    echo "${common_dir}/../main/.autopilot"
    return
  fi
  echo ".autopilot"
}

AUTOPILOT_DIR_RESOLVED=$(_resolve_autopilot_dir)
MG_JSON="${AUTOPILOT_DIR_RESOLVED}/checkpoints/merge-gate.json"

# (b) merge-gate.json 不在 → graceful passthrough (gate 未実行 PR / 非 autopilot PR)
if [[ ! -f "$MG_JSON" ]]; then
  log_event "ALLOW merge-gate.json not found path=${MG_JSON}"
  exit 0
fi

# status 取得 (jq があれば優先、無ければ grep フォールバック)
mg_status=""
if command -v jq >/dev/null 2>&1; then
  mg_status=$(jq -r '.status // empty' "$MG_JSON" 2>/dev/null || echo "")
else
  mg_status=$(grep -oE '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$MG_JSON" 2>/dev/null \
    | sed -E 's/.*"status"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/' \
    | head -n1)
fi

# (c) FAIL 以外 → 通過
if [[ "$mg_status" != "FAIL" ]]; then
  log_event "ALLOW status=${mg_status}"
  exit 0
fi

# (a) TWL_MERGE_GATE_OVERRIDE が command 文字列に含まれる → 通過 + audit log
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])TWL_MERGE_GATE_OVERRIDE='; then
  REASON=$(printf '%s' "$CMD" | grep -oP "TWL_MERGE_GATE_OVERRIDE='[^']+'" | head -1 | sed "s/TWL_MERGE_GATE_OVERRIDE='//;s/'$//" 2>/dev/null \
    || printf '%s' "$CMD" | grep -oP 'TWL_MERGE_GATE_OVERRIDE="[^"]+"' | head -1 | sed 's/TWL_MERGE_GATE_OVERRIDE="//;s/"$//' 2>/dev/null \
    || echo "unspecified")
  AUDIT_LOG="${AUTOPILOT_DIR_RESOLVED}/merge-override-audit.log"
  mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  user="${USER:-$(id -un 2>/dev/null || echo unknown)}"
  printf '%s\tuser=%s\treason=%s\tmerge_gate=%s\n' \
    "$ts" "$user" "$REASON" "$MG_JSON" >> "$AUDIT_LOG" 2>/dev/null || true
  log_event "OVERRIDE user=${user} reason=${REASON}"
  exit 0
fi

# (deny path)
log_event "DENY status=${mg_status} cmd_hash=$(printf '%s' "$CMD" | sha256sum | head -c8)"
DENY_MSG="merge-gate FAIL 状態のため gh pr merge / auto-merge.sh の実行を block します。

merge-gate.json: ${MG_JSON}
status: ${mg_status}

【正規の手順】
  1. merge-gate REJECT 原因 (specialist findings) を fix
  2. autopilot で再 merge-gate を走らせる
  3. status=PASS / WARN になってから merge

【緊急時 override】 (stall recovery のみ、不変条件 R)
  TWL_MERGE_GATE_OVERRIDE='<理由>' を command プレフィックスに付けてください。
  override は ${AUTOPILOT_DIR_RESOLVED}/merge-override-audit.log に記録されます。
  content-REJECT override は不変条件 R により禁止されています。

詳細: 不変条件 R / S / Issue #1626"

jq -nc --arg reason "$DENY_MSG" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
exit 0
