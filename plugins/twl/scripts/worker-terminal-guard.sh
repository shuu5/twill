#!/usr/bin/env bash
# worker-terminal-guard.sh - Worker chain 終端での status terminal 検証ガード
#
# Issue #131: Worker terminal status 検証ガード（chain 終端での status 漏れ検出）
#
# terminal 集合: {"merge-ready", "done", "failed", "conflict"}
#   - cli/twl/src/twl/autopilot/state.py の _TRANSITIONS 定義と一致
#   - merge-ready / failed / conflict は further 遷移可能だが、Worker chain の
#     責務としては「次フェーズに引き渡せる状態」として扱う
#
# 挙動:
#   - AUTOPILOT_DIR 未設定 → no-op（非 autopilot フローには影響させない）
#   - issue 番号なし        → no-op（保守的スキップ）
#   - status が terminal   → no-op（exit 0）
#   - status が非 terminal → stderr WARNING + state write status=failed
#                             failure={message:"non_terminal_chain_end",
#                                      step:"worker-terminal-guard"} → exit 1
#
# Usage: worker-terminal-guard.sh <issue_num>
#
# trap EXIT には登録しない（cleanup 処理との競合リスク）。chain-runner.sh の
# main 関数終端から明示呼び出しする。

set -uo pipefail

# AUTOPILOT_DIR 未設定 → no-op（非 autopilot 保護）
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

issue_num="${1:-}"
if [[ -z "$issue_num" ]]; then
  exit 0
fi

# 数値検証（引数注入防止）
if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
  exit 0
fi

current=$(python3 -m twl.autopilot.state read \
  --autopilot-dir "$AUTOPILOT_DIR" \
  --type issue --issue "$issue_num" --field status 2>/dev/null || echo "")

case "$current" in
  merge-ready|done|failed|conflict)
    # terminal — no-op
    exit 0
    ;;
  *)
    echo "[worker-terminal-guard] WARNING: issue-${issue_num}.json status=${current:-empty} (non-terminal). Force-failing." >&2
    python3 -m twl.autopilot.state write \
      --autopilot-dir "$AUTOPILOT_DIR" \
      --type issue --issue "$issue_num" --role worker \
      --set "status=failed" \
      --set 'failure={"message":"non_terminal_chain_end","step":"worker-terminal-guard"}' >&2 || true
    exit 1
    ;;
esac
