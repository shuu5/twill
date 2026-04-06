#!/usr/bin/env bash
# PostToolUse hook: issue-spec-review specialist spawn の完全性検証
#
# Agent tool 呼び出し後に発火。
# manifest の全 specialist が spawn されたかを追跡し、
# 漏れがある状態で非 specialist agent が呼ばれた場合に警告を出力。

INPUT=$(cat)

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" != "Agent" ]] && exit 0

SUBAGENT_TYPE=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
[[ -z "$SUBAGENT_TYPE" ]] && exit 0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/../spec-review-manifest.sh"
[[ ! -f "$MANIFEST" ]] && exit 0

MANIFEST_SPECIALISTS=$(bash "$MANIFEST")
TOTAL_COUNT=$(printf '%s\n' "$MANIFEST_SPECIALISTS" | wc -l)

# プロジェクト固有のトラッキングファイル（CWD ベースのハッシュでスコープ）
TRACKING_HASH=$(printf '%s' "${CLAUDE_PROJECT_ROOT:-$PWD}" | cksum | awk '{print $1}')
TRACKING_FILE="/tmp/.spec-review-tracking-${TRACKING_HASH}.txt"

if printf '%s\n' "$MANIFEST_SPECIALISTS" | grep -qxF "$SUBAGENT_TYPE"; then
  # manifest に含まれる specialist を記録
  echo "$SUBAGENT_TYPE" >> "$TRACKING_FILE"
  # 重複除去
  sort -u "$TRACKING_FILE" -o "$TRACKING_FILE"

  SPAWNED_COUNT=$(wc -l < "$TRACKING_FILE")
  if [[ "$SPAWNED_COUNT" -ge "$TOTAL_COUNT" ]]; then
    # 全 specialist 完了 → トラッキングファイルを削除（次回の spec-review のためにリセット）
    rm -f "$TRACKING_FILE"
  fi
else
  # manifest 外の agent が呼ばれた場合 → 漏れチェック
  if [[ -f "$TRACKING_FILE" ]]; then
    SPAWNED_COUNT=$(wc -l < "$TRACKING_FILE")
    if [[ "$SPAWNED_COUNT" -lt "$TOTAL_COUNT" ]]; then
      MISSING=$(comm -23 \
        <(printf '%s\n' "$MANIFEST_SPECIALISTS" | sort) \
        <(sort "$TRACKING_FILE"))
      echo "⚠ spec-review-completeness: 以下の specialist が未 spawn です:" >&2
      while IFS= read -r s; do
        echo "  - $s" >&2
      done <<< "$MISSING"
      echo "  issue-spec-review Step 4 に戻り、全 specialist を spawn してください。" >&2
    fi
  fi
fi

exit 0
