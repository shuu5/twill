#!/usr/bin/env bash
# PreToolUse hook: Worker worktree 境界 pre-edit guard
#
# Edit/Write/NotebookEdit の対象パスを realpath -m で正規化し、
# 現在の worktree root の prefix 配下でなければ permissionDecision: deny を返す。
# AUTOPILOT_DIR 設定時のみ発火（通常セッション無影響）。
#
# 不変条件 B（Worktree ライフサイクル Pilot 専任）: Worker は worktree 内で完結。
# symlink 越えによる worktree 外編集を事前ブロックし、permission ダイアログでの
# Worker スタックを回避する。
#
# TOCTOU 注記: realpath 判定後の symlink 差し替え攻撃は想定脅威外
# （co-autopilot は信頼境界内）。本ガードの目的は誤操作・意図せぬ
# symlink 越えの事前ブロックである。

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# AUTOPILOT_DIR 未設定 → no-op（通常セッション）
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# JSON パース失敗時は no-op
if ! echo "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

tool_name=$(echo "$payload" | jq -r '.tool_name // empty')
case "$tool_name" in
  Edit|Write|NotebookEdit) ;;
  *) exit 0 ;;
esac

# Edit/Write は file_path、NotebookEdit は notebook_path
target=$(echo "$payload" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
if [[ -z "$target" ]]; then
  exit 0
fi

# realpath -m: 未存在ファイル（新規 Write）にも対応
resolved=$(realpath -m "$target" 2>/dev/null) || exit 0
if [[ -z "$resolved" ]]; then
  exit 0
fi

wt_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
if [[ -z "$wt_root" ]]; then
  exit 0
fi
wt_root_resolved=$(realpath "$wt_root" 2>/dev/null) || exit 0
if [[ -z "$wt_root_resolved" ]]; then
  exit 0
fi

# 末尾スラッシュ付き prefix 比較で /foo と /foobar の誤マッチを回避
if [[ "$resolved" == "$wt_root_resolved" || "$resolved" == "$wt_root_resolved/"* ]]; then
  exit 0
fi

# worktree 外 → deny
jq -nc \
  --arg target "$target" \
  --arg resolved "$resolved" \
  --arg wt "$wt_root_resolved" \
  '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: ("不変条件 B 違反: worktree 外編集を試行 / target=" + $target + " / resolved=" + $resolved + " / worktree=" + $wt)
    }
  }'

exit 0
