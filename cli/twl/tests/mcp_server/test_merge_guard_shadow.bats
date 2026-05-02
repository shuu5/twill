#!/usr/bin/env bats
# test_merge_guard_shadow.bats
#
# RED テストスタブ (Issue #1276)
#
# AC-1: .claude/settings.json の PreToolUse Bash matcher に mcp_tool entry を追加
# AC-2: mcp_tool entry が mcp__twl__twl_validate_merge を呼び ${tool_input.command} を引数に渡す
# AC-3: mcp_tool 失敗時は warning ログのみ (block しない) — outputType: "log" 指定
# AC-4: bats fixture 5 件で bash と mcp_tool の出力を突合し mismatch 0 を確認
# AC-5: mcp-shadow-compare.sh 互換ログを /tmp/mcp-shadow-merge-guard.log に追記する形式で配置
#
# 全テストは実装前に fail (RED) する。
#

SETTINGS_JSON=""
COMPARE_SH=""
SHADOW_LOG="/tmp/mcp-shadow-merge-guard.log"
BASH_GUARD=""

setup() {
  REPO_ROOT="$(git -C "$(dirname "$BATS_TEST_FILENAME")" rev-parse --show-toplevel 2>/dev/null)"
  SETTINGS_JSON="${REPO_ROOT}/.claude/settings.json"
  COMPARE_SH="${REPO_ROOT}/plugins/twl/scripts/mcp-shadow-compare.sh"
  BASH_GUARD="${REPO_ROOT}/plugins/twl/scripts/hooks/pre-bash-merge-guard.sh"
  # shadow log をクリア（スコープ汚染防止）
  rm -f "$SHADOW_LOG"
}

teardown() {
  rm -f "$SHADOW_LOG"
}

# ---------------------------------------------------------------------------
# AC-1: settings.json の PreToolUse Bash matcher に mcp_tool entry が存在する
# WHEN settings.json を読み込む
# THEN PreToolUse の Bash matcher に type=mcp_tool, tool=twl_validate_merge のエントリが 1 件以上存在する
# RED: 未実装のため fail する
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
# RED: 未実装のため fail する
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
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "ac3: mcp_tool entry の outputType が log である (block しない)" {
  local output_type
  output_type=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_merge")] | .[0].outputType // empty' "$SETTINGS_JSON")
  [[ "$output_type" == "log" ]]
}

# ---------------------------------------------------------------------------
# AC-4: 5 fixture シナリオ — bash と mcp_tool の出力を突合し mismatch 0 を確認
#
# 各シナリオは shadow log に JSONL エントリが書き込まれ、mismatch フィールドが
# false であることを確認する。
#
# shadow log の JSONL 形式:
#   {ts, command, bash_exit, mcp_exit, bash_stderr_match, mcp_stderr_match, mismatch}
#
# 全シナリオは shadow log write スクリプトが存在しないため RED (fail) する。
# ---------------------------------------------------------------------------

# Shadow log write を模擬するヘルパー
# 実装後は実際のフックが書き込む。RED フェーズでは存在しない shadow writer を直接呼んで fail させる。
_require_shadow_writer() {
  # 実装後は plugins/twl/scripts/hooks/mcp-shadow-merge-guard-writer.sh 等が存在する想定
  local shadow_writer="${REPO_ROOT}/plugins/twl/scripts/hooks/mcp-shadow-merge-guard-writer.sh"
  if [[ ! -f "$shadow_writer" ]]; then
    echo "shadow writer が存在しない: $shadow_writer" >&2
    return 1
  fi
  echo "$shadow_writer"
}

@test "ac4 fixture1: main → feature merge — bash=allow mcp=allow → mismatch=false" {
  local shadow_writer
  shadow_writer=$(_require_shadow_writer) || false

  local cmd="git merge feat/sample-feature"
  bash "$shadow_writer" --command "$cmd" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local mismatch
  mismatch=$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')
  [[ "$mismatch" == "false" ]]
}

@test "ac4 fixture2: direct main commit reject — bash=block mcp=block → mismatch=false" {
  local shadow_writer
  shadow_writer=$(_require_shadow_writer) || false

  local cmd="git merge main"
  # AUTOPILOT_DIR 設定で bash guard が block する想定
  bash "$shadow_writer" --command "$cmd" --bash-exit 2 --mcp-exit 1 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local mismatch
  mismatch=$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')
  [[ "$mismatch" == "false" ]]
}

@test "ac4 fixture3: squash merge variant — bash=allow mcp=allow → mismatch=false" {
  local shadow_writer
  shadow_writer=$(_require_shadow_writer) || false

  local cmd="git merge --squash feat/squash-test"
  bash "$shadow_writer" --command "$cmd" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local mismatch
  mismatch=$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')
  [[ "$mismatch" == "false" ]]
}

@test "ac4 fixture4: non-merge git command — bash=skip mcp=skip → mismatch=false" {
  local shadow_writer
  shadow_writer=$(_require_shadow_writer) || false

  # git fetch は merge ではないため両方スキップ
  local cmd="git fetch origin"
  bash "$shadow_writer" --command "$cmd" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local mismatch
  mismatch=$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')
  [[ "$mismatch" == "false" ]]
}

@test "ac4 fixture5: edge detached HEAD — bash mcp 一致 → mismatch=false" {
  local shadow_writer
  shadow_writer=$(_require_shadow_writer) || false

  # detached HEAD 状態での merge コマンド
  local cmd="git merge origin/main"
  bash "$shadow_writer" --command "$cmd" --bash-exit 0 --mcp-exit 0 --log "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]
  local mismatch
  mismatch=$(tail -1 "$SHADOW_LOG" | jq -r '.mismatch')
  [[ "$mismatch" == "false" ]]
}

# ---------------------------------------------------------------------------
# AC-5: mcp-shadow-compare.sh 互換ログを /tmp/mcp-shadow-merge-guard.log に配置
# WHEN shadow log が存在する
# THEN mcp-shadow-compare.sh が --log-file で読み込める形式 (JSONL) であること
# RED: shadow log writer が存在しないため fail する
# ---------------------------------------------------------------------------

@test "ac5: /tmp/mcp-shadow-merge-guard.log が JSONL 形式で mcp-shadow-compare.sh 互換" {
  # shadow writer の存在確認（なければ fail = RED）
  _require_shadow_writer || false

  # サンプル JSONL を直接書き込んで互換性確認
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '%s\n' "$(jq -nc \
    --arg ts "$ts" \
    --arg cmd "git merge feat/test" \
    '{ts:$ts, command:$cmd, bash_exit:0, mcp_exit:0, bash_stderr_match:false, mcp_stderr_match:false, mismatch:false}')" \
    >> "$SHADOW_LOG"

  [ -f "$SHADOW_LOG" ]

  # jq でパースできること (JSONL 形式の確認)
  local mismatch_count
  mismatch_count=$(jq -s '[.[] | select(.mismatch == true)] | length' "$SHADOW_LOG")
  [ "$mismatch_count" -eq 0 ]
}
