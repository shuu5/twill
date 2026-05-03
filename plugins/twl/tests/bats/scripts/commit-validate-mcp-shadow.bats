#!/usr/bin/env bats
# commit-validate-mcp-shadow.bats
#
# RED テストスタブ (Issue #1277)
#
# AC-1: .claude/settings.json の PreToolUse Bash matcher に mcp_tool entry を追加
# AC-2: mcp_tool entry が mcp__twl__twl_validate_commit を呼び、${tool_input.command} を引数に渡す
# AC-3: mcp_tool 失敗時は warning ログのみ（block しない）— outputType: "log" 指定
# AC-4: bats fixture 5+ 件（valid commit / invalid commit / non-git command / edge: empty / edge: timeout）
#        で bash と mcp_tool の出力を突合し mismatch 0 を確認
# AC-5: mcp-shadow-compare.sh 互換ログを /tmp/mcp-shadow-commit-validate.log に追記する形式で配置
#
# 全テストは実装前に fail (RED) する。
#

load '../helpers/common'

SETTINGS_JSON=""
COMPARE_SH=""
SHADOW_LOG=""

setup() {
  common_setup

  local git_root
  git_root="$(cd "$REPO_ROOT" && git rev-parse --show-toplevel 2>/dev/null)"

  SETTINGS_JSON="${git_root}/.claude/settings.json"
  COMPARE_SH="${git_root}/plugins/twl/scripts/mcp-shadow-compare.sh"
  SHADOW_LOG="$SANDBOX/mcp-shadow-commit-validate.log"
}

teardown() {
  common_teardown
}

# ---------------------------------------------------------------------------
# Helper: JSONL ログファイルを作成して mcp-shadow-compare.sh を実行する
# commit-validate 用: source=bash/mcp_tool、command フィールドを使用
# 引数:
#   $1 = bash 判定 ("allow", "block", "error", "skip", "timeout")
#   $2 = mcp 判定  ("allow", "block", "error", "skip", "timeout")
#   $3 = イベント ID (event_id)
#   $4 = command 文字列
# ---------------------------------------------------------------------------
_run_compare_commit() {
  local bash_verdict="$1"
  local mcp_verdict="$2"
  local event_id="${3:-evt-commit-001}"
  local command="${4:-git commit -m 'test'}"

  local log_file="$SANDBOX/commit-validate-shadow.log"
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # bash hook エントリ
  printf '%s\n' "$(jq -nc \
    --arg id "$event_id" \
    --arg ts "$ts" \
    --arg v "$bash_verdict" \
    --arg cmd "$command" \
    '{event_id:$id, ts:$ts, source:"bash", verdict:$v, command:$cmd}')" \
    >> "$log_file"

  # mcp_tool エントリ
  printf '%s\n' "$(jq -nc \
    --arg id "$event_id" \
    --arg ts "$ts" \
    --arg v "$mcp_verdict" \
    --arg cmd "$command" \
    '{event_id:$id, ts:$ts, source:"mcp_tool", verdict:$v, command:$cmd}')" \
    >> "$log_file"

  run bash "$COMPARE_SH" --log-file "$log_file" 2>&1
}

# ---------------------------------------------------------------------------
# AC-1: .claude/settings.json の PreToolUse Bash matcher に mcp_tool entry 追加
# WHEN settings.json を読み込む
# THEN PreToolUse の Bash matcher 配下に type=mcp_tool, tool=twl_validate_commit のエントリが存在する
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC1: settings.json の Bash matcher に mcp_tool hook が存在する" {
  # Bash matcher の hooks 配列に type=mcp_tool, tool=twl_validate_commit のエントリが 1 件以上存在すること
  # RED: 現時点では Bash matcher に mcp_tool エントリが存在しないため fail する
  local count
  count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

@test "AC1: 既存 Bash hook entries（pre-bash-commit-validate.sh 等）が維持されている" {
  # 既存の command type hook が削除されていないこと（regression guard）
  # GREEN: 既存エントリが保持されている限り pass する
  local count
  count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "command")] | length' "$SETTINGS_JSON")
  [ "$count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# AC-2: mcp_tool entry が mcp__twl__twl_validate_commit を呼び、${tool_input.command} を渡す
# WHEN settings.json の Bash matcher mcp_tool entry を読む
# THEN server=twl, tool=twl_validate_commit, input.command="${tool_input.command}" であること
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC2: mcp_tool hook の server が twl である" {
  # RED: mcp_tool entry 未追加のため fail する
  local server
  server=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | .[0].server // empty' "$SETTINGS_JSON")
  [[ "$server" == "twl" ]]
}

@test "AC2: mcp_tool hook の tool が twl_validate_commit である" {
  # RED: mcp_tool entry 未追加のため fail する
  local tool
  tool=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool")] | .[0].tool // empty' "$SETTINGS_JSON")
  [[ "$tool" == "twl_validate_commit" ]]
}

@test "AC2: mcp_tool hook の input.command が \${tool_input.command} を参照する" {
  # RED: mcp_tool entry 未追加のため fail する
  local input_command
  input_command=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | .[0].input.command // empty' "$SETTINGS_JSON")
  [[ "$input_command" == '${tool_input.command}' ]]
}

# ---------------------------------------------------------------------------
# AC-3: mcp_tool 失敗時は warning ログのみ（block しない）— outputType: "log" 指定
# WHEN settings.json の mcp_tool entry を確認する
# THEN outputType フィールドが "log" に設定されていること（または failSilently/nonBlocking 相当）
# RED: 未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC3: mcp_tool hook が outputType: log を持つ（warning ログのみ、block しない）" {
  # RED: mcp_tool entry 未追加のため fail する
  # outputType=log が設定されていることで、失敗時に block ではなく log のみになる
  local output_type
  output_type=$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | .[0].outputType // empty' "$SETTINGS_JSON")
  [[ "$output_type" == "log" ]]
}

# ---------------------------------------------------------------------------
# AC-4: fixture 5+ 件 — bash と mcp_tool の出力を突合し mismatch 0 を確認
# shadow log 形式: event_id, ts, source, verdict, command
#
# fixture 1: valid commit     — bash=allow, mcp=allow   → mismatch false (exit 0)
# fixture 2: invalid commit   — bash=block, mcp=block   → mismatch false (exit 0)
# fixture 3: non-git command  — bash=skip,  mcp=skip    → mismatch false (exit 0)
# fixture 4: empty command    — bash=skip,  mcp=skip    → mismatch false (exit 0)
# fixture 5: timeout (両者error) — bash=error, mcp=error → mismatch false (exit 0)
# extra:     mismatch検出     — bash=allow, mcp=block   → exit 1 (MISMATCH 検出)
# ---------------------------------------------------------------------------

@test "AC4 fixture1: valid commit — bash=allow mcp=allow → mismatch false (exit 0)" {
  # RED: settings.json に mcp_tool entry が存在しないため、mcp_tool hook が実際には動作しない。
  # 実装後は mcp_tool hook が bash hook と同じ allow 判定を返すことで mismatch 0 になる。
  # まず mcp_tool hook の存在を確認（hook なし = 実装前 = RED）
  local mcp_count
  mcp_count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | length' "$SETTINGS_JSON")
  [ "$mcp_count" -ge 1 ] || {
    echo "mcp_tool hook が settings.json の Bash matcher に存在しない（AC1 未実装）" >&2
    false
  }
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_commit "allow" "allow" "evt-valid-commit" "git commit -m 'feat: add feature'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

@test "AC4 fixture2: invalid commit (violations) — bash=block mcp=block → mismatch false (exit 0)" {
  # RED: mcp_tool hook が settings.json に存在しないため fail する
  local mcp_count
  mcp_count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | length' "$SETTINGS_JSON")
  [ "$mcp_count" -ge 1 ] || {
    echo "mcp_tool hook が settings.json の Bash matcher に存在しない（AC1 未実装）" >&2
    false
  }
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_commit "block" "block" "evt-invalid-commit" "git commit -m 'wip: broken deps'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

@test "AC4 fixture3: non-git command (ls) — bash=skip mcp=skip → mismatch false (exit 0)" {
  # RED: mcp_tool hook が settings.json に存在しないため fail する
  local mcp_count
  mcp_count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | length' "$SETTINGS_JSON")
  [ "$mcp_count" -ge 1 ] || {
    echo "mcp_tool hook が settings.json の Bash matcher に存在しない（AC1 未実装）" >&2
    false
  }
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_commit "skip" "skip" "evt-non-git" "ls -la"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

@test "AC4 fixture4: empty command — bash=skip mcp=skip → mismatch false (exit 0)" {
  # RED: mcp_tool hook が settings.json に存在しないため fail する
  local mcp_count
  mcp_count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | length' "$SETTINGS_JSON")
  [ "$mcp_count" -ge 1 ] || {
    echo "mcp_tool hook が settings.json の Bash matcher に存在しない（AC1 未実装）" >&2
    false
  }
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_commit "skip" "skip" "evt-empty-cmd" ""
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

@test "AC4 fixture5: timeout/error (両者error) — bash=error mcp=error → mismatch false (exit 0)" {
  # RED: mcp_tool hook が settings.json に存在しないため fail する
  # 両者が同じ error/timeout 判定の場合は mismatch なし
  local mcp_count
  mcp_count=$(jq '[.hooks.PreToolUse[]? | select(.matcher == "Bash") | .hooks[]? | select(.type == "mcp_tool" and .tool == "twl_validate_commit")] | length' "$SETTINGS_JSON")
  [ "$mcp_count" -ge 1 ] || {
    echo "mcp_tool hook が settings.json の Bash matcher に存在しない（AC1 未実装）" >&2
    false
  }
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_commit "error" "error" "evt-timeout" "git commit -m 'slow operation'"
  [ "$status" -eq 0 ]
  [[ "$output" != *"MISMATCH"* ]]
}

@test "AC4 extra: mismatch — bash=allow mcp=block → exit 1 (MISMATCH 検出)" {
  # このテストは mismatch 検出機能の正確性を確認する。
  # mcp_tool hook の有無に依存せず、compare スクリプトの動作を検証する。
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  _run_compare_commit "allow" "block" "evt-mismatch-commit" "git commit -m 'divergent'"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISMATCH"* ]]
}

# ---------------------------------------------------------------------------
# AC-5: mcp-shadow-compare.sh 互換ログを /tmp/mcp-shadow-commit-validate.log に追記
# WHEN commit-validate の bash hook または mcp_tool hook が実行される
# THEN /tmp/mcp-shadow-commit-validate.log に JSONL 形式でエントリが追記されること
# RED: shadow log 書き込みロジック未実装のため fail する
# ---------------------------------------------------------------------------

@test "AC5: /tmp/mcp-shadow-commit-validate.log に JSONL エントリが書き込まれる" {
  # RED: shadow log 書き込みロジックが未実装のため、ログファイルが存在しないか空のため fail する
  # 実装後は pre-bash-commit-validate.sh または別の shadow hook がこのファイルに書き込む
  [ -f "$SHADOW_LOG" ] || {
    echo "/tmp/mcp-shadow-commit-validate.log が存在しない（shadow log 書き込み未実装）" >&2
    false
  }
  [ -s "$SHADOW_LOG" ] || {
    echo "/tmp/mcp-shadow-commit-validate.log が空（shadow log 書き込み未実装）" >&2
    false
  }
}

@test "AC5: shadow log エントリに source フィールド（bash または mcp_tool）が存在する" {
  # RED: shadow log 書き込みロジックが未実装のため fail する
  [ -f "$SHADOW_LOG" ] || {
    echo "/tmp/mcp-shadow-commit-validate.log が存在しない" >&2
    false
  }
  local has_bash has_mcp
  has_bash=$(grep -c '"source":"bash"' "$SHADOW_LOG" 2>/dev/null || echo "0")
  has_mcp=$(grep -c '"source":"mcp_tool"' "$SHADOW_LOG" 2>/dev/null || echo "0")
  [ "$has_bash" -ge 1 ] || [ "$has_mcp" -ge 1 ]
}

@test "AC5: shadow log エントリに command フィールドが存在する" {
  # RED: shadow log 書き込みロジックが未実装のため fail する
  [ -f "$SHADOW_LOG" ] || {
    echo "/tmp/mcp-shadow-commit-validate.log が存在しない" >&2
    false
  }
  grep -q '"command"' "$SHADOW_LOG" || {
    echo "shadow log に command フィールドが存在しない" >&2
    false
  }
}

@test "AC5: shadow log が mcp-shadow-compare.sh で解析可能（mismatch 0 またはエラーなし）" {
  # RED: shadow log 書き込みロジックが未実装のため fail する
  [ -f "$COMPARE_SH" ] || {
    echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2
    false
  }
  [ -f "$SHADOW_LOG" ] || {
    echo "/tmp/mcp-shadow-commit-validate.log が存在しない" >&2
    false
  }
  run bash "$COMPARE_SH" --log-file "$SHADOW_LOG"
  # exit 0 (mismatch なし) または exit 1 (mismatch あり) のいずれかであること（スクリプトエラーは不可）
  [ "$status" -le 1 ]
}
