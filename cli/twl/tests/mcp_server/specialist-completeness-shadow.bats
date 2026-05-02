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
# 各 fixture で:
#   1. check-specialist-completeness.sh を bash で実行 → verdict を記録
#   2. twl_check_specialist_handler を Python で呼び出す → verdict を記録
#   3. mcp-shadow-compare.sh で突合 → mismatch 0 を確認
#
# RED: handler が stub 実装のため mismatch が発生する
# ---------------------------------------------------------------------------

# --- fixture helper ---
# bash hook を sandbox 上の manifest ファイルで実行し verdict を stdout に出力する
_run_bash_hook_with_manifest() {
  local manifest_file="$1"
  local spawned_file="$2"
  local context="$3"

  # check-specialist-completeness.sh はすでに存在する manifest/spawned ファイルを読む
  # テスト用の一時的な /tmp ファイルとして context を注入
  cp "$manifest_file" "/tmp/.specialist-manifest-${context}.txt" 2>/dev/null || true
  if [[ -f "$spawned_file" ]]; then
    cp "$spawned_file" "/tmp/.specialist-spawned-${context}.txt" 2>/dev/null || true
  fi

  # dummy tool input (Agent tool use をシミュレート)
  local input_json
  input_json='{"tool_name":"Agent","tool_input":{"subagent_type":"twl:twl:dummy-specialist-for-test"}}'
  local verdict="ok"
  if printf '%s' "$input_json" | bash "$CHECK_SH" 2>/dev/null; then
    verdict="ok"
  else
    verdict="warn"
  fi

  # クリーンアップ
  rm -f "/tmp/.specialist-manifest-${context}.txt" "/tmp/.specialist-spawned-${context}.txt"

  printf '%s' "$verdict"
}

# mcp_tool handler を Python で呼び出し verdict を stdout に出力する
_run_mcp_tool_handler() {
  local manifest_context="$1"

  python3 -c "
import sys, json
sys.path.insert(0, '${GIT_ROOT}/cli/twl/src')
from twl.mcp_server.tools import twl_check_specialist_handler
result = twl_check_specialist_handler(manifest_context='${manifest_context}')
# stub 実装は ok=True を返す。本実装では manifest を解析して実際の結果を返す
if result.get('ok'):
    print('ok')
else:
    print('warn')
" 2>/dev/null || printf 'error'
}

@test "AC4 fixture1: all-specialists-present — bash/mcp_tool 両方 ok → mismatch 0" {
  # RED: mcp_tool handler がスタブ実装のため manifest 解析ができず mismatch する
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-all-present-$$"
  local manifest_file="$SANDBOX/manifest-all-present.txt"
  # 全 specialist が spawned されている状態のフィクスチャ
  printf 'spec-reviewer\nsecurity-reviewer\n' > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-all-present.txt"
  printf 'spec-reviewer\nsecurity-reviewer\n' > "$spawned_file"

  local log_file="$SANDBOX/shadow-all-present.log"

  # bash hook の verdict
  local bash_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"

  # mcp_tool handler の verdict (manifest snapshot として context を渡す)
  local mcp_verdict
  mcp_verdict="$(_run_mcp_tool_handler "$context")"

  _append_shadow_log "$log_file" "evt-all-present" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-all-present" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture2: 1 missing — bash/mcp_tool 両方 warn → mismatch 0" {
  # RED: mcp_tool handler がスタブのため verdicts が不一致になる
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-1-missing-$$"
  local manifest_file="$SANDBOX/manifest-1-missing.txt"
  printf 'spec-reviewer\nsecurity-reviewer\n' > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-1-missing.txt"
  printf 'spec-reviewer\n' > "$spawned_file"  # security-reviewer が未 spawn

  local log_file="$SANDBOX/shadow-1-missing.log"

  local bash_verdict mcp_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"
  mcp_verdict="$(_run_mcp_tool_handler "$context")"

  _append_shadow_log "$log_file" "evt-1-missing" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-1-missing" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture3: multiple missing — bash/mcp_tool 両方 warn → mismatch 0" {
  # RED: mcp_tool handler がスタブのため verdicts が不一致になる
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-multi-missing-$$"
  local manifest_file="$SANDBOX/manifest-multi-missing.txt"
  printf 'spec-reviewer\nsecurity-reviewer\ncode-reviewer\n' > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-multi-missing.txt"
  # 全て未 spawn
  : > "$spawned_file"

  local log_file="$SANDBOX/shadow-multi-missing.log"

  local bash_verdict mcp_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"
  mcp_verdict="$(_run_mcp_tool_handler "$context")"

  _append_shadow_log "$log_file" "evt-multi-missing" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-multi-missing" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture4: no policies.json — bash/mcp_tool 同一挙動 → mismatch 0" {
  # RED: mcp_tool handler がスタブのため manifest_context からの policies.json 解析ができない
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-no-policies-$$"
  local manifest_file="$SANDBOX/manifest-no-policies.txt"
  printf 'spec-reviewer\n' > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-no-policies.txt"
  printf 'spec-reviewer\n' > "$spawned_file"

  # manifest_context ディレクトリには deps.yaml だけを置く (policies.json なし)
  local fixture_dir="$SANDBOX/fixture-no-policies"
  mkdir -p "$fixture_dir"
  printf 'plugin_name: test-plugin\n' > "$fixture_dir/deps.yaml"
  # policies.json は意図的に作成しない

  local log_file="$SANDBOX/shadow-no-policies.log"

  local bash_verdict mcp_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"
  mcp_verdict="$(_run_mcp_tool_handler "$fixture_dir")"

  _append_shadow_log "$log_file" "evt-no-policies" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-no-policies" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture5: no deps.yaml — bash/mcp_tool 同一挙動 → mismatch 0" {
  # RED: mcp_tool handler がスタブのため manifest_context からの deps.yaml 解析ができない
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-no-deps-$$"
  local manifest_file="$SANDBOX/manifest-no-deps.txt"
  printf 'spec-reviewer\n' > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-no-deps.txt"
  printf 'spec-reviewer\n' > "$spawned_file"

  # manifest_context ディレクトリには policies.json だけを置く (deps.yaml なし)
  local fixture_dir="$SANDBOX/fixture-no-deps"
  mkdir -p "$fixture_dir"
  printf '{"specialists":["spec-reviewer"]}\n' > "$fixture_dir/policies.json"
  # deps.yaml は意図的に作成しない

  local log_file="$SANDBOX/shadow-no-deps.log"

  local bash_verdict mcp_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"
  mcp_verdict="$(_run_mcp_tool_handler "$fixture_dir")"

  _append_shadow_log "$log_file" "evt-no-deps" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-no-deps" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture6 edge: empty manifest — bash/mcp_tool 同一挙動 → mismatch 0" {
  # RED: mcp_tool handler がスタブのため空マニフェストの処理が実装されていない
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-empty-manifest-$$"
  local manifest_file="$SANDBOX/manifest-empty.txt"
  # 空のマニフェスト
  : > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-empty.txt"
  : > "$spawned_file"

  local fixture_dir="$SANDBOX/fixture-empty"
  mkdir -p "$fixture_dir"
  # 両ファイルとも空
  : > "$fixture_dir/deps.yaml"
  printf '{}' > "$fixture_dir/policies.json"

  local log_file="$SANDBOX/shadow-empty-manifest.log"

  local bash_verdict mcp_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"
  mcp_verdict="$(_run_mcp_tool_handler "$fixture_dir")"

  _append_shadow_log "$log_file" "evt-empty-manifest" "bash" "$bash_verdict"
  _append_shadow_log "$log_file" "evt-empty-manifest" "mcp_tool" "$mcp_verdict"

  run bash "$COMPARE_SH" --log-file "$log_file"
  [ "$status" -eq 0 ]
}

@test "AC4 fixture7 edge: malformed manifest (invalid JSON) — bash/mcp_tool 同一挙動 → mismatch 0" {
  # RED: mcp_tool handler がスタブのため不正 JSON の処理が実装されていない
  [ -f "$CHECK_SH" ] || { echo "check-specialist-completeness.sh が存在しない: $CHECK_SH" >&2; false; }
  [ -f "$COMPARE_SH" ] || { echo "mcp-shadow-compare.sh が存在しない: $COMPARE_SH" >&2; false; }

  local context="1278-test-malformed-$$"
  local manifest_file="$SANDBOX/manifest-malformed.txt"
  printf 'spec-reviewer\n' > "$manifest_file"
  local spawned_file="$SANDBOX/spawned-malformed.txt"
  printf 'spec-reviewer\n' > "$spawned_file"

  local fixture_dir="$SANDBOX/fixture-malformed"
  mkdir -p "$fixture_dir"
  printf 'plugin_name: test-plugin\n' > "$fixture_dir/deps.yaml"
  # 不正な JSON を policies.json に書き込む
  printf '{invalid json: true,,,\n' > "$fixture_dir/policies.json"

  local log_file="$SANDBOX/shadow-malformed.log"

  local bash_verdict mcp_verdict
  bash_verdict="$(_run_bash_hook_with_manifest "$manifest_file" "$spawned_file" "$context")"
  mcp_verdict="$(_run_mcp_tool_handler "$fixture_dir")"

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
