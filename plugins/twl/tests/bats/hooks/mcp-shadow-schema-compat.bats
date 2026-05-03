#!/usr/bin/env bats
# mcp-shadow-schema-compat.bats - Issue #1288: MCP shadow hook schema compatibility
#
# Wave 20 で merge された MCP shadow hook 4 件が、Bash 呼び出し時の
# PreToolUse:Bash hook で schema validation error を出す問題を検証する。
#
# 検証方針: .claude/settings.json を jq で parse し、各 mcp_tool hook の
# input フィールドが MCP tool の期待する schema と一致するかを確認する。
#
# RED: 実装前（settings.json 未修正）は全テストが FAIL する。

load '../helpers/common'

setup() {
  common_setup
  REPO_ROOT_ABS="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../../../.." && pwd)"
  SETTINGS_JSON="${REPO_ROOT_ABS}/.claude/settings.json"
  export REPO_ROOT_ABS SETTINGS_JSON
}

teardown() {
  common_teardown
}

# ===========================================================================
# AC-1: twl_validate_deps hook の input schema が正しいこと
#
# MCP tool 実際の schema: plugin_root: str
# 現在の hook input:      file_path, content, old_string, new_string (全て不正)
# RED: 現在の settings.json には plugin_root フィールドがないため FAIL
# ===========================================================================

@test "ac1: twl_validate_deps hook input has plugin_root field (not file_path)" {
  # AC: MCP tool twl_validate_deps の schema は plugin_root: str を期待する。
  # 現在の hook input には file_path, content 等の不正フィールドがあり plugin_root がない。
  # RED: settings.json 未修正では jq が null を返すため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local hook_input
  hook_input=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_deps")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_deps")
    | .input
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # plugin_root フィールドが存在すること
  local has_plugin_root
  has_plugin_root=$(echo "${hook_input}" | jq 'has("plugin_root")' 2>/dev/null)
  [ "${has_plugin_root}" = "true" ]
}

@test "ac1: twl_validate_deps hook input does NOT have file_path field" {
  # AC: 修正後の hook input に file_path フィールドが含まれないこと（schema 汚染の除去）。
  # RED: 現在の settings.json には file_path が含まれているため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local hook_input
  hook_input=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_deps")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_deps")
    | .input
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # file_path フィールドが存在しないこと
  local has_file_path
  has_file_path=$(echo "${hook_input}" | jq 'has("file_path")' 2>/dev/null)
  [ "${has_file_path}" = "false" ]
}

# ===========================================================================
# AC-2: validation error 時 log を stderr only にする（stdout 汚染回避）
#
# 現在の settings.json で mcp_tool hook が schema error を出す場合、
# Claude Code が hook の output を stdout に混入させる可能性がある。
# ここでは hook の outputType が "log" に設定されているかを検証する。
#
# RED: twl_validate_deps は現在 outputType が未設定であり、stdout 汚染が起きる
# ===========================================================================

@test "ac2: twl_validate_deps hook has outputType log (stderr-only mode)" {
  # AC: validation error を stderr only にするため、outputType が "log" に設定されていること。
  # RED: 現在の twl_validate_deps hook には outputType が設定されていないため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local output_type
  output_type=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_deps")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_deps")
    | .outputType // "MISSING"
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # outputType が "log" に設定されていること
  [ "${output_type}" = "log" ]
}

# ===========================================================================
# AC-3: twl_validate_merge hook の input schema が正しいこと
#
# MCP tool 実際の schema: branch: str, base: str = "main", timeout_sec: int | None = 300
# 現在の hook input:      {"command": "${tool_input.command}"} (フィールド名不正)
# RED: 現在の settings.json には branch フィールドがないため FAIL
# ===========================================================================

@test "ac3: twl_validate_merge hook input has branch field (not command)" {
  # AC: MCP tool twl_validate_merge の schema は branch: str を要求する。
  # 現在の hook input には command フィールドが送られており、schema 不整合が起きている。
  # RED: settings.json 未修正では branch フィールドがないため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local hook_input
  hook_input=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_merge")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_merge")
    | .input
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # branch フィールドが存在すること
  local has_branch
  has_branch=$(echo "${hook_input}" | jq 'has("branch")' 2>/dev/null)
  [ "${has_branch}" = "true" ]
}

@test "ac3: twl_validate_merge hook input does NOT have command field" {
  # AC: 修正後の hook input に command フィールドが含まれないこと。
  # RED: 現在の settings.json には command フィールドが存在するため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local hook_input
  hook_input=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_merge")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_merge")
    | .input
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # command フィールドが存在しないこと
  local has_command
  has_command=$(echo "${hook_input}" | jq 'has("command")' 2>/dev/null)
  [ "${has_command}" = "false" ]
}

@test "ac3: twl_validate_commit hook input has message field (not command)" {
  # AC: MCP tool twl_validate_commit の schema は message: str, files: list[str] を要求する。
  # 現在の hook input には command フィールドが送られており、schema 不整合が起きている。
  # RED: settings.json 未修正では message フィールドがないため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local hook_input
  hook_input=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_commit")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_commit")
    | .input
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # message フィールドが存在すること
  local has_message
  has_message=$(echo "${hook_input}" | jq 'has("message")' 2>/dev/null)
  [ "${has_message}" = "true" ]
}

@test "ac3: twl_validate_commit hook input has files field" {
  # AC: MCP tool twl_validate_commit は files: list[str] も必須パラメータとして要求する。
  # RED: settings.json 未修正では files フィールドがないため fail する。
  [ -f "${SETTINGS_JSON}" ]

  local hook_input
  hook_input=$(jq -r '
    .hooks.PreToolUse[]
    | select(.hooks[]?.type == "mcp_tool" and .hooks[]?.tool == "twl_validate_commit")
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_validate_commit")
    | .input
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # files フィールドが存在すること
  local has_files
  has_files=$(echo "${hook_input}" | jq 'has("files")' 2>/dev/null)
  [ "${has_files}" = "true" ]
}

# ===========================================================================
# AC-4: PreToolUse:Bash hook 実行時に hook error が出ないこと
#
# schema 不整合が解消されれば "PreToolUse:Bash hook error" は出なくなる。
# ここでは settings.json の構造全体を検証し、mcp_tool hook に不正な
# (schema mismatch が確実な) フィールドが残っていないかを確認する。
#
# RED: 現在の settings.json の twl_validate_deps / twl_validate_merge /
#      twl_validate_commit に schema 違反フィールドが存在するため fail する
# ===========================================================================

@test "ac4: no schema-invalid fields in any PreToolUse mcp_tool hook input" {
  # AC: PreToolUse の全 mcp_tool hook について schema 不整合フィールドが存在しないこと。
  # 具体的に:
  #   - twl_validate_deps: file_path / content / old_string / new_string が存在しない
  #   - twl_validate_merge: command フィールドが存在しない
  #   - twl_validate_commit: command フィールドが存在しない
  # RED: 現在の settings.json にはこれらの不正フィールドが存在するため fail する。
  [ -f "${SETTINGS_JSON}" ]

  # 不正フィールドの存在チェック: いずれかが true なら fail
  local invalid_count
  invalid_count=$(jq '
    [
      .hooks.PreToolUse[]
      | .hooks[]
      | select(.type == "mcp_tool")
      | . as $h
      | if .tool == "twl_validate_deps" then
          .input | [has("file_path"), has("content"), has("old_string"), has("new_string")] | map(select(. == true)) | length
        elif .tool == "twl_validate_merge" or .tool == "twl_validate_commit" then
          .input | [has("command")] | map(select(. == true)) | length
        else 0
        end
    ] | add // 0
  ' "${SETTINGS_JSON}" 2>/dev/null)

  # 不正フィールドが 0 件であること
  [ "${invalid_count}" = "0" ]
}

@test "ac4: twl_check_specialist hook input remains correct (manifest_context field)" {
  # AC: twl_check_specialist の hook input は変更不要（manifest_context フィールドが正しい）。
  # この AC-4 の regression テスト: 修正時に正常な hook を壊していないことを確認する。
  # RED: この検証自体は問題ないはずだが、settings.json 全体の修正が完了するまで
  #      上記 ac4 テストが fail するため RED フェーズとして扱う。
  [ -f "${SETTINGS_JSON}" ]

  # Stop hook と SubagentStop hook 両方を確認
  local stop_ctx
  stop_ctx=$(jq -r '
    .hooks.Stop[]
    | .hooks[]
    | select(.type == "mcp_tool" and .tool == "twl_check_specialist")
    | .input.manifest_context // "MISSING"
  ' "${SETTINGS_JSON}" 2>/dev/null | head -1)

  # manifest_context が "session" に設定されていること
  [ "${stop_ctx}" = "session" ]
}
