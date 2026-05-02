#!/usr/bin/env bats
# specialist-completeness-shadow.bats
#
# RED テストスタブ (Issue #1278)
#
# AC-1: .claude/settings.json の Stop / SubagentStop matcher に mcp_tool entry を追加
# AC-2: mcp_tool entry が mcp__twl__twl_check_specialist を呼び manifest_context を渡す
# AC-3: mcp_tool 失敗時は warning ログのみ（outputType: "log" 指定）
# AC-4: bats fixture 7 件で bash と mcp_tool の出力を突合し mismatch 0 を確認
# AC-5: mcp-shadow-compare.sh 互換ログを /tmp/mcp-shadow-specialist-completeness.log に追記
#
# 全テストは実装前に fail (RED) する。
#

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

SETTINGS_JSON=""
CHECK_SH=""
COMPARE_SH=""
SHADOW_LOG="/tmp/mcp-shadow-specialist-completeness.log"
GIT_ROOT=""

setup() {
  # git root を取得してファイルパスを絶対パスで設定
  GIT_ROOT="$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel 2>/dev/null)"

  SETTINGS_JSON="${GIT_ROOT}/.claude/settings.json"
  CHECK_SH="${GIT_ROOT}/plugins/twl/scripts/hooks/check-specialist-completeness.sh"
  COMPARE_SH="${GIT_ROOT}/plugins/twl/scripts/mcp-shadow-compare.sh"

  SANDBOX="$(mktemp -d)"
  export SANDBOX
}

teardown() {
  if [[ -n "${SANDBOX:-}" && -d "$SANDBOX" ]]; then
    rm -rf "$SANDBOX"
  fi
}

# ---------------------------------------------------------------------------
# Fixture helper: manifest snapshot ファイルを SANDBOX に生成する
# 引数:
#   $1 = scenario name (識別子)
#   $2 = deps.yaml content (空文字列 = ファイル不要)
#   $3 = policies.json content (空文字列 = ファイル不要)
# 出力 (stdout): snapshot json 文字列 (manifest_context 引数として使う)
# ---------------------------------------------------------------------------
_create_manifest_snapshot() {
  local scenario="$1"
  local deps_yaml_content="$2"
  local policies_json_content="$3"

  local fixture_dir="$SANDBOX/fixture-${scenario}"
  mkdir -p "$fixture_dir"

  if [[ -n "$deps_yaml_content" ]]; then
    printf '%s' "$deps_yaml_content" > "$fixture_dir/deps.yaml"
  fi
  if [[ -n "$policies_json_content" ]]; then
    printf '%s' "$policies_json_content" > "$fixture_dir/policies.json"
  fi

  # manifest_context として fixture_dir パスを返す
  printf '%s' "$fixture_dir"
}

# ---------------------------------------------------------------------------
# Fixture helper: mcp-shadow-compare.sh 互換形式で JSONL エントリを書き込む
# ---------------------------------------------------------------------------
_append_shadow_log() {
  local log_file="$1"
  local event_id="$2"
  local source="$3"    # "bash" or "mcp_tool"
  local verdict="$4"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -nc \
    --arg id "$event_id" \
    --arg ts "$ts" \
    --arg src "$source" \
    --arg v "$verdict" \
    '{event_id:$id, ts:$ts, source:$src, verdict:$v, tool_name:"Stop", file_path:"specialist-completeness"}' \
    >> "$log_file"
}

# ---------------------------------------------------------------------------
# AC-1: .claude/settings.json の Stop / SubagentStop matcher に mcp_tool entry が存在する
# ---------------------------------------------------------------------------

@test "AC1: settings.json の Stop hooks に mcp_tool entry が存在する" {
  # RED: Stop フックに mcp_tool が追加されていないため fail する
  local count
  count=$(jq '[.hooks.Stop[]? | .hooks[]? | select(.type == "mcp_tool")] | length' "$SETTINGS_JSON" 2>/dev/null || echo "0")
  [ "$count" -ge 1 ]
}

@test "AC1: settings.json の SubagentStop hooks に mcp_tool entry が存在する" {
  # RED: SubagentStop キー自体が未存在のため fail する
  local count
  count=$(jq '[.hooks.SubagentStop[]? | .hooks[]? | select(.type == "mcp_tool")] | length' "$SETTINGS_JSON" 2>/dev/null || echo "0")
  [ "$count" -ge 1 ]
}

@test "AC1: settings.json の Stop hooks に既存の bash entry が維持されている" {
  # GREEN 維持 (regression guard): 既存 bash hook が消えていないことを確認
  local count
  count=$(jq '[.hooks.Stop[]? | .hooks[]? | select(.type == "command")] | length' "$SETTINGS_JSON" 2>/dev/null || echo "0")
  [ "$count" -ge 1 ]
}

# ---------------------------------------------------------------------------
# AC-2: mcp_tool entry が twl_check_specialist を呼び manifest_context を渡す
# ---------------------------------------------------------------------------

@test "AC2: Stop mcp_tool entry の tool が twl_check_specialist である" {
  # RED: entry 未追加のため fail する
  local tool
  tool=$(jq -r '[.hooks.Stop[]? | .hooks[]? | select(.type == "mcp_tool")] | .[0].tool // empty' "$SETTINGS_JSON" 2>/dev/null || true)
  [[ "$tool" == "twl_check_specialist" ]]
}

@test "AC2: Stop mcp_tool entry の server が twl である" {
  # RED: entry 未追加のため fail する
  local server
  server=$(jq -r '[.hooks.Stop[]? | .hooks[]? | select(.type == "mcp_tool")] | .[0].server // empty' "$SETTINGS_JSON" 2>/dev/null || true)
  [[ "$server" == "twl" ]]
}

@test "AC2: Stop mcp_tool entry の input に manifest_context フィールドが存在する" {
  # RED: entry 未追加のため fail する
  local manifest_ctx
  manifest_ctx=$(jq -r '[.hooks.Stop[]? | .hooks[]? | select(.type == "mcp_tool")] | .[0].input.manifest_context // empty' "$SETTINGS_JSON" 2>/dev/null || true)
  [[ -n "$manifest_ctx" ]]
}

# ---------------------------------------------------------------------------
# AC-3: mcp_tool 失敗時は warning ログのみ — outputType: "log" 指定
# ---------------------------------------------------------------------------

@test "AC3: Stop mcp_tool entry に outputType が log で設定されている" {
  # RED: entry 未追加のため fail する
  local output_type
  output_type=$(jq -r '[.hooks.Stop[]? | .hooks[]? | select(.type == "mcp_tool")] | .[0].outputType // empty' "$SETTINGS_JSON" 2>/dev/null || true)
  [[ "$output_type" == "log" ]]
}

# ---------------------------------------------------------------------------
# AC-4: bats fixture 7 件で bash と mcp_tool 出力を突合し mismatch 0 を確認
#
# 正しい呼び出し順序 (fixtures 1-3: context mode):
#   1. /tmp manifest files をセットアップ
#   2. MCP handler を呼び出す (manifest files が存在する状態で)
#   3. bash hook を実行 (同じ manifest files を読む; all-present なら削除する)
#   4. context 固有の bash verdict を確認 (他コンテキストの出力は無視)
#   5. 比較ログに記録 → mismatch 0 を確認
#
# fixtures 4-7 (directory mode): MCP は directory を読む; bash は context files を読む
# ---------------------------------------------------------------------------

# /tmp に manifest/spawned files をセットアップする
_tmp_specialist_setup() {
  local context="$1"
  local manifest_content="$2"
  local spawned_content="$3"
  printf '%s' "$manifest_content" > "/tmp/.specialist-manifest-${context}.txt"
  printf '%s' "$spawned_content" > "/tmp/.specialist-spawned-${context}.txt"
}

# bash hook を実行し、指定 context の warning 有無で verdict (ok/warn) を返す
# /tmp ファイルは事前にセットアップ済みであること
_run_bash_verdict() {
  local context="$1"
  local input_json='{"tool_name":"Agent","tool_input":{"subagent_type":"twl:twl:dummy-specialist-for-test"}}'
  local hook_output
  hook_output=$(printf '%s' "$input_json" | bash "$CHECK_SH" 2>/dev/null)
  local verdict="ok"
  # 当該 context の warning が出力されていれば warn
  if printf '%s' "$hook_output" | grep -qF "[context: ${context}]"; then
    verdict="warn"
  fi
  # フックが残したファイルがあれば削除 (all-present の場合フックが先に削除している)
  rm -f "/tmp/.specialist-manifest-${context}.txt" "/tmp/.specialist-spawned-${context}.txt"
  printf '%s' "$verdict"
}

# MCP handler を Python で呼び出し verdict (ok/warn/error) を返す
_run_mcp_verdict() {
  local manifest_context="$1"
  python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_check_specialist_handler
result = twl_check_specialist_handler(manifest_context='${manifest_context}')
print('ok' if result.get('ok') else 'warn')
" 2>/dev/null || printf 'error'
}

@test "AC4 fixture1: all-specialists-present — bash/mcp_tool 両方 ok → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-all-present-$$"
  local log_file="$SANDBOX/shadow-all-present.log"

  # 1. /tmp manifest files をセットアップ (全 specialist spawned 済み)
  _tmp_specialist_setup "$context" $'spec-reviewer\nsecurity-reviewer\n' $'spec-reviewer\nsecurity-reviewer\n'

  # 2. MCP handler を先に呼ぶ (/tmp files が存在する状態で)
  local mcp_verdict
  mcp_verdict="$(_run_mcp_verdict "$context")"

  # 3. bash hook を実行 (all-present → /tmp files を削除)
  local bash_verdict
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-all-present" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-all-present" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture2: 1 missing — bash/mcp_tool 両方 warn → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-1-missing-$$"
  local log_file="$SANDBOX/shadow-1-missing.log"

  # security-reviewer が未 spawn の状態
  _tmp_specialist_setup "$context" $'spec-reviewer\nsecurity-reviewer\n' $'spec-reviewer\n'

  local mcp_verdict
  mcp_verdict="$(_run_mcp_verdict "$context")"

  local bash_verdict
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-1-missing" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-1-missing" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture3: multiple missing — bash/mcp_tool 両方 warn → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-multi-missing-$$"
  local log_file="$SANDBOX/shadow-multi-missing.log"

  # 全 specialist が未 spawn の状態
  _tmp_specialist_setup "$context" $'spec-reviewer\nsecurity-reviewer\ncode-reviewer\n' ''

  local mcp_verdict
  mcp_verdict="$(_run_mcp_verdict "$context")"

  local bash_verdict
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-multi-missing" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-multi-missing" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture4: no policies.json — bash/mcp_tool 同一挙動 → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-no-policies-$$"
  local log_file="$SANDBOX/shadow-no-policies.log"

  # bash: context files に spec-reviewer (all spawned → ok)
  _tmp_specialist_setup "$context" $'spec-reviewer\n' $'spec-reviewer\n'

  # MCP: directory には deps.yaml のみ (policies.json なし) → directory mode → ok
  local fixture_dir="$SANDBOX/fixture-no-policies"
  mkdir -p "$fixture_dir"
  printf 'plugin_name: test-plugin\n' > "$fixture_dir/deps.yaml"

  local mcp_verdict bash_verdict
  mcp_verdict="$(_run_mcp_verdict "$fixture_dir")"
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-no-policies" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-no-policies" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture5: no deps.yaml — bash/mcp_tool 同一挙動 → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-no-deps-$$"
  local log_file="$SANDBOX/shadow-no-deps.log"

  _tmp_specialist_setup "$context" $'spec-reviewer\n' $'spec-reviewer\n'

  # MCP: directory には policies.json のみ (deps.yaml なし) → directory mode → ok
  local fixture_dir="$SANDBOX/fixture-no-deps"
  mkdir -p "$fixture_dir"
  printf '{"specialists":["spec-reviewer"]}\n' > "$fixture_dir/policies.json"

  local mcp_verdict bash_verdict
  mcp_verdict="$(_run_mcp_verdict "$fixture_dir")"
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-no-deps" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-no-deps" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture6 edge: empty manifest — bash/mcp_tool 同一挙動 → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-empty-manifest-$$"
  local log_file="$SANDBOX/shadow-empty-manifest.log"

  # 空マニフェスト: specialists なし → no check → ok
  _tmp_specialist_setup "$context" '' ''

  # MCP: directory も空ファイル → ok
  local fixture_dir="$SANDBOX/fixture-empty"
  mkdir -p "$fixture_dir"
  : > "$fixture_dir/deps.yaml"
  printf '{}' > "$fixture_dir/policies.json"

  local mcp_verdict bash_verdict
  mcp_verdict="$(_run_mcp_verdict "$fixture_dir")"
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-empty-manifest" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-empty-manifest" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture7 edge: malformed manifest (invalid JSON) — bash/mcp_tool 同一挙動 → mismatch 0" {
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-malformed-$$"
  local log_file="$SANDBOX/shadow-malformed.log"

  _tmp_specialist_setup "$context" $'spec-reviewer\n' $'spec-reviewer\n'

  # MCP: policies.json が不正 JSON → parse error → graceful ok
  local fixture_dir="$SANDBOX/fixture-malformed"
  mkdir -p "$fixture_dir"
  printf 'plugin_name: test-plugin\n' > "$fixture_dir/deps.yaml"
  printf '{invalid json: true,,,\n' > "$fixture_dir/policies.json"

  local mcp_verdict bash_verdict
  mcp_verdict="$(_run_mcp_verdict "$fixture_dir")"
  bash_verdict="$(_run_bash_verdict "$context")"

  _append_shadow_log "$log_file" "evt-malformed" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-malformed" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC-5: mcp-shadow-compare.sh 互換ログを /tmp/mcp-shadow-specialist-completeness.log に追記
# ---------------------------------------------------------------------------

@test "AC5: twl_check_specialist_handler 実行時に shadow log が追記される" {
  # RED: handler がスタブのためログ追記処理が実装されていない
  local before_size=0
  [[ -f "$SHADOW_LOG" ]] && before_size=$(wc -c < "$SHADOW_LOG")

  # handler を呼び出す (本実装では shadow log に追記される)
  python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_check_specialist_handler
twl_check_specialist_handler(manifest_context='test-context-1278')
" 2>/dev/null || true

  local after_size=0
  [[ -f "$SHADOW_LOG" ]] && after_size=$(wc -c < "$SHADOW_LOG")

  # ログが追記されていること（before より after が大きい）
  [ "$after_size" -gt "$before_size" ]
}

@test "AC5: shadow log のエントリが mcp-shadow-compare.sh 互換 JSONL 形式である" {
  # RED: handler がスタブのためログ追記処理が実装されていない
  # まずログを生成させる
  python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_check_specialist_handler
twl_check_specialist_handler(manifest_context='test-context-1278-fmt')
" 2>/dev/null || true

  # ログファイルが存在すること
  [ -f "$SHADOW_LOG" ]

  # 最終行が有効な JSONL (jq でパースできること) で source フィールドを持つこと
  local last_line
  last_line=$(tail -1 "$SHADOW_LOG" 2>/dev/null || true)
  [[ -n "$last_line" ]]
  local source_val
  source_val=$(printf '%s' "$last_line" | jq -r '.source // empty' 2>/dev/null || true)
  [[ "$source_val" == "mcp_tool" ]]
}

@test "AC5: shadow log が /tmp/mcp-shadow-specialist-completeness.log に出力される" {
  # RED: handler がスタブのためログファイルが生成されない
  # ログを生成させる
  python3 -c "
import sys
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_check_specialist_handler
twl_check_specialist_handler(manifest_context='test-context-1278-path')
" 2>/dev/null || true

  [ -f "/tmp/mcp-shadow-specialist-completeness.log" ]
}
