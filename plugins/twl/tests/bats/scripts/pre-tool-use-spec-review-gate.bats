#!/usr/bin/env bats
# pre-tool-use-spec-review-gate.bats
#
# Tests for plugins/twl/scripts/hooks/pre-tool-use-spec-review-gate.sh
#
# Spec: deltaspec/changes/issue-446/specs/pretooluse-gate/spec.md
#   Requirement: PreToolUse gate スクリプト（pre-tool-use-spec-review-gate.sh）
#
# Scenarios:
#   1. completed < total でブロック: state={"total":3,"completed":1} + Skill(issue-review-aggregate) → deny JSON
#   2. completed == total でゲート通過: state={"total":3,"completed":3} + Skill(issue-review-aggregate) → no deny
#   3. state ファイル不在（フォールバック）: state ファイルなし + Skill(issue-review-aggregate) → no deny
#   4. 対象外ツール(Edit) → noop
#   5. Skill だが skill が issue-review-aggregate 以外 → noop
#   6. deny メッセージに残り Issue 数を含む
#   7. deny メッセージに /twl:issue-spec-review 呼び出し指示を含む
#   8. completed == total 時、state file がクリーンアップされる
#   9. completed == total 時、lock file がクリーンアップされる（存在する場合）
#  10. 不正 JSON 入力 → noop (exit 0)
#  11. state ファイルが symlink の場合 → noop（セキュリティ: フォールバック）
#  12. completed > total（異常値）→ ゲート通過（安全側フォールバック）

load '../helpers/common'

HOOK_SRC=""

setup() {
  common_setup

  HOOK_SRC="$(cd "$REPO_ROOT" && pwd)/scripts/hooks/pre-tool-use-spec-review-gate.sh"

  # Override CLAUDE_PROJECT_ROOT to sandbox for predictable hash
  export CLAUDE_PROJECT_ROOT="$SANDBOX"

  EXPECTED_HASH=$(printf '%s' "$SANDBOX" | cksum | awk '{print $1}')
  export EXPECTED_HASH
  STATE_FILE="/tmp/.spec-review-session-${EXPECTED_HASH}.json"
  export STATE_FILE
  LOCK_FILE="/tmp/.spec-review-lock-${EXPECTED_HASH}"
  export LOCK_FILE
}

teardown() {
  rm -f "$STATE_FILE" "$LOCK_FILE" 2>/dev/null || true
  common_teardown
}

# Helper: build a Skill tool_use JSON payload
_skill_payload() {
  local skill_name="$1"
  jq -nc --arg s "$skill_name" '{tool_name:"Skill", tool_input:{skill:$s}}'
}

# Helper: invoke hook with given JSON payload
_run_hook() {
  local payload="$1"
  echo "$payload" | bash "$HOOK_SRC"
}

# ---------------------------------------------------------------------------
# Scenario 1: completed < total でブロック
# WHEN state={"total":3,"completed":1} + Skill(issue-review-aggregate) が呼ばれる
# THEN permissionDecision=deny + 残り Issue 数 + /twl:issue-spec-review 指示
# ---------------------------------------------------------------------------
@test "completed < total のとき deny を返す" {
  printf '{"total":3,"completed":1,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    || { echo "expected deny, got: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario: deny メッセージに残り Issue 数を含む
# ---------------------------------------------------------------------------
@test "deny メッセージに残り Issue 数（2）が含まれる" {
  printf '{"total":3,"completed":1,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  # remaining = 3 - 1 = 2
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("2")' \
    || { echo "remaining count not in message: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario: deny メッセージに /twl:issue-spec-review 呼び出し指示を含む
# ---------------------------------------------------------------------------
@test "deny メッセージに /twl:issue-spec-review が含まれる" {
  printf '{"total":3,"completed":1,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("/twl:issue-spec-review")' \
    || { echo "/twl:issue-spec-review not in message: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 2: completed == total でゲート通過
# WHEN state={"total":3,"completed":3} + Skill(issue-review-aggregate) が呼ばれる
# THEN deny を返さない
# ---------------------------------------------------------------------------
@test "completed == total のときゲートを通過する（deny しない）" {
  printf '{"total":3,"completed":3,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  # No deny decision
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny when completed==total: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario 8: completed == total 時 state file がクリーンアップされる
# ---------------------------------------------------------------------------
@test "completed == total 時に state ファイルが削除される" {
  printf '{"total":3,"completed":3,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  [ ! -f "$STATE_FILE" ] || { echo "state file not cleaned up" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 9: completed == total 時 lock file がクリーンアップされる（存在する場合）
# ---------------------------------------------------------------------------
@test "completed == total 時に lock ファイルが削除される（存在する場合）" {
  printf '{"total":2,"completed":2,"issues":{}}' > "$STATE_FILE"
  touch "$LOCK_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  [ ! -f "$LOCK_FILE" ] || { echo "lock file not cleaned up" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 3: state ファイル不在（フォールバック）
# WHEN state ファイルなし + Skill(issue-review-aggregate) が呼ばれる
# THEN deny しない（安全側フォールバック）
# ---------------------------------------------------------------------------
@test "state ファイル不在でもブロックしない（安全側フォールバック）" {
  # Ensure state file does not exist
  rm -f "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny when no state file: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# edge: 対象外ツール(Edit) → noop（出力なし）
# ---------------------------------------------------------------------------
@test "対象外ツール (Edit) は noop" {
  printf '{"total":3,"completed":0,"issues":{}}' > "$STATE_FILE"
  local payload
  payload=$(jq -nc '{tool_name:"Edit", tool_input:{file_path:"/tmp/foo.txt"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# edge: Skill だが skill が issue-review-aggregate 以外 → noop
# ---------------------------------------------------------------------------
@test "Skill ツールでも skill 名が issue-review-aggregate 以外なら noop" {
  printf '{"total":3,"completed":0,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "other-skill")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny for non-target skill: $output" >&2
    return 1
  fi
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# edge: 不正 JSON 入力 → noop (exit 0)
# ---------------------------------------------------------------------------
@test "不正 JSON 入力は noop (exit 0)" {
  run bash "$HOOK_SRC" <<< "not-a-json{"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# edge: state ファイルが symlink → noop（セキュリティフォールバック）
# ---------------------------------------------------------------------------
@test "state ファイルが symlink の場合はブロックしない（フォールバック）" {
  local real_file="${SANDBOX}/state-real.json"
  printf '{"total":3,"completed":0,"issues":{}}' > "$real_file"
  ln -s "$real_file" "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  # Should not deny (treat symlink as missing for security)
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny when state is symlink: $output" >&2
    rm -f "$real_file"
    return 1
  fi
  rm -f "$real_file"
}

# ---------------------------------------------------------------------------
# edge: completed > total（異常値）→ ゲート通過（安全側フォールバック）
# ---------------------------------------------------------------------------
@test "completed > total の異常値でもブロックしない（安全側フォールバック）" {
  printf '{"total":2,"completed":5,"issues":{}}' > "$STATE_FILE"
  run _run_hook "$(_skill_payload "issue-review-aggregate")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny when completed > total: $output" >&2
    return 1
  fi
}
