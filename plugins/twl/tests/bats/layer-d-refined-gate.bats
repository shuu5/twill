#!/usr/bin/env bats
# DEPRECATED: ADR-024 Phase B Tier A (Issue #1291) — pre-bash-refined-label-gate.sh 削除に伴い全テスト skip
# layer-d-refined-gate.bats — DEPRECATED (ADR-024 Phase B Tier A, Issue #1291)
#
# pre-bash-refined-label-gate.sh は削除済み。全テストを skip する。
# Sub-2 (#1292) で本ファイルごと削除予定。
#
# Scenarios:
#   1. 正規経路: session file 存在 + gh issue edit N --add-label refined → allow (exit 0)
#   2. 不正経路: session file 不在 + gh issue edit N --add-label refined → deny
#   3. 複合コマンド: gh issue edit ... && gh issue comment ... (refined 付与なし) → allow
#   4. wildcard label: --add-label bug (refined 以外) → allow
#   5. 部分マッチ: --add-label refined-v2 → deny (word boundary match)
#   6. Bash tool 以外 → no-op (exit 0)
#   7. tool_input.command なし → no-op
#   8. 不正 JSON 入力 → no-op
#   9. deny JSON が permissionDecision=deny を含む
#  10. deny メッセージに workflow 指示が含まれる
#  11. --label フラグでも検出される
#  12. gh issue edit を含まないコマンド → no-op
#  13. deny 後 exit 0 (hook が正常終了する)

load 'helpers/common'

HOOK_SRC=""
SESSION_FILE=""
SESSION_TMP_DIR_TEST=""

setup() {
  skip "DEPRECATED: pre-bash-refined-label-gate.sh は削除済み (ADR-024 Phase B Tier A, Issue #1291)"
  common_setup
  HOOK_SRC="$(cd "$REPO_ROOT" && pwd)/scripts/hooks/pre-bash-refined-label-gate.sh"
  SESSION_TMP_DIR_TEST="$SANDBOX/session-tmp"
  mkdir -p "$SESSION_TMP_DIR_TEST"
  SESSION_FILE="$SESSION_TMP_DIR_TEST/.spec-review-session-bats.json"
}

teardown() {
  common_teardown
}

# Build a Bash tool JSON payload
_bash_payload() {
  local cmd="$1"
  jq -nc --arg c "$cmd" '{tool_name:"Bash", tool_input:{command:$c}}'
}

# Run hook with payload on stdin (SESSION_TMP_DIR_TEST でセッションファイルを隔離)
_run_hook() {
  local payload="$1"
  echo "$payload" | SESSION_TMP_DIR="$SESSION_TMP_DIR_TEST" bash "$HOOK_SRC"
}

# ---------------------------------------------------------------------------
# Scenario 1: 正規経路 — session file 存在 → allow
# WHEN /tmp/.spec-review-session-*.json が存在し
#      gh issue edit 843 --add-label refined が実行される
# THEN exit 0（allow）で deny 出力なし
# ---------------------------------------------------------------------------
@test "正規経路: session file 存在時に allow する" {
  touch "$SESSION_FILE"
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
}

@test "正規経路: session file 存在時に deny 出力が出ない" {
  touch "$SESSION_FILE"
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny when session file exists: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario 2: 不正経路 — session file 不在 → deny
# WHEN /tmp/.spec-review-session-*.json が存在せず
#      gh issue edit 843 --add-label refined が実行される
# THEN permissionDecision=deny を含む JSON を出力する
# ---------------------------------------------------------------------------
@test "不正経路: session file 不在時に deny する" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    || { echo "expected deny, got: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 3: 複合コマンド — refined ラベル付与なし → allow
# WHEN gh issue edit ... && gh issue comment ... で refined --add-label がない
# THEN gate scope 外として allow する
# ---------------------------------------------------------------------------
@test "複合コマンド: refined 付与なし複合コマンドは allow する" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --remove-label bug && gh issue comment 843 \"done\"")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny for non-refined compound command: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario 4: wildcard label — refined 以外のラベル付与 → allow
# WHEN --add-label bug (refined でないラベル) が実行される
# THEN allow する
# ---------------------------------------------------------------------------
@test "wildcard label: refined 以外のラベル付与は allow する" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label bug")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny for non-refined label: $output" >&2
    return 1
  fi
}

@test "wildcard label: --add-label enhancement は allow する" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label enhancement")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny for enhancement label: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario 5: 部分マッチ — --add-label refined-v2 → deny
# WHEN ラベル名が refined-v2 であっても \brefined\b が word boundary でマッチする
# THEN deny する（spec: refined は word として出現するため）
# ---------------------------------------------------------------------------
@test "部分マッチ: --add-label refined-v2 は deny する" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined-v2")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    || { echo "expected deny for refined-v2 label, got: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 6: Bash tool 以外 → no-op
# WHEN tool_name が Edit など Bash 以外である
# THEN exit 0、出力なし
# ---------------------------------------------------------------------------
@test "Bash tool 以外 (Edit) は no-op" {
  local payload
  payload=$(jq -nc '{tool_name:"Edit", tool_input:{file_path:"/tmp/foo.txt"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Bash tool 以外 (Skill) は no-op" {
  local payload
  payload=$(jq -nc '{tool_name:"Skill", tool_input:{skill:"some-skill"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 7: tool_input.command なし → no-op
# WHEN tool_name=Bash だが command が空の場合
# THEN exit 0、出力なし
# ---------------------------------------------------------------------------
@test "tool_input.command なし は no-op" {
  local payload
  payload=$(jq -nc '{tool_name:"Bash", tool_input:{}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Scenario 8: 不正 JSON 入力 → no-op
# WHEN stdin が JSON でない
# THEN exit 0、出力なし
# ---------------------------------------------------------------------------
@test "不正 JSON 入力は no-op (exit 0)" {
  run bash -c "echo 'not-a-json{' | SESSION_TMP_DIR=\"$SESSION_TMP_DIR_TEST\" bash \"$HOOK_SRC\""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "空入力は no-op (exit 0)" {
  run bash -c "echo '' | SESSION_TMP_DIR=\"$SESSION_TMP_DIR_TEST\" bash \"$HOOK_SRC\""
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scenario 9: deny JSON 構造検証
# WHEN session file 不在で deny が発火する
# THEN JSON に hookSpecificOutput.permissionDecision=deny が含まれる
# ---------------------------------------------------------------------------
@test "deny 時の JSON に hookSpecificOutput.hookEventName=PreToolUse が含まれる" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' \
    || { echo "hookEventName not PreToolUse: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 10: deny メッセージに workflow 指示が含まれる
# WHEN deny が発生する
# THEN permissionDecisionReason に workflow-issue-lifecycle または workflow-issue-refine が含まれる
# ---------------------------------------------------------------------------
@test "deny メッセージに workflow-issue-lifecycle が含まれる" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("workflow-issue-lifecycle")' \
    || { echo "workflow-issue-lifecycle not in deny reason: $output" >&2; return 1; }
}

@test "deny メッセージに Layer D enforcement が含まれる" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("Layer D")' \
    || { echo "Layer D not in deny reason: $output" >&2; return 1; }
}

# ---------------------------------------------------------------------------
# Scenario 11: --label フラグでも検出される
# WHEN --add-label の代わりに --label を使っても deny される
# ---------------------------------------------------------------------------
@test "--label フラグでも deny される（session file 不在時）" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --label refined")"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' \
    || { echo "expected deny for --label flag, got: $output" >&2; return 1; }
}

@test "--label フラグで session file 存在時は allow する" {
  touch "$SESSION_FILE"
  run _run_hook "$(_bash_payload "gh issue edit 843 --label refined")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny when session file exists (--label): $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario 12: gh issue edit を含まないコマンド → no-op
# WHEN コマンドに gh issue edit が含まれない
# THEN allow する（gate は gh issue edit にのみ発火）
# ---------------------------------------------------------------------------
@test "gh issue edit を含まない refined 付与は no-op" {
  run _run_hook "$(_bash_payload "gh label create refined --color red")"
  [ "$status" -eq 0 ]
  if echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' 2>/dev/null; then
    echo "unexpected deny for non-issue-edit command: $output" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Scenario 13: deny 後 exit 0 (hook 正常終了)
# WHEN deny が発生する
# THEN exit code は 0（hook はエラーではなく正常終了）
# ---------------------------------------------------------------------------
@test "deny 時の exit code は 0（hook は正常終了）" {
  run _run_hook "$(_bash_payload "gh issue edit 843 --add-label refined")"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# deps.yaml 登録確認
# WHEN plugins/twl/deps.yaml を参照する
# THEN scripts セクションに pre-bash-refined-label-gate エントリが存在する
# ---------------------------------------------------------------------------
@test "deps.yaml に pre-bash-refined-label-gate エントリが存在する" {
  local deps_yaml="$REPO_ROOT/deps.yaml"
  [[ -f "$deps_yaml" ]] || { echo "deps.yaml not found at $deps_yaml" >&2; return 1; }
  grep -q "pre-bash-refined-label-gate" "$deps_yaml" || {
    echo "pre-bash-refined-label-gate not found in deps.yaml" >&2
    return 1
  }
}

@test "deps.yaml の pre-bash-refined-label-gate エントリに path が設定されている" {
  local deps_yaml="$REPO_ROOT/deps.yaml"
  [[ -f "$deps_yaml" ]] || { echo "deps.yaml not found at $deps_yaml" >&2; return 1; }
  grep -A5 "pre-bash-refined-label-gate:" "$deps_yaml" | grep -q "path:" || {
    echo "path field not found in pre-bash-refined-label-gate entry" >&2
    return 1
  }
}
