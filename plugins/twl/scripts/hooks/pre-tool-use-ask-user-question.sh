#!/usr/bin/env bash
# PreToolUse hook: AskUserQuestion 自動応答（autopilot ヘッドレス Worker 用）
# 選択肢付き → 最初の option を選択、open-ended → "(autopilot: skipped)"
set -uo pipefail

INPUT=$(cat 2>/dev/null || echo "")

# AUTOPILOT_DIR 未設定 or 空 → 通常セッションでは自動応答しない
if [[ -z "${AUTOPILOT_DIR:-}" ]]; then
  exit 0
fi

# AUTOPILOT_DIR が実在するディレクトリでなければ無視
if [[ ! -d "${AUTOPILOT_DIR}" ]]; then
  exit 0
fi

# JSON パース失敗時は何もせず exit 0
if ! echo "$INPUT" | jq empty 2>/dev/null; then
  exit 0
fi

# questions 配列を取得
QUESTIONS=$(echo "$INPUT" | jq -c '.tool_input.questions // []' 2>/dev/null)
if [[ -z "$QUESTIONS" || "$QUESTIONS" == "null" || "$QUESTIONS" == "[]" ]]; then
  exit 0
fi

# answers オブジェクトを構築
ANSWERS="{}"
QUESTION_COUNT=$(echo "$QUESTIONS" | jq 'length' 2>/dev/null || echo "0")

for ((i=0; i<QUESTION_COUNT; i++)); do
  QUESTION_TEXT=$(echo "$QUESTIONS" | jq -r ".[$i].question // \"\"" 2>/dev/null)
  OPTIONS_COUNT=$(echo "$QUESTIONS" | jq ".[$i].options // [] | length" 2>/dev/null || echo "0")

  if [[ "$OPTIONS_COUNT" -gt 0 ]]; then
    # 選択肢あり → 最初の option の label を選択
    ANSWER=$(echo "$QUESTIONS" | jq -r ".[$i].options[0].label // \"\"" 2>/dev/null)
  else
    # open-ended → skipped マーカー
    ANSWER="(autopilot: skipped)"
  fi

  ANSWERS=$(echo "$ANSWERS" | jq --arg q "$QUESTION_TEXT" --arg a "$ANSWER" '. + {($q): $a}' 2>/dev/null)
done

# updatedInput: 元の questions を保持し answers を追加
UPDATED_INPUT=$(echo "$INPUT" | jq -c --argjson answers "$ANSWERS" '{questions: .tool_input.questions, answers: $answers}' 2>/dev/null)

# hookSpecificOutput を出力
jq -n --argjson updated "$UPDATED_INPUT" '{
  hookSpecificOutput: {
    permissionDecision: "allow",
    updatedInput: $updated
  }
}'

exit 0
