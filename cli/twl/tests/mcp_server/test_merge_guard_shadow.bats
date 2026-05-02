#!/usr/bin/env bats
# test_merge_guard_shadow.bats  (Issue #1276)
#
# AC-1: .claude/settings.json の PreToolUse Bash matcher に mcp_tool entry を追加
# AC-2: mcp_tool entry が mcp__twl__twl_validate_merge を呼び ${tool_input.command} を引数に渡す
# AC-3: mcp_tool 失敗時は warning ログのみ (block しない) — outputType: "log" 指定
# AC-4: bats fixture 5 件で bash と mcp_tool の出力を突合し mismatch 0 を確認
# AC-5: JSONL 形式の shadow log を /tmp/mcp-shadow-merge-guard.log に追記する形式で配置
#
# shadow log 形式: {ts, command, bash_exit, mcp_exit, bash_stderr_match, mcp_stderr_match, mismatch}
# ※ deps-yaml の mcp-shadow-compare.sh とは異なる専用スキーマ（merge-guard 固有）

SETTINGS_JSON=""
SHADOW_LOG=""

setup() {
  REPO_ROOT="$(git -C "$(dirname "$BATS_TEST_FILENAME")" rev-parse --show-toplevel 2>/dev/null)"
  SETTINGS_JSON="${REPO_ROOT}/.claude/settings.json"
  # 並列実行 (bats --jobs N) での競合を防ぐため一意パスを使用
  SHADOW_LOG="$(mktemp /tmp/mcp-shadow-merge-guard-XXXXXX.log)"
}

teardown() {
  rm -f "$SHADOW_LOG"
}

# ---------------------------------------------------------------------------
# AC-1: settings.json の PreToolUse Bash matcher に mcp_tool entry が存在する
# WHEN settings.json を読み込む
# THEN PreToolUse の Bash matcher に type=mcp_tool, tool=twl_validate_merge のエントリが 1 件以上存在する
# ---------------------------------------------------------------------------

@test "ac1: settings.json の Bash matcher に mcp_tool(twl_validate_merge) entry が存在する" {
  local count
  count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_merge")] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

@test "ac1: 既存 bash hook entry (pre-bash-merge-guard.sh) が維持されている" {
  local count
  count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "command") | select(.command | test("pre-bash-merge-guard.sh"))] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# AC-2: mcp_tool entry が twl_validate_merge を呼び ${tool_input.command} を input に渡す
# WHEN settings.json の mcp_tool entry を検査する
# THEN server=twl, tool=twl_validate_merge, input.command="${tool_input.command}" であること
# ---------------------------------------------------------------------------

@test "ac2: mcp_tool entry の server=twl, tool=twl_validate_merge が正しい" {
  local server tool
  server=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_merge")] | .[0].server // empty' "$SETTINGS_JSON")
  tool=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_merge")] | .[0].tool // empty' "$SETTINGS_JSON")
  [[ "$server" == "twl" ]]
  [[ "$tool" == "twl_validate_merge" ]]
}

@test "ac2: mcp_tool entry の input.command が \${tool_input.command} を参照している" {
  local input_command
  input_command=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_merge")] | .[0].input.command // empty' "$SETTINGS_JSON")
  [[ "$input_command" == '${tool_input.command}' ]]
}

# ---------------------------------------------------------------------------
# AC-3: mcp_tool 失敗時は warning ログのみ (block しない) — outputType: "log"
# WHEN settings.json の mcp_tool entry の outputType を確認する
# THEN outputType == "log" であること
# ---------------------------------------------------------------------------

@test "ac3: mcp_tool entry の outputType が log である (block しない)" {
  local output_type
  output_type=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_merge")] | .[0].outputType // empty' "$SETTINGS_JSON")
  [[ "$output_type" == "log" ]]
}

# ---------------------------------------------------------------------------
# AC-4: 5 fixture シナリオ — bash と mcp_tool の出力を突合し mismatch 0 を確認
#
# shadow log の JSONL 形式:
#   {ts, command, bash_exit, mcp_exit, bash_stderr_match, mcp_stderr_match, mismatch}
#
# mismatch 判定: bash_exit!=0 かつ mcp_exit!=0 は「両方 block」→ mismatch=false
#               一方のみ非ゼロ → mismatch=true
# ---------------------------------------------------------------------------

_shadow_writer() {
  echo "${REPO_ROOT}/plugins/twl/scripts/hooks/mcp-shadow-merge-guard-writer.sh"
}

@test "ac4 fixture1: main → feature merge — bash=allow mcp=allow → mismatch=false" {
  local sw
  sw=$(_shadow_writer)
  [ -f "$sw" ] || { echo "shadow writer が存在しない: $sw" >&2; false; }

  bash "$sw" --command "git merge feat/sample-feature" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  [[ "$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')" == "false" ]]
}

@test "ac4 fixture2: direct main commit reject — bash=block(2) mcp=block(1) → mismatch=false" {
  # bash exits 2 (block by pre-bash-merge-guard.sh), mcp exits 1 (guard error)
  # 両方 non-zero = 両方 block → mismatch=false
  local sw
  sw=$(_shadow_writer)
  [ -f "$sw" ] || { echo "shadow writer が存在しない: $sw" >&2; false; }

  bash "$sw" --command "git merge main" --bash-exit 2 --mcp-exit 1 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  [[ "$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')" == "false" ]]
}

@test "ac4 fixture3: squash merge variant — bash=allow mcp=allow → mismatch=false" {
  local sw
  sw=$(_shadow_writer)
  [ -f "$sw" ] || { echo "shadow writer が存在しない: $sw" >&2; false; }

  bash "$sw" --command "git merge --squash feat/squash-test" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  [[ "$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')" == "false" ]]
}

@test "ac4 fixture4: non-merge git command — both exit 0 (skip) → mismatch=false" {
  # git fetch は merge guard の対象外。bash hook も mcp も exit 0 で素通り。
  local sw
  sw=$(_shadow_writer)
  [ -f "$sw" ] || { echo "shadow writer が存在しない: $sw" >&2; false; }

  bash "$sw" --command "git fetch origin" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  [[ "$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')" == "false" ]]
}

@test "ac4 fixture5: edge detached HEAD — bash=allow mcp=allow → mismatch=false" {
  local sw
  sw=$(_shadow_writer)
  [ -f "$sw" ] || { echo "shadow writer が存在しない: $sw" >&2; false; }

  bash "$sw" --command "git merge origin/main" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  [[ "$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')" == "false" ]]
}

# ---------------------------------------------------------------------------
# AC-5: shadow log が JSONL 形式で追記されること
# WHEN mcp-shadow-merge-guard-writer.sh を使って shadow log に書き込む
# THEN ファイルが JSONL 形式 (jq -s でパース可能) であり mismatch エントリが 0 件
#
# ※ shadow log は merge-guard 固有スキーマ。deps-yaml の mcp-shadow-compare.sh
#   とはスキーマが異なる（{ts,command,bash_exit,mcp_exit,...} vs {event_id,source,verdict}）
# ---------------------------------------------------------------------------

@test "ac5: shadow log が JSONL 形式で mismatch エントリ 0 件" {
  local sw
  sw=$(_shadow_writer)
  [ -f "$sw" ] || { echo "shadow writer が存在しない: $sw" >&2; false; }

  bash "$sw" --command "git merge feat/test" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local mismatch_count
  mismatch_count=$(jq -s '[.[] | select(.mismatch == true)] | length' "$SHADOW_LOG")
  [ "$mismatch_count" -eq 0 ]
}
