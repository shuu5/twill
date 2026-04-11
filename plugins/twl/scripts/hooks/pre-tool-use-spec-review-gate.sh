#!/usr/bin/env bash
# PreToolUse hook: spec-review 完了ゲート
#
# Skill(issue-review-aggregate) 呼び出し時に、セッション state の
# completed < total であれば deny する。
#
# 動作:
#   - tool_input.skill が "issue-review-aggregate" のときのみ発火
#   - セッション state ファイルが存在しない場合: フォールバック（通過）
#   - completed < total: deny（残り Issue 数と issue-spec-review 呼び出し指示）
#   - completed == total: 通過 → state file + lock file をクリーンアップ
#
# セッション state: /tmp/.spec-review-session-{hash}.json
# hash: CLAUDE_PROJECT_ROOT または PWD から cksum 算出

set -uo pipefail

payload=$(cat 2>/dev/null || echo "")

# JSON パース失敗 → no-op
if ! printf '%s' "$payload" | jq empty 2>/dev/null; then
  exit 0
fi

# Skill tool 以外 → no-op
tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
if [[ "$tool_name" != "Skill" ]]; then
  exit 0
fi

# skill 名を取得
skill_name=$(printf '%s' "$payload" | jq -r '.tool_input.skill // empty')
if [[ "$skill_name" != "issue-review-aggregate" ]]; then
  exit 0
fi

# hash 算出
HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
STATE_FILE="/tmp/.spec-review-session-${HASH}.json"
LOCK_FILE="/tmp/.spec-review-session-${HASH}.lock"

# LOCK_FILE の symlink チェック（flock 前に実施 — TOCTOU 対策）
if [[ -L "$LOCK_FILE" ]]; then
  exit 0
fi

# state ファイルの事前チェック（symlink + 存在）
# flock 取得前に -f と -L を同時検査して TOCTOU ウィンドウを最小化
if [[ -L "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# state を読み取る（flock 付き）
{
  flock -w 5 9 || exit 0  # ロック取得失敗 → フォールバック（通過）

  # flock 取得後に再チェック（TOCTOU ウィンドウを閉じる）
  if [[ -L "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
    exit 0
  fi

  TOTAL=$(jq -r '.total // 0' "$STATE_FILE" 2>/dev/null || echo "0")
  COMPLETED=$(jq -r '.completed // 0' "$STATE_FILE" 2>/dev/null || echo "0")

  # 数値バリデーション（TOTAL=0 はフォールバック通過）
  if ! [[ "$TOTAL" =~ ^[0-9]+$ ]] || ! [[ "$COMPLETED" =~ ^[0-9]+$ ]] || [[ "$TOTAL" -eq 0 ]]; then
    exit 0
  fi

  if [[ "$COMPLETED" -lt "$TOTAL" ]]; then
    REMAINING=$(( TOTAL - COMPLETED ))
    REASON="spec-review ゲート: 残り ${REMAINING} Issue が未完了です（${COMPLETED}/${TOTAL} 完了）。先に /twl:issue-spec-review を ${REMAINING} 回実行してください。"
    jq -nc \
      --arg reason "$REASON" \
      '{
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: "deny",
          permissionDecisionReason: $reason
        }
      }'
    exit 0
  fi

  # completed >= total → 通過 + クリーンアップ
  rm -f "$STATE_FILE"

} 9>"$LOCK_FILE"

# LOCK_FILE は flock ブロック外でクリーンアップ（flock 解放後）
rm -f "$LOCK_FILE"

exit 0
