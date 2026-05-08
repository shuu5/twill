#!/usr/bin/env bats
# settings-json-status-transition-mcp.bats
#
# RED テストスタブ (Issue #1563)
#
# AC1: .claude/settings.json PreToolUse[3] (Bash matcher) hooks 配列に mcp_tool entry を追加
#      (server: "twl", tool: "twl_validate_status_transition")
# AC2: hook 入力は {"command": "${tool_input.command}", "tool_name": "${tool_name}"}
# AC3: timeout: 10 (秒単位)
# AC4: 配置順序 Sub-1 (command型, [5]) → Sub-3 (mcp_tool型, [6])。Sub-1 不在時 skip
# AC5: outputType: "log" で配置 (shadow mode、Bash 実行を block しない)
# AC6: bats 6 件 (S1-S6) を本ファイルに追加
# AC7: bypass override は autopilot-launch.sh / launcher.py 集約継続 (プロセス AC)
# AC8: shadow → blocking 切替 follow-up Issue 起票 (merge 時プロセス AC)
#
# 全テストは実装前に fail (RED) する。
# 現在 settings.json には twl_validate_status_transition エントリが存在しないため、
# S1-S5 は自然に fail する。
#

load '../helpers/common'

SETTINGS_JSON=""

setup() {
  common_setup

  local git_root
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"

  SETTINGS_JSON="${git_root}/.claude/settings.json"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# S1: PreToolUse[3] Bash matcher の hooks[] から type==mcp_tool,
#     server==twl, tool==twl_validate_status_transition を select → exit 0,
#     entry が 1 件返る
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "S1: settings.json PreToolUse Bash matcher に twl_validate_status_transition mcp_tool hook が 1 件存在する" {
  # AC1: Bash matcher の hooks 配列に mcp_tool entry が追加されていること
  # RED: 現時点では twl_validate_status_transition エントリが存在しないため fail する
  local count
  count=$(jq '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks[]?
    | select(.type == "mcp_tool" and .server == "twl" and .tool == "twl_validate_status_transition")
  ] | length' "$SETTINGS_JSON")
  [ "$count" -eq 1 ]
}

# ---------------------------------------------------------------------------
# S2: S1 entry の .input フィールド → command と tool_name が
#     "${tool_input.command}" / "${tool_name}" の string 値
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "S2: twl_validate_status_transition hook の input.command が \${tool_input.command} を参照する" {
  # AC2: hook input の command フィールドが宣言的展開形式であること
  # RED: entry 未追加のため fail する
  local input_command
  input_command=$(jq -r '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_status_transition")
  ] | .[0].input.command // empty' "$SETTINGS_JSON")
  [[ "$input_command" == '${tool_input.command}' ]]
}

@test "S2: twl_validate_status_transition hook の input.tool_name が \${tool_name} を参照する" {
  # AC2: hook input の tool_name フィールドが宣言的展開形式であること
  # RED: entry 未追加のため fail する
  local input_tool_name
  input_tool_name=$(jq -r '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_status_transition")
  ] | .[0].input.tool_name // empty' "$SETTINGS_JSON")
  [[ "$input_tool_name" == '${tool_name}' ]]
}

# ---------------------------------------------------------------------------
# S3: S1 entry の .timeout と .outputType → timeout==10, outputType=="log"
# 注意: timeout は秒単位。command 型 hook の ms 単位 timeout と混在しないよう注意すること。
#   - command 型 hook: timeout はミリ秒単位 (例: 5000 = 5秒)
#   - mcp_tool 型 hook: timeout は秒単位 (例: 10 = 10秒)
#   この差異を誤認すると 10ms タイムアウトになる恐れがあるため要注意。
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "S3: twl_validate_status_transition hook の timeout が 10 (秒単位) である" {
  # AC3: mcp_tool hook の timeout は秒単位で 10 を指定すること
  # 注意: command 型 hook の ms 単位 timeout と混在しないよう注意
  # RED: entry 未追加のため fail する
  local timeout_val
  timeout_val=$(jq '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_status_transition")
  ] | .[0].timeout // -1' "$SETTINGS_JSON")
  [ "$timeout_val" -eq 10 ]
}

@test "S3: twl_validate_status_transition hook の outputType が log である" {
  # AC5: outputType=log (shadow mode) であること
  # RED: entry 未追加のため fail する
  local output_type
  output_type=$(jq -r '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_status_transition")
  ] | .[0].outputType // empty' "$SETTINGS_JSON")
  [[ "$output_type" == "log" ]]
}

# ---------------------------------------------------------------------------
# S4: hooks 配列内 pre-bash-refined-status-gate.sh (command 型) と
#     twl_validate_status_transition (mcp_tool 型) の index 比較
#     → command index < mcp_tool index
#     Sub-1 entry (pre-bash-refined-status-gate.sh) 不在時は skip
# RED: Sub-1 entry が存在しない間は skip する。実装後に check される。
# ---------------------------------------------------------------------------

@test "S4: Bash matcher 内で pre-bash-refined-status-gate.sh (command型) が twl_validate_status_transition (mcp_tool型) より前に位置する" {
  # AC4: 配置順序 Sub-1 (command型, [5]) → Sub-3 (mcp_tool型, [6])
  # Sub-1 entry 不在時は skip する
  local gate_index
  gate_index=$(jq '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks
  ] | .[0] | to_entries[]
    | select(.value.type == "command" and (.value.command // "" | contains("pre-bash-refined-status-gate.sh")))
    | .key' "$SETTINGS_JSON")

  if [[ -z "$gate_index" ]]; then
    skip "Sub-1 PR not merged yet: pre-bash-refined-status-gate.sh entry が Bash matcher hooks に存在しない"
  fi

  local mcp_index
  mcp_index=$(jq '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks
  ] | .[0] | to_entries[]
    | select(.value.type == "mcp_tool" and .value.tool == "twl_validate_status_transition")
    | .key' "$SETTINGS_JSON")

  if [[ -z "$mcp_index" ]]; then
    # mcp_tool entry が存在しない = AC1 未実装 = RED
    false
  fi

  [ "$gate_index" -lt "$mcp_index" ]
}

# ---------------------------------------------------------------------------
# S5: settings.json 全体から mcp_tool hook 5 件
#     (twl_validate_deps, twl_validate_merge, twl_validate_commit, twl_check_specialist x2)
#     を列挙 → 5 件全件検出
# 注意: twl_validate_status_transition が追加されると 6 件になるが、
#       S5 は既存 5 件のカバレッジ確認テストである。
# GREEN: 既存 5 件が存在する間は PASS する (regression guard)
# ---------------------------------------------------------------------------

@test "S5: settings.json 全体に既存 mcp_tool hook 5 件 (twl_validate_deps, twl_validate_merge, twl_validate_commit, twl_check_specialist x2) が存在する" {
  # AC6 S5: 既存 5 件の mcp_tool hook がすべて検出されること
  # このテストは実装前後で GREEN を維持することが目的 (regression guard)
  local count
  count=$(jq '[
    .hooks
    | to_entries[]
    | .value[]?
    | .hooks[]?
    | select(.type == "mcp_tool" and .server == "twl")
  ] | length' "$SETTINGS_JSON")
  # 既存 5 件 (twl_validate_deps, twl_validate_merge, twl_validate_commit, twl_check_specialist x2)
  # 実装後は twl_validate_status_transition が追加されて 6 件になる
  [ "$count" -ge 5 ]
}

@test "S5: twl_validate_deps の mcp_tool hook が存在する (regression guard)" {
  local count
  count=$(jq '[
    .hooks | to_entries[] | .value[]? | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_deps")
  ] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

@test "S5: twl_validate_merge の mcp_tool hook が存在する (regression guard)" {
  local count
  count=$(jq '[
    .hooks | to_entries[] | .value[]? | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_merge")
  ] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

@test "S5: twl_validate_commit の mcp_tool hook が存在する (regression guard)" {
  local count
  count=$(jq '[
    .hooks | to_entries[] | .value[]? | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_commit")
  ] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

@test "S5: twl_check_specialist の mcp_tool hook が 2 件存在する (regression guard)" {
  local count
  count=$(jq '[
    .hooks | to_entries[] | .value[]? | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_check_specialist")
  ] | length' "$SETTINGS_JSON")
  [ "$count" -eq 2 ]
}

# ---------------------------------------------------------------------------
# S6: outputType: "log" フィールドの存在確認で shadow mode (non-blocking) を検証
# 注意: dry-run での実際の Bash block 非発生確認は自動テストで困難なため、
#       settings.json 構造確認 (outputType=log フィールド存在) で代替する。
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "S6: twl_validate_status_transition hook が outputType=log を持ち Bash 実行を block しない (shadow mode 確認)" {
  # AC5: outputType=log により Bash command 実行を block しないこと
  # dry-run での挙動確認は困難なため、outputType フィールドの存在確認で代替する
  # RED: entry 未追加のため fail する
  local entry_json
  entry_json=$(jq -r '[
    .hooks.PreToolUse[]?
    | select(.matcher == "Bash")
    | .hooks[]?
    | select(.type == "mcp_tool" and .tool == "twl_validate_status_transition")
  ] | .[0]' "$SETTINGS_JSON")

  # entry が存在しない場合は fail (RED)
  [[ "$entry_json" != "null" && -n "$entry_json" ]]

  # outputType が "log" であること (blocking でないこと)
  local output_type
  output_type=$(echo "$entry_json" | jq -r '.outputType // empty')
  [[ "$output_type" == "log" ]]

  # type が "mcp_tool" であること (command 型 hook は outputType を持たないため)
  local hook_type
  hook_type=$(echo "$entry_json" | jq -r '.type // empty')
  [[ "$hook_type" == "mcp_tool" ]]
}
