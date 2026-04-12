#!/usr/bin/env bats
# pre-tool-use-deps-yaml-guard.bats
#
# Tests for plugins/twl/scripts/hooks/pre-tool-use-deps-yaml-guard.sh
#
# Spec: deltaspec/changes/issue-565/specs/pre-tool-use-yaml-guard/spec.md
#   Requirement: PreToolUse YAML syntax guard スクリプト
#
# The hook receives stdin JSON with tool_name (Write or Edit) and tool_input.
# - Write: validates tool_input.content as YAML
# - Edit:  simulates old_string/new_string apply on tool_input.file_content,
#          then validates the result as YAML
# - Invalid YAML -> exit 2 + stderr message
# - Valid YAML   -> exit 0
#
# Coverage: --type=unit --coverage=edge-cases
#
# Scenarios:
#   1. Write で不正 YAML -> exit 2 + stderr にエラーメッセージ
#   2. Edit で simulated apply 後に不正 YAML -> exit 2 + stderr にエラーメッセージ
#   3. Write で有効 YAML -> exit 0
#   4. Edit で simulated apply 後も有効 YAML -> exit 0
#   5. 不正 JSON ペイロード -> no-op (exit 0)
#   6. tool_name が Write/Edit 以外 -> no-op (exit 0)
#   7. content が空文字列 -> YAML として有効 (exit 0)
#   8. YAML 構文エラーメッセージが stderr に出力される (exit 2 時)
#   9. Write で content が null/未設定 -> no-op (exit 0, フォールバック)
#  10. Edit で old_string が file_content 内に存在しない -> exit 2 (apply 失敗)
#  11. Edit で new_string 適用後に YAML コロン欠落エラー -> exit 2
#  12. 深くネストされた有効 YAML (Write) -> exit 0
#  13. タブ文字を含む不正 YAML (Write) -> exit 2

load '../helpers/common'

HOOK_SRC=""

setup() {
  common_setup

  HOOK_SRC="$(cd "$REPO_ROOT" && pwd)/scripts/hooks/pre-tool-use-deps-yaml-guard.sh"
}

teardown() {
  common_teardown
}

# Helper: invoke hook with given JSON payload via stdin
_run_hook() {
  local payload="$1"
  printf '%s' "$payload" | bash "$HOOK_SRC"
}

# ---------------------------------------------------------------------------
# Scenario 1: Write ツールで不正な YAML を送信した場合
# WHEN Write(deps.yaml) で YAML parse エラーになるコンテンツが tool_input.content に含まれる
# THEN exit 2 で終了し、stderr に YAML syntax エラーメッセージが表示される
# ---------------------------------------------------------------------------

@test "Write: 不正 YAML は exit 2 を返す" {
  local invalid_yaml='key: value
  bad_indent:
- not: valid
    extra: colon: here'
  local payload
  payload=$(jq -nc --arg content "$invalid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 2 ]
}

@test "Write: 不正 YAML は stderr にエラーメッセージを出力する" {
  local invalid_yaml=': bad yaml {unclosed bracket'
  local payload stderr_file
  payload=$(jq -nc --arg content "$invalid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  stderr_file=$(mktemp)
  printf '%s' "$payload" | bash "$HOOK_SRC" 2>"$stderr_file"
  local exit_code=$?
  local stderr_output
  stderr_output=$(cat "$stderr_file")
  rm -f "$stderr_file"
  [ "$exit_code" -eq 2 ]
  [[ -n "$stderr_output" ]]
}

@test "Write: コロン重複による不正 YAML は exit 2 を返す" {
  # key: value: extra はパーサ依存だが mapping ではない形式でエラーになるケース
  local invalid_yaml='key: [unclosed list
another: key'
  local payload
  payload=$(jq -nc --arg content "$invalid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Scenario 2: Edit ツールで不正な YAML になる変更を送信した場合
# WHEN Edit(deps.yaml) で old_string/new_string の simulated apply 後に YAML parse エラーになる
# THEN exit 2 で終了し、stderr に YAML syntax エラーメッセージが表示される
# ---------------------------------------------------------------------------

@test "Edit: simulated apply 後に不正 YAML になる場合は exit 2 を返す" {
  # 元のファイルは有効 YAML だが, new_string 適用後は不正になる
  local original_content='plugins:
  name: my-plugin
  version: "1.0"'
  local old_string='  version: "1.0"'
  local new_string='  version: [broken'
  local payload
  payload=$(jq -nc \
    --arg fc "$original_content" \
    --arg os "$old_string" \
    --arg ns "$new_string" \
    '{tool_name:"Edit", tool_input:{file_path:"deps.yaml", file_content:$fc, old_string:$os, new_string:$ns}}')
  run _run_hook "$payload"
  [ "$status" -eq 2 ]
}

@test "Edit: simulated apply 後の不正 YAML は stderr にエラーを出力する" {
  local original_content='key: value'
  local old_string='key: value'
  local new_string='key: {broken'
  local payload stderr_file
  payload=$(jq -nc \
    --arg fc "$original_content" \
    --arg os "$old_string" \
    --arg ns "$new_string" \
    '{tool_name:"Edit", tool_input:{file_path:"deps.yaml", file_content:$fc, old_string:$os, new_string:$ns}}')
  stderr_file=$(mktemp)
  printf '%s' "$payload" | bash "$HOOK_SRC" 2>"$stderr_file"
  local exit_code=$?
  local stderr_output
  stderr_output=$(cat "$stderr_file")
  rm -f "$stderr_file"
  [ "$exit_code" -eq 2 ]
  [[ -n "$stderr_output" ]]
}

# ---------------------------------------------------------------------------
# Scenario 3: 正常な YAML の Write を送信した場合
# WHEN Write(deps.yaml) で有効な YAML コンテンツが送信される
# THEN exit 0 で正常通過し、ツールの実行がブロックされない
# ---------------------------------------------------------------------------

@test "Write: 有効な YAML は exit 0 を返す" {
  local valid_yaml='name: my-plugin
version: "1.0"
dependencies:
  - dep-a
  - dep-b'
  local payload
  payload=$(jq -nc --arg content "$valid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

@test "Write: 有効 YAML 通過時は stdout が空である" {
  local valid_yaml='key: value'
  local payload
  payload=$(jq -nc --arg content "$valid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Write: マルチドキュメント YAML は exit 0 を返す" {
  local valid_yaml='---
key: value
---
another: doc'
  local payload
  payload=$(jq -nc --arg content "$valid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Scenario 4: 正常な YAML になる Edit を送信した場合
# WHEN Edit(deps.yaml) の simulated apply 後も有効な YAML が維持される
# THEN exit 0 で正常通過する
# ---------------------------------------------------------------------------

@test "Edit: simulated apply 後も有効な YAML なら exit 0 を返す" {
  local original_content='name: my-plugin
version: "1.0"'
  local old_string='version: "1.0"'
  local new_string='version: "2.0"'
  local payload
  payload=$(jq -nc \
    --arg fc "$original_content" \
    --arg os "$old_string" \
    --arg ns "$new_string" \
    '{tool_name:"Edit", tool_input:{file_path:"deps.yaml", file_content:$fc, old_string:$os, new_string:$ns}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

@test "Edit: simulated apply 後の有効 YAML は stdout を出力しない" {
  local original_content='key: old_value'
  local old_string='key: old_value'
  local new_string='key: new_value'
  local payload
  payload=$(jq -nc \
    --arg fc "$original_content" \
    --arg os "$old_string" \
    --arg ns "$new_string" \
    '{tool_name:"Edit", tool_input:{file_path:"deps.yaml", file_content:$fc, old_string:$os, new_string:$ns}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Edge case 5: 不正 JSON ペイロード -> no-op (exit 0)
# ---------------------------------------------------------------------------

@test "不正 JSON ペイロードは no-op (exit 0)" {
  run bash -c "printf 'not-valid-json{' | bash '$HOOK_SRC'"
  [ "$status" -eq 0 ]
}

@test "空ペイロードは no-op (exit 0)" {
  run bash -c "printf '' | bash '$HOOK_SRC'"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Edge case 6: tool_name が Write/Edit 以外 -> no-op (exit 0)
# ---------------------------------------------------------------------------

@test "tool_name が Bash の場合は no-op (exit 0)" {
  local payload
  payload=$(jq -nc '{tool_name:"Bash", tool_input:{command:"echo hello"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tool_name が Read の場合は no-op (exit 0)" {
  local payload
  payload=$(jq -nc '{tool_name:"Read", tool_input:{file_path:"deps.yaml"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---------------------------------------------------------------------------
# Edge case 7: content が空文字列 -> YAML として有効 (exit 0)
# ---------------------------------------------------------------------------

@test "Write: content が空文字列は有効 YAML として通過する (exit 0)" {
  local payload
  payload=$(jq -nc --arg content "" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Edge case 9: Write で content が null/未設定 -> no-op (exit 0, フォールバック)
# ---------------------------------------------------------------------------

@test "Write: content が null の場合は no-op (exit 0)" {
  local payload
  payload=$(jq -nc \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:null}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

@test "Write: tool_input に content フィールドなし -> no-op (exit 0)" {
  local payload
  payload=$(jq -nc \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml"}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Edge case 10: Edit で old_string が file_content 内に存在しない -> exit 2
# (simulated apply 失敗 = YAML 未検証 = ブロック)
# ---------------------------------------------------------------------------

@test "Edit: old_string が file_content に見つからない場合は exit 2 を返す" {
  local original_content='key: value'
  local payload
  payload=$(jq -nc \
    --arg fc "$original_content" \
    --arg os "nonexistent_string" \
    --arg ns "replacement" \
    '{tool_name:"Edit", tool_input:{file_path:"deps.yaml", file_content:$fc, old_string:$os, new_string:$ns}}')
  run _run_hook "$payload"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Edge case 11: Edit で new_string 適用後に YAML コロン欠落エラー -> exit 2
# ---------------------------------------------------------------------------

@test "Edit: new_string 適用後にインデント崩れで不正 YAML になる場合 exit 2" {
  local original_content='plugins:
  name: valid-plugin
  version: "1.0"'
  local old_string='  name: valid-plugin'
  # インデントなしで配置するとブロックマッピングの構文エラーになる
  local new_string='name: [broken indent'
  local payload
  payload=$(jq -nc \
    --arg fc "$original_content" \
    --arg os "$old_string" \
    --arg ns "$new_string" \
    '{tool_name:"Edit", tool_input:{file_path:"deps.yaml", file_content:$fc, old_string:$os, new_string:$ns}}')
  run _run_hook "$payload"
  [ "$status" -eq 2 ]
}

# ---------------------------------------------------------------------------
# Edge case 12: 深くネストされた有効 YAML (Write) -> exit 0
# ---------------------------------------------------------------------------

@test "Write: 深くネストされた有効 YAML は exit 0 を返す" {
  local valid_yaml='level1:
  level2:
    level3:
      level4:
        key: deep_value
        list:
          - item1
          - item2
        nested_map:
          a: 1
          b: 2'
  local payload
  payload=$(jq -nc --arg content "$valid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Edge case 13: タブ文字を含む不正 YAML (Write) -> exit 2
# YAML 仕様ではインデントにタブ文字は使用不可
# ---------------------------------------------------------------------------

@test "Write: タブインデントを含む YAML は exit 2 を返す" {
  # タブ文字によるインデントは YAML 仕様違反
  local invalid_yaml
  # printf で実際のタブ文字を埋め込む
  invalid_yaml="key: value
$(printf '\t')bad_tab_indent: here"
  local payload
  payload=$(jq -nc --arg content "$invalid_yaml" \
    '{tool_name:"Write", tool_input:{file_path:"deps.yaml", content:$content}}')
  run _run_hook "$payload"
  [ "$status" -eq 2 ]
}
